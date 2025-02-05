/// The vault holds all of the assets of a house. At the end of all
/// transaction processing, the vault is used to settle the balances for the account.
/// The vault is also responsible for taking a fee when processing transactions
module openplay_core::vault;

use openplay_core::balance_manager::{BalanceManager, PlayProof};
use openplay_core::constants::precision_error_allowance;
use sui::balance::{Self, Balance};
use sui::sui::SUI;
use sui::vec_map::{Self, VecMap};
use sui::event::emit;

// === Errors ===
const EInsufficientFunds: u64 = 1;
const EReferralDoesNotExist: u64 = 3;

// === Structs ===
public struct Vault has store {
    epoch: u64,
    collected_house_fees: Balance<SUI>,
    collected_protocol_fees: Balance<SUI>,
    collected_referral_fees: VecMap<ID, Balance<SUI>>,
    play_balance: Balance<SUI>,
    reserve_balance: Balance<SUI>,
}

public struct PlayBalanceFundedEvent has copy, drop {
    amount: u64
}

public struct PlayBalanceClearedEvent has copy, drop {
    amount: u64
}

// === Public-View Functions ---
public fun play_balance(self: &Vault): u64 {
    self.play_balance.value()
}

public fun reserve_balance(self: &Vault): u64 {
    self.reserve_balance.value()
}

public fun collected_referral_fees(self: &Vault, referral_id: ID): u64 {
    assert!(self.collected_referral_fees.contains(&referral_id), EReferralDoesNotExist);
    self.collected_referral_fees[&referral_id].value()
}

public fun collected_house_fees(self: &Vault): u64 {
    self.collected_house_fees.value()
}

public fun collected_protocol_fees(self: &Vault): u64 {
    self.collected_protocol_fees.value()
}

public fun epoch(self: &Vault): u64 {
    self.epoch
}

// === Public-Package Functions ===

/// Creates an empty vault, with all balances initialized to zero and the epoch set to the current epoch.
public(package) fun empty(ctx: &TxContext): Vault {
    Vault {
        epoch: ctx.epoch(),
        collected_referral_fees: vec_map::empty(),
        collected_protocol_fees: balance::zero(),
        collected_house_fees: balance::zero(),
        play_balance: balance::zero(),
        reserve_balance: balance::zero(),
    }
}

/// If there is an epoch switch, the end of day is processed. The playable balance is joined back into the reserves, and the last
/// playable balance, which we call the end of day balance, is returned. Current vault epoch is updated.
/// returns (epoch_switched, prev_epoch, end_of_day_balance, was_active)
/// - `epoch_switched` is true if there was a new epoch, and the end of day was processed.
/// - `prev_epoch` will be 0 if there was no epoch switch, and the old epoch number otherwise.
/// - `end_of_day_balance` will be 0 if there was no epoch swith, and the last `play_balance` otherwise.
public(package) fun process_end_of_day(self: &mut Vault, ctx: &TxContext): (bool, u64, u64) {
    if (self.epoch == ctx.epoch()) return (false, 0, 0);
    let prev_epoch = self.epoch;
    let end_of_day_balance = self.play_balance.value();

    // Move the house funds back to the reserve
    let leftover_balance = self.play_balance.withdraw_all();
    let amount_cleared = leftover_balance.value();
    self.reserve_balance.join(leftover_balance);
    self.epoch = ctx.epoch();

    // Event
    emit(PlayBalanceClearedEvent {
        amount: amount_cleared
    });

    return (true, prev_epoch, end_of_day_balance)
}

/// Funds the `play_balance` to the target_balance.
/// Fails if the reserve does not have enough funds
public(package) fun fund_play_balance(self: &mut Vault, target_balance: u64) {
    assert!(self.reserve_balance.value() >= target_balance, EInsufficientFunds);
    let fresh_play_balance = self.reserve_balance.split(target_balance);
    self.play_balance.join(fresh_play_balance);

    // Event
    emit(PlayBalanceFundedEvent {
        amount: target_balance
    });
}

public(package) fun deposit(self: &mut Vault, stake: Balance<SUI>) {
    self.reserve_balance.join(stake);
}

public(package) fun withdraw(self: &mut Vault, amount: u64): Balance<SUI> {
    self.reserve_balance.split(amount)
}

public(package) fun withdraw_referral_fees(self: &mut Vault, referral_id: ID): Balance<SUI> {
    self.ensure_referral_fee_balance(referral_id);

    let balance = &mut self.collected_referral_fees[&referral_id];
    balance.withdraw_all()
}

public(package) fun withdraw_house_fees(self: &mut Vault): Balance<SUI> {
    self.collected_house_fees.withdraw_all()
}

public(package) fun withdraw_protocol_fees(self: &mut Vault): Balance<SUI> {
    self.collected_protocol_fees.withdraw_all()
}

/// Settles the balances between the `vault` and `balance_manager`.
/// For `amount_in`, balances are withdrawn from the `balance_manager` and joined with the `play_balance`.
/// For `amount_out`, balances are split from the `play_balance` and deposited into `balance_manager`.
/// Fails if the balance_manager funds are lower than the amount_in for safety reasons.
public(package) fun settle_balance_manager(
    self: &mut Vault,
    amount_out: u64,
    amount_in: u64,
    balance_manager: &mut BalanceManager,
    play_proof: &PlayProof,
) {
    // No matter what, the balance manager should have sufficient funds to cover the debits
    balance_manager.ensure_sufficient_funds(amount_in);
    if (amount_out > amount_in) {
        // Vault needs to pay the difference to the balance_manager
        let balance;
        if (self.play_balance.value() >= amount_out - amount_in) {
            balance = self.play_balance.split(amount_out - amount_in);
        } else if (amount_out - amount_in - self.play_balance.value() <= precision_error_allowance()) {
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

public(package) fun process_protocol_fee(self: &mut Vault, protocol_fee: u64) {
    assert!(self.play_balance.value() >= protocol_fee, EInsufficientFunds);
    if (protocol_fee > 0) {
        let balance = self.play_balance.split(protocol_fee);
        self.collected_protocol_fees.join(balance);
    };
}

public(package) fun process_house_fee(self: &mut Vault, house_fee: u64) {
    assert!(self.play_balance.value() >= house_fee, EInsufficientFunds);
    if (house_fee > 0) {
        let balance = self.play_balance.split(house_fee);
        self.collected_house_fees.join(balance);
    };
}

public(package) fun process_referral_fee(self: &mut Vault, referral_id: ID, referral_fee: u64) {
    assert!(self.play_balance.value() >= referral_fee, EInsufficientFunds);
    if (referral_fee > 0) {
        self.ensure_referral_fee_balance(referral_id);
        let balance = self.play_balance.split(referral_fee);
        let referral_balance = &mut self.collected_referral_fees[&referral_id];
        referral_balance.join(balance);
    };
}

// === Private Functions ===
fun ensure_referral_fee_balance(self: &mut Vault, referral_id: ID) {
    if (!self.collected_referral_fees.contains(&referral_id)) {
        self.collected_referral_fees.insert(referral_id, balance::zero());
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
    referral_id: ID,
    amount: u64,
    ctx: &mut TxContext,
) {
    let balance = sui::coin::mint_for_testing(amount, ctx).into_balance();
    let ref_balance = &mut self.collected_referral_fees[&referral_id];
    ref_balance.join(balance);
}

#[test_only]
public fun fund_protocol_fees_for_testing(self: &mut Vault, amount: u64, ctx: &mut TxContext) {
    let balance = sui::coin::mint_for_testing(amount, ctx).into_balance();
    self.collected_protocol_fees.join(balance);
}
