#[test_only]
module openplay_coin_flip::state_tests;

use openplay_coin_flip::constants::{head_result, tail_result, house_bias_result, max_recent_throws};
use openplay_coin_flip::context;
use openplay_coin_flip::state;
use sui::test_utils::destroy;

#[test]
public fun counter_ok() {
    // Create empty state
    let mut state = state::empty();
    let (nb_of_heads, nb_of_tails, nb_of_house_bias) = state.counters();
    assert!(nb_of_heads == 0);
    assert!(nb_of_tails == 0);
    assert!(nb_of_house_bias == 0);

    // Process some contexts
    let mut unfinished_context = context::empty();
    unfinished_context.bet(10, head_result());

    let mut head_context = context::empty();
    head_context.bet(10, head_result());
    head_context.settle(head_result(), 0);

    let mut tail_context = context::empty();
    tail_context.bet(10, head_result());
    tail_context.settle(tail_result(), 0);

    let mut house_context = context::empty();
    house_context.bet(10, head_result());
    house_context.settle(house_bias_result(), 0);

    // Process them by state and check the counters
    state.process_context(&unfinished_context);
    state.process_context(&head_context);
    let (nb_of_heads, nb_of_tails, nb_of_house_bias) = state.counters();
    assert!(nb_of_heads == 1);
    assert!(nb_of_tails == 0);
    assert!(nb_of_house_bias == 0);

    state.process_context(&tail_context);
    let (nb_of_heads, nb_of_tails, nb_of_house_bias) = state.counters();
    assert!(nb_of_heads == 1);
    assert!(nb_of_tails == 1);
    assert!(nb_of_house_bias == 0);

    state.process_context(&house_context);
    let (nb_of_heads, nb_of_tails, nb_of_house_bias) = state.counters();
    assert!(nb_of_heads == 1);
    assert!(nb_of_tails == 1);
    assert!(nb_of_house_bias == 1);

    destroy(state);
    destroy(head_context);
    destroy(tail_context);
    destroy(house_context);
    destroy(unfinished_context);
}

#[test]
public fun recent_throws_ok() {
    // Create empty state
    let mut state = state::empty();
    let recent_throws = state.recent_throws();
    assert!(recent_throws.length() == 0);

    // Process some contexts
    let mut unfinished_context = context::empty();
    unfinished_context.bet(10, head_result());

    let mut head_context = context::empty();
    head_context.bet(10, head_result());
    head_context.settle(head_result(), 0);

    let mut tail_context = context::empty();
    tail_context.bet(10, head_result());
    tail_context.settle(tail_result(), 0);

    let mut house_context = context::empty();
    house_context.bet(10, head_result());
    house_context.settle(house_bias_result(), 0);

    // Process them by state and check the counters
    state.process_context(&head_context);
    let recent_throws = state.recent_throws();
    assert!(recent_throws == vector[head_result()]);

    state.process_context(&tail_context);
    let recent_throws = state.recent_throws();
    assert!(recent_throws == vector[head_result(), tail_result()]);

    state.process_context(&house_context);
    let recent_throws = state.recent_throws();
    assert!(recent_throws == vector[head_result(), tail_result(), house_bias_result()]);

    // Now check the max size of it
    let mut i = max_recent_throws();
    while (i > 0) {
        state.process_context(&tail_context);
        i = i - 1
    };
    let recent_throws = state.recent_throws();
    assert!(recent_throws.length() == max_recent_throws());
    assert!(recent_throws.all!(|x| x == tail_result()));

    destroy(state);
    destroy(head_context);
    destroy(tail_context);
    destroy(house_context);
    destroy(unfinished_context);
}
