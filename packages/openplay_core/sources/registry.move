/// Registry holds all created games.
module openplay_core::registry;

// === Structs ===
public struct Registry has key {
    id: UID,
    houses: vector<ID>,
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
// === Private Functions ===
fun init(_: REGISTRY, ctx: &mut TxContext) {
    let registry = Registry {
        id: object::new(ctx),
        houses: vector::empty(),
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
        houses: vector::empty()
    }
}