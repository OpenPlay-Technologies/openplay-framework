#[test_only]
module openplay_coin_flip::game_tests;

use openplay_coin_flip::constants::{
    place_bet_action,
    tail_result,
    settled_status,
    head_result,
    house_bias_result
};
use openplay_coin_flip::game::{Self, new_interact, get_admin_cap_for_testing};
use openplay_coin_flip::test_utils::default_game;
use openplay_core::balance_manager;
use openplay_core::core_test_utils::create_and_fix_random;
use openplay_core::transaction::{bet, win};
use sui::random::Random;
use sui::test_scenario::{begin, return_shared};
use sui::test_utils::destroy;

#[test]
public fun success_win_flow() {
    // We create and fix random
    // The result will be HEAD
    create_and_fix_random(x"1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F");

    // Start scenario
    let addr = @0xa;
    let mut scenario = begin(addr);

    // Create a coinflip backend
    let (mut game, house, admin_cap) = default_game(scenario.ctx());

    // Create a balance manager
    let (balance_manager, balance_manager_cap) = balance_manager::new(scenario.ctx());

    // Internal interact
let rand = scenario.take_shared<Random>();
    let mut rand_generator = rand.new_generator(scenario.ctx());
    let mut interact = new_interact(place_bet_action(), balance_manager.id(), head_result(), 100);
    game.interact_int(&mut interact, &mut rand_generator);

    // Validate context
    let context = game.get_context(&balance_manager);
    assert!(context.result() == head_result());
    assert!(context.prediction() == head_result());
    assert!(context.status() == settled_status());
    assert!(context.player_won() == true);

    // Validate transactions
    assert!(interact.transactions() == vector[bet(100), win(200)]);

    destroy(game);
    destroy(balance_manager);
    destroy(balance_manager_cap);
    destroy(admin_cap);
    destroy(house);

    return_shared(rand);
    scenario.end();
}

#[test]
public fun success_lose_flow() {
    // We create and fix random
    // The result will be HEAD
    create_and_fix_random(x"1F1F2F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F2F");

    // Start scenario
    let addr = @0xa;
    let mut scenario = begin(addr);

    // Create a coinflip backend
    let (mut game, house, admin_cap) = default_game(scenario.ctx());

    // Create a balance manager
    let (balance_manager, balance_manager_cap) = balance_manager::new(scenario.ctx());

    // Internal interact
let rand = scenario.take_shared<Random>();
    let mut rand_generator = rand.new_generator(scenario.ctx());
    let mut interact = new_interact(place_bet_action(), balance_manager.id(), tail_result(), 100);
    game.interact_int(&mut interact, &mut rand_generator);

    // Validate context
    let context = game.get_context(&balance_manager);
    assert!(context.result() == head_result());
    assert!(context.prediction() == tail_result());
    assert!(context.status() == settled_status());
    assert!(context.player_won() == false);

    // Validate transactions
    assert!(interact.transactions() == vector[bet(100), win(0)]);

    destroy(game);
    destroy(balance_manager);
    destroy(balance_manager_cap);
    destroy(admin_cap);
    destroy(house);

    return_shared(rand);
    scenario.end();
}

#[test]
public fun success_house_bias_flow() {
    // We create and fix random
    // The result will be HOUSE BIAS
    create_and_fix_random(x"0F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1E");

    // Start scenario
    let addr = @0xa;
    let mut scenario = begin(addr);

    // Create a coinflip backend
    let coin_flip_cap = get_admin_cap_for_testing(scenario.ctx());
    let mut game = game::admin_create(
        &coin_flip_cap,
        0,
        10_000_000,
        9_999,
        20_000,
        scenario.ctx(),
    );

    // Create a balance manager
    let (balance_manager, balance_manager_cap) = balance_manager::new(scenario.ctx());

    // Internal interact
let rand = scenario.take_shared<Random>();
    let mut rand_generator = rand.new_generator(scenario.ctx());
    let mut interact = new_interact(place_bet_action(), balance_manager.id(), tail_result(), 100);
    game.interact_int(&mut interact, &mut rand_generator);

    // Validate context
    let context = game.get_context(&balance_manager);
    assert!(context.result() == house_bias_result());
    assert!(context.prediction() == tail_result());
    assert!(context.status() == settled_status());
    assert!(context.player_won() == false);

    // Validate transactions
    assert!(interact.transactions() == vector[bet(100), win(0)]);

    destroy(game);
    destroy(balance_manager);
    destroy(balance_manager_cap);
    destroy(coin_flip_cap);
    return_shared(rand);
    scenario.end();
}
