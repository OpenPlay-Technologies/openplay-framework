/// The vault holds all of the assets of a game. At the end of all
/// transaction processing, the vault is used to settle the balances for the user.
/// The vault is also responsible for taking a fee when processing transactions
module openplay_core::vault;

use openplay_core::balance_manager::{BalanceManager, PlayProof};
use openplay_core::constants::precision_error_allowance;
use sui::balance::{Self, Balance};
use sui::sui::SUI;
use sui::table::{Self, Table};

// === Errors ===
const EInsufficientFunds: u64 = 1;
const EVaultNotActive: u64 = 2;

// === Structs ===
public struct Vault has store {
    epoch: u64,
    collected_protocol_fees: Balance<SUI>,
    collected_referral_fees: Table<ID, Balance<SUI>>,
    play_balance: Balance<SUI>,
    reserve_balance: Balance<SUI>,
    active: bool, // A boolean indicating whether the vault has been activated by stake, and the play_balance funded
}

// === Public-View Functions ---
public fun play_balance(self: &Vault): u64 {
    self.play_balance.value()
}

public fun reserve_balance(self: &Vault): u64 {
    self.reserve_balance.value()
}

public fun collected_referral_fees(self: &Vault, referral_id: ID): u64 {
    self.collected_referral_fees[referral_id].value()
}

public fun collected_protocol_fees(self: &Vault): u64 {
    self.collected_protocol_fees.value()
}

public fun epoch(self: &Vault): u64 {
    self.epoch
}

public fun active(self: &Vault): bool {
    self.active
}

// === Public-Package Functions ===

/// Creates an empty vault, with all balances initialized to zero and the epoch set to the current epoch.
public(package) fun empty(ctx: &mut TxContext): Vault {
    Vault {
        epoch: ctx.epoch(),
        collected_protocol_fees: balance::zero(),
        collected_referral_fees: table::new(ctx),
        play_balance: balance::zero(),
        reserve_balance: balance::zero(),
        active: false,
    }
}

/// Processes the end of day for the vault, if applicable.
/// returns (epoch_switched, prev_epoch, end_of_day_balance, was_active)
/// - `epoch_switched` is true if there was a new epoch, and the end of day was processed.
/// - `prev_epoch` will be 0 if there was no epoch switch, and the old epoch number otherwise.
/// - `end_of_day_balance` will be 0 if there was no epoch swith, and the last `play_balance` otherwise.
/// - `was_active` will be false if there was no epoch switch, and the vault activation state otherwise. This
/// says if the vault was activated in the previous epoch.
public(package) fun process_end_of_day(self: &mut Vault, ctx: &TxContext): (bool, u64, u64, bool) {
    if (self.epoch == ctx.epoch()) return (false, 0, 0, false);
    let prev_epoch = self.epoch;
    let end_of_day_balance = self.play_balance.value();
    let was_active = self.active;

    // Move the house funds back to the reserve
    let leftover_balance = self.play_balance.withdraw_all();
    self.reserve_balance.join(leftover_balance);
    self.active = false;

    self.epoch = ctx.epoch();
    return (true, prev_epoch, end_of_day_balance, was_active)
}

/// Activates the vault. This will set `active` to true, and fund the `play_balance` to the target_balance.
public(package) fun activate(self: &mut Vault, target_balance: u64) {
    assert!(self.reserve_balance.value() >= target_balance, EInsufficientFunds);
    let fresh_play_balance = self.reserve_balance.split(target_balance);
    self.play_balance.join(fresh_play_balance);
    self.active = true;
}

public(package) fun deposit(self: &mut Vault, stake: Balance<SUI>) {
    self.reserve_balance.join(stake);
}

public(package) fun withdraw(self: &mut Vault, amount: u64): Balance<SUI> {
    self.reserve_balance.split(amount)
}

public(package) fun withdraw_referral_fees(self: &mut Vault, referral_id: ID): Balance<SUI> {
    self.ensure_referral_fee_balance(referral_id);
    self.collected_referral_fees.borrow_mut(referral_id).withdraw_all()
}

/// Settles the balances between the `vault` and `balance_manager`.
/// For `amount_in`, balances are withdrawn from the `balance_manager` and joined with the `play_balance`.
/// For `amount_out`, balances are split from the `play_balance` and deposited into `balance_manager`.
public(package) fun settle_balance_manager(
    self: &mut Vault,
    amount_out: u64,
    amount_in: u64,
    balance_manager: &mut BalanceManager,
    play_proof: &PlayProof,
) {
    assert!(self.active, EVaultNotActive);
    if (amount_out > amount_in) {
        // Vault needs to pay the difference to the balance_manager
        let balance;
        if (self.play_balance.value() >= amount_out - amount_in) {
            balance = self.play_balance.split(amount_out - amount_in);
        } else if (
            amount_out - amount_in - self.play_balance.value() <= precision_error_allowance()
        ) {
            // Small precision errors
            balance = self.play_balance.withdraw_all();
        } else {
            abort EInsufficientFunds
        };
        balance_manager.deposit_with_proof(play_proof, balance);
    } else if (amount_in > amount_out) {
        // Balance manager needs to pay the difference to the vault
        let balance;
        balance = balance_manager.withdraw_with_proof(play_proof, amount_in - amount_out);
        self.play_balance.join(balance);
    };
}

/// Process the fees of the game owner and protocol.
public(package) fun process_referral_fee(self: &mut Vault, referral_id: ID, referral_fee: u64) {
    assert!(self.play_balance.value() >= referral_fee, EInsufficientFunds);
    if (referral_fee > 0) {
        self.ensure_referral_fee_balance(referral_id);
        let balance = self.play_balance.split(referral_fee);
        self.collected_referral_fees.borrow_mut(referral_id).join(balance);
    };
}

public(package) fun process_protocol_fee(self: &mut Vault, protocol_fee: u64) {
    assert!(self.play_balance.value() >= protocol_fee, EInsufficientFunds);
    if (protocol_fee > 0) {
        let balance = self.play_balance.split(protocol_fee);
        self.collected_protocol_fees.join(balance);
    };
}

// === Private Functions ===
fun ensure_referral_fee_balance(self: &mut Vault, game_id: ID) {
    if (!self.collected_referral_fees.contains(game_id)) {
        self.collected_referral_fees.add(game_id, balance::zero());
    };
}

// === Test Functions ===
#[test_only]
public fun fund_play_balance_for_testing(self: &mut Vault, amount: u64, ctx: &mut TxContext) {
    let balance = sui::coin::mint_for_testing(amount, ctx).into_balance();
    self.play_balance.join(balance);
}

#[test_only]
public fun burn_play_balance_for_testing(self: &mut Vault, amount: u64, ctx: &mut TxContext) {
    let balance = self.play_balance.split(amount);
    balance.into_coin(ctx).burn_for_testing();
}

#[test_only]
public fun fund_reserve_balance_for_testing(self: &mut Vault, amount: u64, ctx: &mut TxContext) {
    let balance = sui::coin::mint_for_testing(amount, ctx).into_balance();
    self.reserve_balance.join(balance);
}

#[test_only]
public fun burn_reserve_balance_for_testing(self: &mut Vault, amount: u64, ctx: &mut TxContext) {
    let balance = self.reserve_balance.split(amount);
    balance.into_coin(ctx).burn_for_testing();
}

#[test_only]
public fun fund_referral_fees_for_testing(
    self: &mut Vault,
    game_id: ID,
    amount: u64,
    ctx: &mut TxContext,
) {
    let balance = sui::coin::mint_for_testing(amount, ctx).into_balance();
    self.collected_referral_fees.borrow_mut(game_id).join(balance);
}
