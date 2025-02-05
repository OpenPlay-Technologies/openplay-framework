/// The participation module maintains all the house participation state.
/// Resonsible for managing staking, unstaking, and profit/loss sharing.
module openplay_core::participation;

use openplay_core::constants::precision_error_allowance;
use sui::event::emit;

// == Errors ==
const EInvalidGgrShare: u64 = 1;
const ECancellationWasRequested: u64 = 2;
const EEpochMismatch: u64 = 3;
const EEpochHasNotFinishedYet: u64 = 4;
const EInvalidProfitsOrLosses: u64 = 5;
const ENotEmpty: u64 = 6;

// === Structs ===
public struct Participation has key, store {
    id: UID,
    house_id: ID,
    last_updated_epoch: u64,
    stake: u64, // Stake that is currently counting towards profits/loss sharing
    pending_stake: u64, // Pending stake is stake that needs to wait until the end of the epoch to become active
    claimable_balance: u64,
    unstake_requested: bool,
}

public struct ParticipationCreatedEvent has copy, drop {
    participation_id: ID
}

public struct ParticipationRemovedEvent has copy, drop {
    participation_id: ID
}

public struct StakeAddedEvent has copy, drop {
    participation_id: ID,
    amount: u64,
    pending: bool,
}

public struct StakeRemovedEvent has copy, drop {
    participation_id: ID,
    amount: u64,
    pending_stake_removed: u64,
}

public struct ParticipationEndOfDayProcessedEvent has copy, drop {
    participation_id: ID,
    profits: u64,
    losses: u64
}

// === Public-View Functions ===
public fun stake(self: &Participation): u64 {
    self.stake
}

public fun pending_stake(self: &Participation): u64 {
    self.pending_stake
}

public fun claimable_balance(self: &Participation): u64 {
    self.claimable_balance
}

public fun house_id(self: &Participation): ID {
    self.house_id
}

public fun last_updated_epoch(self: &Participation): u64 {
    self.last_updated_epoch
}

public fun unstake_requested(self: &Participation): bool {
    self.unstake_requested
}

public fun id(self: &Participation): ID {
    self.id.to_inner()
}

// === Public-Mutative Functions ===
public fun destroy_empty(self: Participation, ctx: &mut TxContext) {
    assert!(self.last_updated_epoch == ctx.epoch(), EEpochMismatch);
    assert!(self.stake == 0, ENotEmpty);
    assert!(self.claimable_balance == 0, ENotEmpty);

    let Participation {
        id,
        house_id: _,
        last_updated_epoch: _,
        stake: _,
        pending_stake: _,
        claimable_balance: _,
        unstake_requested: _,
    } = self;

    // Event
    emit(ParticipationRemovedEvent {
        participation_id: id.to_inner()
    });

    object::delete(id);
}

// === Public-Package Functions ===
/// Create a new house participation object. The stake is added to the `inactive_stake` and is activated in the next epoch.
public(package) fun empty(house_id: ID, ctx: &mut TxContext): Participation {
    let participation = Participation {
        id: object::new(ctx),
        house_id,
        last_updated_epoch: ctx.epoch(),
        stake: 0,
        pending_stake: 0,
        claimable_balance: 0,
        unstake_requested: false,
    };

    // Event
    emit(ParticipationCreatedEvent {
        participation_id: participation.id()
    });

    participation
}

/// Adds stake to the participation.
/// If the house is active, then it will be added to the `pending_stake` which wil be activated in the next epoch.
/// If the house is not active, then it will be added to `stake`.
public(package) fun add_stake(
    self: &mut Participation,
    amount: u64,
    is_active: bool,
    ctx: &TxContext,
) {
    assert!(self.last_updated_epoch == ctx.epoch(), EEpochMismatch);
    assert!(self.unstake_requested == false, ECancellationWasRequested);

    if (is_active) {
        self.pending_stake = self.pending_stake + amount;
    } else {
        self.stake = self.stake + amount;
    };

    // Event
    emit(StakeAddedEvent {
        participation_id: self.id(),
        amount: amount,
        pending: is_active,
    });
}

/// Unstakes the account. This does one of two things
/// - If the house is not active, then the stake is immediately moved to the claimable balance.
/// - If the house is active, then `unstake_requested` is set to `true` and the funds will be available after the end
/// The pending_stake is always moved to the claimable balance because it was not active yet.
/// Fails if an unstake action was already performed this epoch.
/// Returns (prev_stake, pending_stake_removed)
public(package) fun unstake(
    self: &mut Participation,
    is_active: bool,
    ctx: &TxContext,
): (u64, u64) {
    assert!(self.unstake_requested == false, ECancellationWasRequested);
    assert!(self.last_updated_epoch == ctx.epoch(), EEpochMismatch);

    // If the game is active we need to set `unstake_requested` to `true` and wait until the rest of the epoch to claim it.
    // Otherwise the stake can be moved to the claimable balance
    let prev_stake = self.stake;
    if (is_active) {
        self.unstake_requested = true;
    } else {
        self.claimable_balance = self.claimable_balance + self.stake;
        self.stake = 0;
    };

    // Unstake the pending stake
    let pending_stake_removed = self.pending_stake;
    self.claimable_balance = self.claimable_balance + pending_stake_removed;
    self.pending_stake = 0;

    // Evemt
    emit(StakeRemovedEvent {
        participation_id: self.id(),
        amount: prev_stake,
        pending_stake_removed,
    });

    (prev_stake, pending_stake_removed)
}

/// Processes the profits or losses for the provided epoch by adding/substracting them to/from the stake.
/// Additionally, pending stake is activated (added to the stake balance) and if an unstake was requested then the active take is added to the claimable balance.
/// Only the `last_updated_epoch` can be ended.
/// Fails if profits AND losses both contain a value.
public(package) fun process_end_of_day(
    self: &mut Participation,
    epoch: u64,
    profits: u64,
    losses: u64,
    ctx: &TxContext,
) {
    assert!(profits == 0 || losses == 0, EInvalidGgrShare);
    assert!(self.last_updated_epoch == epoch, EEpochMismatch);
    assert!(ctx.epoch() > self.last_updated_epoch, EEpochHasNotFinishedYet);
    if (profits > 0) {
        self.stake = self.stake + profits;
    } else if (losses > 0) {
        if (self.stake >= losses) {
            self.stake = self.stake - losses;
        } else if (losses - self.stake <= precision_error_allowance()) {
            // Small rounding errors
            self.stake = 0;
        } else {
            abort EInvalidProfitsOrLosses
        }
    };
    // Unlock the staked amount
    if (self.unstake_requested) {
        self.claimable_balance = self.claimable_balance + self.stake;
        self.stake = 0;
    };
    // Activate the pending stake that was waiting for activation
    self.stake = self.stake + self.pending_stake;
    self.pending_stake = 0;
    self.unstake_requested = false;
    self.last_updated_epoch = self.last_updated_epoch + 1;

    // Event
    emit(ParticipationEndOfDayProcessedEvent {
        participation_id: self.id(),
        profits,
        losses
    });
}

/// Returns the current state of the participation
/// (last_updated_epoch, stake, pending_stake)
public(package) fun current_state(self: &Participation): (u64, u64, u64) {
    (self.last_updated_epoch, self.stake, self.pending_stake)
}

public(package) fun claim_all(self: &mut Participation, ctx: &TxContext): u64 {
    assert!(self.last_updated_epoch == ctx.epoch(), EEpochMismatch);
    let claimable = self.claimable_balance;
    self.claimable_balance = 0;
    claimable
}
