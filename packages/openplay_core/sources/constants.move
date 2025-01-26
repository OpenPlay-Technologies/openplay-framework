module openplay_core::constants;

// === Constant ===
const PRECISION_ERROR_ALLOWANCE: u64 = 2;

// === Public-View Functions ===
public fun precision_error_allowance(): u64 {
    PRECISION_ERROR_ALLOWANCE
}

public fun max_bps(): u64 {
    10_000
}