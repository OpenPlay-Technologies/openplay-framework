#[test_only]
module openplay_coin_flip::versioning_tests;

use openplay_coin_flip::constants::current_version;
use openplay_coin_flip::game::{Self, get_admin_cap_for_testing};
use openplay_coin_flip::test_utils::default_game;
use sui::test_scenario::begin;

#[test, expected_failure(abort_code = game::EPackageVersionDisabled)]
public fun version_disabled() {
    let addr = @0xA;
    let mut scenario = begin(addr);

    // Create a coinflip backend
    let (mut game, _house, _admin_cap) = default_game(scenario.ctx());
    let coin_flip_cap = get_admin_cap_for_testing(scenario.ctx());

    // Ok
    game.house_id();

    // Disallow current version
    game.admin_disallow_version(&coin_flip_cap, current_version());

    // Not ok
    game.house_id();
    abort 0
}

#[test, expected_failure(abort_code = game::EVersionAlreadyAllowed)]
public fun version_already_enabled() {
    let addr = @0xA;
    let mut scenario = begin(addr);

    // Create a coinflip backend
    let (mut game, _house, _admin_cap) = default_game(scenario.ctx());
    let coin_flip_cap = get_admin_cap_for_testing(scenario.ctx());

    // Allow current version
    game.admin_allow_version(&coin_flip_cap, current_version());
    abort 0
}
