#[test_only]
module openplay_coin_flip::e2e_tests;

use openplay_coin_flip::backend;
use openplay_coin_flip::constants::{place_bet_action, head_result};
use openplay_coin_flip::test_utils::{
    create_and_fix_random,
    fund_house_for_playing,
    assert_eq_within_precision_allowance
};
use openplay_core::balance_manager;
use openplay_core::constants::protocol_fee;
use openplay_core::referral;
use std::string::utf8;
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
    let (mut backend, backend_admin_cap, mut house) = backend::new(
        100_000,
        0,
        20_000,
        10_000,
        0,
        scenario.ctx(),
    );

    // Fund the house
    let mut participation = fund_house_for_playing(&mut house, 200_000, scenario.ctx());
    scenario.next_epoch(addr);

    // Create a balance manager with 10_000 stake
    let (mut balance_manager, balance_manager_cap) = balance_manager::new(scenario.ctx());
    let play_cap = balance_manager.mint_play_cap(&balance_manager_cap, scenario.ctx());
    let deposit = mint_for_testing<SUI>(10_000, scenario.ctx());
    balance_manager.deposit(&balance_manager_cap, deposit, scenario.ctx());

    // Make a referral
    let (referral, referral_cap) = referral::new(utf8(b""), utf8(b""), utf8(b""), scenario.ctx());

    // Place 1_000 bet on head
    let rand = scenario.take_shared<Random>();
    backend.interact_with_referral(
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
    let expected_fee = int_mul(1_000, protocol_fee()) + int_mul(1_000, house.referral_fee_factor());
    assert_eq_within_precision_allowance(
        participation.active_stake(),
        199_000 - expected_fee,
    );

    destroy(balance_manager);
    destroy(participation);
    destroy(balance_manager_cap);
    destroy(play_cap);
    destroy(backend);
    destroy(referral);
    destroy(referral_cap);
    destroy(backend_admin_cap);
    return_shared(rand);
    destroy(house);
    scenario.end();
}

// #[test]
// public fun success_flow_lose() {
//     // We create and fix random
//     // The result will be HEAD
//     create_and_fix_random(x"0F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1E");

//     // Create and fund the coin flip game
//     let addr = @0xa;
//     let mut scenario = begin(addr);
//     let mut registry = registry_for_testing(scenario.ctx());
//     let rand = scenario.take_shared<Random>();
//     let (mut coin_flip_game,  cap) = game::new_coin_flip(
//         &mut registry,
//                 utf8(b""),
//         utf8(b""),
//         utf8(b""),
//         100_000,
//         10_000,
//         0,
//         20_000,
//         scenario.ctx(),
//     );

//     // Fund the game
//     let mut participation = fund_game_for_playing(
//         &mut coin_flip_game,
//         200_000,
//         scenario.ctx(),
//     );
//     scenario.next_epoch(addr);

//     // Create a balance manager with 10_000 stake
//     let (mut balance_manager, balance_manager_cap) = balance_manager::new(scenario.ctx());
//     let proof = balance_manager.generate_proof_as_owner(&balance_manager_cap, scenario.ctx());
//     let play_cap = balance_manager.mint_play_cap(&balance_manager_cap, scenario.ctx());
//     let deposit_balance = mint_for_testing<SUI>(10_000, scenario.ctx()).into_balance();
//     balance_manager.deposit_with_proof(&proof, deposit_balance);

//     // Place 1_000 bet on tail
//     let interact = coin_flip_game.interact_coin_flip(
//         &mut balance_manager,
//         &play_cap,
//         place_bet_action(),
//         1_000,
//         tail_result(),
//         &rand,
//         scenario.ctx(),
//     );

//     assert!(balance_manager.balance() == 9_000);
//     assert!(interact.transactions() == vector[bet(1_000), win(0)]);

//     // Check the stake balance manager
//     scenario.next_epoch(addr);
//     coin_flip_game.update_participation(&mut participation, scenario.ctx());
//     let expected_fee = int_mul(1_000, protocol_fee()) + int_mul(1_000, owner_fee());
//     assert_eq_within_precision_allowance(
//         participation.active_stake(),
//         201_000 - expected_fee,
//     );

//     destroy(coin_flip_game);
//     destroy(balance_manager);
//     destroy(participation);
//     destroy(cap);
//     destroy(balance_manager_cap);
//     destroy(play_cap);
//     destroy(registry);
//     return_shared(rand);
//     scenario.end();
// }
