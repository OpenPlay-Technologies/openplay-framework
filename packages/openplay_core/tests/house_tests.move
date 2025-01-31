#[test_only]
module openplay_core::house_tests;

use openplay_core::balance_manager;
use openplay_core::core_test_utils::{
    assert_eq_within_precision_allowance,
    fund_house_for_playing,
    default_house
};
use openplay_core::house;
use openplay_core::participation;
use openplay_core::referral;
use openplay_core::registry::registry_for_testing;
use openplay_core::transaction::{bet, win};
use std::uq32_32::{UQ32_32, int_mul, from_quotient};
use sui::coin::{mint_for_testing, burn_for_testing};
use sui::sui::SUI;
use sui::test_scenario::begin;
use sui::test_utils::destroy;

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

    // Create a new house and balance manager
    let (mut house, admin_cap, tx_cap) = default_house(scenario.ctx());
    let registry = registry_for_testing(scenario.ctx());
    let mut participation = participation::empty(house.id(), scenario.ctx());
    let mut another_participation = participation::empty(house.id(), scenario.ctx());
    let (mut balance_manager, balance_manager_cap) = balance_manager::new(scenario.ctx());
    let play_cap = balance_manager.mint_play_cap(&balance_manager_cap, scenario.ctx());
    let (referral, referral_cap) = referral::new(house.id(), scenario.ctx());

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
    house.tx_admin_process_transactions_with_referral(
        &registry,
        &tx_cap,
        &mut balance_manager,
        &vector[bet(10_000), win(20_000)],
        &play_cap,
        &referral,
        scenario.ctx(),
    );

    let expected_fee =
        int_mul(10_000, house.house_fee_factor()) 
        + int_mul(10_000, registry.protocol_fee_factor())
        + int_mul(10_000, house.referral_fee_factor());
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
    destroy(tx_cap);
    destroy(registry);
    destroy(play_cap);
    destroy(admin_cap);
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

    // Create a new house and balance manager
    let (mut house, admin_cap, tx_cap) = default_house(scenario.ctx());
    let registry = registry_for_testing(scenario.ctx());
    let mut participation = participation::empty(house.id(), scenario.ctx());
    let mut another_participation = participation::empty(house.id(), scenario.ctx());
    let (mut balance_manager, balance_manager_cap) = balance_manager::new(scenario.ctx());
    let play_cap = balance_manager.mint_play_cap(&balance_manager_cap, scenario.ctx());
    let (referral, referral_cap) = referral::new(house.id(), scenario.ctx());

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
    house.tx_admin_process_transactions_with_referral(
        &registry,
        &tx_cap,
        &mut balance_manager,
        &vector[bet(10_000), win(5_000)],
        &play_cap,
        &referral,
        scenario.ctx(),
    );
    let expected_fee =
        int_mul(10_000, house.house_fee_factor()) 
        + int_mul(10_000, registry.protocol_fee_factor())
        + int_mul(10_000, house.referral_fee_factor());
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
    destroy(registry);
    destroy(play_cap);
    destroy(tx_cap);
    destroy(admin_cap);
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

    // Create a new house and balance manager
    let (mut house, admin_cap, tx_cap) = default_house(scenario.ctx());
    let registry = registry_for_testing(scenario.ctx());
    let mut participation = participation::empty(house.id(), scenario.ctx());
    let mut another_participation = participation::empty(house.id(), scenario.ctx());
    let (mut balance_manager, balance_manager_cap) = balance_manager::new(scenario.ctx());
    let play_cap = balance_manager.mint_play_cap(&balance_manager_cap, scenario.ctx());
    let (referral, referral_cap) = referral::new(house.id(), scenario.ctx());

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
    house.tx_admin_process_transactions_with_referral(
        &registry,
        &tx_cap,
        &mut balance_manager,
        &vector[bet(10_000), win(5_000)],
        &play_cap,
        &referral,
        scenario.ctx(),
    );
    let expected_fee =
        int_mul(10_000, house.house_fee_factor()) 
        + int_mul(10_000, registry.protocol_fee_factor())
        + int_mul(10_000, house.referral_fee_factor());

    // Skip 1 epoch without any activity and process some more transactions
    scenario.next_epoch(addr);
    scenario.next_epoch(addr);
    house.tx_admin_process_transactions_with_referral(
        &registry,
        &tx_cap,
        &mut balance_manager,
        &vector[bet(10_000), win(5_000)],
        &play_cap,
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
    destroy(registry);
    destroy(play_cap);
    destroy(tx_cap);
    destroy(admin_cap);
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

    // Create a new house and balance manager
    let registry = registry_for_testing(scenario.ctx());
    let (mut house, admin_cap, tx_cap) = default_house(scenario.ctx());
    let mut participation = participation::empty(house.id(), scenario.ctx());
    let mut another_participation = participation::empty(house.id(), scenario.ctx());
    let (mut balance_manager, balance_manager_cap) = balance_manager::new(scenario.ctx());
    let play_cap = balance_manager.mint_play_cap(&balance_manager_cap, scenario.ctx());
    let (referral, referral_cap) = referral::new(house.id(), scenario.ctx());

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
    house.tx_admin_process_transactions_with_referral(
        &registry,
        &tx_cap,
        &mut balance_manager,
        &vector[bet(10_000), win(5_000)],
        &play_cap,
        &referral,
        scenario.ctx(),
    );
    let expected_fee =
        int_mul(10_000, house.house_fee_factor()) 
        + int_mul(10_000, registry.protocol_fee_factor())
        + int_mul(10_000, house.referral_fee_factor());

    // Skip 1 epoch without any activity and process some more transactions
    // Net result should be even
    scenario.next_epoch(addr);
    scenario.next_epoch(addr);
    house.tx_admin_process_transactions_with_referral(
        &registry,
        &tx_cap,
        &mut balance_manager,
        &vector[bet(10_000), win(15_000)],
        &play_cap,
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

    destroy(registry);
    destroy(house);
    destroy(play_cap);
    destroy(tx_cap);
    destroy(admin_cap);
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

    // Create a new house and balance manager
    let registry = registry_for_testing(scenario.ctx());
    let (mut house, admin_cap, tx_cap) = default_house(scenario.ctx());
    let mut participation = participation::empty(house.id(), scenario.ctx());
    let mut another_participation = participation::empty(house.id(), scenario.ctx());
    let (mut balance_manager, balance_manager_cap) = balance_manager::new(scenario.ctx());
    let play_cap = balance_manager.mint_play_cap(&balance_manager_cap, scenario.ctx());
    let (referral, referral_cap) = referral::new(house.id(), scenario.ctx());

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
    house.tx_admin_process_transactions_with_referral(
        &registry,
        &tx_cap,
        &mut balance_manager,
        &vector[bet(10_000), win(20_000)],
        &play_cap,
        &referral,
        scenario.ctx(),
    );
    let expected_fee =
        int_mul(10_000, house.house_fee_factor()) 
        + int_mul(10_000, registry.protocol_fee_factor())
        + int_mul(10_000, house.referral_fee_factor());
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
    destroy(registry);
    destroy(play_cap);
    destroy(tx_cap);
    destroy(admin_cap);
    destroy(balance_manager);
    destroy(participation);
    destroy(another_participation);
    destroy(balance_manager_cap);
    destroy(referral);
    destroy(referral_cap);
    scenario.end();
}

#[test, expected_failure(abort_code = balance_manager::EBalanceTooLow)]
public fun insufficient_funds_should_fail() {
    let addr = @0xa;
    let mut scenario = begin(addr);

    // Create a new house and balance manager
    let registry = registry_for_testing(scenario.ctx());
    let (mut house, _admin_cap, tx_cap) = default_house(scenario.ctx());
    let mut participation = participation::empty(house.id(), scenario.ctx());
    let (mut balance_manager, balance_manager_cap) = balance_manager::new(scenario.ctx());
    let play_cap = balance_manager.mint_play_cap(&balance_manager_cap, scenario.ctx());

    // Stake 100_000
    let stake = mint_for_testing<SUI>(100_000, scenario.ctx());
    house.stake(&mut participation, stake, scenario.ctx());
    assert!(house.play_balance(scenario.ctx()) == 0); // house is yet to start

    // Advance epoch
    // At this point, the house starts. 100k is moved to the play balance
    scenario.next_epoch(addr);
    house.update_participation(&mut participation, scenario.ctx());
    assert!(house.play_balance(scenario.ctx()) == 100_000); // house has stared

    // Process some transactions
    // a bet of 10k and a win of 20k
    // This should fail
    house.tx_admin_process_transactions(
        &registry,
        &tx_cap,
        &mut balance_manager,
        &vector[bet(10_000), win(20_000)],
        &play_cap,
        scenario.ctx(),
    );
    abort 0
}

#[test]
public fun stake_unstake_ok() {
    let addr = @0xa;
    let mut scenario = begin(addr);

    // Create a new house and balance manager
    let (mut house, admin_cap, tx_cap) = default_house(scenario.ctx());
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
    destroy(tx_cap);
    destroy(admin_cap);
    destroy(participation);
    destroy(another_participation);
    scenario.end();
}

#[test]
public fun house_doesnt_start_when_everything_unstaked() {
    let addr = @0xa;
    let mut scenario = begin(addr);

    // Create a new house and balance manager
    let (mut house, admin_cap, tx_cap) = default_house(scenario.ctx());
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
    destroy(tx_cap);
    destroy(admin_cap);
    destroy(participation);
    scenario.end();
}

#[test]
public fun collect_fees_ok() {
    let addr = @0xa;
    let mut scenario = begin(addr);

    // Create a new house and balance manager
    let (mut house, admin_cap, tx_cap) = default_house(scenario.ctx());
    let participation = fund_house_for_playing(&mut house, 100_000, scenario.ctx());
    scenario.next_epoch(addr);
    let (referral, referral_cap) = referral::new(house.id(), scenario.ctx());

    house.add_referral_fees_for_testing(&referral, 100, scenario.ctx());
    house.add_house_fees_for_testing(200, scenario.ctx());

    let coin1 = house.referral_admin_claim_referral_fees(&referral_cap, scenario.ctx());
    assert!(coin1.value() == 100);

    let coin2 = house.admin_claim_house_fees(&admin_cap, scenario.ctx());
    assert!(coin2.value() == 200);

    destroy(house);
    destroy(tx_cap);
    destroy(admin_cap);
    destroy(referral);
    destroy(referral_cap);
    destroy(participation);
    burn_for_testing(coin1);
    burn_for_testing(coin2);
    scenario.end();
}

#[test]
public fun collect_fees_empty() {
    let addr = @0xa;
    let mut scenario = begin(addr);
    // Create a new house and balance manager
    let (mut house, admin_cap, tx_cap) = default_house(scenario.ctx());
    let (referral, referral_cap) = referral::new(house.id(), scenario.ctx());
    let coin1 = house.referral_admin_claim_referral_fees(&referral_cap, scenario.ctx());
    assert!(coin1.value() == 0);

    let coin2 = house.admin_claim_house_fees(&admin_cap, scenario.ctx());
    assert!(coin2.value() == 0);

    destroy(referral);
    destroy(referral_cap);
    destroy(house);
    destroy(tx_cap);
    destroy(admin_cap);
    burn_for_testing(coin1);
    burn_for_testing(coin2);
    scenario.end();
}

#[test]
public fun collect_referral_fees_multiple_caps() {
    let addr = @0xa;
    let mut scenario = begin(addr);

    // Create a new house and balance manager
    let (mut house, admin_cap, tx_cap) = default_house(scenario.ctx());
    let participation = fund_house_for_playing(&mut house, 100_000, scenario.ctx());

    let (referral1, referral_cap1) = referral::new(house.id(), scenario.ctx());
    let (referral2, referral_cap2) = referral::new(house.id(), scenario.ctx());

    scenario.next_epoch(addr);

    house.add_referral_fees_for_testing(&referral1, 100, scenario.ctx());

    let coin1 = house.referral_admin_claim_referral_fees(&referral_cap1, scenario.ctx());
    assert!(coin1.value() == 100);
    let coin2 = house.referral_admin_claim_referral_fees(&referral_cap2, scenario.ctx());
    assert!(coin2.value() == 0);

    burn_for_testing(coin1);
    burn_for_testing(coin2);

    destroy(referral1);
    destroy(referral_cap1);
    destroy(referral2);
    destroy(referral_cap2);
    destroy(house);
    destroy(tx_cap);
    destroy(admin_cap);
    destroy(participation);
    scenario.end();
}

#[test, expected_failure(abort_code = house::EInvalidAdminCap)]
public fun collect_house_fees_wrong_cap() {
    let addr = @0xa;
    let mut scenario = begin(addr);

    // Create a new house and balance manager
    let (mut house1, _admin_cap1, _tx_cap1) = default_house(scenario.ctx());
    let (mut _house2, admin_cap2, _tx_cap2) = default_house(scenario.ctx());

    let _coin = house1.admin_claim_house_fees(&admin_cap2, scenario.ctx());
    abort 0
}

#[test]
public fun private_house_ok() {
    let addr = @0xa;
    let mut scenario = begin(addr);

    // Create a private house
    let (house, admin_cap) = house::new(true, 100_000, 50, 1_500, scenario.ctx());
    let participation = house.admin_new_participation(&admin_cap, scenario.ctx());

    destroy(house);
    destroy(admin_cap);
    destroy(participation);
    scenario.end();
}

#[test, expected_failure(abort_code = house::EHouseIsPrivate)]
public fun private_house_error() {
    let addr = @0xa;
    let mut scenario = begin(addr);

    // Create a private house
    let (house, _admin_cap) = house::new(true, 100_000, 50, 1_500, scenario.ctx());
    let _participation = house.new_participation(scenario.ctx());
    abort 0
}

#[test, expected_failure(abort_code = house::EInvalidTxCap)]
public fun process_transactions_wrong_cap() {
    let addr = @0xa;
    let mut scenario = begin(addr);

    // Create a new house and balance manager
    let registry = registry_for_testing(scenario.ctx());
    let (mut house1, _admin_cap1, _tx_cap1) = default_house(scenario.ctx());
    let (mut _house2, _admin_cap2, tx_cap2) = default_house(scenario.ctx());

    let (mut balance_manager, balance_manager_cap) = balance_manager::new(scenario.ctx());
    let play_cap = balance_manager.mint_play_cap(&balance_manager_cap, scenario.ctx());

    house1.tx_admin_process_transactions(
        &registry,
        &tx_cap2,
        &mut balance_manager,
        &vector[bet(10_000), win(5_000)],
        &play_cap,
        scenario.ctx(),
    );
    abort 0
}

#[test]
public fun process_transactions_no_referral() {
    let addr = @0xa;
    let mut scenario = begin(addr);

    // Create a new house and balance manager
    let registry = registry_for_testing(scenario.ctx());
    let (mut house, admin_cap, tx_cap) = default_house(scenario.ctx());
    let participation = fund_house_for_playing(&mut house, 100_000, scenario.ctx());
    scenario.next_epoch(addr);
    let (mut balance_manager, balance_manager_cap) = balance_manager::new(scenario.ctx());
    // Deposit 50_000 on the balance manager
    let deposit = mint_for_testing<SUI>(50_000, scenario.ctx());
    balance_manager.deposit(&balance_manager_cap, deposit, scenario.ctx());
    let play_cap = balance_manager.mint_play_cap(&balance_manager_cap, scenario.ctx());

    house.tx_admin_process_transactions(
        &registry,
        &tx_cap,
        &mut balance_manager,
        &vector[bet(10_000), win(5_000)],
        &play_cap,
        scenario.ctx(),
    );

    let house_fee_coin = house.admin_claim_house_fees(&admin_cap, scenario.ctx());
    let expected_house_fee = int_mul(10_000, house.house_fee_factor());

    assert!(house_fee_coin.value() == expected_house_fee);

    destroy(house);
    destroy(registry);
    destroy(admin_cap);
    destroy(tx_cap);
    destroy(balance_manager);
    destroy(balance_manager_cap);
    destroy(play_cap);
    destroy(house_fee_coin);
    destroy(participation);
    scenario.end();
}

#[test]
public fun process_transactions_with_referral() {
    let addr = @0xa;
    let mut scenario = begin(addr);

    // Create a new house and balance manager
    let registry = registry_for_testing(scenario.ctx());
    let (mut house, admin_cap, tx_cap) = default_house(scenario.ctx());
    let participation = fund_house_for_playing(&mut house, 100_000, scenario.ctx());
    scenario.next_epoch(addr);

    let (mut balance_manager, balance_manager_cap) = balance_manager::new(scenario.ctx());
    // Deposit 50_000 on the balance manager
    let deposit = mint_for_testing<SUI>(50_000, scenario.ctx());
    balance_manager.deposit(&balance_manager_cap, deposit, scenario.ctx());
    let play_cap = balance_manager.mint_play_cap(&balance_manager_cap, scenario.ctx());
    let (referral, referral_cap) = referral::new(house.id(), scenario.ctx());

    house.tx_admin_process_transactions_with_referral(
        &registry,
        &tx_cap,
        &mut balance_manager,
        &vector[bet(10_000), win(5_000)],
        &play_cap,
        &referral,
        scenario.ctx(),
    );

    let expected_house_fee = int_mul(10_000, house.house_fee_factor());
    let expected_referral_fee = int_mul(10_000, house.referral_fee_factor());

    let house_fee_coin = house.admin_claim_house_fees(&admin_cap, scenario.ctx());
    let referral_fee_coin = house.referral_admin_claim_referral_fees(&referral_cap, scenario.ctx());

    assert!(house_fee_coin.value() == expected_house_fee);
    assert!(referral_fee_coin.value() == expected_referral_fee);

    destroy(house);
    destroy(registry);
    destroy(admin_cap);
    destroy(tx_cap);
    destroy(balance_manager);
    destroy(balance_manager_cap);
    destroy(play_cap);
    destroy(house_fee_coin);
    destroy(referral_fee_coin);
    destroy(participation);
    destroy(referral);
    destroy(referral_cap);
    scenario.end();
}
