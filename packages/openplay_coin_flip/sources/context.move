module openplay_coin_flip::context;

use openplay_coin_flip::constants::{
    head_result,
    tail_result,
    house_bias_result,
    new_status,
    initialized_status,
    settled_status
};
use std::string::String;

// === Errors ===
const EInvalidStateTransition: u64 = 1;
const EUnsupportedResult: u64 = 2;
const EUnsupportedPrediction: u64 = 3;

// === Structs ===
// Context representing the current state of the game for a single user
public struct CoinFlipContext has copy, drop, store {
    stake: u64,
    prediction: String,
    result: String,
    status: String,
    win: u64,
}

// === Public-View Functions ===
/// True if the prediction is equal to the result of the coin flip, false otherwise.
/// Does not check the state of the game.
public fun player_won(self: &CoinFlipContext): bool {
    self.result == self.prediction
}

/// The result of the coin flip.
/// Does not check the state of the game.
public fun result(self: &CoinFlipContext): String {
    self.result
}

public fun status(self: &CoinFlipContext): String {
    self.status
}

public fun prediction(self: &CoinFlipContext): String {
    self.prediction
}

public fun win(self: &CoinFlipContext): u64 {
    self.win
}

// === Public-Package Functions ===
public(package) fun empty(): CoinFlipContext {
    CoinFlipContext {
        stake: 0,
        prediction: head_result(),
        result: head_result(),
        status: new_status(),
        win: 0,
    }
}

public(package) fun bet(self: &mut CoinFlipContext, stake: u64, prediction: String) {
    assert_valid_prediction(&prediction);

    // Transition status
    let new_status = initialized_status();
    self.assert_valid_state_transition(new_status);
    self.status = new_status;

    // Update context
    self.stake = stake;
    self.prediction = prediction;
    self.win = 0;
}

public(package) fun settle(self: &mut CoinFlipContext, result: String, win: u64) {
    assert_valid_result(&result);

    // Transition status
    let new_status = settled_status();
    self.assert_valid_state_transition(new_status);
    self.status = new_status;

    // Update context
    self.result = result;
    self.win = win;
}

// === Private Functions ===
fun assert_valid_result(result: &String) {
    assert!(
        result == head_result() || result == tail_result() || result == house_bias_result(),
        EUnsupportedResult,
    );
}

fun assert_valid_prediction(prediction: &String) {
    assert!(prediction == head_result() || prediction == tail_result(), EUnsupportedPrediction);
}

fun assert_valid_state_transition(self: &CoinFlipContext, state_to: String) {
    if (self.status == new_status()) {
        assert!(state_to == initialized_status(), EInvalidStateTransition)
    } else if (self.status == initialized_status()) {
        assert!(state_to == settled_status(), EInvalidStateTransition)
    } else if (self.status == settled_status()) {
        assert!(state_to == initialized_status(), EInvalidStateTransition)
    } else {
        abort EInvalidStateTransition
    }
}
