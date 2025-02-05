#[test_only]
module openplay_coin_flip::test_utils;

use openplay_coin_flip::game::{Self, Game, get_admin_cap_for_testing};
use openplay_core::house::{Self, House, HouseAdminCap};
use sui::test_utils::destroy;

public fun default_game(ctx: &mut TxContext): (Game, House, HouseAdminCap) {
    let coin_flip_cap = get_admin_cap_for_testing(ctx);
    let game = game::admin_create(&coin_flip_cap, 0, 10_000_000, 2_000, 20_000, ctx);

    let (house, house_admin_cap) = house::new(false, 10_000_000, 50, 50, ctx);

    destroy(coin_flip_cap);
    (game, house, house_admin_cap)
}
