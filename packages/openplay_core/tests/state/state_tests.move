#[test_only]
module openplay_core::state_tests;

use openplay_core::balance_manager;
use openplay_core::state;
use openplay_core::transaction::{bet, win};
use std::option::{some, none};
use std::uq32_32::{int_mul, from_quotient, add, from_int, sub};
use sui::test_scenario::begin;
use sui::test_utils::destroy;

#[test]
public fun transactions_process_referral_fee_ok() {
    let addr = @0xa;
    let referral_fee_factor = from_quotient(1, 100);
    let house_fee_factor = from_quotient(3, 100);
    let protocol_fee_factor = from_quotient(7, 100);
    let mut scenario = begin(addr);

    // Initialize state and balance manager
    let mut state = state::new(scenario.ctx());
    let (bm, bm_cap) = balance_manager::new(scenario.ctx());

    // Activate the state so it can process transactions
    assert!(state.maybe_activate(0, scenario.ctx()));

    // Process transactions: total bet of 10 and win of 5
    let txs = vector[bet(10), bet(0), win(5), win(0)];
    let (
        credit_balance,
        debit_balance,
        house_fee,
        protocol_fee,
        referral_fee,
    ) = state.process_transactions(
        &txs,
        bm.id(),
        house_fee_factor,
        protocol_fee_factor,
        some(referral_fee_factor),
        scenario.ctx(),
    );
    assert!(credit_balance == 5);
    assert!(debit_balance == 10);
    assert!(house_fee == int_mul(10, house_fee_factor));
    assert!(referral_fee == int_mul(10, referral_fee_factor));
    assert!(protocol_fee == int_mul(10, protocol_fee_factor));

    destroy(bm);
    destroy(state);
    destroy(bm_cap);
    scenario.end();
}

#[test]
public fun transactions_process_ok() {
    let addr = @0xa;
    let house_fee_factor = from_quotient(3, 100);
    let protocol_fee_factor = from_quotient(7, 100);
    let mut scenario = begin(addr);

    // Initialize state and balance manager
    let mut state = state::new(scenario.ctx());
    let (bm, bm_cap) = balance_manager::new(scenario.ctx());

    // Activate the state so it can process transactions
    assert!(state.maybe_activate(0, scenario.ctx()));

    // Process transactions: total bet of 10 and win of 5
    let txs = vector[bet(10), bet(0), win(5), win(0)];
    let (
        credit_balance,
        debit_balance,
        house_fee,
        protocol_fee,
        referral_fee,
    ) = state.process_transactions(
        &txs,
        bm.id(),
        house_fee_factor,
        protocol_fee_factor,
        none(),
        scenario.ctx(),
    );
    // Assert account balance
    assert!(credit_balance == 5);
    assert!(debit_balance == 10);
    // Assert fees
    assert!(house_fee == int_mul(10, house_fee_factor));
    assert!(referral_fee == 0);
    assert!(protocol_fee == int_mul(10, protocol_fee_factor));
    // Assert volumes
    assert!(state.current_volumes().total_bet_amount() == 10);
    assert!(state.current_volumes().total_win_amount() == 5);
    assert!(state.all_time_bet_amount() == 10);
    assert!(state.all_time_win_amount() == 5);

    destroy(bm);
    destroy(state);
    destroy(bm_cap);
    scenario.end();
}

#[test]
public fun stake_unstake_tests() {
    let addr = @0xa;
    let mut scenario = begin(addr);

    // Create empty history
    let mut state = state::new(scenario.ctx());

    // Stake 10
    state.process_stake(10, scenario.ctx());

    assert!(state.inactive_stake() == 10);
    assert!(state.active_stake() == 0);
    assert!(state.pending_unstake() == 0);

    // Stake 10 more
    state.process_stake(10, scenario.ctx());

    assert!(state.inactive_stake() == 20);
    assert!(state.active_stake() == 0);
    assert!(state.pending_unstake() == 0);

    // Activate the state
    assert!(state.maybe_activate(0, scenario.ctx()));

    // Stake 10 more
    state.process_stake(10, scenario.ctx());

    assert!(state.inactive_stake() == 10);
    assert!(state.active_stake() == 20);
    assert!(state.pending_unstake() == 0);

    // Unstake: 4 from pending (immediately) and 6 from active (pending until end of epoch)
    state.process_unstake(6, 4, scenario.ctx());

    assert!(state.inactive_stake() == 6); // 4 stake is immediately removed because it was still pending
    assert!(state.active_stake() == 20); // active stake can never change throughout a cycle
    assert!(state.pending_unstake() == 6); // 6 is added to pending_unstake and will be removed at the end of the cycle

    // Process end of day with 5 profits
    scenario.next_epoch(addr);
    state.process_end_of_day(0, 5, 0, scenario.ctx());

    assert!(state.inactive_stake() == 24); // 6 (inactive) + 20 (active) + 5 (profits) - 6 (unstaked) - 1 (profits on the unstaked amount also need to be removed)
    assert!(state.active_stake() == 0);
    assert!(state.pending_unstake() == 0);

    destroy(state);

    scenario.end();
}

#[test, expected_failure(abort_code = state::ECannotUnstakeMoreThanStaked)]
public fun unstake_too_much() {
    let addr = @0xa;
    let mut scenario = begin(addr);

    let mut state = state::new(scenario.ctx());
    state.process_stake(100, scenario.ctx());
    state.process_unstake(150, 0, scenario.ctx());

    abort 0
}

#[test, expected_failure(abort_code = state::EEndOfDayNotAvailable)]
public fun end_of_day_empty() {
    let addr = @0xa;
    let mut scenario = begin(addr);

    // Create empty state
    let state = state::new(scenario.ctx());
    state.end_of_day_for_epoch(0);

    abort 0
}

#[test]
public fun end_of_day_available() {
    let addr = @0xA;
    let mut scenario = begin(addr);

    // Create empty state
    let mut state = state::new(scenario.ctx());

    // Process end of day for epoch 0: profits of 100 and end of day balance of 200
    scenario.next_epoch(addr);
    state.process_end_of_day(0, 100, 0, scenario.ctx());

    // Check data
    let eod = state.end_of_day_for_epoch(scenario.ctx().epoch() - 1);
    assert!(eod.day_losses() == 0);
    assert!(eod.day_profits() == 100);

    destroy(state);
    scenario.end();
}

#[test, expected_failure(abort_code = state::EEpochHasNotFinishedYet)]
public fun cannot_process_eod_before_epoch_ended() {
    let addr = @0xA;
    let mut scenario = begin(addr);

    let mut state = state::new(scenario.ctx());
    state.process_end_of_day(0, 100, 0, scenario.ctx());

    abort 0
}

#[test, expected_failure(abort_code = state::EEpochMismatch)]
public fun cannot_process_eod_for_wrong_epoch() {
    let addr = @0xA;
    let mut scenario = begin(addr);

    let mut state = state::new(scenario.ctx());

    // Advance to epoch 2
    scenario.next_epoch(addr);
    scenario.next_epoch(addr);

    // Process eod for epoch 1
    state.process_end_of_day(1, 100, 0, scenario.ctx());

    abort 0
}

#[test, expected_failure(abort_code = state::EInvalidProfitsOrLosses)]
public fun cannot_process_eod_wrong_profits_or_losses() {
    let addr = @0xA;
    let mut scenario = begin(addr);
    // Initialize history to epoch 0
    let mut state = state::new(scenario.ctx());

    // Advance to epoch 1
    scenario.next_epoch(addr);
    state.process_end_of_day(0, 100, 100, scenario.ctx());

    abort 0
}

#[test]
public fun stake_amount_correctly_transferred_basic() {
    let addr = @0xA;
    let mut scenario = begin(addr);

    let mut state = state::new(scenario.ctx());

    // Add pending stake of 100
    state.process_stake(100, scenario.ctx());

    // Activate
    assert!(state.maybe_activate(100, scenario.ctx()));

    // Add pending unstake of 50
    state.process_unstake(50, 0, scenario.ctx());

    // Transfer next epoch
    scenario.next_epoch(addr);
    state.process_end_of_day(scenario.ctx().epoch() - 1, 0, 0, scenario.ctx());
    assert!(state.inactive_stake() == 50);
    assert!(state.pending_unstake() == 0);
    assert!(state.active_stake() == 0);

    // Activate
    assert!(state.maybe_activate(50, scenario.ctx()));

    // Transfer next epoch with some profits
    scenario.next_epoch(addr);
    state.process_end_of_day(scenario.ctx().epoch() - 1, 10, 0, scenario.ctx());
    assert!(state.inactive_stake() == 60);

    // Activate
    assert!(state.maybe_activate(60, scenario.ctx()));

    // Transfer next epoch with some losses
    scenario.next_epoch(addr);
    state.process_end_of_day(scenario.ctx().epoch() - 1, 0, 20, scenario.ctx());
    assert!(state.inactive_stake() == 40);

    destroy(state);
    scenario.end();
}

#[test]
public fun stake_amount_correctly_transferred_profits() {
    let addr = @0xA;
    let mut scenario = begin(addr);

    // Initialize history to epoch 0
    let mut state = state::new(scenario.ctx());

    // Add pending stake of 100
    state.process_stake(100, scenario.ctx());

    // Activate
    assert!(state.maybe_activate(100, scenario.ctx()));

    // Now do a complete setup, starting from a stake of 100

    // 30 being added
    state.process_stake(30, scenario.ctx());

    // 10 being removed
    // 10 cancelled immediately
    state.process_unstake(10, 10, scenario.ctx());

    // Transfer next epoch with profits of 30
    scenario.next_epoch(addr);
    state.process_end_of_day(scenario.ctx().epoch() - 1, 30, 0, scenario.ctx());

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
    assert!(state.inactive_stake()== expected_value);

    destroy(state);
    scenario.end();
}

#[test]
public fun stake_amount_correctly_transferred_losses() {
    let addr = @0xA;
    let mut scenario = begin(addr);

    // Initialize history to epoch 0
    let mut state = state::new(scenario.ctx());

    // Add pending stake of 100
    state.process_stake(100, scenario.ctx());

    // Activate
    assert!(state.maybe_activate(100, scenario.ctx()));

    // Now do a complete setup, starting from a stake of 100

    // 30 being added
    state.process_stake(30, scenario.ctx());

    // 10 being removed
    // 10 cancelled immediately
    state.process_unstake(10, 10, scenario.ctx());

    // Transfer next epoch with losses of 30
    scenario.next_epoch(addr);
    state.process_end_of_day(scenario.ctx().epoch() - 1, 0, 30, scenario.ctx());

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
    assert!(state.inactive_stake() == expected_value);

    destroy(state);
    scenario.end();
}

#[test]
public fun stake_amount_correctly_transferred_full_unstake_profits() {
    let addr = @0xA;
    let mut scenario = begin(addr);

    // Initialize history to epoch 0
    let mut state = state::new(scenario.ctx());

    // Add pending stake of 100
    state.process_stake(100, scenario.ctx());

    // Activate
    assert!(state.maybe_activate(100, scenario.ctx()));

    // Now the staker wish to fully unstake
    state.process_unstake(100, 0, scenario.ctx());

    // 5 new stake is coming in
    state.process_stake(5, scenario.ctx());

    // Transfer next epoch with some profits
    scenario.next_epoch(addr);
    state.process_end_of_day(scenario.ctx().epoch() - 1, 7, 0, scenario.ctx());

    // !!! This should be 5 but instead of 107 only 106 is being unstaked because of precision errors, leaving 1 in the stake balance
    assert!(state.inactive_stake() == 6);
    destroy(state);
    scenario.end();
}

#[test]
public fun stake_amount_correctly_transferred_full_unstake_losses() {
    let addr = @0xA;
    let mut scenario = begin(addr);

    // Initialize state to epoch 0
    let mut state = state::new(scenario.ctx());

    // Add pending stake of 100
    state.process_stake(100, scenario.ctx());

    // Activate
    assert!(state.maybe_activate(100, scenario.ctx()));

    // Now the staker wish to fully unstake
    state.process_unstake(100, 0, scenario.ctx());

    // 5 new stake is coming in
    state.process_stake(5, scenario.ctx());

    // Transfer next epoch with some profits
    scenario.next_epoch(addr);
    state.process_end_of_day(scenario.ctx().epoch() - 1, 0, 7, scenario.ctx());

    let negative_roi = from_quotient(7, 100);
    let expected_value =
        100 // From last epoch
    - 7 // The distributed losses
    - int_mul(100, sub(from_int(1), negative_roi))  // The unstaked amount
    + 5; // The new added stake

    assert!(state.inactive_stake() == expected_value);
    assert!(state.inactive_stake() == 5);

    destroy(state);
    scenario.end();
}

#[test]
public fun stake_amount_correctly_transferred_bankrupt() {
    let addr = @0xA;
    let mut scenario = begin(addr);

    // Initialize state to epoch 0
    let mut state = state::new(scenario.ctx());

    // Add pending stake of 100
    state.process_stake(100, scenario.ctx());

    // Activate
    assert!(state.maybe_activate(100, scenario.ctx()));

    // Now the staker wish to fully unstake
    state.process_unstake(100, 0, scenario.ctx());

    // 5 new stake is coming in
    state.process_stake(5, scenario.ctx());

    // Transfer next epoch with bankrupt losses
    // We make the losses even more than the full 100. This is only possible because of precision errors in practice
    scenario.next_epoch(addr);
    state.process_end_of_day(scenario.ctx().epoch() - 1, 0, 101, scenario.ctx());

    // The new stakers should never be taking any sort of losses from the previous epoch
    assert!(state.inactive_stake() == 5);

    destroy(state);
    scenario.end();
}

#[test]
public fun calculate_ggr_share_losses() {
    let addr = @0xA;
    let mut scenario = begin(addr);

    // Initialize state to epoch 0
    let mut state = state::new(scenario.ctx());

    // Add stake of 100
    state.process_stake(100, scenario.ctx());

    // Activate
    assert!(state.maybe_activate(100, scenario.ctx()));

    // Transfer next epoch with losses of 31
    scenario.next_epoch(addr);
    state.process_end_of_day(scenario.ctx().epoch() - 1, 0, 31, scenario.ctx());

    let (profits_no_stake, losses_no_stake) = state.calculate_ggr_share(
        scenario.ctx().epoch() - 1,
        0,
    );
    assert!(losses_no_stake == 0);
    assert!(profits_no_stake == 0);

    let volume = state.volume_for_epoch(scenario.ctx().epoch() - 1);
    let eod = state.end_of_day_for_epoch(scenario.ctx().epoch() - 1);
    assert!(volume.total_stake_amount() == 100);
    assert!(eod.day_losses() == 31);
    assert!(eod.day_profits() == 0);

    let (profits_full_stake, losses_full_stake) = state.calculate_ggr_share(
        scenario.ctx().epoch() - 1,
        100,
    );
    assert!(losses_full_stake == 31);
    assert!(profits_full_stake == 0);

    let stake_range = vector[1, 7, 13, 21, 25, 30, 40, 60, 80, 99];
    stake_range.do!(|stake| {
        let expected_loss = int_mul(31, from_quotient(stake, 100));
        let (profits, losses) = state.calculate_ggr_share(scenario.ctx().epoch() - 1, stake);
        assert!(profits == 0);
        assert!(losses == expected_loss);
    });

    destroy(state);
    scenario.end();
}

#[test]
public fun calculate_ggr_share_profits() {
    let addr = @0xA;
    let mut scenario = begin(addr);

    // Initialize state to epoch 0
    let mut state = state::new(scenario.ctx());

    // Add stake of 100
    state.process_stake(100, scenario.ctx());

    // Activate
    assert!(state.maybe_activate(100, scenario.ctx()));

    // Transfer next epoch with profits of 81
    scenario.next_epoch(addr);
    state.process_end_of_day(scenario.ctx().epoch() - 1, 81, 0, scenario.ctx());

    let (profits_no_stake, losses_no_stake) = state.calculate_ggr_share(
        scenario.ctx().epoch() - 1,
        0,
    );
    assert!(losses_no_stake == 0);
    assert!(profits_no_stake == 0);

    let volume = state.volume_for_epoch(scenario.ctx().epoch() - 1);
    let eod = state.end_of_day_for_epoch(scenario.ctx().epoch() - 1);
    assert!(volume.total_stake_amount() == 100);
    assert!(eod.day_losses() == 0);
    assert!(eod.day_profits() == 81);

    let (profits_full_stake, losses_full_stake) = state.calculate_ggr_share(
        scenario.ctx().epoch() - 1,
        100,
    );
    assert!(losses_full_stake == 0);
    assert!(profits_full_stake == 81);

    let stake_range = vector[1, 7, 13, 21, 25, 30, 40, 60, 80, 99];
    stake_range.do!(|stake| {
        let expected_profit = int_mul(81, from_quotient(stake, 100));
        let (profits, losses) = state.calculate_ggr_share(scenario.ctx().epoch() - 1, stake);
        assert!(profits == expected_profit);
        assert!(losses == 0);
    });

    destroy(state);
    scenario.end();
}
