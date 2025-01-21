/// The participation module maintains all the house participation state.
/// Resonsible for managing staking, unstaking, and profit/loss sharing.
module openplay_core::participation;

use openplay_core::constants::precision_error_allowance;

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
    active_stake: u64,
    inactive_stake: u64,
    claimable_balance: u64,
    unstake_requested: bool
}

// === Public-View Functions ===
public fun active_stake(self: &Participation): u64 {
    self.active_stake
}

public fun inactive_stake(self: &Participation): u64 {
    self.inactive_stake
}

public fun claimable_balance(self: &Participation): u64 {
    self.claimable_balance
}

public fun house_id(self: &Participation): ID {
    self.house_id
}

// === Public-Mutative Functions ===
public fun destroy_empty(self: Participation, ctx: &mut TxContext) {
    assert!(self.last_updated_epoch == ctx.epoch(), EEpochMismatch);
    assert!(self.active_stake == 0, ENotEmpty);
    assert!(self.inactive_stake == 0, ENotEmpty);
    assert!(self.claimable_balance == 0, ENotEmpty);

    let Participation {id, house_id: _, last_updated_epoch: _, active_stake: _, inactive_stake: _, claimable_balance: _, unstake_requested: _} = self;
    object::delete(id);
}


// === Public-Package Functions ===
/// Create a new house participation object. The stake is added to the `inactive_stake` and is activated in the next epoch.
public(package) fun empty(house_id: ID, ctx: &mut TxContext): Participation {
    Participation {
        id: object::new(ctx),
        house_id,
        last_updated_epoch: ctx.epoch(),
        active_stake: 0,
        inactive_stake: 0,
        claimable_balance: 0,
        unstake_requested: false
    }
}

public(package) fun add_inactive_stake(self: &mut Participation, amount: u64, ctx: &TxContext) {
    assert!(self.last_updated_epoch == ctx.epoch(), EEpochMismatch);
    assert!(self.unstake_requested == false, ECancellationWasRequested);
    self.inactive_stake = self.inactive_stake + amount;
} 

/// Unstakes the account. This does two things
/// 1) The inactive stake is returned immediately
/// 2) The active stake is requested to be unstaked, and will be returned at the next epoch
/// Fails if an unstake action was already performed this epoch.
/// Returns a tuple (unstake_immediately, pending_unstake)
public(package) fun unstake(self: &mut Participation, ctx: &TxContext): (u64, u64) {
    assert!(self.unstake_requested == false, ECancellationWasRequested);
    assert!(self.last_updated_epoch == ctx.epoch(), EEpochMismatch);

    let prev_inactive_stake = self.inactive_stake;

    // Inactive stake
    if (self.inactive_stake > 0) {
        self.claimable_balance = self.claimable_balance + self.inactive_stake;
        self.inactive_stake = 0;
    };

    // Active stake
    if (self.active_stake > 0) {
        self.unstake_requested = true; // Only set this to true when there is active stake, such that we can still change our mind between staking and unstaking during an epoch.
    };

    return (prev_inactive_stake, self.active_stake)
}

public(package) fun process_end_of_day(self: &mut Participation, epoch: u64, profits: u64, losses: u64,  ctx: &TxContext) {
    assert!(profits == 0 || losses == 0, EInvalidGgrShare);
    assert!(self.last_updated_epoch == epoch, EEpochMismatch);
    assert!(ctx.epoch() > self.last_updated_epoch, EEpochHasNotFinishedYet);
    if (profits > 0) {
        self.active_stake = self.active_stake + profits;
    } else if (losses > 0) {
        if (self.active_stake >= losses){
            self.active_stake = self.active_stake - losses;
        }
        else if (losses - self.active_stake <= precision_error_allowance()){
            // Small rounding errors
            self.active_stake = 0;
        }
        else {
            abort EInvalidProfitsOrLosses
        }
    };
    // Unlock the staked amount
    if (self.unstake_requested) {
        self.claimable_balance = self.claimable_balance + self.active_stake;
        self.active_stake = 0;
    };
    // Activate the stake that was waiting for activation
    self.active_stake = self.active_stake + self.inactive_stake;
    self.inactive_stake = 0;
    self.unstake_requested = false;
    self.last_updated_epoch = self.last_updated_epoch + 1;
}

public(package) fun current_state(self: &Participation): (u64, u64) {
    (self.last_updated_epoch, self.active_stake)
}

public(package) fun claim_all(self: &mut Participation, ctx: &TxContext): u64 {
    assert!(self.last_updated_epoch == ctx.epoch(), EEpochMismatch);
    let claimable = self.claimable_balance;
    self.claimable_balance = 0;
    claimable
}