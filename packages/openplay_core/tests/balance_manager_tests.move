#[test_only]
module openplay_core::balance_manager_tests;

use openplay_core::balance_manager;
use sui::coin::{mint_for_testing, burn_for_testing};
use sui::sui::SUI;
use sui::test_scenario::begin;
use sui::test_utils::destroy;

#[test, expected_failure(abort_code = balance_manager::EBalanceTooLow)]
public fun deposit_withdraw_int() { let addr = @0xA; let mut scenario = begin(addr); {
        let (mut balance_manager, balance_manager_cap) = balance_manager::new(scenario.ctx());
        let proof = balance_manager.generate_proof_as_owner(&balance_manager_cap, scenario.ctx());
        assert!(balance_manager.balance() == 0);


        // Deposit 100 OK
        let deposit_balance = mint_for_testing<SUI>(100, scenario.ctx()).into_balance();
        balance_manager.deposit_with_proof(&proof, deposit_balance);

        // Withdraw 50 OK
        let withdraw_balance = balance_manager.withdraw_with_proof(&proof, 50);
        burn_for_testing(withdraw_balance.into_coin(scenario.ctx()));

        // Withdraw 51 fails
        let fail = balance_manager.withdraw_with_proof(&proof, 51);
        burn_for_testing(fail.into_coin(scenario.ctx()));

        destroy(balance_manager);
        abort 0
    } }


#[test, expected_failure(abort_code = balance_manager::EBalanceTooLow)]
public fun deposit_withdraw() { let addr = @0xA; let mut scenario = begin(addr); {
        let (mut balance_manager, balance_manager_cap) = balance_manager::new(scenario.ctx());
        assert!(balance_manager.balance() == 0);

        // Deposit 100 OK
        let deposit_balance = mint_for_testing<SUI>(100, scenario.ctx());
        balance_manager.deposit(&balance_manager_cap, deposit_balance, scenario.ctx());

        // Withdraw 50 OK
        let withdraw_balance = balance_manager.withdraw(&balance_manager_cap, 50, scenario.ctx());
        burn_for_testing(withdraw_balance);

        // Withdraw 51 fails
        let fail = balance_manager.withdraw(&balance_manager_cap, 51, scenario.ctx());
        burn_for_testing(fail);

        destroy(balance_manager);
        abort 0
    } }

#[test]
public fun play_cap_and_proofs_ok() {
    let addr = @0xA;
    let mut scenario = begin(addr);
    
    let (mut balance_manager, balance_manager_cap) = balance_manager::new(scenario.ctx());

    let play_cap = balance_manager.mint_play_cap(&balance_manager_cap, scenario.ctx());
    assert!(play_cap.cap_balance_manager_id() == balance_manager.id());

    let play_proof1 = balance_manager.generate_proof_as_owner(&balance_manager_cap, scenario.ctx());
    assert!(play_proof1.proof_balance_manager_id() == balance_manager.id());
    assert!(play_proof1.player() == scenario.ctx().sender());

    let play_proof2 = balance_manager.generate_proof_as_player(&play_cap, scenario.ctx());
    assert!(play_proof2.proof_balance_manager_id() == balance_manager.id());
    assert!(play_proof2.player() == scenario.ctx().sender());

    destroy(balance_manager);
    destroy(balance_manager_cap);
    destroy(play_cap);
    destroy(play_proof1);
    destroy(play_proof2);
    scenario.end();
}

#[test, expected_failure(abort_code = balance_manager::EInvalidOwner)]
public fun incorrect_bm_cap_1() {
    let addr = @0xA;
    let mut scenario = begin(addr);
    
    let (mut balance_manager1, balance_manager_cap1) = balance_manager::new(scenario.ctx());
    let (mut _balance_manager2, balance_manager_cap2) = balance_manager::new(scenario.ctx());

    // Ok
    let _play_cap1 = balance_manager1.mint_play_cap(&balance_manager_cap1, scenario.ctx());
    // Invalid cap
    let _play_cap2 = balance_manager1.mint_play_cap(&balance_manager_cap2, scenario.ctx());

    abort 0
}

#[test, expected_failure(abort_code = balance_manager::EInvalidOwner)]
public fun incorrect_bm_cap_2() {
    let addr = @0xA;
    let mut scenario = begin(addr);
    
    let (mut balance_manager1, balance_manager_cap1) = balance_manager::new(scenario.ctx());
    let (mut _balance_manager2, balance_manager_cap2) = balance_manager::new(scenario.ctx());

    // Ok
    let _play_proof1 = balance_manager1.generate_proof_as_owner(&balance_manager_cap1, scenario.ctx());
    // Invalid cap
    let _play_proof2 = balance_manager1.generate_proof_as_owner(&balance_manager_cap2, scenario.ctx());

    abort 0
}



#[test, expected_failure(abort_code = balance_manager::EInvalidPlayer)]
public fun incorrect_play_cap() {
    let addr = @0xA;
    let mut scenario = begin(addr);
    
    let (mut balance_manager1, balance_manager_cap1) = balance_manager::new(scenario.ctx());
    let (mut balance_manager2, balance_manager_cap2) = balance_manager::new(scenario.ctx());

    let play_cap1 = balance_manager1.mint_play_cap(&balance_manager_cap1, scenario.ctx());
    let play_cap2 = balance_manager2.mint_play_cap(&balance_manager_cap2, scenario.ctx());

    // Ok
    let _play_proof1 = balance_manager1.generate_proof_as_player(&play_cap1, scenario.ctx());
    // Invalid cap
    let _play_proof1 = balance_manager1.generate_proof_as_player(&play_cap2, scenario.ctx());

    abort 0
}

#[test, expected_failure(abort_code = balance_manager::EInvalidPlayer)]
public fun revoked_play_cap() {
    let addr = @0xA;
    let mut scenario = begin(addr);
    
    let (mut balance_manager, balance_manager_cap) = balance_manager::new(scenario.ctx());

    let play_cap = balance_manager.mint_play_cap(&balance_manager_cap, scenario.ctx());

    // Ok
    let _play_proof1 = balance_manager.generate_proof_as_player(&play_cap, scenario.ctx());

    // Revoke
    balance_manager.revoke_play_cap(&balance_manager_cap, &play_cap.cap_id());

    // Invalid cap
    let _play_proof2 = balance_manager.generate_proof_as_player(&play_cap, scenario.ctx());

    abort 0
}