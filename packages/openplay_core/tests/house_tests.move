#[test_only]
module openplay_core::house_tests;

use openplay_core::balance_manager;
use openplay_core::constants::{protocol_fee};
use openplay_core::house::empty_house_for_testing;
use openplay_core::participation;
use openplay_core::core_test_utils::{assert_eq_within_precision_allowance,fund_house_for_playing};
use openplay_core::transaction::{bet, win};
use std::uq32_32::{UQ32_32, int_mul, from_quotient};
use sui::coin::{mint_for_testing, burn_for_testing};
use sui::sui::SUI;
use sui::test_scenario::begin;
use sui::test_utils::destroy;
use openplay_core::referral;
use std::string::utf8;


public fun four_fifths(): UQ32_32 {
    from_quotient(4, 5)
}

public fun one_fifth(): UQ32_32 {
    from_quotient(1, 5)
}

#[test]
public fun complete_flow_share_losses() {
    let addr = @0xa;
    let mut scenario = begin(addr);

    let (referral, referral_cap) = referral::new(utf8(b""), utf8(b""), utf8(b""), scenario.ctx());
    let referral_fee_bps = 50;
    let referral_fee_factor = from_quotient(referral_fee_bps, 10_000);

    // Create a new house and balance manager
    let mut house = empty_house_for_testing(100_000, referral_fee_bps, scenario.ctx());
    let mut participation = participation::empty(house.id(), scenario.ctx());
    let mut another_participation = participation::empty(house.id(), scenario.ctx());
    let (mut balance_manager, balance_manager_cap) = balance_manager::new(scenario.ctx());

    // Deposit 50_000 on the balance manager
    let deposit = mint_for_testing<SUI>(50_000, scenario.ctx());
    balance_manager.deposit(&balance_manager_cap, deposit, scenario.ctx());

    // Stake 20_000 on first participation
    let stake = mint_for_testing<SUI>(20_000, scenario.ctx());
    house.stake(&mut participation, stake, scenario.ctx());
    assert!(house.play_balance(scenario.ctx()) == 0); // house is yet to start

    // Stake 80_000 on second participation
    let stake = mint_for_testing<SUI>(80_000, scenario.ctx());
    house.stake(&mut another_participation, stake, scenario.ctx());
    assert!(house.play_balance(scenario.ctx()) == 0); // house is yet to start

    // Advance epoch
    // At this point, the house starts. 100k is moved to the play balance
    scenario.next_epoch(addr);
    assert!(house.play_balance(scenario.ctx()) == 100_000); // house has stared

    // Refresh the participations
    house.update_participation(&mut participation, scenario.ctx());
    house.update_participation(&mut another_participation, scenario.ctx());
    // Check active stake
    assert!(participation.active_stake() == 20_000);
    assert!(another_participation.active_stake() == 80_000);

    // Process some transactions
    // a bet of 10k and a win of 20k
    // this results in a loss of 10k + the extra owner and protocol fees
    house.process_transactions_for_testing_with_referral(
        &vector[bet(10_000), win(20_000)],
        &mut balance_manager,
        &referral,
        scenario.ctx(),
    );
    let expected_fee = int_mul(10_000, referral_fee_factor) + int_mul(10_000, protocol_fee());
    assert!(balance_manager.balance() == 60_000); // The 10k in profits is added to the first balance manager
    assert!(house.play_balance(scenario.ctx()) == 90_000 - expected_fee); // The losses and fees are deducted from the play balance

    // Refresh the participations
    house.update_participation(&mut participation, scenario.ctx());
    house.update_participation(&mut another_participation, scenario.ctx());
    // Check active stake
    assert!(participation.active_stake() == 20_000); // Active stake remains the same, losses are only deducted later on
    assert!(another_participation.active_stake() == 80_000); // Idem

    // End the epoch
    scenario.next_epoch(addr);
    // Refresh the participations
    house.update_participation(&mut participation, scenario.ctx());
    house.update_participation(&mut another_participation, scenario.ctx());

    assert!(house.play_balance(scenario.ctx()) == 0); // Not enough funds for another active round
    assert_eq_within_precision_allowance(
        participation.active_stake(),
        20_000 - int_mul((10_000 + expected_fee), one_fifth()),
    );
    assert_eq_within_precision_allowance(
        another_participation.active_stake(),
        80_000 - int_mul((10_000 + expected_fee), four_fifths()),
    );

    // Now unstake everything
    house.unstake(&mut participation, scenario.ctx());
    house.unstake(&mut another_participation, scenario.ctx());
    // Funds should not be added yet
    assert!(participation.claimable_balance() == 0);
    assert!(another_participation.claimable_balance() == 0);

    // Advance epoch
    scenario.next_epoch(addr);
    assert!(house.play_balance(scenario.ctx()) == 0); // Play balance stays the same because it was not funded

    // Refresh the participations
    house.update_participation(&mut participation, scenario.ctx());
    house.update_participation(&mut another_participation, scenario.ctx());

    assert_eq_within_precision_allowance(
        participation.claimable_balance(),
        20_000 - int_mul(10_000 + expected_fee, one_fifth()),
    ); // Now the rest is released, namely 20_000 minus his bm's share of the losses
    assert_eq_within_precision_allowance(
        another_participation.claimable_balance(),
        80_000 - int_mul(10_000 + expected_fee, four_fifths()),
    ); // Now the rest is released, namely 80_000 minus his bm's share of the losses

    destroy(house);
    destroy(balance_manager);
    destroy(balance_manager_cap);
    destroy(participation);
    destroy(another_participation);
    destroy(referral);
    destroy(referral_cap);
    scenario.end();
}

#[test]
public fun complete_flow_share_profits() {
    let addr = @0xa;
    let mut scenario = begin(addr);

    let (referral, referral_cap) = referral::new(utf8(b""), utf8(b""), utf8(b""), scenario.ctx());
    let referral_fee_bps = 50;
    let referral_fee_factor = from_quotient(referral_fee_bps, 10_000);

    // Create a new house and balance manager
    let mut house = empty_house_for_testing(100_000, referral_fee_bps, scenario.ctx());
    let mut participation = participation::empty(house.id(), scenario.ctx());
    let mut another_participation = participation::empty(house.id(), scenario.ctx());
    let (mut balance_manager, balance_manager_cap) = balance_manager::new(scenario.ctx());

    // Deposit 50_000 on the balance manager
    let deposit = mint_for_testing<SUI>(50_000, scenario.ctx());
    balance_manager.deposit(&balance_manager_cap, deposit, scenario.ctx());

    // Stake 20_000 on first participation
    let stake = mint_for_testing<SUI>(20_000, scenario.ctx());
    house.stake(&mut participation, stake, scenario.ctx());
    assert!(house.play_balance(scenario.ctx()) == 0); // house is yet to start

    // Stake 80_000 on second participation
    let stake = mint_for_testing<SUI>(80_000, scenario.ctx());
    house.stake(&mut another_participation, stake, scenario.ctx());
    assert!(house.play_balance(scenario.ctx()) == 0); // house is yet to start

    // Advance epoch
    // At this point, the house starts. 100k is moved to the play balance
    scenario.next_epoch(addr);
    assert!(house.play_balance(scenario.ctx()) == 100_000); // house has stared

    // Process some transactions
    // a bet of 10k and a win of 5k
    // this results in a profit of 5k - the extra owner and protocol fees
    house.process_transactions_for_testing_with_referral(
        &vector[bet(10_000), win(5_000)],
        &mut balance_manager,
        &referral,
        scenario.ctx(),
    );
    let expected_fee = int_mul(10_000, referral_fee_factor) + int_mul(10_000, protocol_fee());
    assert!(balance_manager.balance() == 45_000); // The 5k in losses is added to the first balance manager
    assert!(house.play_balance(scenario.ctx()) == 105_000 - expected_fee); // The profits are added to the play_balance, minus the fees

    // Refresh the participations
    house.update_participation(&mut participation, scenario.ctx());
    house.update_participation(&mut another_participation, scenario.ctx());
    assert!(participation.active_stake() == 20_000);
    assert!(another_participation.active_stake() == 80_000);

    // End the epoch
    scenario.next_epoch(addr);

    // Refresh the participations
    house.update_participation(&mut participation, scenario.ctx());
    house.update_participation(&mut another_participation, scenario.ctx());

    assert!(house.play_balance(scenario.ctx()) == 100_000); // House is funded again
    assert_eq_within_precision_allowance(
        participation.active_stake(),
        20_000 + int_mul((5_000 - expected_fee), one_fifth()),
    );
    assert_eq_within_precision_allowance(
        another_participation.active_stake(),
        80_000 + int_mul((5_000 - expected_fee), four_fifths()),
    );

    // Now unstake everything
    house.unstake(&mut participation, scenario.ctx());
    house.unstake(&mut another_participation, scenario.ctx());
    // Funds should not be added yet
    assert!(participation.claimable_balance() == 0);
    assert!(another_participation.claimable_balance() == 0);

    // Advance epoch
    scenario.next_epoch(addr);
    assert!(house.play_balance(scenario.ctx()) == 0); // Play balance stays the same because it was not funded

    // Refresh the participations
    house.update_participation(&mut participation, scenario.ctx());
    house.update_participation(&mut another_participation, scenario.ctx());

    assert_eq_within_precision_allowance(
        participation.claimable_balance(),
        20_000 + int_mul(5_000 - expected_fee, one_fifth()),
    ); // Now the rest is released, namely 20_000 plus his bm's share of the profits
    assert_eq_within_precision_allowance(
        another_participation.claimable_balance(),
        80_000 + int_mul(5_000 - expected_fee, four_fifths()),
    ); // Now the rest is released, namely 80_000 plus his bm's share of the profits

    destroy(house);
    destroy(balance_manager_cap);
    destroy(balance_manager);
    destroy(participation);
    destroy(another_participation);
    destroy(referral);
    destroy(referral_cap);
    scenario.end();
}

#[test]
public fun complete_flow_share_profits_multi_round() {
    let addr = @0xa;
    let mut scenario = begin(addr);
    
    let (referral, referral_cap) = referral::new(utf8(b""), utf8(b""), utf8(b""), scenario.ctx());
    let referral_fee_bps = 50;
    let referral_fee_factor = from_quotient(referral_fee_bps, 10_000);

    // Create a new house and balance manager
    let mut house = empty_house_for_testing(100_000, referral_fee_bps, scenario.ctx());
    let mut participation = participation::empty(house.id(), scenario.ctx());
    let mut another_participation = participation::empty(house.id(), scenario.ctx());
    let (mut balance_manager, balance_manager_cap) = balance_manager::new(scenario.ctx());

    // Deposit 50_000 on the balance manager
    let deposit = mint_for_testing<SUI>(50_000, scenario.ctx());
    balance_manager.deposit(&balance_manager_cap, deposit, scenario.ctx());

    // Stake 20_000 on first participation
    let stake = mint_for_testing<SUI>(20_000, scenario.ctx());
    house.stake(&mut participation, stake, scenario.ctx());
    assert!(house.play_balance(scenario.ctx()) == 0); // house is yet to start

    // Stake 80_000 on second participation
    let stake = mint_for_testing<SUI>(80_000, scenario.ctx());
    house.stake(&mut another_participation, stake, scenario.ctx());
    assert!(house.play_balance(scenario.ctx()) == 0); // house is yet to start

    // Advance epoch and play
    // a bet of 10k and a win of 5k
    // this results in a profit of 5k - the extra owner and protocol fees
    scenario.next_epoch(addr);
    house.process_transactions_for_testing_with_referral(
        &vector[bet(10_000), win(5_000)],
        &mut balance_manager,
        &referral,
        scenario.ctx(),
    );
    let expected_fee = int_mul(10_000, referral_fee_factor) + int_mul(10_000, protocol_fee());

    // Skip 1 epoch without any activity and process some more transactions
    scenario.next_epoch(addr);
    scenario.next_epoch(addr);
    house.process_transactions_for_testing_with_referral(
        &vector[bet(10_000), win(5_000)],
        &mut balance_manager,
        &referral,
        scenario.ctx(),
    );

    // Refresh the participations
    house.update_participation(&mut participation, scenario.ctx());
    house.update_participation(&mut another_participation, scenario.ctx());

    // Now unstake everything
    house.unstake(&mut participation, scenario.ctx());
    house.unstake(&mut another_participation, scenario.ctx());

    // Advance epoch
    scenario.next_epoch(addr);
    assert!(house.play_balance(scenario.ctx()) == 0);

    // Refresh the participations
    house.update_participation(&mut participation, scenario.ctx());
    house.update_participation(&mut another_participation, scenario.ctx());

    assert_eq_within_precision_allowance(
        participation.claimable_balance(),
        20_000 + 2 * int_mul(5_000 - expected_fee, one_fifth()),
    );
    assert_eq_within_precision_allowance(
        another_participation.claimable_balance(),
        80_000 + 2 * int_mul(5_000 - expected_fee, four_fifths()),
    );

    destroy(house);
    destroy(balance_manager_cap);
    destroy(balance_manager);
    destroy(participation);
    destroy(another_participation);
    destroy(referral);
    destroy(referral_cap);
    scenario.end();
}

#[test]
public fun complete_flow_profits_and_losses_multi_round() {
    let addr = @0xa;
    let mut scenario = begin(addr);

    
    let (referral, referral_cap) = referral::new(utf8(b""), utf8(b""), utf8(b""), scenario.ctx());
    let referral_fee_bps = 50;
    let referral_fee_factor = from_quotient(referral_fee_bps, 10_000);

    // Create a new house and balance manager
    let mut house = empty_house_for_testing(100_000, referral_fee_bps, scenario.ctx());
    let mut participation = participation::empty(house.id(), scenario.ctx());
    let mut another_participation = participation::empty(house.id(), scenario.ctx());
    let (mut balance_manager, balance_manager_cap) = balance_manager::new(scenario.ctx());

    // Deposit 50_000 on the balance manager
    let deposit = mint_for_testing<SUI>(50_000, scenario.ctx());
    balance_manager.deposit(&balance_manager_cap, deposit, scenario.ctx());

    // Stake 20_000 on first participation
    let stake = mint_for_testing<SUI>(20_000, scenario.ctx());
    house.stake(&mut participation, stake, scenario.ctx());
    assert!(house.play_balance(scenario.ctx()) == 0); // house is yet to start

    // Stake 80_000 on second participation
    let stake = mint_for_testing<SUI>(80_000, scenario.ctx());
    house.stake(&mut another_participation, stake, scenario.ctx());
    assert!(house.play_balance(scenario.ctx()) == 0); // house is yet to start

    // Advance epoch and play
    // a bet of 10k and a win of 5k
    // this results in a profit of 5k - the extra owner and protocol fees
    scenario.next_epoch(addr);
    house.process_transactions_for_testing_with_referral(
        &vector[bet(10_000), win(5_000)],
        &mut balance_manager,
        &referral,
        scenario.ctx(),
    );
    let expected_fee = int_mul(10_000, referral_fee_factor) + int_mul(10_000, protocol_fee());

    // Skip 1 epoch without any activity and process some more transactions
    // Net result should be even
    scenario.next_epoch(addr);
    scenario.next_epoch(addr);
    house.process_transactions_for_testing_with_referral(
        &vector[bet(10_000), win(15_000)],
        &mut balance_manager,
        &referral,
        scenario.ctx(),
    );

    // Refresh the participations
    house.update_participation(&mut participation, scenario.ctx());
    house.update_participation(&mut another_participation, scenario.ctx());

    // Now unstake everything
    house.unstake(&mut participation, scenario.ctx());
    house.unstake(&mut another_participation, scenario.ctx());

    // Advance epoch
    scenario.next_epoch(addr);
    assert!(house.play_balance(scenario.ctx()) == 0);

    // Refresh the participations
    house.update_participation(&mut participation, scenario.ctx());
    house.update_participation(&mut another_participation, scenario.ctx());

    assert_eq_within_precision_allowance(
        participation.claimable_balance(),
        20_000 - 2 * int_mul(expected_fee, one_fifth()), // We only lost the tx fees
    );
    assert_eq_within_precision_allowance(
        another_participation.claimable_balance(),
        80_000 - 2 * int_mul(expected_fee, four_fifths()), // We only lost the tx fees
    );

    destroy(house);
    destroy(balance_manager_cap);
    destroy(balance_manager);
    destroy(participation);
    destroy(another_participation);
    destroy(referral);
    destroy(referral_cap);
    scenario.end();
}

#[test]
public fun complete_flow_multiple_funded_rounds() {
    let addr = @0xa;
    let mut scenario = begin(addr);

    let (referral, referral_cap) = referral::new(utf8(b""), utf8(b""), utf8(b""), scenario.ctx());
    let referral_fee_bps = 50;
    let referral_fee_factor = from_quotient(referral_fee_bps, 10_000);

    // Create a new house and balance manager
    let mut house = empty_house_for_testing(100_000, referral_fee_bps, scenario.ctx());
    let mut participation = participation::empty(house.id(), scenario.ctx());
    let mut another_participation = participation::empty(house.id(), scenario.ctx());
    let (mut balance_manager, balance_manager_cap) = balance_manager::new(scenario.ctx());

    // Deposit 50_000 on the balance manager
    let deposit = mint_for_testing<SUI>(50_000, scenario.ctx());
    balance_manager.deposit(&balance_manager_cap, deposit, scenario.ctx());

    // Stake 30_000 on first participation
    let stake = mint_for_testing<SUI>(30_000, scenario.ctx());
    house.stake(&mut participation, stake, scenario.ctx());
    assert!(house.play_balance(scenario.ctx()) == 0); // house is yet to start

    // Stake 120_000 on second participation
    let stake = mint_for_testing<SUI>(120_000, scenario.ctx());
    house.stake(&mut another_participation, stake, scenario.ctx());
    assert!(house.play_balance(scenario.ctx()) == 0); // house is yet to start

    // Advance epoch
    // At this point, the house starts. 100k is moved to the play balance
    scenario.next_epoch(addr);

    // Refresh the participations
    house.update_participation(&mut participation, scenario.ctx());
    house.update_participation(&mut another_participation, scenario.ctx());

    assert!(house.play_balance(scenario.ctx()) == 100_000); // house has stared
    assert!(participation.active_stake() == 30_000);
    assert!(another_participation.active_stake() == 120_000);

    // Process some transactions
    // a bet of 10k and a win of 20k
    // this results in a loss of 10k + the extra owner and protocol fees
    house.process_transactions_for_testing_with_referral(
        &vector[bet(10_000), win(20_000)],
        &mut balance_manager,
        &referral,
        scenario.ctx(),
    );
    let expected_fee = int_mul(10_000, referral_fee_factor) + int_mul(10_000, protocol_fee());
    assert!(balance_manager.balance() == 60_000); // The 10k in profits is added to the first balance manager
    assert!(house.play_balance(scenario.ctx()) == 90_000 - expected_fee); // The losses and fees are deducted from the play balance
    assert!(participation.active_stake() == 30_000);
    assert!(another_participation.active_stake() == 120_000);

    // End the epoch
    scenario.next_epoch(addr);
    // Refresh the participations
    house.update_participation(&mut participation, scenario.ctx());
    house.update_participation(&mut another_participation, scenario.ctx());

    assert!(house.play_balance(scenario.ctx()) == 100_000); // Fresh play balance
    assert_eq_within_precision_allowance(
        participation.active_stake(),
        30_000 - int_mul((10_000 + expected_fee), one_fifth()),
    ); // Losses are deducted now from the active stake
    assert_eq_within_precision_allowance(
        another_participation.active_stake(),
        120_000 - int_mul((10_000 + expected_fee), four_fifths()),
    );

    // Stake another 20_000 with the first balance manager
    let stake = mint_for_testing<SUI>(20_000, scenario.ctx());
    house.stake(&mut participation, stake, scenario.ctx());
    assert!(house.play_balance(scenario.ctx()) == 100_000); // Play balance stays the same

    // Now unstake for first staker
    house.unstake(&mut participation, scenario.ctx());
    assert!(participation.claimable_balance() == 20_000); // Only the 20_000 that was still pending is immediately released, the rest is now pending to be unstaked

    // Advance epoch
    scenario.next_epoch(addr);
    // Refresh the participations
    house.update_participation(&mut participation, scenario.ctx());

    assert!(house.play_balance(scenario.ctx()) == 100_000); // Play balance should be funded once again because the second staker has enough funds staked
    assert_eq_within_precision_allowance(
        participation.claimable_balance(),
        20_000 + 30_000 - int_mul(10_000 + expected_fee, one_fifth()),
    ); // Now the rest is released, namely 30_000 minus his bm's share of the losses

    destroy(house);
    destroy(balance_manager);
    destroy(participation);
    destroy(another_participation);
    destroy(balance_manager_cap);
    destroy(referral);
    destroy(referral_cap);
    scenario.end();
}

#[test]
public fun stake_unstake_ok() {
    let addr = @0xa;
    let mut scenario = begin(addr);

    let referral_fee_bps = 50;

    // Create a new house and balance manager
    let mut house = empty_house_for_testing(100_000, referral_fee_bps, scenario.ctx());
    let mut participation = participation::empty(house.id(), scenario.ctx());
    let mut another_participation = participation::empty(house.id(), scenario.ctx());

    // Stake 30_000 on first participation
    let stake = mint_for_testing<SUI>(30_000, scenario.ctx());
    house.stake(&mut participation, stake, scenario.ctx());
    assert!(house.play_balance(scenario.ctx()) == 0); // house is yet to start

    // Stake 120_000 on second participation
    let stake = mint_for_testing<SUI>(120_000, scenario.ctx());
    house.stake(&mut another_participation, stake, scenario.ctx());
    assert!(house.play_balance(scenario.ctx()) == 0); // house is yet to start

    // Advance epoch
    // At this point, the house starts. 100k is moved to the play balance. 50k is left in reserve
    scenario.next_epoch(addr);
    // Refresh the participations
    house.update_participation(&mut participation, scenario.ctx());
    house.update_participation(&mut another_participation, scenario.ctx());
    // Check active stake
    assert!(participation.active_stake() == 30_000);
    assert!(another_participation.active_stake() == 120_000);
    assert!(house.play_balance(scenario.ctx()) == 100_000); // house has stared

    // First participant unstakes
    house.unstake(&mut participation, scenario.ctx());
    assert!(participation.claimable_balance() == 0); // No funds should be added yet

    // Advance epoch
    scenario.next_epoch(addr);
    // Refresh the participations
    house.update_participation(&mut participation, scenario.ctx());
    house.update_participation(&mut another_participation, scenario.ctx());
    // Stake is now released
    assert!(house.play_balance(scenario.ctx()) == 100_000); // Play balance still has enough
    assert!(participation.active_stake() == 0);
    assert!(participation.claimable_balance() == 30_000);
    assert!(another_participation.active_stake() == 120_000);

    //  First one now stakes 100k again
    let stake = mint_for_testing<SUI>(100_000, scenario.ctx());
    house.stake(&mut participation, stake, scenario.ctx());
    assert!(participation.active_stake() == 0); // Not active yet
    // Second one unstakes
    house.unstake(&mut another_participation, scenario.ctx());
    // Refresh the participations
    house.update_participation(&mut participation, scenario.ctx());
    house.update_participation(&mut another_participation, scenario.ctx());

    assert!(another_participation.claimable_balance() == 0); // No funds should be added yet
    assert!(another_participation.active_stake() == 120_000); // Still active

    // Advance epoch
    scenario.next_epoch(addr);
    // Refresh the participations
    house.update_participation(&mut participation, scenario.ctx());
    house.update_participation(&mut another_participation, scenario.ctx());
    assert!(house.play_balance(scenario.ctx()) == 100_000); // Play balance still has enough

    // Stake of the first one should be active
    assert!(participation.active_stake() == 100_000); // Active now
    // Second one should get funds back
    assert!(another_participation.claimable_balance() == 120_000);
    assert!(another_participation.active_stake() == 0); // Not active anymore

    // Now unstake the remaining funds
    house.unstake(&mut participation, scenario.ctx());
    assert!(participation.claimable_balance() == 30_000); // This is the 30k from before

    // Advance epoch
    scenario.next_epoch(addr);
    // Refresh the participations
    house.update_participation(&mut participation, scenario.ctx());
    house.update_participation(&mut another_participation, scenario.ctx());
    assert!(house.play_balance(scenario.ctx()) == 0); // Not enough balance anymore
    // Claim funds
    assert!(participation.claimable_balance() == 130_000); // This is the 30k from before
    assert!(another_participation.claimable_balance() == 120_000);

    destroy(house);
    destroy(participation);
    destroy(another_participation);
    scenario.end();
}

#[test]
public fun house_doesnt_start_when_everything_unstaked() {
    let addr = @0xa;
    let mut scenario = begin(addr);
    
    let referral_fee_bps = 50;

    // Create a new house and balance manager
    let mut house = empty_house_for_testing(100_000, referral_fee_bps, scenario.ctx());
    let mut participation = participation::empty(house.id(), scenario.ctx());

    // Stake 100_000 on first participation
    let stake = mint_for_testing<SUI>(100_000, scenario.ctx());
    house.stake(&mut participation, stake, scenario.ctx());
    assert!(house.play_balance(scenario.ctx()) == 0); // house is yet to start
    assert!(house.play_balance(scenario.ctx()) == 0); // house is yet to start

    // Advance epoch
    // At this point, the house starts. 100k is moved to the play balance. 50k is left in reserve
    scenario.next_epoch(addr);
    assert!(house.play_balance(scenario.ctx()) == 100_000); // house has stared
    house.update_participation(&mut participation, scenario.ctx());
    assert!(participation.active_stake() == 100_000);

    // First bm unstakes
    house.unstake(&mut participation, scenario.ctx());
    house.update_participation(&mut participation, scenario.ctx());
    assert!(participation.claimable_balance() == 0); // No funds should be added yet

    // Advance epoch
    // Stake is now released
    scenario.next_epoch(addr);
    house.update_participation(&mut participation, scenario.ctx());
    assert!(house.play_balance(scenario.ctx()) == 0); // Not enough anymore
    assert!(participation.active_stake() == 0);
    assert!(participation.claimable_balance() == 100_000);

    destroy(house);
    destroy(participation);
    scenario.end();
}

#[test]
public fun collect_owner_fees_ok() {
    let addr = @0xa;
    let mut scenario = begin(addr);

    let (referral, referral_cap) = referral::new(utf8(b""), utf8(b""), utf8(b""), scenario.ctx());
    let referral_fee_bps = 50;

    // Create a new house and balance manager
    let mut house1 = empty_house_for_testing(100_000, referral_fee_bps, scenario.ctx());
    let participation = fund_house_for_playing(&mut house1, 100_000, scenario.ctx());
    scenario.next_epoch(addr);

    house1.add_referral_fees_for_testing(&referral, 100, scenario.ctx());

    let coin = house1.claim_referral_fees(&referral_cap, scenario.ctx());
    assert!(coin.value() == 100);

    destroy(house1);
    destroy(referral);
    destroy(referral_cap);
    destroy(participation);
    burn_for_testing(coin);
    scenario.end();
}

#[test]
public fun collect_owner_fees_empty() {
    let addr = @0xa;
    let mut scenario = begin(addr);

    let (referral, referral_cap) = referral::new(utf8(b""), utf8(b""), utf8(b""), scenario.ctx());
    let referral_fee_bps = 50;

    // Create a new house and balance manager
    let mut house = empty_house_for_testing(100_000, referral_fee_bps, scenario.ctx());
    let coin = house.claim_referral_fees(&referral_cap, scenario.ctx());
    assert!(coin.value() == 0);

    destroy(referral);
    destroy(referral_cap);
    destroy(house);
    burn_for_testing(coin);
    scenario.end();
}

#[test]
public fun collect_owner_fees_multiple_caps() {
    let addr = @0xa;
    let mut scenario = begin(addr);

    let referral_fee_bps = 50;
    let (referral1, referral_cap1) = referral::new(utf8(b""), utf8(b""), utf8(b""), scenario.ctx());
    let (referral2, referral_cap2) = referral::new(utf8(b""), utf8(b""), utf8(b""), scenario.ctx());


    // Create a new house and balance manager
    let mut house = empty_house_for_testing(100_000, referral_fee_bps, scenario.ctx());
    let participation = fund_house_for_playing(&mut house, 100_000, scenario.ctx());

    scenario.next_epoch(addr);

    house.add_referral_fees_for_testing(&referral1, 100, scenario.ctx());

    let coin1 = house.claim_referral_fees(&referral_cap1, scenario.ctx());
    assert!(coin1.value() == 100);
    let coin2 = house.claim_referral_fees(&referral_cap2, scenario.ctx());
    assert!(coin2.value() == 0);

    burn_for_testing(coin1);
    burn_for_testing(coin2);

    destroy(referral1);
    destroy(referral_cap1);
    destroy(referral2);
    destroy(referral_cap2);
    destroy(house);
    destroy(participation);
    scenario.end();
}
