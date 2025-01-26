#[test_only]
module openplay_core::state_tests;

use openplay_core::balance_manager;
use openplay_core::state;
use openplay_core::transaction::{bet, win};
use std::uq32_32::{int_mul, from_quotient};
use sui::test_scenario::begin;
use sui::test_utils::destroy;
use std::option::{some, none};

#[test]
public fun transactions_process_referral_fee_ok() {
    let addr = @0xa;
    let referral_fee_factor = from_quotient(1, 100);
    let house_fee_factor = from_quotient(3, 100);
    let protocol_fee_factor = from_quotient(7, 100);
    let mut scenario = begin(addr);

    // Initialize state and balance manager
    let mut state = state::new(scenario.ctx());
    let (bm, bm_cap) = balance_manager::new(scenario.ctx());

    // Process transactions: total bet of 10 and win of 5
    let txs = vector[bet(10), bet(0), win(5), win(0)];
    let (credit_balance, debit_balance, house_fee, protocol_fee, referral_fee) = state.process_transactions(
        &txs,
        bm.id(),
        house_fee_factor,
        protocol_fee_factor,
        some(referral_fee_factor)
    );
    assert!(credit_balance == 5);
    assert!(debit_balance == 10);
    assert!(house_fee == int_mul(10, house_fee_factor));
    assert!(referral_fee == int_mul(10, referral_fee_factor));
    assert!(protocol_fee == int_mul(10, protocol_fee_factor));

    destroy(bm);
    destroy(state);
    destroy(bm_cap);
    scenario.end();
}

#[test]
public fun transactions_process_ok() {
    let addr = @0xa;
    let house_fee_factor = from_quotient(3, 100);
    let protocol_fee_factor = from_quotient(7, 100);
    let mut scenario = begin(addr);

    // Initialize state and balance manager
    let mut state = state::new(scenario.ctx());
    let (bm, bm_cap) = balance_manager::new(scenario.ctx());

    // Process transactions: total bet of 10 and win of 5
    let txs = vector[bet(10), bet(0), win(5), win(0)];
    let (credit_balance, debit_balance, house_fee, protocol_fee, referral_fee) = state.process_transactions(
        &txs,
        bm.id(),
        house_fee_factor,
        protocol_fee_factor,
        none()
    );
    assert!(credit_balance == 5);
    assert!(debit_balance == 10);
    assert!(house_fee == int_mul(10, house_fee_factor));
    assert!(referral_fee == 0);
    assert!(protocol_fee == int_mul(10, protocol_fee_factor));

    destroy(bm);
    destroy(state);
    destroy(bm_cap);
    scenario.end();
}
