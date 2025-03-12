#[test_only]
module openplay_piggy_bank::context_tests;

use openplay_piggy_bank::constants::{
    game_finished_status,
    game_ongoing_status,
    empty_position,
    new_status,
    initialized_status
};
use openplay_piggy_bank::context;

#[test]
public fun success_win_flow() {
    let mut context = context::empty();

    assert!(context.status() == new_status());
    assert!(context.stake() == 0);
    assert!(context.current_position() == empty_position());
    assert!(context.get_win() == 0);

    context.start_game(10);

    assert!(context.status() == initialized_status());
    assert!(context.stake() == 10);
    assert!(context.current_position() == empty_position());
    assert!(context.get_win() == 0);

    context.advance_position();

    assert!(context.status() == game_ongoing_status());
    assert!(context.stake() == 10);
    assert!(context.current_position() == 0);
    assert!(context.get_win() == 0);

    context.advance_position();

    assert!(context.status() == game_ongoing_status());
    assert!(context.stake() == 10);
    assert!(context.current_position() == 1);
    assert!(context.get_win() == 0);

    context.process_win(100);

    assert!(context.status() == game_finished_status());
    assert!(context.stake() == 10);
    assert!(context.current_position() == 1);
    assert!(context.get_win() == 100);
}

#[test]
public fun success_lose_flow() {
    let mut context = context::empty();

    assert!(context.status() == new_status());
    assert!(context.stake() == 0);
    assert!(context.current_position() == empty_position());
    assert!(context.get_win() == 0);

    context.start_game(10);

    assert!(context.status() == initialized_status());
    assert!(context.stake() == 10);
    assert!(context.current_position() == empty_position());
    assert!(context.get_win() == 0);

    context.advance_position();

    assert!(context.status() == game_ongoing_status());
    assert!(context.stake() == 10);
    assert!(context.current_position() == 0);
    assert!(context.get_win() == 0);

    context.advance_position();

    assert!(context.status() == game_ongoing_status());
    assert!(context.stake() == 10);
    assert!(context.current_position() == 1);
    assert!(context.get_win() == 0);

    context.die();

    assert!(context.status() == game_finished_status());
    assert!(context.stake() == 10);
    assert!(context.current_position() == 1);
    assert!(context.get_win() == 0);
}

#[test, expected_failure(abort_code = context::EInvalidStateTransition)]
public fun fail_advance_without_start() {
    let mut context = context::empty();
    context.advance_position();

    abort 0
}

#[test, expected_failure(abort_code = context::EInvalidStateTransition)]
public fun fail_advance_after_finish() {
    let mut context = context::empty();
    context.start_game(10);
    context.die();
    context.advance_position();
    abort 0
}

#[test, expected_failure(abort_code = context::EInvalidStateTransition)]
public fun fail_win_after_finish() {
    let mut context = context::empty();
    context.start_game(10);
    context.die();
    context.process_win(100);
    abort 0
}

#[test, expected_failure(abort_code = context::EInvalidStateTransition)]
public fun fail_start_after_advance() {
    let mut context = context::empty();
    context.start_game(10);
    context.advance_position();
    context.start_game(10);
    abort 0
}
