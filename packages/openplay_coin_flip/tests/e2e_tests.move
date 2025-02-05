#[test_only]
module openplay_coin_flip::e2e_tests;

use openplay_coin_flip::constants::{place_bet_action, head_result, tail_result};
use openplay_coin_flip::test_utils::default_game;
use openplay_core::balance_manager;
use openplay_core::core_test_utils::{
    create_and_fix_random,
    fund_house_for_playing,
    assert_eq_within_precision_allowance
};
use openplay_core::registry::registry_for_testing;
use std::uq32_32::int_mul;
use sui::coin::mint_for_testing;
use sui::random::Random;
use sui::sui::SUI;
use sui::test_scenario::{begin, return_shared};
use sui::test_utils::destroy;

#[test]
public fun success_flow_win() {
    // We create and fix random
    // The result will be HEAD
    create_and_fix_random(x"0F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1E");

    // Start scenario
    let addr = @0xa;
    let mut scenario = begin(addr);

    // Create a coinflip backend
    let registry = registry_for_testing(scenario.ctx());
    let (mut game, mut house, admin_cap) = default_game(scenario.ctx());
    house.admin_add_tx_allowed(&admin_cap, game.id());

    // Fund the house
    let mut participation = fund_house_for_playing(&mut house, 200_000_000, scenario.ctx());
    scenario.next_epoch(addr);

    // Create a balance manager with 10_000 stake
    let (mut balance_manager, balance_manager_cap) = balance_manager::new(scenario.ctx());
    let play_cap = balance_manager.mint_play_cap(&balance_manager_cap, scenario.ctx());
    let deposit = mint_for_testing<SUI>(10_000, scenario.ctx());
    balance_manager.deposit(&balance_manager_cap, deposit, scenario.ctx());

    // Make a referral
    let (referral, referral_cap) = house.referral_for_testing(scenario.ctx());

    // Place 1_000 bet on head
    let rand = scenario.take_shared<Random>();
    game.interact_with_referral(
        &registry,
        &mut balance_manager,
        &mut house,
        &referral,
        &play_cap,
        place_bet_action(),
        1_000,
        head_result(),
        &rand,
        scenario.ctx(),
    );

    assert!(balance_manager.balance() == 11_000);
    // TODO: listen on event
    // assert!(interact.transactions() == vector[bet(1_000), win(2_000)]);

    // Check the stake balance manager
    scenario.next_epoch(addr);
    house.update_participation(&mut participation, scenario.ctx());
    let expected_fee =
        int_mul(1_000, house.referral_fee_factor()) 
    + int_mul(1_000, registry.protocol_fee_factor())
    + int_mul(1_000, house.house_fee_factor());
    assert_eq_within_precision_allowance(
        participation.stake(),
        200_000_000 - 1000 - expected_fee,
    );

    destroy(balance_manager);
    destroy(participation);
    destroy(balance_manager_cap);
    destroy(registry);
    destroy(play_cap);
    destroy(game);
    destroy(referral);
    destroy(referral_cap);
    destroy(admin_cap);

    return_shared(rand);
    destroy(house);
    scenario.end();
}

#[test]
public fun success_flow_lose() {
    // We create and fix random
    // The result will be HEAD
    create_and_fix_random(x"0F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1E");

    // Start scenario
    let addr = @0xa;
    let mut scenario = begin(addr);

    // Create a coinflip backend
    let registry = registry_for_testing(scenario.ctx());
    let (mut game, mut house, admin_cap) = default_game(scenario.ctx());
    house.admin_add_tx_allowed(&admin_cap, game.id());

    // Fund the house
    let mut participation = fund_house_for_playing(&mut house, 200_000_000, scenario.ctx());
    scenario.next_epoch(addr);

    // Create a balance manager with 10_000 stake
    let (mut balance_manager, balance_manager_cap) = balance_manager::new(scenario.ctx());
    let play_cap = balance_manager.mint_play_cap(&balance_manager_cap, scenario.ctx());
    let deposit = mint_for_testing<SUI>(10_000, scenario.ctx());
    balance_manager.deposit(&balance_manager_cap, deposit, scenario.ctx());

    // Make a referral
    let (referral, referral_cap) = house.referral_for_testing(scenario.ctx());

    // Place 1_000 bet on tail
    let rand = scenario.take_shared<Random>();
    game.interact_with_referral(
        &registry,
        &mut balance_manager,
        &mut house,
        &referral,
        &play_cap,
        place_bet_action(),
        1_000,
        tail_result(),
        &rand,
        scenario.ctx(),
    );

    assert!(balance_manager.balance() == 9_000);
    // TODO: listen on event
    // assert!(interact.transactions() == vector[bet(1_000), win(0)]);

    // Check the stake balance manager
    scenario.next_epoch(addr);
    house.update_participation(&mut participation, scenario.ctx());
    let expected_fee =
        int_mul(1_000, house.referral_fee_factor()) 
    + int_mul(1_000, registry.protocol_fee_factor())
    + int_mul(1_000, house.house_fee_factor());
    assert_eq_within_precision_allowance(
        participation.stake(),
        200_000_000 + 1000 - expected_fee,
    );

    destroy(balance_manager);
    destroy(participation);
    destroy(balance_manager_cap);
    destroy(play_cap);
    destroy(game);
    destroy(referral);
    destroy(referral_cap);
    destroy(admin_cap);
    destroy(registry);

    return_shared(rand);
    destroy(house);
    scenario.end();
}
