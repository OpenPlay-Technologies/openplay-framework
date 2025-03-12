module openplay_core::constants;

use std::string::{String, utf8};

// === Constant ===
const PRECISION_ERROR_ALLOWANCE: u64 = 2;
const CURRENT_VERSION: u64 = 2;

// === Public-View Functions ===
public fun precision_error_allowance(): u64 {
    PRECISION_ERROR_ALLOWANCE
}

public fun max_bps(): u64 {
    10_000
}

public fun tx_type_bet(): String {
    utf8(b"Bet")
}

public fun tx_type_win(): String {
    utf8(b"Win")
}

public fun current_version(): u64 {
    CURRENT_VERSION
}