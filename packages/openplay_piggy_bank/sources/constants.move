module openplay_piggy_bank::constants;

use std::string::{String, utf8};

// === Constants ===
const CURRENT_VERSION: u64 = 1; // Update version during upgrades
const MAX_STEPS: u8 = 50;
const EMPTY_POSITION: u8 = 255;
const MAX_PAYOUT_FACTOR_BPS: u64 = 100_000_000; // This is 10_000 times the stake or 1_000_000%

// === Public-View Functions ===
public fun current_version(): u64 {
    CURRENT_VERSION
}

public fun empty_position(): u8 {
    EMPTY_POSITION
}

public fun max_steps(): u8 {
    MAX_STEPS
}

public fun max_payout_factor_bps(): u64 {
    MAX_PAYOUT_FACTOR_BPS
}

public fun new_status(): String {
    utf8(b"New")
}

public fun initialized_status(): String {
    utf8(b"Initialized")
}

public fun game_ongoing_status(): String {
    utf8(b"GameOngoing")
}

public fun game_finished_status(): String {
    utf8(b"GameFinished")
}

public fun start_game_action(): String {
    utf8(b"StartGame")
}

public fun advance_action(): String {
    utf8(b"Advance")
}

public fun cash_out_action(): String {
    utf8(b"CashOut")
}
