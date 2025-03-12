module openplay_piggy_bank::context;

use openplay_piggy_bank::constants::{
    new_status,
    game_ongoing_status,
    game_finished_status,
    empty_position,
    initialized_status
};
use std::string::String;

// === Errors ===
const EInvalidStateTransition: u64 = 1;

// === Structs ===
public struct PiggyBankContext has copy, drop, store {
    stake: u64,
    win: u64,
    current_position: u8,
    status: String,
}

// === Public-View Functions ===
public fun status(self: &PiggyBankContext): String {
    self.status
}

public fun current_position(self: &PiggyBankContext): u8 {
    self.current_position
}

public fun stake(self: &PiggyBankContext): u64 {
    self.stake
}

public fun get_win(self: &PiggyBankContext): u64 {
    self.win
}

// === Public-Package Functions ===
public(package) fun empty(): PiggyBankContext {
    PiggyBankContext {
        stake: 0,
        win: 0,
        current_position: empty_position(),
        status: new_status(),
    }
}

public(package) fun start_game(self: &mut PiggyBankContext, stake: u64) {
    // Transition status
    let status = initialized_status();
    self.assert_valid_state_transition(status);
    self.status = status;

    // Update context
    self.stake = stake;
    self.win = 0;
    self.current_position = empty_position();
}

public(package) fun advance_position(self: &mut PiggyBankContext) {
    // Enter first position
    if (self.current_position == empty_position()) {
        assert!(self.status() == initialized_status(), EInvalidStateTransition);
        self.current_position = 0;

        // Transition status
        let status = game_ongoing_status();
        self.assert_valid_state_transition(status);
        self.status = status;
    } else {
        // Move to next position
        assert!(self.status() == game_ongoing_status(), EInvalidStateTransition);
        self.current_position = self.current_position + 1;
    }
}

public(package) fun die(self: &mut PiggyBankContext) {
    // Transition status
    let status = game_finished_status();
    self.assert_valid_state_transition(status);
    self.status = status;

    self.win = 0;
}

public(package) fun process_win(self: &mut PiggyBankContext, win: u64) {
    // Transition status
    let status = game_finished_status();
    self.assert_valid_state_transition(status);
    self.status = status;

    self.win = win;
}

// === Private Functions ===
fun assert_valid_state_transition(self: &PiggyBankContext, state_to: String) {
    if (self.status == new_status()) {
        assert!(state_to == initialized_status(), EInvalidStateTransition);
    } else if (self.status == initialized_status()) {
        assert!(
            state_to == game_ongoing_status() || state_to == game_finished_status(),
            EInvalidStateTransition,
        );
    } else if (self.status == game_ongoing_status()) {
        assert!(
            state_to == game_ongoing_status() || state_to == game_finished_status(),
            EInvalidStateTransition,
        )
    } else if (self.status == game_finished_status()) {
        assert!(state_to == initialized_status(), EInvalidStateTransition)
    } else {
        abort EInvalidStateTransition
    }
}

// === Test Functions ===
#[test_only]
public fun create_for_testing(
    stake: u64,
    win: u64,
    current_position: u8,
    status: String,
): PiggyBankContext {
    PiggyBankContext {
        stake,
        win,
        current_position,
        status,
    }
}
