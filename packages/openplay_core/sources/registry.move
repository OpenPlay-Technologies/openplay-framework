/// Registry holds all created games.
module openplay_core::registry;

use openplay_core::constants::{max_bps, current_version};
use std::uq32_32::{UQ32_32, from_quotient};
use sui::vec_set::{Self, VecSet};

// === Errors ===
const EPackageVersionDisabled: u64 = 1;
const EVersionAlreadyAllowed: u64 = 2;
const EVersionAlreadyDisabled: u64 = 3;

// === Structs ===
public struct Registry has key {
    id: UID,
    allowed_versions: VecSet<u64>,
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
    self.assert_version();
    self.houses.push_back(house_id);
}

// === Public-View ===
public fun protocol_fee_factor(self: &Registry): UQ32_32 {
    self.assert_version();
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

public fun admin_allow_version(self: &mut Registry, _cap: &OpenPlayAdminCap, version: u64) {
    assert!(!self.allowed_versions.contains(&version), EVersionAlreadyAllowed);
    self.allowed_versions.insert(version);
}

public fun admin_disallow_version(self: &mut Registry, _cap: &OpenPlayAdminCap, version: u64) {
    assert!(self.allowed_versions.contains(&version), EVersionAlreadyDisabled);
    self.allowed_versions.remove(&version);
}

// === Private Functions ===
fun init(_: REGISTRY, ctx: &mut TxContext) {
    let mut allowed_versions = vec_set::empty();
    allowed_versions.insert(current_version());

    let registry = Registry {
        id: object::new(ctx),
        allowed_versions,
        houses: vector::empty(),
        protocol_fee_bps: 50,
    };
    transfer::share_object(registry);
    let admin = OpenPlayAdminCap { id: object::new(ctx) };
    transfer::public_transfer(admin, ctx.sender());
}

fun assert_version(self: &Registry) {
    let package_version = current_version();
    assert!(self.allowed_versions.contains(&package_version), EPackageVersionDisabled);
}

// === Test Functions ===
#[test_only]
public fun registry_for_testing(ctx: &mut TxContext): Registry {
    let mut allowed_versions = vec_set::empty();
    allowed_versions.insert(current_version());

    Registry {
        id: object::new(ctx),
        allowed_versions,
        houses: vector::empty(),
        protocol_fee_bps: 50,
    }
}

#[test_only]
public fun cap_for_testing(ctx: &mut TxContext): OpenPlayAdminCap {
    OpenPlayAdminCap { 
        id: object::new(ctx)
    }
}