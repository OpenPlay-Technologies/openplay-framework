/// Registry holds all created games.
module openplay_core::registry;

use openplay_core::constants::max_bps;
use std::uq32_32::{UQ32_32, from_quotient};

// === Structs ===
public struct Registry has key {
    id: UID,
    houses: vector<ID>,
    protocol_fee_bps: u64,
}

public struct REGISTRY has drop {}

/// OpenPlayAdminCap is used to call admin functions.
public struct OpenPlayAdminCap has key, store {
    id: UID,
}

// === Public-Package Functions ===
public(package) fun register_house(self: &mut Registry, house_id: ID) {
    self.houses.push_back(house_id);
}

// === Public-View ===
public fun protocol_fee_factor(self: &Registry): UQ32_32 {
    from_quotient(self.protocol_fee_bps, max_bps())
}

// === Admin Functions ===
public fun update_protocol_fee_bps(
    self: &mut Registry,
    _cap: &OpenPlayAdminCap,
    protocol_fee_bps: u64,
) {
    self.protocol_fee_bps = protocol_fee_bps
}

// === Private Functions ===
fun init(_: REGISTRY, ctx: &mut TxContext) {
    let registry = Registry {
        id: object::new(ctx),
        houses: vector::empty(),
        protocol_fee_bps: 50,
    };
    transfer::share_object(registry);
    let admin = OpenPlayAdminCap { id: object::new(ctx) };
    transfer::public_transfer(admin, ctx.sender());
}

// === Test Functions ===
#[test_only]
public fun registry_for_testing(ctx: &mut TxContext): Registry {
    Registry {
        id: object::new(ctx),
        houses: vector::empty(),
        protocol_fee_bps: 50,
    }
}
