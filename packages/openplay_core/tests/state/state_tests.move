#[test_only]
module openplay_core::state_tests;

use openplay_core::balance_manager;
use openplay_core::constants::{protocol_fee};
use openplay_core::state;
use openplay_core::transaction::{bet, win};
use std::uq32_32::{int_mul, from_quotient};
use sui::test_scenario::begin;
use sui::test_utils::destroy;

#[test]
public fun transactions_process_ok() {
    let addr = @0xa;
    let referral_fee_factor = from_quotient(1, 100);
    let mut scenario = begin(addr);

    // Initialize state and balance manager
    let mut state = state::new(scenario.ctx());
    let (bm, bm_cap) = balance_manager::new(scenario.ctx());

    // Process transactions: total bet of 10 and win of 5
    let txs = vector[bet(10), bet(0), win(5), win(0)];
    let (credit_balance, debit_balance, owner_fee, protocol_fee) = state.process_transactions(
        &txs,
        bm.id(),
        referral_fee_factor
    );
    assert!(credit_balance == 5);
    assert!(debit_balance == 10);
    assert!(owner_fee == int_mul(10, referral_fee_factor));
    assert!(protocol_fee == int_mul(10, protocol_fee()));

    destroy(bm);
    destroy(state);
    destroy(bm_cap);
    scenario.end();
}
