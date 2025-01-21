#[test_only]
module openplay_core::history_tests;

use openplay_core::history::{Self, add_pending_stake, add_pending_unstake, unstake_immediately};
use std::uq32_32::{int_mul, from_quotient, add, from_int, sub};
use sui::test_scenario::begin;
use sui::test_utils::destroy;

#[test]
public fun pending_stake_tests() {
    let addr = @0xa;
    let mut scenario = begin(addr);

    // Create empty history
    let mut history = history::empty(scenario.ctx());
    assert!(history.pending_stake() == 0);
    assert!(history.pending_unstake() == 0);

    history.add_pending_stake(100);
    assert!(history.pending_stake() == 100);
    assert!(history.pending_unstake() == 0);

    history.add_pending_unstake(50);
    assert!(history.pending_stake() == 100);
    assert!(history.pending_unstake() == 50);

    history.unstake_immediately(20);
    assert!(history.pending_stake() == 80);
    assert!(history.pending_unstake() == 50);

    destroy(history);

    scenario.end();
}

#[test, expected_failure(abort_code = history::ECannotUnstakeMoreThanStaked)]
public fun unstake_too_much() {
    let addr = @0xa;
    let mut scenario = begin(addr);

    let mut history = history::empty(scenario.ctx());
    history.add_pending_stake(100);
    history.unstake_immediately(101);

    abort 0
}

#[test, expected_failure(abort_code = history::EEndOfDayNotAvailable)]
public fun end_of_day_empty() {
    let addr = @0xa;
    let mut scenario = begin(addr);

    // Create empty history
    let history = history::empty(scenario.ctx());
    history.end_of_day_for_epoch(scenario.ctx().epoch());

    abort 0
}

#[test]
public fun end_of_day_available() {
    let addr = @0xA;
    let mut scenario = begin(addr);

    // Create empty history
    let mut history = history::empty(scenario.ctx());

    // Process end of day for epoch 0: profits of 100 and end of day balance of 200
    scenario.next_epoch(addr);
    history.process_end_of_day(0, 100, 0, scenario.ctx());

    // Check data
    let eod = history.end_of_day_for_epoch(scenario.ctx().epoch() - 1);
    assert!(eod.day_losses() == 0);
    assert!(eod.day_profits() == 100);

    destroy(history);
    scenario.end();
}

#[test, expected_failure(abort_code = history::EEpochHasNotFinishedYet)]
public fun cannot_process_eod_before_epoch_ended() {
    let addr = @0xA;
    let mut scenario = begin(addr);

    let mut history = history::empty(scenario.ctx());
    history.process_end_of_day(0, 100, 0, scenario.ctx());

    abort 0
}

#[test, expected_failure(abort_code = history::EEpochMismatch)]
public fun cannot_process_eod_for_wrong_epoch() {
    let addr = @0xA;
    let mut scenario = begin(addr);
    // Initialize history to epoch 0
    let mut history = history::empty(scenario.ctx());

    // Advance to epoch 2
    scenario.next_epoch(addr);
    scenario.next_epoch(addr);

    // Process eod for epoch 1
    history.process_end_of_day(1, 100, 0, scenario.ctx());

    abort 0
}

#[test, expected_failure(abort_code = history::EInvalidProfitsOrLosses)]
public fun cannot_process_eod_wrong_profits_or_losses() {
    let addr = @0xA;
    let mut scenario = begin(addr);
    // Initialize history to epoch 0
    let mut history = history::empty(scenario.ctx());

    // Advance to epoch 1
    scenario.next_epoch(addr);
    history.process_end_of_day(0, 100, 100, scenario.ctx());

    abort 0
}

#[test]
public fun stake_amount_correctly_transferred_basic() {
    let addr = @0xA;
    let mut scenario = begin(addr);

    // Initialize history to epoch 0
    let mut history = history::empty(scenario.ctx());

    // Add pending stake of 100
    history.add_pending_stake(100);
    assert!(history.current_stake() == 0);
    assert!(history.pending_stake() == 100);

    // Transfer next epoch
    scenario.next_epoch(addr);
    history.process_end_of_day(scenario.ctx().epoch() - 1, 0, 0, scenario.ctx());
    assert!(history.current_stake() == 100);
    assert!(history.pending_stake() == 0);

    // Add pending unstake of 50
    history.add_pending_unstake(50);

    // Transfer next epoch
    scenario.next_epoch(addr);
    history.process_end_of_day(scenario.ctx().epoch() - 1, 0, 0, scenario.ctx());
    assert!(history.current_stake() == 50);
    assert!(history.pending_stake() == 0);

    // Add pending stake and immediately unstake a part of it
    history.add_pending_stake(100);
    history.unstake_immediately(80);

    // Transfer next epoch
    scenario.next_epoch(addr);
    history.process_end_of_day(scenario.ctx().epoch() - 1, 0, 0, scenario.ctx());
    assert!(history.current_stake() == 70);
    assert!(history.pending_stake() == 0);
    assert!(history.pending_unstake() == 0);

    // Transfer next epoch with some profits
    scenario.next_epoch(addr);
    history.process_end_of_day(scenario.ctx().epoch() - 1, 10, 0, scenario.ctx());
    assert!(history.current_stake() == 80); // added to the current stake portion

    // Transfer next epoch with some losses
    scenario.next_epoch(addr);
    history.process_end_of_day(scenario.ctx().epoch() - 1, 0, 20, scenario.ctx());
    assert!(history.current_stake() == 60); // dedcued from current stake portion

    destroy(history);
    scenario.end();
}

#[test]
public fun stake_amount_correctly_transferred_profits() {
    let addr = @0xA;
    let mut scenario = begin(addr);

    // Initialize history to epoch 0
    let mut history = history::empty(scenario.ctx());

    // Add pending stake of 100
    history.add_pending_stake(100);
    assert!(history.current_stake() == 0);
    assert!(history.pending_stake() == 100);

    // Transfer next epoch
    scenario.next_epoch(addr);
    history.process_end_of_day(scenario.ctx().epoch() - 1, 0, 0, scenario.ctx());
    assert!(history.current_stake() == 100);
    assert!(history.pending_stake() == 0);

    // Now do a complete setup, starting from a stake of 100
    history.add_pending_stake(30); // 30 being added
    history.add_pending_unstake(10); // 10 being removed
    history.unstake_immediately(10); // 10 cancelled immediately

    // Transfer next epoch with profits of 30
    scenario.next_epoch(addr);
    history.process_end_of_day(scenario.ctx().epoch() - 1, 30, 0, scenario.ctx());

    // 10 stake is being removed, but this 10 stake has also accrued profits
    // 10 stake is equal to 10% in our example, so they take a share of 3 on the profits
    // this means that 13 should be unstaked
    // We are adding 20 stake, so sums up to +7
    // Plus 30 of the profits

    let roi = from_quotient(30, 100);
    let expected_value =
        100 // From last epoch
    + 30 // The distributed profits
    - int_mul(10, add(from_int(1), roi))  // The unstaked amount
    + 20; // The new added stake

    // Note: this fails when you replace it by 137
    // In this particular example, because of precision errors, the amount is rounded up to 138
    assert!(history.current_stake() == expected_value);

    destroy(history);
    scenario.end();
}

#[test]
public fun stake_amount_correctly_transferred_losses() {
    let addr = @0xA;
    let mut scenario = begin(addr);

    // Initialize history to epoch 0
    let mut history = history::empty(scenario.ctx());

    // Add pending stake of 100
    history.add_pending_stake(100);
    assert!(history.current_stake() == 0);
    assert!(history.pending_stake() == 100);

    // Transfer next epoch
    scenario.next_epoch(addr);
    history.process_end_of_day(scenario.ctx().epoch() - 1, 0, 0, scenario.ctx());
    assert!(history.current_stake() == 100);
    assert!(history.pending_stake() == 0);

    // Now do a complete setup, starting from a stake of 100
    history.add_pending_stake(30); // 30 being added
    history.add_pending_unstake(10); // 10 being removed
    history.unstake_immediately(10); // 10 cancelled immediately

    // Transfer next epoch with losses of 30
    scenario.next_epoch(addr);
    history.process_end_of_day(scenario.ctx().epoch() - 1, 0, 30, scenario.ctx());

    // 10 stake is being removed, but this 10 stake has also accrued losses
    // 10 stake is equal to 10% in our example, so they take a loss of 3
    // this means that only 7 should be unstaked and returned to the stakers
    // We are adding 20 stake, so sums up to +13
    // Minus 30 of the profits
    // This gives 83

    let negative_roi = from_quotient(30, 100);
    let expected_value =
        100 // From last epoch
    - 30 // The distributed losses
    - int_mul(10, sub(from_int(1), negative_roi))  // The unstaked amount
    + 20; // The new added stake

    // Note: this also succeeds if you replace it by 83
    // In this particular example, there are no precision errors, but this is not a guarantee
    assert!(history.current_stake() == expected_value);

    destroy(history);
    scenario.end();
}

#[test]
public fun stake_amount_correctly_transferred_full_unstake_profits() {
    let addr = @0xA;
    let mut scenario = begin(addr);

    // Initialize history to epoch 0
    let mut history = history::empty(scenario.ctx());

    // Add pending stake of 100
    history.add_pending_stake(100);
    assert!(history.current_stake() == 0);
    assert!(history.pending_stake() == 100);

    // Transfer next epoch
    scenario.next_epoch(addr);
    history.process_end_of_day(scenario.ctx().epoch() - 1, 0, 0, scenario.ctx());
    assert!(history.current_stake() == 100);
    assert!(history.pending_stake() == 0);

    // Now the staker wish to fully unstake
    history.add_pending_unstake(100);
    // 5 new stake is coming in
    history.add_pending_stake(5);

    // Transfer next epoch with some profits
    scenario.next_epoch(addr);
    history.process_end_of_day(scenario.ctx().epoch() - 1, 7, 0, scenario.ctx());

    let roi = from_quotient(7, 100);
    let expected_value =
        100 // From last epoch
    + 7 // The distributed profits
    - int_mul(100, add(from_int(1), roi))  // The unstaked amount
    + 5; // The new added stake

    // !!! This should be 5 but instead of 107 only 106 is being unstaked because of precision errors, leaving 1 in the stake balance
    assert!(history.current_stake() == 6);
    assert!(history.current_stake() == expected_value);

    destroy(history);
    scenario.end();
}

#[test]
public fun stake_amount_correctly_transferred_full_unstake_losses() {
    let addr = @0xA;
    let mut scenario = begin(addr);

    // Initialize history to epoch 0
    let mut history = history::empty(scenario.ctx());

    // Add pending stake of 100
    history.add_pending_stake(100);
    assert!(history.current_stake() == 0);
    assert!(history.pending_stake() == 100);

    // Transfer next epoch
    scenario.next_epoch(addr);
    history.process_end_of_day(scenario.ctx().epoch() - 1, 0, 0, scenario.ctx());
    assert!(history.current_stake() == 100);
    assert!(history.pending_stake() == 0);

    // Now the staker wish to fully unstake
    history.add_pending_unstake(100);
    // 5 new stake is coming in
    history.add_pending_stake(5);

    // Transfer next epoch with some profits
    scenario.next_epoch(addr);
    history.process_end_of_day(scenario.ctx().epoch() - 1, 0, 7, scenario.ctx());

    let negative_roi = from_quotient(7, 100);
    let expected_value =
        100 // From last epoch
    - 7 // The distributed losses
    - int_mul(100, sub(from_int(1), negative_roi))  // The unstaked amount
    + 5; // The new added stake

    assert!(history.current_stake() == expected_value);
    assert!(history.current_stake() == 5);

    destroy(history);
    scenario.end();
}

#[test]
public fun stake_amount_correctly_transferred_bankrupt() {
    let addr = @0xA;
    let mut scenario = begin(addr);

    // Initialize history to epoch 0
    let mut history = history::empty(scenario.ctx());

    // Add pending stake of 100
    history.add_pending_stake(100);
    assert!(history.current_stake() == 0);
    assert!(history.pending_stake() == 100);

    // Transfer next epoch
    scenario.next_epoch(addr);
    history.process_end_of_day(scenario.ctx().epoch() - 1, 0, 0, scenario.ctx());
    assert!(history.current_stake() == 100);
    assert!(history.pending_stake() == 0);

    // 5 new stake is coming in
    history.add_pending_stake(5);

    // Transfer next epoch with bankrupt losses
    // We make the losses even more than the full 100. This is only possible because of precision errors in practice
    scenario.next_epoch(addr);
    history.process_end_of_day(scenario.ctx().epoch() - 1, 0, 101, scenario.ctx());

    // The new stakers should never be taking any sort of losses from the previous epoch
    assert!(history.current_stake() == 5);

    destroy(history);
    scenario.end();
}

#[test]
public fun calculate_ggr_share_losses() {
    let addr = @0xA;
    let mut scenario = begin(addr);

    // Initialize history to epoch 0
    let mut history = history::empty(scenario.ctx());

    // Add pending stake of 100
    history.add_pending_stake(100);

    // Transfer next epoch to activate this stake
    // No profits or losses
    scenario.next_epoch(addr);
    history.process_end_of_day(scenario.ctx().epoch() - 1, 0, 0, scenario.ctx());

    // Transfer next epoch with losses of 31
    scenario.next_epoch(addr);
    history.process_end_of_day(scenario.ctx().epoch() - 1, 0, 31, scenario.ctx());

    let (profits_no_stake, losses_no_stake) = history.calculate_ggr_share(
        scenario.ctx().epoch() - 1,
        0,
    );
    assert!(losses_no_stake == 0);
    assert!(profits_no_stake == 0);

    let volume = history.volume_for_epoch(scenario.ctx().epoch() - 1);
    let eod = history.end_of_day_for_epoch(scenario.ctx().epoch() - 1);
    assert!(volume.total_stake_amount() == 100);
    assert!(eod.day_losses() == 31);
    assert!(eod.day_profits() == 0);

    let (profits_full_stake, losses_full_stake) = history.calculate_ggr_share(
        scenario.ctx().epoch() - 1,
        100,
    );
    assert!(losses_full_stake == 31);
    assert!(profits_full_stake == 0);

    let stake_range = vector[1, 7, 13, 21, 25, 30, 40, 60, 80, 99];
    stake_range.do!(|stake| {
        let expected_loss = int_mul(31, from_quotient(stake, 100));
        let (profits, losses) = history.calculate_ggr_share(scenario.ctx().epoch() - 1, stake);
        assert!(profits == 0);
        assert!(losses == expected_loss);
    });

    destroy(history);
    scenario.end();
}

#[test]
public fun calculate_ggr_share_profits() {
    let addr = @0xA;
    let mut scenario = begin(addr);

    // Initialize history to epoch 0
    let mut history = history::empty(scenario.ctx());

    // Add pending stake of 100
    history.add_pending_stake(100);

    // Transfer next epoch to activate this stake
    // No profits or losses
    scenario.next_epoch(addr);
    history.process_end_of_day(scenario.ctx().epoch() - 1, 0, 0, scenario.ctx());

    // Transfer next epoch with profits of 81
    scenario.next_epoch(addr);
    history.process_end_of_day(scenario.ctx().epoch() - 1, 81, 0, scenario.ctx());

    let (profits_no_stake, losses_no_stake) = history.calculate_ggr_share(
        scenario.ctx().epoch() - 1,
        0,
    );
    assert!(losses_no_stake == 0);
    assert!(profits_no_stake == 0);

    let volume = history.volume_for_epoch(scenario.ctx().epoch() - 1);
    let eod = history.end_of_day_for_epoch(scenario.ctx().epoch() - 1);
    assert!(volume.total_stake_amount() == 100);
    assert!(eod.day_losses() == 0);
    assert!(eod.day_profits() == 81);

    let (profits_full_stake, losses_full_stake) = history.calculate_ggr_share(
        scenario.ctx().epoch() - 1,
        100,
    );
    assert!(losses_full_stake == 0);
    assert!(profits_full_stake == 81);

    let stake_range = vector[1, 7, 13, 21, 25, 30, 40, 60, 80, 99];
    stake_range.do!(|stake| {
        let expected_profit = int_mul(81, from_quotient(stake, 100));
        let (profits, losses) = history.calculate_ggr_share(scenario.ctx().epoch() - 1, stake);
        assert!(profits == expected_profit);
        assert!(losses == 0);
    });

    destroy(history);
    scenario.end();
}
