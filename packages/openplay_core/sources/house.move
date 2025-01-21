/// Game is responsible for executing the flow for placing bets and wins.
/// The game module plays a similar role as Pool in deepbookv3.
module openplay_core::house;

use openplay_core::referral::{Referral, ReferralAdminCap, referral_id};
use openplay_core::balance_manager::{BalanceManager, PlayProof};
use openplay_core::participation::{Self, Participation};
use openplay_core::state::{Self, State};
use openplay_core::vault::{Self, Vault};
use sui::coin::Coin;
use sui::sui::SUI;
use openplay_core::transaction::Transaction;
use std::uq32_32::{UQ32_32, from_quotient};

#[test_only]
use openplay_core::balance_manager::generate_proof_for_testing;

// === Errors ===
const EInsufficientFunds: u64 = 1;
const EInvalidCap: u64 = 2;
const EInvalidParticipation: u64 = 3;
const EVaultNotActive: u64 = 4;

// === Structs ===
public struct House has key, store {
    id: UID,
    vault: Vault,
    state: State,
    target_balance: u64,
    referral_fee_bps: u64
}

public struct HouseAdminCap has key, store {
    id: UID,
    house_id: ID,
}

// === Public-View Functions ===
public fun id (self: &House): ID {
    self.id.to_inner()
}

public fun play_balance(self: &mut House, ctx: &mut TxContext): u64 {
    self.process_end_of_day(ctx);
    self.vault.play_balance()
}

public fun referral_fee_factor(self: &House): UQ32_32 {
    from_quotient(self.referral_fee_bps, 10000)
}

public fun cap_house_id(cap: &HouseAdminCap): ID {
    cap.house_id
}

// === Public-Mutative Functions ===
public fun new(
    target_balance: u64,
    referral_fee_bps: u64,
    ctx: &mut TxContext,
): (House, HouseAdminCap) {
    let house = House {
        id: object::new(ctx),
        vault: vault::empty(ctx),
        state: state::new(ctx),
        target_balance,
        referral_fee_bps
    };
    let house_admin_cap = HouseAdminCap {
        id: object::new(ctx),
        house_id: house.id()
    };

    (house, house_admin_cap)
}

/// Ensures that the vault can cover `max_payout` with the play balance
public fun ensure_sufficient_funds(self: &mut House, amount: u64, ctx: &TxContext) {
    // Make sure the vault and participation are up to date (end of day is processed for previous days)
    self.process_end_of_day(ctx);

    assert!(self.vault.active(), EVaultNotActive);
    assert!(self.vault.play_balance() >= amount, EInsufficientFunds)
}

/// Create a new participation
public fun new_participation(self: &House, ctx: &mut TxContext): Participation {
    participation::empty(self.id.to_inner(), ctx)
}

/// Stake money in the protocol to participate in the house winnings.
/// The stake is first added to the account's inactive stake, and is only activated in the next epoch.
public fun stake(
    self: &mut House,
    participation: &mut Participation,
    stake: Coin<SUI>,
    ctx: &mut TxContext,
) {
    self.assert_valid_participation(participation);

    // Make sure the vault and participation are up to date (end of day is processed for previous days)
    self.process_end_of_day(ctx);

    // Process the stake in the history
    self.state.process_stake(stake.value());

    // Add funds to the participation
    participation.add_inactive_stake(stake.value(), ctx);

    // Move funds to the vault
    self.vault.deposit(stake.into_balance());
}

/// Refreshes the participation to process any unprocessed profits or losses.
public fun update_participation(
    self: &mut House,
    participation: &mut Participation,
    ctx: &mut TxContext,
) {
    self.assert_valid_participation(participation);

    // Make sure the end of day is processed
    self.process_end_of_day(ctx);

    // Refresh the participation
    self.state.refresh(participation, ctx);
}

/// Withdraws the stake from the current game. This only goes into effect in the next epoch.
public fun unstake(self: &mut House, participation: &mut Participation, ctx: &mut TxContext) {
    self.assert_valid_participation(participation);

    // Make sure the vault and participation are up to date (end of day is processed for previous days)
    self.process_end_of_day(ctx);

    // Unstake the funds in the participation
    let (unstake_immediately, pending_unstake) = participation.unstake(ctx);

    // Process the unstake in the history
    self.state.process_unstake(unstake_immediately, pending_unstake);
}

public fun claim_all(
    self: &mut House,
    participation: &mut Participation,
    ctx: &mut TxContext,
): Coin<SUI> {
    self.assert_valid_participation(participation);

    // Make sure the vault and participation are up to date (end of day is processed for previous days)
    self.process_end_of_day(ctx);

    // Take the claimable balance from participation
    let claimable = participation.claim_all(ctx);

    // Withdraw from vault
    self.vault.withdraw(claimable).into_coin(ctx)
}

/// Claims all the fees for this game. Can only be called by the game owner (using the house_admin_cap)
public fun claim_referral_fees(
    self: &mut House,
    referral_admin_cap: &ReferralAdminCap,
    ctx: &mut TxContext,
): Coin<SUI> {
    self.vault.withdraw_referral_fees(referral_admin_cap.referral_id()).into_coin(ctx)
}

// === Admin Functions ===
public fun admin_process_transactions_with_referral(
    self: &mut House,
    cap: &HouseAdminCap,
    balance_manager: &mut BalanceManager,
    transactions: &vector<Transaction>,
    play_proof: &PlayProof,
    referral: &Referral,
    ctx: &TxContext,
) {
    // Check the admin cap
    self.assert_valid_cap(cap);

    let referral_fee_factor = self.referral_fee_factor();

    // Make sure the vault and participation are up to date (end of day is processed for previous days)
    self.process_end_of_day(ctx);

    let (credit_balance, debit_balance, referral_fee, protocol_fee) = self
        .state
        .process_transactions(transactions, balance_manager.id(), referral_fee_factor);

    // Settle the balances in vault
    self.vault.settle_balance_manager(credit_balance, debit_balance, balance_manager, play_proof);

    // Process fees
    self.vault.process_referral_fee(referral.id(), referral_fee);
    self.vault.process_protocol_fee(protocol_fee);
}

public fun admin_process_transactions(
    self: &mut House,
    cap: &HouseAdminCap,
    balance_manager: &mut BalanceManager,
    transactions: &vector<Transaction>,
    play_proof: &PlayProof,
    ctx: &TxContext,
) {
    // Check the admin cap
    self.assert_valid_cap(cap);

    let referral_fee_factor = self.referral_fee_factor();

    // Make sure the vault and participation are up to date (end of day is processed for previous days)
    self.process_end_of_day(ctx);

    let (credit_balance, debit_balance, _referral_fee, protocol_fee) = self
        .state
        .process_transactions(transactions, balance_manager.id(), referral_fee_factor);

    // Settle the balances in vault
    self.vault.settle_balance_manager(credit_balance, debit_balance, balance_manager, play_proof);

    // Process fees
    self.vault.process_protocol_fee(protocol_fee);
}



// == Private Functions ==
/// The first time this gets called on a new epoch, the end of the day procedure is initiated for the last known epoch.
/// The vault saves the end of day balance for the house and resets to the target balance if there are enough funds available.
/// Note: there can be a number of epochs in between without any activity.
fun process_end_of_day(self: &mut House, ctx: &TxContext) {
    let (epoch_switched, prev_epoch, end_of_day_balance, was_active) = self
        .vault
        .process_end_of_day(ctx);

    if (epoch_switched) {
        let profits: u64;
        let losses: u64;
        if (was_active) {
            if (end_of_day_balance > self.target_balance) {
                profits = end_of_day_balance - self.target_balance;
                losses = 0;
            } else {
                losses = self.target_balance - end_of_day_balance;
                profits = 0;
            };
        } else {
            // The house was not funded so no profits or losses were made
            profits = 0;
            losses = 0;
        };
        let new_stake_amount = self.state.process_end_of_day(prev_epoch, profits, losses, ctx);
        if (new_stake_amount >= self.target_balance) {
            self.vault.activate(self.target_balance);
        };
    }
}

fun assert_valid_cap(self: &House, house_cap: &HouseAdminCap) {
    assert!(self.id() == house_cap.house_id, EInvalidCap);
}

fun assert_valid_participation(self: &House, participation: &Participation) {
    assert!(self.id() == participation.house_id(), EInvalidParticipation);
}

// === Test Functions ===
#[test_only]
public fun empty_house_for_testing(
    target_balance: u64, 
    referral_fee_bps: u64,
    ctx: &mut TxContext): House {
    House {
        id: object::new(ctx),
        vault: vault::empty(ctx),
        state: state::new(ctx),
        target_balance,
        referral_fee_bps
    }
}

#[test_only]
public fun cap_for_testing(house: &House, ctx: &mut TxContext): HouseAdminCap {
    HouseAdminCap {
        id: object::new(ctx),
        house_id: house.id()
    }
}

#[test_only]
public fun process_transactions_for_testing(
    self: &mut House,
    txs: &vector<Transaction>,
    balance_manager: &mut BalanceManager,
    ctx: &TxContext,
) {
    let referral_fee_factor = self.referral_fee_factor();
    // Make sure the vault is up to date (end of day is processed for previous days)
    self.process_end_of_day(ctx);

    // Process transactions by state
    let (credit_balance, debit_balance, _referral_fee, protocol_fee) = self
        .state
        .process_transactions(txs, balance_manager.id(), referral_fee_factor);

    let play_proof = balance_manager.generate_proof_for_testing(ctx);

    // Settle the balances in vault
    self.vault.settle_balance_manager(credit_balance, debit_balance, balance_manager, &play_proof);
    self.vault.process_protocol_fee(protocol_fee);
}


#[test_only]
public fun process_transactions_for_testing_with_referral(
    self: &mut House,
    txs: &vector<Transaction>,
    balance_manager: &mut BalanceManager,
    referral: &Referral,
    ctx: &TxContext,
) {
    let referral_fee_factor = self.referral_fee_factor();
    // Make sure the vault is up to date (end of day is processed for previous days)
    self.process_end_of_day(ctx);

    // Process transactions by state
    let (credit_balance, debit_balance, referral_fee, protocol_fee) = self
        .state
        .process_transactions(txs, balance_manager.id(), referral_fee_factor);

    let play_proof = balance_manager.generate_proof_for_testing(ctx);

    // Settle the balances in vault
    self.vault.settle_balance_manager(credit_balance, debit_balance, balance_manager, &play_proof);
    self.vault.process_protocol_fee(protocol_fee);
    self.vault.process_referral_fee(referral.id(), referral_fee);
}

#[test_only]
public fun add_referral_fees_for_testing(self: &mut House, referral: &Referral, amount: u64, ctx: &TxContext) {
    self.process_end_of_day(ctx);
    self.vault.process_referral_fee(referral.id(), amount);
}