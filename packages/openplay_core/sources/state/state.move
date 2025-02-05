/// The state module represents the current global state of a game. It maintains all accounts and history.
/// It needs to process all gamerounds to keep the state up to date.
/// It serves a similar function as the State in deepbookv3.
module openplay_core::state;

use openplay_core::account::{Self, Account};
use openplay_core::constants::precision_error_allowance;
use openplay_core::participation::Participation;
use openplay_core::transaction::{Transaction, is_credit};
use std::option::do;
use std::uq32_32::{UQ32_32, from_quotient, int_mul, add, sub, from_int};
use sui::event::emit;
use sui::table::{Self, Table};

// === Structs ===
public struct State has store {
    accounts: Table<ID, Account>,
    epoch: u64, // The current epoch of the state
    is_active: bool, // Boolean that indicates whether a cycle is currently active
    inactive_stake: u64, // Stake that is available to be activated in the next cycle
    active_stake: u64, // Stake that is currently active, this can never change throughout a cycle
    pending_unstake: u64, // The stake from epoch i that will be disactived in epoch i+1
    // Keep track of volumes
    current_volumes: Volumes,
    // All time statistics
    all_time_bet_amount: u128,
    all_time_win_amount: u128,
    all_time_profits: u128,
    all_time_losses: u128,
    // History for cycles, eof, and volumes
    active_history: Table<u64, bool>,
    historic_volumes: Table<u64, Volumes>,
    eod_history: Table<u64, EndOfDay>,
}

public struct Volumes has copy, drop, store {
    total_stake_amount: u64,
    total_bet_amount: u64,
    total_win_amount: u64,
}

public struct EndOfDay has copy, drop, store {
    day_profits: u64,
    day_losses: u64,
}

public struct HouseActivatedEvent has copy, drop {
    active_stake: u64,
}

public struct StateEndOfDayProcessedEvent has copy, drop {
    epoch: u64,
    profits: u64,
    losses: u64,
    total_bets: u64,
    total_wins: u64,
    total_stake: u64
}


// === Errors ===
const EUnknownTransaction: u64 = 1;
const EEpochMismatch: u64 = 2;
const ECannotUnstakeMoreThanStaked: u64 = 3;
const EEndOfDayNotAvailable: u64 = 4;
const EEpochHasNotFinishedYet: u64 = 5;
const EVolumeNotAvailable: u64 = 6;
const EInvalidProfitsOrLosses: u64 = 7;
const EHouseIsNotActive: u64 = 8;
const EHouseIsAlreadyActive: u64 = 9;

// == Public-View Functions ==
public fun is_active(self: &State): bool {
    self.is_active
}

public fun epoch(self: &State): u64 {
    self.epoch
}

public fun active_stake(self: &State): u64 {
    self.active_stake
}

public fun inactive_stake(self: &State): u64 {
    self.inactive_stake
}

public fun pending_unstake(self: &State): u64 {
    self.pending_unstake
}

public fun volume_for_epoch(self: &State, epoch: u64): Volumes {
    assert!(self.historic_volumes.contains(epoch), EVolumeNotAvailable);
    self.historic_volumes[epoch]
}

public fun all_time_bet_amount(self: &State): u128 {
    self.all_time_bet_amount
}

public fun all_time_win_amount(self: &State): u128 {
    self.all_time_win_amount
}

public fun all_time_profits(self: &State): u128 {
    self.all_time_profits
}

public fun all_time_losses(self: &State): u128 {
    self.all_time_losses
}

public fun total_stake_amount(volume: &Volumes): u64 {
    volume.total_stake_amount
}

public fun total_bet_amount(volume: &Volumes): u64 {
    volume.total_bet_amount
}

public fun total_win_amount(volume: &Volumes): u64 {
    volume.total_win_amount
}

public fun current_volumes(self: &State): Volumes {
    self.current_volumes
}

public fun end_of_day_for_epoch(self: &State, epoch: u64): EndOfDay {
    assert!(self.eod_history.contains(epoch), EEndOfDayNotAvailable);
    self.eod_history[epoch]
}

public fun day_profits(eod: &EndOfDay): u64 {
    eod.day_profits
}

public fun day_losses(eod: &EndOfDay): u64 {
    eod.day_losses
}

// == Public-Package Functions ==
/// Process the transactions in the given state by updating the history and account.
/// Returns a tuple (credit_balance, debit_balance, house_fee, protocol_fee, referral_fee).
/// The first two values are the to_credit and to_debit balance by the balance manager.
/// The last two values are the fees taken by the owner and protocol.
/// These are calculated by the state because they might depend on state values (such as volumes).
/// The Vault uses these values to perform any necessary transfers.
public(package) fun process_transactions(
    self: &mut State,
    transactions: &vector<Transaction>,
    balance_manager_id: ID,
    house_fee_factor: UQ32_32,
    protocol_fee_factor: UQ32_32,
    referral_fee_factor: Option<UQ32_32>,
    ctx: &TxContext,
): (u64, u64, u64, u64, u64) {
    self.assert_active();
    self.assert_epoch_up_to_date(ctx);
    self.update_account(balance_manager_id);

    // Process transactions on the account
    self.process_transactions_for_account(balance_manager_id, transactions);

    // Process transactions for the history
    self.process_volumes(transactions);

    // Calculate fees
    let house_fee = calculate_fee(transactions, house_fee_factor);
    let protocol_fee = calculate_fee(transactions, protocol_fee_factor);
    // If a referral_fee_factor is provided, we calculate the referral_fee
    let mut referral_fee = 0;
    referral_fee_factor.do!(
        |referral_fee_factor| referral_fee = calculate_fee(transactions, referral_fee_factor),
    );

    // Settle account balance
    let (credit_balance, debit_balance) = self.accounts[balance_manager_id].settle();

    (credit_balance, debit_balance, house_fee, protocol_fee, referral_fee)
}

/// Processes a stake transaction in the game.
public(package) fun process_stake(self: &mut State, amount: u64, ctx: &TxContext) {
    self.assert_epoch_up_to_date(ctx);
    // Add the stake to the pending stake of this epoch
    // It will become active in the next epoch
    self.add_stake(amount);
}

/// Processes an unstake.
/// Takes two arguments:
/// `stake_removed` is the stake that was removed, this can be inactive or active stake depending on the house state.
/// `pending_stake_removed` is pending stake that was removed. This is the stake that was supposed to become active in the next epoch, but cancelled now.
/// If the house is active, then the removed stake need to be queued through the `pending_unstake` balance. This will go in effect next epoch.
/// If the house is inactive, then the removed stake can be deducted from the `inactive_stake` balance immediately.
public(package) fun process_unstake(
    self: &mut State,
    stake_removed: u64,
    pending_stake_removed: u64,
    ctx: &TxContext,
) {
    self.assert_epoch_up_to_date(ctx);
    // Can only remove stake if the state is up to date
    assert!(ctx.epoch() == self.epoch, EEpochMismatch);

    if (self.is_active) {
        self.add_pending_unstake(stake_removed);
    } else {
        self.remove_inactive_stake(stake_removed);
    };
    self.remove_inactive_stake(pending_stake_removed);
}

/// Advances the epoch: updates the history and saves the end of day of the house.
/// Fails if the epoch that is trying to be processed is not the last known one.
/// Also fails if the epoch is in the future or not finished yet.
/// Returns the stake amount for the new epoch.
public(package) fun process_end_of_day(
    self: &mut State,
    epoch: u64,
    profits: u64,
    losses: u64,
    ctx: &TxContext,
) {
    // We can only process an epoch after it has been finished
    assert!(ctx.epoch() > self.epoch, EEpochHasNotFinishedYet);

    // We can only process the epoch that we are currently on
    // This means that the vault and state epochs need to be kept in sync
    assert!(self.epoch == epoch, EEpochMismatch);

    // Make sure the chain is correct, and only profits OR losses are reported
    assert!(losses == 0 || profits == 0, EInvalidProfitsOrLosses);

    // The new staked amount is
    // 1) the previous stake amount
    // 2) plus profits or minus losses
    // 3) minus the pending unstake (actualized)
    // 4) plus the pending stake
    let prev_stake_amount = self.current_volumes.total_stake_amount;
    let mut new_stake_amount = prev_stake_amount;

    if (profits > 0) {
        new_stake_amount = new_stake_amount + profits
    } else if (losses > 0) {
        if (new_stake_amount >= losses) {
            new_stake_amount = new_stake_amount - losses;
        } else if (losses - new_stake_amount <= precision_error_allowance()) {
            // Small rounding errors
            new_stake_amount = 0;
        } else {
            abort EInvalidProfitsOrLosses
        }
    };

    // The pending unstake need to be actualized to get the actual unstake amount
    // The reason for this is:
    // - If you unstake you still need to bear the losses or receive the winnings from that epoch
    // => If you receive winnings, then the actual unstake amount is greater than the pending unstake amount
    // => If you bear losses, then the actual unstake amount is smaller than the pending unstake amount
    if (self.pending_unstake > 0) {
        // Calculate the actual unstake amount
        let actual_unstake_amount;
        if (profits > 0) {
            let return_on_investment = from_quotient(profits, prev_stake_amount);
            let multiplier = add(from_int(1), return_on_investment);
            actual_unstake_amount = int_mul(self.pending_unstake, multiplier);
        } else if (losses > 0) {
            if (losses >= prev_stake_amount) {
                // edge case: bankrupty
                actual_unstake_amount = 0;
            } else {
                let loss_on_investment = from_quotient(losses, prev_stake_amount);
                let multiplier = sub(from_int(1), loss_on_investment);
                actual_unstake_amount = int_mul(self.pending_unstake, multiplier)
            }
        } else {
            actual_unstake_amount = self.pending_unstake;
        };

        // Deduct it from the new stake amount
        if (actual_unstake_amount > new_stake_amount) {
            new_stake_amount = 0;
        } else {
            new_stake_amount = new_stake_amount - actual_unstake_amount;
        }
    };

    // Update the current active stake by the new amount
    self.active_stake = new_stake_amount;
    self.pending_unstake = 0;

    // Desactivate the state
    let was_active = self.is_active;
    self.desactivate();

    // Reset the volumes
    let prev_volume = self.current_volumes;
    self.current_volumes = new_volumes();

    // Save the history eod, volume, active
    self.historic_volumes.add(epoch, prev_volume);
    self.active_history.add(epoch, was_active);
    let eod = EndOfDay {
        day_profits: profits,
        day_losses: losses,
    };
    self.eod_history.add(epoch, eod);

    // Update the all time statistics
    self.all_time_losses = self.all_time_losses + (losses as u128);
    self.all_time_profits = self.all_time_profits + (profits as u128);

    // Update the epoch
    self.epoch = ctx.epoch();

    // Emit event
    emit(StateEndOfDayProcessedEvent {
        epoch: epoch,
        profits: profits,
        losses: losses,
        total_bets: prev_volume.total_bet_amount,
        total_wins: prev_volume.total_win_amount,
        total_stake: prev_volume.total_stake_amount
    })
}

public(package) fun new(ctx: &mut TxContext): State {
    State {
        accounts: table::new(ctx),
        epoch: ctx.epoch(),
        is_active: false,
        inactive_stake: 0,
        active_stake: 0,
        pending_unstake: 0,
        // Keep track of volumes
        current_volumes: new_volumes(),
        // All time statistics
        all_time_bet_amount: 0,
        all_time_win_amount: 0,
        all_time_profits: 0,
        all_time_losses: 0,
        // History for cycles, eof, and volumes
        active_history: table::new(ctx),
        historic_volumes: table::new(ctx),
        eod_history: table::new(ctx),
    }
}

/// This function can be used to settle any remaining balances on the account.
/// This can be used to claim profits or to claim unstaked amount that can available.
/// Returns a tuple (credit_balance, debit_balance).
/// The Vault uses thes values to perform any necessary transfers in the balance manager.
public(package) fun refresh(self: &State, participation: &mut Participation, ctx: &TxContext) {
    self.update_participation(participation, ctx);
}

/// Function that activates the house if 1) it is not active yet and 2) there is enough pending stake.
/// Returns true if the state was activated, false if nothing changed.
public(package) fun maybe_activate(self: &mut State, target_balance: u64, ctx: &TxContext): bool {
    // Can only activate if up to date
    self.assert_epoch_up_to_date(ctx);

    // No need to do anything if the house is already active
    if (self.is_active()) {
        return false
    };

    // Check if there is enough pending stake to activate
    if (self.inactive_stake >= target_balance) {
        self.activate();
        return true
    };

    false
}

/// Returns `true` if the provided epoch was active, and `false` if the epoch was inactive.
/// Crashes if the provided epoch number is unseen.
public(package) fun epoch_active(self: &State, epoch: u64): bool {
    // Check if the epoch is in the future
    assert!(epoch <= self.epoch, EEpochMismatch);

    // Check if it is the current epoch
    if (self.epoch == epoch) {
        return self.is_active()
    };
    // Return false if the epoch was not in the history
    if (!self.active_history.contains(epoch)) {
        return false
    };

    self.active_history[epoch]
}

public(package) fun calculate_ggr_share(self: &State, epoch: u64, account_stake: u64): (u64, u64) {
    // If the epoch data is unavailable, there is no ggr_share
    if (
        !self.historic_volumes.contains(epoch) || !self.eod_history.contains(epoch) || !self.active_history.contains(epoch)
    ) {
        return (0, 0)
    };
    let epoch_volume = &self.historic_volumes[epoch];
    let end_of_day = &self.eod_history[epoch];
    let was_active = self.active_history[epoch];

    // If there was no stake, or no active cycle, there is no ggr_share
    if (epoch_volume.total_stake_amount == 0 || !was_active) {
        return (0, 0)
    };

    let participation_ratio = from_quotient(account_stake, epoch_volume.total_stake_amount);
    if (end_of_day.day_losses > 0) {
        let losses = int_mul(end_of_day.day_losses, participation_ratio);
        return (0, losses)
    };
    if (end_of_day.day_profits > 0) {
        let profits = int_mul(end_of_day.day_profits, participation_ratio);
        return (profits, 0)
    };
    return (0, 0)
}

// == Private Functions ==
/// Advances the account state to the latest epoch, if this is not the case.
/// Inactive stake will be activated, while profits / losses will be added to the active stake.
fun update_participation(self: &State, participation: &mut Participation, ctx: &TxContext) {
    let (
        mut current_participation_epoch,
        mut stake,
        mut _pending_stake,
    ) = participation.current_state();

    // process the account's ggr share for all epochs between the last activate epoch and the current one
    while (current_participation_epoch < ctx.epoch()) {

        let (epoch_profits, epoch_losses) = self.calculate_ggr_share(
            current_participation_epoch,
            stake,
        );

        participation.process_end_of_day(
            current_participation_epoch,
            epoch_profits,
            epoch_losses,
            ctx,
        );

        (current_participation_epoch, stake, _pending_stake) = participation.current_state();
    }
}

/// Advances the account state to the latest epoch, if this is not the case.
/// Inactive stake will be activated, while profits / losses will be added to the active stake.
fun update_account(self: &mut State, balance_manager_id: ID) {
    if (!self.accounts.contains(balance_manager_id)) {
        self.accounts.add(balance_manager_id, account::empty());
    };
}

/// Processes the transactions for an account by increasing the debit or credit balance based on the transaction types.
fun process_transactions_for_account(
    self: &mut State,
    balance_manager_id: ID,
    transactions: &vector<Transaction>,
) {
    transactions.do_ref!<Transaction>(|tx| {
        if (tx.is_credit()) {
            self.accounts[balance_manager_id].credit(tx.amount())
        } else if (tx.is_debit()) {
            self.accounts[balance_manager_id].debit(tx.amount())
        } else {
            // should never happen!
            abort EUnknownTransaction
        }
    });
}

/// Processes the transactions for the history by updating the statistics.
fun process_volumes(self: &mut State, transactions: &vector<Transaction>) {
    transactions.do_ref!<Transaction>(|tx| {
        let amount = tx.amount();
        if (tx.is_credit()) {
            self.process_win(amount);
        } else if (tx.is_debit()) {
            self.process_bet(amount);
        } else {
            // should never happen!
            abort EUnknownTransaction
        }
    });
}

/// Calculates the total fee for the owner based on the transactions
fun calculate_fee(transactions: &vector<Transaction>, house_fee_factor: UQ32_32): u64 {
    let mut total_fee = 0;
    transactions.do_ref!(|tx| {
        if (tx.is_debit()) {
            let fee_amount = int_mul(tx.amount(), house_fee_factor);
            total_fee = total_fee + fee_amount
        }
    });
    total_fee
}

fun activate(self: &mut State) {
    // Can only activate if not activated yet
    assert!(self.is_active == false, EHouseIsAlreadyActive);

    // Activate the state by setting is_active to `true` and moving the stake from inactive_to_active
    self.is_active = true;
    self.active_stake = self.inactive_stake;
    self.inactive_stake = 0;
    self.current_volumes.total_stake_amount = self.active_stake;

    // Event
    emit(HouseActivatedEvent {
        active_stake: self.active_stake
    })
}

fun process_bet(self: &mut State, amount: u64) {
    self.current_volumes.total_bet_amount = self.current_volumes.total_bet_amount + amount;
    self.all_time_bet_amount = self.all_time_bet_amount + (amount as u128);
}

fun process_win(self: &mut State, amount: u64) {
    self.current_volumes.total_win_amount = self.current_volumes.total_win_amount + amount;
    self.all_time_win_amount = self.all_time_win_amount + (amount as u128);
}

fun remove_inactive_stake(self: &mut State, amount: u64) {
    if (self.inactive_stake >= amount) {
        self.inactive_stake = self.inactive_stake - amount;
    } else if (amount - self.inactive_stake <= precision_error_allowance()) {
        // Small rounding errors
        self.inactive_stake = 0;
    } else {
        abort ECannotUnstakeMoreThanStaked
    }
}

fun add_pending_unstake(self: &mut State, amount: u64) {
    self.pending_unstake = self.pending_unstake + amount;
}

/// Stakes `amount` by adding it to the `inactive_stake` balance.
fun add_stake(self: &mut State, amount: u64) {
    self.inactive_stake = self.inactive_stake + amount;
}

/// Desactivates the state by 1) moving the active stake back to inactive and 2) setting is_active to false
fun desactivate(self: &mut State) {
    self.inactive_stake = self.inactive_stake + self.active_stake;
    self.active_stake = 0;
    self.is_active = false;
}

fun new_volumes(): Volumes {
    Volumes {
        total_stake_amount: 0,
        total_bet_amount: 0,
        total_win_amount: 0,
    }
}

fun assert_active(self: &State) {
    assert!(self.is_active == true, EHouseIsNotActive);
}

fun assert_epoch_up_to_date(self: &State, ctx: &TxContext) {
    assert!(self.epoch == ctx.epoch(), EEpochMismatch);
}
