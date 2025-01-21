module openplay_core::constants;
// === Imports ===
use std::uq32_32::{UQ32_32, from_quotient};

// === Constant ===
const PROTOCOL_FEE_BPS: u64 = 0; // in bps , taken on bets
const PRECISION_ERROR_ALLOWANCE: u64 = 2;

// === Public-View Functions ===
public fun protocol_fee(): UQ32_32 {
    from_quotient(PROTOCOL_FEE_BPS, 10000)
}

public fun precision_error_allowance(): u64 {
    PRECISION_ERROR_ALLOWANCE
}
