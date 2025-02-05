#[test_only]
module openplay_core::participation_tests;

use openplay_core::core_test_utils::default_house;
use openplay_core::participation;
use sui::test_scenario::begin;
use sui::test_utils::destroy;

#[test]
public fun stake_unstake_ok() {
    let addr = @0xa;
    let mut scenario = begin(addr);

    // Create participation
    let (house, admin_cap) = default_house(scenario.ctx());
    let mut participation = participation::empty(house.id(), scenario.ctx());

    // Stake 10
    participation.add_stake(10, false, scenario.ctx());

    // Should be added to stake because house is not active
    assert!(participation.stake() == 10);
    assert!(participation.pending_stake() == 0);
    assert!(participation.claimable_balance() == 0);

    // Unstake right away
    let (prev_stake, pending_stake_removed) = participation.unstake(false, scenario.ctx());
    assert!(prev_stake == 10);
    assert!(pending_stake_removed == 0);

    assert!(participation.stake() == 0);
    assert!(participation.pending_stake() == 0);
    assert!(participation.claimable_balance() == 10);

    // Stake 20: 10 with inactive house, and 10 with active house
    participation.add_stake(10, false, scenario.ctx());
    // Now the house is supposedly activated
    participation.add_stake(10, true, scenario.ctx());

    assert!(participation.stake() == 10);
    assert!(participation.pending_stake() == 10);
    assert!(participation.claimable_balance() == 10);

    // Advance epoch, should activate the pending stake
    scenario.next_epoch(addr);
    participation.process_end_of_day(scenario.ctx().epoch() - 1, 0, 0, scenario.ctx());

    assert!(participation.stake() == 20);
    assert!(participation.pending_stake() == 0);
    assert!(participation.claimable_balance() == 10);

    // Stake 5 more
    participation.add_stake(5, true, scenario.ctx());

    assert!(participation.stake() == 20);
    assert!(participation.pending_stake() == 5);
    assert!(participation.claimable_balance() == 10);

    // Unstake: 5 should be instant and 20 pending
    assert!(participation.unstake_requested() == false);
    let (prev_stake, pending_stake_removed) = participation.unstake(true, scenario.ctx());

    assert!(pending_stake_removed == 5);
    assert!(prev_stake == 20);
    assert!(participation.unstake_requested() == true);

    assert!(participation.stake() == 20);
    assert!(participation.pending_stake() == 0);
    assert!(participation.claimable_balance() == 15);

    // Advance epoch, should free up the stake
    scenario.next_epoch(addr);
    participation.process_end_of_day(scenario.ctx().epoch() - 1, 0, 0, scenario.ctx());

    assert!(participation.stake() == 0);
    assert!(participation.pending_stake() == 0);
    assert!(participation.claimable_balance() == 35);

    let claimed = participation.claim_all(scenario.ctx());

    assert!(claimed == 35);
    assert!(participation.stake() == 0);
    assert!(participation.pending_stake() == 0);
    assert!(participation.claimable_balance() == 0);

    destroy(participation);
    destroy(house);
    destroy(admin_cap);

    scenario.end();
}

#[test, expected_failure(abort_code = participation::ECancellationWasRequested)]
public fun cannot_unstake_twice() {
    let addr = @0xa;
    let mut scenario = begin(addr);

    // Create participation
    let (house, _admin_cap) = default_house(scenario.ctx());
    let mut participation = participation::empty(house.id(), scenario.ctx());

    // Stake 10 (Active house)
    participation.add_stake(10, true, scenario.ctx());

    // Unstake twice
    participation.unstake(true, scenario.ctx());
    participation.unstake(true, scenario.ctx());
    abort 0
}

#[test, expected_failure(abort_code = participation::ECancellationWasRequested)]
public fun cannot_stake_after_unstake() {
    let addr = @0xa;
    let mut scenario = begin(addr);

    // Create participation
    let (house, _admin_cap) = default_house(scenario.ctx());
    let mut participation = participation::empty(house.id(), scenario.ctx());

    // Stake 10 (Active house)
    participation.add_stake(10, true, scenario.ctx());

    // Unstake
    participation.unstake(true, scenario.ctx());
    // Try to stake again (active)
    participation.add_stake(10, true, scenario.ctx());
    abort 0
}

#[test]
public fun process_ggr_share_ok() {
    let addr = @0xa;
    let mut scenario = begin(addr);

    // Create participation
    let (house, admin_cap) = default_house(scenario.ctx());
    let mut participation = participation::empty(house.id(), scenario.ctx());

    assert!(participation.stake() == 0);
    // Profits should be added to the active stake
    scenario.next_epoch(addr);
    participation.process_end_of_day(0, 10, 0, scenario.ctx());
    assert!(participation.stake() == 10);
    // Losses should be deducted from the active stake
    scenario.next_epoch(addr);
    participation.process_end_of_day(1, 0, 5, scenario.ctx());
    assert!(participation.stake() == 5);
    // Can deduct more from active stake than available (because of precision errors)
    scenario.next_epoch(addr);
    participation.process_end_of_day(2, 0, 6, scenario.ctx());
    assert!(participation.stake() == 0);

    destroy(participation);
    destroy(house);
    destroy(admin_cap);

    scenario.end();
}

#[test]
public fun end_of_day_unstake_ok() {
    let addr = @0xa;
    let mut scenario = begin(addr);

    // Create participation
    let (house, admin_cap) = default_house(scenario.ctx());
    let mut participation = participation::empty(house.id(), scenario.ctx());

    // Stake 10 (inactive house)
    participation.add_stake(10, false, scenario.ctx());

    // Request unstake (active house, so it's pending)
    participation.unstake(true, scenario.ctx());

    assert!(participation.stake() == 10);
    assert!(participation.pending_stake() == 0);
    assert!(participation.claimable_balance() == 0);
    assert!(participation.unstake_requested() == true);

    // Take losses of 6
    scenario.next_epoch(addr);
    participation.process_end_of_day(scenario.ctx().epoch() - 1, 0, 6, scenario.ctx());

    assert!(participation.stake() == 0);
    assert!(participation.pending_stake() == 0);
    assert!(participation.claimable_balance() == 4);
    assert!(participation.unstake_requested() == false);

    destroy(participation);
    destroy(house);
    destroy(admin_cap);

    scenario.end();
}

#[test]
public fun end_of_day_pending_stake_ok() {
    let addr = @0xa;
    let mut scenario = begin(addr);

    // Create participation
    let (house, admin_cap) = default_house(scenario.ctx());
    let mut participation = participation::empty(house.id(), scenario.ctx());

    // Stake 10 (active house)
    participation.add_stake(10, true, scenario.ctx());

    assert!(participation.stake() == 0);
    assert!(participation.pending_stake() == 10);
    assert!(participation.claimable_balance() == 0);

    scenario.next_epoch(addr);
    participation.process_end_of_day(scenario.ctx().epoch() - 1, 0, 0, scenario.ctx());

    assert!(participation.stake() == 10);
    assert!(participation.pending_stake() == 0);
    assert!(participation.claimable_balance() == 0);

    destroy(participation);
    destroy(house);
    destroy(admin_cap);

    scenario.end();
}

#[test, expected_failure(abort_code = participation::EInvalidProfitsOrLosses)]
public fun end_of_day_cannot_bear_more_losses_than_available() {
    let addr = @0xa;
    let mut scenario = begin(addr);

    // Create participation
    let (house, _admin_cap) = default_house(scenario.ctx());
    let mut participation = participation::empty(house.id(), scenario.ctx());

    // Stake 10 (active house)
    participation.add_stake(10, false, scenario.ctx());

    assert!(participation.stake() == 10);
    assert!(participation.pending_stake() == 0);
    assert!(participation.claimable_balance() == 0);

    scenario.next_epoch(addr);
    participation.process_end_of_day(scenario.ctx().epoch() - 1, 0, 50, scenario.ctx());
    abort 0
}

#[test, expected_failure(abort_code = participation::EEpochMismatch)]
public fun cannot_stake_invalid_epoch() {
    let addr = @0xa;
    let mut scenario = begin(addr);

    // Create participation
    let (house, _admin_cap) = default_house(scenario.ctx());
    let mut participation = participation::empty(house.id(), scenario.ctx());

    // Advance epoch
    scenario.next_epoch(addr);
    // Stake 10
    participation.add_stake(10, false, scenario.ctx());
    abort 0
}

#[test, expected_failure(abort_code = participation::EEpochMismatch)]
public fun cannot_unstake_invalid_epoch() {
    let addr = @0xa;
    let mut scenario = begin(addr);

    // Create participation
    let (house, _admin_cap) = default_house(scenario.ctx());
    let mut participation = participation::empty(house.id(), scenario.ctx());
    participation.add_stake(10, false, scenario.ctx());

    // Advance epoch
    scenario.next_epoch(addr);
    // Unstake
    participation.unstake(false, scenario.ctx());
    abort 0
}

#[test, expected_failure(abort_code = participation::EEpochMismatch)]
public fun cannot_process_eod_invalid_epoch() {
    let addr = @0xa;
    let mut scenario = begin(addr);

    // Create participation
    let (house, _admin_cap) = default_house(scenario.ctx());
    let mut participation = participation::empty(house.id(), scenario.ctx());
    participation.add_stake(10, false, scenario.ctx());

    // Advance epoch
    scenario.next_epoch(addr);
    scenario.next_epoch(addr);
    // Unstake
    participation.process_end_of_day(1, 0, 0, scenario.ctx());
    abort 0
}
