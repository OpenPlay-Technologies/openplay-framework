#[test_only]
module openplay_piggy_bank::test_utils;

use openplay_core::house::{Self, House, HouseAdminCap};
use openplay_piggy_bank::game::{Self, Game, get_admin_cap_for_testing};
use sui::test_utils::destroy;

public fun default_game(ctx: &mut TxContext): (Game, House, HouseAdminCap) {
    let cap = get_admin_cap_for_testing(ctx);
    let game = game::admin_create(
        &cap,
        0,
        10_000_000,
        5_000,
        vector[20_000, 40_000, 80_000, 160_000],
        ctx,
    );

    let (house, house_admin_cap) = house::new(false, 10_000_000, 50, 50, ctx);

    destroy(cap);
    (game, house, house_admin_cap)
}

public fun always_die_game(ctx: &mut TxContext): (Game, House, HouseAdminCap) {
    let cap = get_admin_cap_for_testing(ctx);
    let game = game::admin_create(
        &cap,
        0,
        10_000_000,
        0,
        vector[20_000, 40_000, 80_000, 160_000],
        ctx,
    );

    let (house, house_admin_cap) = house::new(false, 10_000_000, 50, 50, ctx);

    destroy(cap);
    (game, house, house_admin_cap)
}

public fun always_win_game(ctx: &mut TxContext): (Game, House, HouseAdminCap) {
    let cap = get_admin_cap_for_testing(ctx);
    let game = game::admin_create(
        &cap,
        0,
        10_000_000,
        10_000,
        vector[20_000, 40_000, 80_000, 160_000],
        ctx,
    );

    let (house, house_admin_cap) = house::new(false, 10_000_000, 50, 50, ctx);

    destroy(cap);
    (game, house, house_admin_cap)
}
