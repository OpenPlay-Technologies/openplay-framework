#[test_only]
module openplay_core::participation_tests;

use openplay_core::participation::{Self};
use sui::test_scenario::begin;
use sui::test_utils::destroy;
use openplay_core::house::empty_house_for_testing;

#[test]
public fun stake_unstake_ok() {
    let addr = @0xa;
    let mut scenario = begin(addr);

    // Create participation
    let house = empty_house_for_testing(0, 0, scenario.ctx());
    let mut participation = participation::empty(house.id(), scenario.ctx());

    // Stake 10
    participation.add_inactive_stake(10, scenario.ctx());
    // Active stake should be 0 because it is still pending
    assert!(participation.active_stake() == 0);
    assert!(participation.inactive_stake() == 10);
    // Unstake right away
    let (unstake_immediately, pending_unstake) = participation.unstake(scenario.ctx());
    assert!(unstake_immediately == 10);
    assert!(pending_unstake == 0);
    assert!(participation.claimable_balance() == 10);
    assert!(participation.inactive_stake() == 0);

    // Stake 10
    participation.add_inactive_stake(10, scenario.ctx());
    // Advance epoch
    scenario.next_epoch(addr);
    participation.process_end_of_day(0, 0, 0, scenario.ctx());
    // Active stake should be updated now
    assert!(participation.active_stake() == 10);
    assert!(participation.inactive_stake() == 0);
    // Stake 5 more
    participation.add_inactive_stake(5, scenario.ctx());
    assert!(participation.active_stake() == 10);
    assert!(participation.inactive_stake() == 5);
    // Unstake: 5 should be instant and 10 pending
    let (unstake_immediately, pending_unstake) = participation.unstake(scenario.ctx());
    assert!(unstake_immediately == 5);
    assert!(pending_unstake == 10);
    assert!(participation.active_stake() == 10);
    assert!(participation.claimable_balance() == 15);
    assert!(participation.inactive_stake() == 0);
    // Advance epoch, should free up the stake
    scenario.next_epoch(addr);
    participation.process_end_of_day(1, 0, 0, scenario.ctx());
    assert!(participation.claimable_balance() == 25);
    
    destroy(participation);
    destroy(house);
    scenario.end();
}

#[test, expected_failure(abort_code = participation::ECancellationWasRequested)]
public fun cannot_unstake_twice() {
    let addr = @0xa;
    let mut scenario = begin(addr);

    // Create participation
    let house = empty_house_for_testing(0, 0, scenario.ctx());
    let mut participation = participation::empty(house.id(), scenario.ctx());

    // Stake 10
    participation.add_inactive_stake(10, scenario.ctx());
    // Advance epoch
    scenario.next_epoch(addr);
    participation.process_end_of_day(0, 0, 0, scenario.ctx());

    // Unstake twice
    participation.unstake(scenario.ctx());
    participation.unstake(scenario.ctx());
    abort 0
}

#[test, expected_failure(abort_code = participation::ECancellationWasRequested)]
public fun cannot_stake_after_unstake() {
    let addr = @0xa;
    let mut scenario = begin(addr);

    // Create participation
    let house = empty_house_for_testing(0, 0, scenario.ctx());
    let mut participation = participation::empty(house.id(), scenario.ctx());

    // Stake 10
    participation.add_inactive_stake(10, scenario.ctx());
    // Advance epoch
    scenario.next_epoch(addr);
    participation.process_end_of_day(0, 0, 0, scenario.ctx());

    // Unstake twice
    participation.unstake(scenario.ctx());
    participation.add_inactive_stake(10, scenario.ctx());
    abort 0
}

#[test]
public fun process_ggr_share_ok() {
    let addr = @0xa;
    let mut scenario = begin(addr);

    // Create participation
    let house = empty_house_for_testing(0, 0, scenario.ctx());
    let mut participation = participation::empty(house.id(), scenario.ctx());

    assert!(participation.active_stake() == 0);
    // Profits should be added to the active stake
    scenario.next_epoch(addr);
    participation.process_end_of_day(0, 10, 0, scenario.ctx());
    assert!(participation.active_stake() == 10);
    // Losses should be deducted from the active stake
    scenario.next_epoch(addr);
    participation.process_end_of_day(1, 0, 5, scenario.ctx());
    assert!(participation.active_stake() == 5);
    // Can deduct more from active stake than available (because of precision errors)
    scenario.next_epoch(addr);
    participation.process_end_of_day(2, 0, 6, scenario.ctx());
    assert!(participation.active_stake() == 0);

    destroy(participation);
    destroy(house);
    scenario.end();
}

#[test, expected_failure(abort_code = participation::EEpochMismatch)]
public fun cannot_stake_invalid_epoch() {
    let addr = @0xa;
    let mut scenario = begin(addr);

    // Create participation
    let house = empty_house_for_testing(0, 0, scenario.ctx());
    let mut participation = participation::empty(house.id(), scenario.ctx());

    // Advance epoch
    scenario.next_epoch(addr);
    // Stake 10
    participation.add_inactive_stake(10, scenario.ctx());
    abort 0
}

#[test, expected_failure(abort_code = participation::EEpochMismatch)]
public fun cannot_unstake_invalid_epoch() {
    let addr = @0xa;
    let mut scenario = begin(addr);

    // Create participation
    let house = empty_house_for_testing(0, 0, scenario.ctx());
    let mut participation = participation::empty(house.id(), scenario.ctx());
    participation.add_inactive_stake(10, scenario.ctx());

    // Advance epoch
    scenario.next_epoch(addr);
    // Unstake
    participation.unstake(scenario.ctx());
    abort 0
}

#[test, expected_failure(abort_code = participation::EEpochMismatch)]
public fun cannot_process_eod_invalid_epoch() {
    let addr = @0xa;
    let mut scenario = begin(addr);

    // Create participation
    let house = empty_house_for_testing(0, 0, scenario.ctx());
    let mut participation = participation::empty(house.id(), scenario.ctx());
    participation.add_inactive_stake(10, scenario.ctx());

    // Advance epoch
    scenario.next_epoch(addr);
    scenario.next_epoch(addr);
    // Unstake
    participation.process_end_of_day(1, 0, 0, scenario.ctx());
    abort 0
}