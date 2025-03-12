#[test_only]
module openplay_piggy_bank::game_tests;

use openplay_core::balance_manager;
use openplay_core::core_test_utils::create_and_fix_random;
use openplay_core::transaction::{bet, win};
use openplay_piggy_bank::constants::{
    start_game_action,
    advance_action,
    cash_out_action,
    game_finished_status,
    game_ongoing_status,
    empty_position,
    current_version
};
use openplay_piggy_bank::context;
use openplay_piggy_bank::game::{Self, new_interact, get_admin_cap_for_testing};
use openplay_piggy_bank::test_utils::{default_game, always_die_game, always_win_game};
use std::uq32_32::{int_mul, from_quotient};
use sui::random::Random;
use sui::test_scenario::{begin, return_shared};
use sui::test_utils::destroy;

#[test]
public fun success_instant_lose() {
    // We create and fix random
    create_and_fix_random(x"1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F");

    // Start scenario
    let addr = @0xa;
    let mut scenario = begin(addr);

    // Create the game
    let (mut game, house, admin_cap) = always_die_game(scenario.ctx());

    // Create a balance manager
    let (balance_manager, balance_manager_cap) = balance_manager::new(scenario.ctx());

    // Internal interact
    let rand = scenario.take_shared<Random>();
    let mut rand_generator = rand.new_generator(scenario.ctx());
    let mut interact = new_interact(start_game_action(), balance_manager.id(), 100);
    game.interact_int(&mut interact, &mut rand_generator);

    // Validate context
    let context = game.get_context_ref(&balance_manager);
    assert!(context.stake() == 100);
    assert!(context.status() == game_finished_status());
    assert!(context.get_win() == 0);
    assert!(context.current_position() == empty_position());

    // Validate transactions
    assert!(interact.transactions() == vector[bet(100)]);

    destroy(game);
    destroy(balance_manager);
    destroy(balance_manager_cap);
    destroy(admin_cap);
    destroy(house);

    return_shared(rand);
    scenario.end();
}

#[test]
public fun success_start_win() {
    // We create and fix random
    create_and_fix_random(x"1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1C");

    // Start scenario
    let addr = @0xa;
    let mut scenario = begin(addr);

    // Create the game
    let (mut game, house, admin_cap) = always_win_game(scenario.ctx());

    // Create a balance manager
    let (balance_manager, balance_manager_cap) = balance_manager::new(scenario.ctx());

    // Internal interact
    let rand = scenario.take_shared<Random>();
    let mut rand_generator = rand.new_generator(scenario.ctx());
    let mut interact = new_interact(start_game_action(), balance_manager.id(), 100);
    game.interact_int(&mut interact, &mut rand_generator);

    // Validate context
    let context = game.get_context_ref(&balance_manager);
    assert!(context.stake() == 100);
    assert!(context.status() == game_ongoing_status());
    assert!(context.get_win() == 0);
    assert!(context.current_position() == 0);

    // Validate transactions
    assert!(interact.transactions() == vector[bet(100)]);

    destroy(game);
    destroy(balance_manager);
    destroy(balance_manager_cap);
    destroy(admin_cap);
    destroy(house);

    return_shared(rand);
    scenario.end();
}

#[test]
public fun success_cash_out() {
    // We create and fix random
    create_and_fix_random(x"1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1C");

    // Start scenario
    let addr = @0xa;
    let mut scenario = begin(addr);

    // Create the game
    let (mut game, house, admin_cap) = default_game(scenario.ctx());

    // Create a balance manager
    let (balance_manager, balance_manager_cap) = balance_manager::new(scenario.ctx());

    // Fix context
    let context = context::create_for_testing(100, 0, 0, game_ongoing_status());
    game.fix_context_for_testing(balance_manager.id(), context);

    // Internal interact
    let rand = scenario.take_shared<Random>();
    let mut rand_generator = rand.new_generator(scenario.ctx());
    let mut interact = new_interact(cash_out_action(), balance_manager.id(), 0);
    game.interact_int(&mut interact, &mut rand_generator);

    // Validate context
    let context = game.get_context_ref(&balance_manager);
    let expected_win = int_mul(100, game.payout_factor(0));
    assert!(context.stake() == 100);
    assert!(context.status() == game_finished_status());
    assert!(context.get_win() == expected_win);
    assert!(context.current_position() == 0);

    // Validate transactions
    assert!(interact.transactions() == vector[win(expected_win)]);

    destroy(game);
    destroy(balance_manager);
    destroy(balance_manager_cap);
    destroy(admin_cap);
    destroy(house);

    return_shared(rand);
    scenario.end();
}

#[test]
public fun success_cash_out_invalid_pos() {
    // We create and fix random
    create_and_fix_random(x"1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1C");

    // Start scenario
    let addr = @0xa;
    let mut scenario = begin(addr);

    // Create the game
    let (mut game, house, admin_cap) = default_game(scenario.ctx());

    // Create a balance manager
    let (balance_manager, balance_manager_cap) = balance_manager::new(scenario.ctx());

    // Fix context
    let context = context::create_for_testing(100, 0, 99, game_ongoing_status());
    game.fix_context_for_testing(balance_manager.id(), context);

    // Internal interact
    let rand = scenario.take_shared<Random>();
    let mut rand_generator = rand.new_generator(scenario.ctx());
    let mut interact = new_interact(cash_out_action(), balance_manager.id(), 0);
    game.interact_int(&mut interact, &mut rand_generator);

    // Validate context
    let context = game.get_context_ref(&balance_manager);
    let expected_win = 0;
    assert!(context.stake() == 100);
    assert!(context.status() == game_finished_status());
    assert!(context.get_win() == expected_win);
    assert!(context.current_position() == 99);

    // Validate transactions
    assert!(interact.transactions() == vector[win(expected_win)]);

    destroy(game);
    destroy(balance_manager);
    destroy(balance_manager_cap);
    destroy(admin_cap);
    destroy(house);

    return_shared(rand);
    scenario.end();
}

#[test]
public fun success_advance_start_0() {
    // We create and fix random
    create_and_fix_random(x"1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1C");

    // Start scenario
    let addr = @0xa;
    let mut scenario = begin(addr);

    // Create the game
    let (mut game, house, admin_cap) = always_win_game(scenario.ctx());

    // Create a balance manager
    let (balance_manager, balance_manager_cap) = balance_manager::new(scenario.ctx());

    // Fix context
    let context = context::create_for_testing(100, 0, 0, game_ongoing_status());
    game.fix_context_for_testing(balance_manager.id(), context);

    // Internal interact
    let rand = scenario.take_shared<Random>();
    let mut rand_generator = rand.new_generator(scenario.ctx());
    let mut interact = new_interact(advance_action(), balance_manager.id(), 0);
    game.interact_int(&mut interact, &mut rand_generator);

    // Validate context
    let context = game.get_context_ref(&balance_manager);
    assert!(context.stake() == 100);
    assert!(context.status() == game_ongoing_status());
    assert!(context.get_win() == 0);
    assert!(context.current_position() == 1);

    // Validate transactions
    assert!(interact.transactions() == vector[]);

    destroy(game);
    destroy(balance_manager);
    destroy(balance_manager_cap);
    destroy(admin_cap);
    destroy(house);

    return_shared(rand);
    scenario.end();
}

#[test]
public fun success_advance_start_1() {
    // We create and fix random
    create_and_fix_random(x"1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1C");

    // Start scenario
    let addr = @0xa;
    let mut scenario = begin(addr);

    // Create the game
    let (mut game, house, admin_cap) = always_win_game(scenario.ctx());

    // Create a balance manager
    let (balance_manager, balance_manager_cap) = balance_manager::new(scenario.ctx());

    // Fix context
    let context = context::create_for_testing(100, 0, 1, game_ongoing_status());
    game.fix_context_for_testing(balance_manager.id(), context);

    // Internal interact
    let rand = scenario.take_shared<Random>();
    let mut rand_generator = rand.new_generator(scenario.ctx());
    let mut interact = new_interact(advance_action(), balance_manager.id(), 0);
    game.interact_int(&mut interact, &mut rand_generator);

    // Validate context
    let context = game.get_context_ref(&balance_manager);
    assert!(context.stake() == 100);
    assert!(context.status() == game_ongoing_status());
    assert!(context.get_win() == 0);
    assert!(context.current_position() == 2);

    // Validate transactions
    assert!(interact.transactions() == vector[]);

    destroy(game);
    destroy(balance_manager);
    destroy(balance_manager_cap);
    destroy(admin_cap);
    destroy(house);

    return_shared(rand);
    scenario.end();
}

#[test]
public fun success_win() {
    // We create and fix random
    create_and_fix_random(x"1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1C");

    // Start scenario
    let addr = @0xa;
    let mut scenario = begin(addr);

    // Create the game
    let (mut game, house, admin_cap) = always_win_game(scenario.ctx());

    // Create a balance manager
    let (balance_manager, balance_manager_cap) = balance_manager::new(scenario.ctx());

    // Fix context
    let context = context::create_for_testing(100, 0, 2, game_ongoing_status());
    game.fix_context_for_testing(balance_manager.id(), context);

    // Internal interact
    let rand = scenario.take_shared<Random>();
    let mut rand_generator = rand.new_generator(scenario.ctx());
    let mut interact = new_interact(advance_action(), balance_manager.id(), 0);
    game.interact_int(&mut interact, &mut rand_generator);

    // Validate context
    let context = game.get_context_ref(&balance_manager);
    let expected_win = game.max_payout(100);
    assert!(context.stake() == 100);
    assert!(context.status() == game_finished_status());
    assert!(context.get_win() == expected_win);
    assert!(context.current_position() == 3);

    // Validate transactions
    assert!(interact.transactions() == vector[win(expected_win)]);

    destroy(game);
    destroy(balance_manager);
    destroy(balance_manager_cap);
    destroy(admin_cap);
    destroy(house);

    return_shared(rand);
    scenario.end();
}

#[test]
public fun success_new_game_after_win() {
    // We create and fix random
    create_and_fix_random(x"1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1C");

    // Start scenario
    let addr = @0xa;
    let mut scenario = begin(addr);

    // Create the game
    let (mut game, house, admin_cap) = always_win_game(scenario.ctx());

    // Create a balance manager
    let (balance_manager, balance_manager_cap) = balance_manager::new(scenario.ctx());

    // Fix context
    let context = context::create_for_testing(100, 100, 2, game_finished_status());
    game.fix_context_for_testing(balance_manager.id(), context);

    // Internal interact
    let rand = scenario.take_shared<Random>();
    let mut rand_generator = rand.new_generator(scenario.ctx());
    let mut interact = new_interact(start_game_action(), balance_manager.id(), 200);
    game.interact_int(&mut interact, &mut rand_generator);

    // Validate context
    let context = game.get_context_ref(&balance_manager);
    assert!(context.stake() == 200);
    assert!(context.status() == game_ongoing_status());
    assert!(context.get_win() == 0);
    assert!(context.current_position() == 0);

    // Validate transactions
    assert!(interact.transactions() == vector[bet(200)]);

    destroy(game);
    destroy(balance_manager);
    destroy(balance_manager_cap);
    destroy(admin_cap);
    destroy(house);

    return_shared(rand);
    scenario.end();
}

#[test]
public fun success_instant_loss_after_win() {
    // We create and fix random
    create_and_fix_random(x"1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1C");

    // Start scenario
    let addr = @0xa;
    let mut scenario = begin(addr);

    // Create the game
    let (mut game, house, admin_cap) = always_die_game(scenario.ctx());

    // Create a balance manager
    let (balance_manager, balance_manager_cap) = balance_manager::new(scenario.ctx());

    // Fix context
    let context = context::create_for_testing(100, 100, 2, game_finished_status());
    game.fix_context_for_testing(balance_manager.id(), context);

    // Internal interact
    let rand = scenario.take_shared<Random>();
    let mut rand_generator = rand.new_generator(scenario.ctx());
    let mut interact = new_interact(start_game_action(), balance_manager.id(), 200);
    game.interact_int(&mut interact, &mut rand_generator);

    // Validate context
    let context = game.get_context_ref(&balance_manager);
    assert!(context.stake() == 200);
    assert!(context.status() == game_finished_status());
    assert!(context.get_win() == 0);
    assert!(context.current_position() == empty_position());

    // Validate transactions
    assert!(interact.transactions() == vector[bet(200)]);

    destroy(game);
    destroy(balance_manager);
    destroy(balance_manager_cap);
    destroy(admin_cap);
    destroy(house);

    return_shared(rand);
    scenario.end();
}

#[test]
public fun success_new_game_after_loss() {
    // We create and fix random
    create_and_fix_random(x"1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1C");

    // Start scenario
    let addr = @0xa;
    let mut scenario = begin(addr);

    // Create the game
    let (mut game, house, admin_cap) = always_win_game(scenario.ctx());

    // Create a balance manager
    let (balance_manager, balance_manager_cap) = balance_manager::new(scenario.ctx());

    // Fix context
    let context = context::create_for_testing(100, 0, empty_position(), game_finished_status());
    game.fix_context_for_testing(balance_manager.id(), context);

    // Internal interact
    let rand = scenario.take_shared<Random>();
    let mut rand_generator = rand.new_generator(scenario.ctx());
    let mut interact = new_interact(start_game_action(), balance_manager.id(), 200);
    game.interact_int(&mut interact, &mut rand_generator);

    // Validate context
    let context = game.get_context_ref(&balance_manager);
    assert!(context.stake() == 200);
    assert!(context.status() == game_ongoing_status());
    assert!(context.get_win() == 0);
    assert!(context.current_position() == 0);

    // Validate transactions
    assert!(interact.transactions() == vector[bet(200)]);

    destroy(game);
    destroy(balance_manager);
    destroy(balance_manager_cap);
    destroy(admin_cap);
    destroy(house);

    return_shared(rand);
    scenario.end();
}

#[test]
public fun success_advance_die() {
    // We create and fix random
    create_and_fix_random(x"1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1C");

    // Start scenario
    let addr = @0xa;
    let mut scenario = begin(addr);

    // Create the game
    let (mut game, house, admin_cap) = always_die_game(scenario.ctx());

    // Create a balance manager
    let (balance_manager, balance_manager_cap) = balance_manager::new(scenario.ctx());

    // Fix context
    let context = context::create_for_testing(100, 0, 0, game_ongoing_status());
    game.fix_context_for_testing(balance_manager.id(), context);

    // Internal interact
    let rand = scenario.take_shared<Random>();
    let mut rand_generator = rand.new_generator(scenario.ctx());
    let mut interact = new_interact(advance_action(), balance_manager.id(), 0);
    game.interact_int(&mut interact, &mut rand_generator);

    // Validate context
    let context = game.get_context_ref(&balance_manager);
    assert!(context.stake() == 100);
    assert!(context.status() == game_finished_status());
    assert!(context.get_win() == 0);
    assert!(context.current_position() == 0);

    // Validate transactions
    assert!(interact.transactions() == vector[]);

    destroy(game);
    destroy(balance_manager);
    destroy(balance_manager_cap);
    destroy(admin_cap);
    destroy(house);

    return_shared(rand);
    scenario.end();
}

#[test, expected_failure(abort_code = game::EGameNotInProgress)]
public fun fail_advance_after_finish() {
    // We create and fix random
    create_and_fix_random(x"1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1C");

    // Start scenario
    let addr = @0xa;
    let mut scenario = begin(addr);

    // Create the game
    let (mut game, _house, _admin_cap) = default_game(scenario.ctx());

    // Create a balance manager
    let (balance_manager, _balance_manager_cap) = balance_manager::new(scenario.ctx());

    // Fix context
    let context = context::create_for_testing(100, 0, 0, game_finished_status());
    game.fix_context_for_testing(balance_manager.id(), context);

    // Internal interact
    let rand = scenario.take_shared<Random>();
    let mut rand_generator = rand.new_generator(scenario.ctx());
    let mut interact = new_interact(advance_action(), balance_manager.id(), 0);
    game.interact_int(&mut interact, &mut rand_generator);
    abort 0
}

#[test, expected_failure(abort_code = game::ECannotAdvanceFurther)]
public fun fail_advance_invalid_position() {
    // We create and fix random
    create_and_fix_random(x"1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1C");

    // Start scenario
    let addr = @0xa;
    let mut scenario = begin(addr);

    // Create the game
    let (mut game, _house, _admin_cap) = default_game(scenario.ctx());

    // Create a balance manager
    let (balance_manager, _balance_manager_cap) = balance_manager::new(scenario.ctx());

    // Fix context
    let context = context::create_for_testing(100, 0, 99, game_ongoing_status());
    game.fix_context_for_testing(balance_manager.id(), context);

    // Internal interact
    let rand = scenario.take_shared<Random>();
    let mut rand_generator = rand.new_generator(scenario.ctx());
    let mut interact = new_interact(advance_action(), balance_manager.id(), 0);
    game.interact_int(&mut interact, &mut rand_generator);
    abort 0
}

#[test, expected_failure(abort_code = game::EGameAlreadyOngoing)]
public fun fail_start_game_while_ongoing() {
    // We create and fix random
    create_and_fix_random(x"1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1C");

    // Start scenario
    let addr = @0xa;
    let mut scenario = begin(addr);

    // Create the game
    let (mut game, _house, _admin_cap) = default_game(scenario.ctx());

    // Create a balance manager
    let (balance_manager, _balance_manager_cap) = balance_manager::new(scenario.ctx());

    // Fix context
    let context = context::create_for_testing(100, 0, 99, game_ongoing_status());
    game.fix_context_for_testing(balance_manager.id(), context);

    // Internal interact
    let rand = scenario.take_shared<Random>();
    let mut rand_generator = rand.new_generator(scenario.ctx());
    let mut interact = new_interact(start_game_action(), balance_manager.id(), 100);
    game.interact_int(&mut interact, &mut rand_generator);
    abort 0
}

#[test, expected_failure(abort_code = game::EInvalidCashOut)]
public fun fail_cash_out_empty_pos() {
    // We create and fix random
    create_and_fix_random(x"1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1C");

    // Start scenario
    let addr = @0xa;
    let mut scenario = begin(addr);

    // Create the game
    let (mut game, _house, _admin_cap) = default_game(scenario.ctx());

    // Create a balance manager
    let (balance_manager, _balance_manager_cap) = balance_manager::new(scenario.ctx());

    // Fix context
    let context = context::create_for_testing(100, 0, empty_position(), game_ongoing_status());
    game.fix_context_for_testing(balance_manager.id(), context);

    // Internal interact
    let rand = scenario.take_shared<Random>();
    let mut rand_generator = rand.new_generator(scenario.ctx());
    let mut interact = new_interact(cash_out_action(), balance_manager.id(), 100);
    game.interact_int(&mut interact, &mut rand_generator);
    abort 0
}

#[test, expected_failure(abort_code = game::EGameNotInProgress)]
public fun fail_cash_out_game_finished() {
    // We create and fix random
    create_and_fix_random(x"1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1C");

    // Start scenario
    let addr = @0xa;
    let mut scenario = begin(addr);

    // Create the game
    let (mut game, _house, _admin_cap) = default_game(scenario.ctx());

    // Create a balance manager
    let (balance_manager, _balance_manager_cap) = balance_manager::new(scenario.ctx());

    // Fix context
    let context = context::create_for_testing(100, 0, 1, game_finished_status());
    game.fix_context_for_testing(balance_manager.id(), context);

    // Internal interact
    let rand = scenario.take_shared<Random>();
    let mut rand_generator = rand.new_generator(scenario.ctx());
    let mut interact = new_interact(cash_out_action(), balance_manager.id(), 100);
    game.interact_int(&mut interact, &mut rand_generator);
    abort 0
}

#[test, expected_failure(abort_code = game::EUnsupportedStake)]
public fun fail_unsupported_stake() {
    // We create and fix random
    create_and_fix_random(x"1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1C");

    // Start scenario
    let addr = @0xa;
    let mut scenario = begin(addr);

    // Create the game
    let (mut game, _house, _admin_cap) = default_game(scenario.ctx());

    // Create a balance manager
    let (balance_manager, _balance_manager_cap) = balance_manager::new(scenario.ctx());

    // Internal interact
    let rand = scenario.take_shared<Random>();
    let mut rand_generator = rand.new_generator(scenario.ctx());
    let mut interact = new_interact(start_game_action(), balance_manager.id(), 10_000_000 + 1);
    game.interact_int(&mut interact, &mut rand_generator);
    abort 0
}

#[test]
public fun correct_props() {
    let addr = @0xa;
    let mut scenario = begin(addr);

    // Create the game
    let (game, house, admin_cap) = default_game(scenario.ctx());

    // Payout factor
    assert!(game.payout_factor(0) == from_quotient(20_000, 10_000));
    assert!(game.payout_factor(3) == from_quotient(160_000, 10_000));

    // Max step
    assert!(game.max_step_index() == 3);

    // Stake
    assert!(game.max_stake() == 10_000_000);
    assert!(game.min_stake() == 0);

    destroy(game);
    destroy(admin_cap);
    destroy(house);
    scenario.end();
}

#[test, expected_failure(abort_code = game::EPackageVersionDisabled)]
public fun version_check_ok() {
    let addr = @0xa;
    let mut scenario = begin(addr);
    create_and_fix_random(x"1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1C");

    // Create the game
    let (mut game, _house, _admin_cap) = default_game(scenario.ctx());

    // Disable the current version
    let cap = get_admin_cap_for_testing(scenario.ctx());
    game.admin_disallow_version(&cap, current_version());

    // Interact
    let rand = scenario.take_shared<Random>();
    let mut generator = rand.new_generator(scenario.ctx());
    game.interact_int(
        &mut new_interact(cash_out_action(), object::id_from_address(@0xa), 0),
        &mut generator,
    );

    abort 0
}
