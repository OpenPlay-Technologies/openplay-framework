#[test_only]
module openplay_core::vault_tests;

use openplay_core::balance_manager;
use openplay_core::vault;
use openplay_core::referral;
use sui::coin::mint_for_testing;
use sui::sui::SUI;
use sui::test_scenario::{begin, next_epoch};
use sui::test_utils::destroy;
use std::string::utf8;

#[test]
public fun deposit_withdraw_ok(){

    let addr = @0xA;
    let mut scenario = begin(addr);

    // Create empty vault
    let mut vault = vault::empty(scenario.ctx());
    assert!(vault.reserve_balance() == 0);

    // Deposit 100
    let deposit_balance = mint_for_testing<SUI>(100, scenario.ctx()).into_balance();
    vault.deposit(deposit_balance);
    assert!(vault.reserve_balance() == 100);

    // Withdraw 20
    let withdraw1 = vault.withdraw(20);
    assert!(vault.reserve_balance() == 80);

    // Deposit 20
    let deposit_balance = mint_for_testing<SUI>(20, scenario.ctx()).into_balance();
    vault.deposit(deposit_balance);
    assert!(vault.reserve_balance() == 100);

    // Deposit 20
    let deposit_balance = mint_for_testing<SUI>(20, scenario.ctx()).into_balance();
    vault.deposit(deposit_balance);
    assert!(vault.reserve_balance() == 120);

    // Withdraw all
    let withdraw2 = vault.withdraw(120);
    assert!(vault.reserve_balance() == 0);

    destroy(vault);
    destroy(withdraw1);
    destroy(withdraw2);
    scenario.end();
}

#[test]
public fun activate_ok() { let addr = @0xA; let mut scenario = begin(addr); {
        // Initialize balance manager with 100 MIST

        // Create empty vault
        let mut vault = vault::empty(scenario.ctx());
        assert!(vault.reserve_balance() == 0);

        // Fund vault
        let deposit_balance = mint_for_testing<SUI>(100, scenario.ctx()).into_balance();
        vault.deposit(deposit_balance);
        assert!(vault.reserve_balance() == 100);

        // Activate game
        vault.activate(50);
        assert!(vault.play_balance() == 50);
        assert!(vault.reserve_balance() == 50);

        destroy(vault);
    }; scenario.end(); }

#[test, expected_failure(abort_code = vault::EInsufficientFunds)]
public fun activate_not_enough_funds() { let addr = @0xA; let mut scenario = begin(addr); {
        // Create empty vault
        let mut vault = vault::empty(scenario.ctx());
        assert!(vault.reserve_balance() == 0);

        // Fund vault
        let deposit_balance = mint_for_testing<SUI>(100, scenario.ctx()).into_balance();
        vault.deposit(deposit_balance);
        assert!(vault.reserve_balance() == 100);

        // Activate game
        vault.activate(150);
        abort 0
    } }

#[test]
public fun settle_balance_manager_gameplay_ok() { let addr = @0xA; let mut scenario = begin(addr); {
        // Initialize balance manager with 100 MIST
        let (mut balance_manager, balance_manager_cap) = balance_manager::new(scenario.ctx());
        let proof = balance_manager.generate_proof_as_owner(&balance_manager_cap, scenario.ctx());
        let deposit_balance = mint_for_testing<SUI>(100, scenario.ctx()).into_balance();
        balance_manager.deposit_with_proof(&proof, deposit_balance);

        // Create empty vault
        let mut vault = vault::empty(scenario.ctx());
        vault.activate(0);
        assert!(vault.play_balance() == 0);

        // Settle balance for 20 MIST from balance manager to vault
        vault.settle_balance_manager(0, 80, &mut balance_manager, &proof);
        assert!(vault.play_balance() == 0 + 80);
        assert!(balance_manager.balance() == 100 - 80);

        // Settle balance for 10 MIST from vault to balance manager
        vault.settle_balance_manager(20, 0, &mut balance_manager, &proof);
        assert!(vault.play_balance() == 0 + 80 - 20);
        assert!(balance_manager.balance() == 100 - 80 + 20);

        // Now a mix
        vault.settle_balance_manager(30, 40, &mut balance_manager, &proof);
        assert!(vault.play_balance() == 0 + 80 - 20 - 30 + 40);
        assert!(balance_manager.balance() == 100 - 80 + 20 + 30 - 40);

        destroy(vault);
        destroy(balance_manager);
        destroy(balance_manager_cap);
    }; scenario.end(); }

#[test, expected_failure(abort_code = balance_manager::EBalanceTooLow)]
public fun settle_balance_manager_insufficient_funds_bm() {
    let addr = @0xA;
    let mut scenario = begin(addr);
    {
        // Initialize balance manager with 100 MIST
        let (mut balance_manager, balance_manager_cap) = balance_manager::new(scenario.ctx());
        let proof = balance_manager.generate_proof_as_owner(&balance_manager_cap, scenario.ctx());
        let deposit_balance = mint_for_testing<SUI>(100, scenario.ctx()).into_balance();
        balance_manager.deposit_with_proof(&proof, deposit_balance);

        // Create empty vault
        let mut vault = vault::empty(scenario.ctx());
        assert!(vault.play_balance() == 0);
        vault.activate(0);

        // Try to move 101 MIST from bm to vault
        vault.settle_balance_manager(0, 101, &mut balance_manager, &proof);
        abort 0
    }
}

#[test, expected_failure(abort_code = vault::EInsufficientFunds)]
public fun settle_balance_manager_insufficient_funds_vault() {
    let addr = @0xA;
    let mut scenario = begin(addr);
    {
        // Initialize balance manager with 100 MIST
        let (mut balance_manager, balance_manager_cap) = balance_manager::new(scenario.ctx());
        let proof = balance_manager.generate_proof_as_owner(&balance_manager_cap, scenario.ctx());

        // Create empty vault
        let mut vault = vault::empty(scenario.ctx());
        vault.activate(0);
        assert!(vault.play_balance() == 0);

        // Try to move 5 MIST from vaul to bm
        vault.settle_balance_manager(5, 0, &mut balance_manager, &proof);
        abort 0
    }
}

#[test]
public fun process_fees_ok() {
    let addr = @0xA;
    let mut scenario = begin(addr);
    {
        // Create and fund vault with 100 MIST
        let mut vault = vault::empty(scenario.ctx());
        vault.fund_play_balance_for_testing(100, scenario.ctx());

        let (referral, referral_admin_cap) = referral::new(utf8(b""), utf8(b""), utf8(b""), scenario.ctx());

        // Process fees (both)
        vault.process_protocol_fee(20);
        vault.process_referral_fee(referral.id(), 10);
        assert!(vault.play_balance() == 70);
        assert!(vault.collected_referral_fees(referral.id()) == 10);
        assert!(vault.collected_protocol_fees() == 20);

        // Process fees (just referral)
        vault.process_referral_fee(referral.id(), 10);
        assert!(vault.play_balance() == 60);
        assert!(vault.collected_referral_fees(referral.id()) == 20);
        assert!(vault.collected_protocol_fees() == 20);

        // Process fees (just protocol)
        vault.process_protocol_fee(10);
        assert!(vault.play_balance() == 50);
        assert!(vault.collected_protocol_fees() == 30);

        destroy(vault);
        destroy(referral);
        destroy(referral_admin_cap);
    };
    scenario.end();
}

#[test, expected_failure(abort_code = vault::EInsufficientFunds)]
public fun process_protocol_fees_fail() {
    let addr = @0xA;
    let mut scenario = begin(addr);
    {
        // Create and fund vault with 100 MIST
        let mut vault = vault::empty(scenario.ctx());
        vault.fund_play_balance_for_testing(100, scenario.ctx());

        // Process fees
        vault.process_protocol_fee(101);
        destroy(vault);
        abort 0
    }
}

#[test, expected_failure(abort_code = vault::EInsufficientFunds)]
public fun process_referral_fees_fail() {
    let addr = @0xA;
    let mut scenario = begin(addr);
    {
        let (referral, _referral_admin_cap) = referral::new(utf8(b""), utf8(b""), utf8(b""), scenario.ctx());

        // Create and fund vault with 100 MIST
        let mut vault = vault::empty(scenario.ctx());
        vault.fund_play_balance_for_testing(100, scenario.ctx());

        // Process fees
        vault.process_referral_fee(referral.id(), 101);
        destroy(vault);
        abort 0
    }
}

#[test]
public fun update_epoch() {
    let addr = @0xA;
    let target_balance = 100;
    let mut scenario = begin(addr);
    {
        // Fund reserve balance with 150 MIST
        let mut vault = vault::empty(scenario.ctx());
        vault.fund_reserve_balance_for_testing(150, scenario.ctx());
        assert!(vault.epoch() == scenario.ctx().epoch());
        assert!(vault.play_balance() == 0); // Game is not funded yet

        // Advance epoch (enough funding)
        scenario.next_epoch(addr);
        let (
            epoch_switch,
            prev_epoch,
            end_balance,
            play_balance_funded,
        ) = vault.process_end_of_day(scenario.ctx());
        assert!(epoch_switch);
        assert!(prev_epoch == 0);
        assert!(end_balance == 0);
        assert!(play_balance_funded == false); // The previous epoch was not funded, only the new (current) one is
        assert!(vault.epoch() == scenario.ctx().epoch());
        assert!(vault.reserve_balance() == 150); // everything is in reserve because game is not activated
        assert!(vault.play_balance() == 0); // Game is not funded yet
        // Activate vault
        vault.activate(target_balance);
        assert!(vault.reserve_balance() == 50); // 50 is left in reserve
        assert!(vault.play_balance() == 100); // Game is funded now

        // Simulate some profits and deduce some fees
        vault.fund_play_balance_for_testing(20, scenario.ctx());
        vault.process_protocol_fee(10);
        assert!(vault.play_balance() == 110); // increased by 10
        assert!(vault.reserve_balance() == 50); // the same

        // Update vault without advancing epoch, this should have no effect
        let (
            epoch_switch,
            _prev_epoch,
            _end_balance,
            _play_balance_funded,
        ) = vault.process_end_of_day(scenario.ctx());
        assert!(epoch_switch == false);

        // Advance epoch (enough funding, play_balance reset to target balance)
        scenario.next_epoch(addr);
        let (
            epoch_switch,
            prev_epoch,
            end_balance,
            play_balance_funded,
        ) = vault.process_end_of_day(scenario.ctx());
        assert!(epoch_switch);
        assert!(prev_epoch == 1);
        assert!(end_balance == 110);
        assert!(play_balance_funded == true);
        assert!(vault.play_balance() == 0);
        assert!(vault.reserve_balance() == 160);
        assert!(vault.collected_protocol_fees() == 10);
        // Activate vault
        vault.activate(target_balance);
        assert!(vault.reserve_balance() == 60); // 60 is left in reserve
        assert!(vault.play_balance() == 100); // Game is funded again

        // Simulate losses and deduce some fees
        vault.burn_play_balance_for_testing(60, scenario.ctx());
        vault.process_protocol_fee(10);
        assert!(vault.play_balance() == 30); // reduced by 60
        assert!(vault.reserve_balance() == 60); // the same

        // Advance epoch (not enough funding this time)
        scenario.next_epoch(addr);
        let (
            epoch_switch,
            prev_epoch,
            end_balance,
            play_balance_funded,
        ) = vault.process_end_of_day(scenario.ctx());
        assert!(epoch_switch);
        assert!(prev_epoch == 2);
        assert!(end_balance == 30);
        assert!(play_balance_funded == true);
        assert!(vault.play_balance() == 0);
        assert!(vault.reserve_balance() == 90);
        assert!(vault.collected_protocol_fees() == 20);

        destroy(vault);
    };

    scenario.end();
}
