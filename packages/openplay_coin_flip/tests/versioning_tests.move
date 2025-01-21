#[test_only]
module openplay_coin_flip::versioning_tests;

use openplay_coin_flip::backend;
use openplay_coin_flip::constants::current_version;
use sui::test_scenario::begin;

#[test, expected_failure(abort_code = backend::EPackageVersionDisabled)]
public fun version_disabled() {
    let addr = @0xA;
    let mut scenario = begin(addr);

    // Create a coinflip backend
    let (mut backend, backend_admin_cap, _house) = backend::new(
        100_000,
        0,
        20_000,
        10_000,
        0,
        scenario.ctx(),
    );

    // Ok
    backend.house_id();

    // Disallow current version
    backend.admin_disallow_version(&backend_admin_cap, current_version());

    // Not ok
    backend.house_id();
    abort 0
}

#[test, expected_failure(abort_code = backend::EVersionAlreadyAllowed)]
public fun version_already_enabled() {
    let addr = @0xA;
    let mut scenario = begin(addr);

    // Create a coinflip backend
    let (mut backend, backend_admin_cap, _house) = backend::new(
        100_000,
        0,
        20_000,
        10_000,
        0,
        scenario.ctx(),
    );

    // Allow current version
    backend.admin_allow_version(&backend_admin_cap, current_version());
    abort 0
}

#[test, expected_failure(abort_code = backend::EUnauthorized)]
public fun version_unauthorized() {
    let addr = @0xA;
    let mut scenario = begin(addr);

    // Create a coinflip backend
    let (mut backend1, _backend_admin_cap1, mut _house1) = backend::new(
        100_000,
        0,
        20_000,
        10_000,
        0,
        scenario.ctx(),
    );
    // And a second one
    let (mut _backend2, backend_admin_cap2, mut _house) = backend::new(
        100_000,
        0,
        20_000,
        10_000,
        0,
        scenario.ctx(),
    );

    // Allow current version
    backend1.admin_disallow_version(&backend_admin_cap2, current_version());
    abort 0
}
