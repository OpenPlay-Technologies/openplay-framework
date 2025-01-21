/// Balance manager is a shared object that keeps the balances for the different assets.
/// It needs to be passed along mutably when playing a game.
/// The balance_manager module works in a similar fashion as the one in deepbookv3.
module openplay_core::balance_manager;

use sui::balance::{Self, Balance};
use sui::coin::Coin;
use sui::event::emit;
use sui::sui::SUI;
use sui::transfer::share_object;
use sui::vec_set::{Self, VecSet};

// === Errors ===
const EBalanceTooLow: u64 = 1;
const EInvalidOwner: u64 = 2;
const EInvalidPlayer: u64 = 3;
const EMaxPlayCapsReached: u64 = 4;
const EPlayCapNotInList: u64 = 5;
const EInvalidProof: u64 = 6;

// === Constants ===
const MAX_PLAY_CAPS: u64 = 1000;

// === Structs ===
public struct BalanceManager has key {
    id: UID,
    balance: Balance<SUI>,
    allow_listed: VecSet<ID>,
}

public struct BalanceManagerCap has key, store {
    id: UID,
    balance_manager_id: ID,
}

/// Owners of a `PlayCap` need to get a `PlayProof` to interact with games in a single PTB (drops after).
public struct PlayCap has key, store {
    id: UID,
    balance_manager_id: ID,
}

/// BalanceManager owner and `PlayCap` owners can generate a `PlayProof`.
/// `PlayProof` is used to validate the balance_manager when interacting with OpenPlay.
public struct PlayProof has drop {
    balance_manager_id: ID,
    player: address,
}

/// Event emitted when a deposit or withdrawal occurs.
public struct BalanceEvent has copy, drop {
    balance_manager_id: ID,
    amount: u64,
    deposit: bool,
}

// === Public-View Functions ===
/// Returns the id of the balance_manager.
public fun id(self: &BalanceManager): ID {
    self.id.to_inner()
}

public fun cap_id(play_cap: &PlayCap): ID {
    play_cap.id.to_inner()
}

public fun cap_balance_manager_id(play_cap: &PlayCap): ID {
    play_cap.balance_manager_id
}

public fun proof_balance_manager_id(proof: &PlayProof): ID {
    proof.balance_manager_id
}

public fun player(proof: &PlayProof): address {
    proof.player
}

/// Gets the current amount on the balance.
public fun balance(self: &BalanceManager): u64 {
    self.balance.value()
}

// === Public-Mutative Functions ===
public fun new(ctx: &mut TxContext): (BalanceManager, BalanceManagerCap) {
    let balance_manager = BalanceManager {
        id: object::new(ctx),
        balance: balance::zero(),
        allow_listed: vec_set::empty(),
    };
    let balance_manager_cap = BalanceManagerCap {
        id: object::new(ctx),
        balance_manager_id: object::id(&balance_manager),
    };
    (balance_manager, balance_manager_cap)
}

public fun share(self: BalanceManager) {
    share_object(self)
}

/// Mint a `PlayCap`, only owner can mint a `PlayCap`.
public fun mint_play_cap(
    self: &mut BalanceManager,
    cap: &BalanceManagerCap,
    ctx: &mut TxContext,
): PlayCap {
    self.validate_owner(cap);
    assert!(self.allow_listed.size() < MAX_PLAY_CAPS, EMaxPlayCapsReached);

    let id = object::new(ctx);
    self.allow_listed.insert(id.to_inner());

    PlayCap {
        id,
        balance_manager_id: self.id(),
    }
}

/// Revoke a `PlayCap`. Only the owner can revoke a `PlayCap`.
public fun revoke_play_cap(self: &mut BalanceManager, cap: &BalanceManagerCap, player_cap_id: &ID) {
    self.validate_owner(cap);

    assert!(self.allow_listed.contains(player_cap_id), EPlayCapNotInList);
    self.allow_listed.remove(player_cap_id);
}

/// Generate a `PlayProof` by the owner.
public fun generate_proof_as_owner(
    balance_manager: &mut BalanceManager,
    cap: &BalanceManagerCap,
    ctx: &TxContext,
): PlayProof {
    balance_manager.validate_owner(cap);

    PlayProof {
        balance_manager_id: object::id(balance_manager),
        player: ctx.sender(),
    }
}

/// Generate a `PlayProof` with a `PlayCap`.
/// Risk of equivocation since `PlayCap` is an owned object.
public fun generate_proof_as_player(
    balance_manager: &mut BalanceManager,
    play_cap: &PlayCap,
    ctx: &TxContext,
): PlayProof {
    balance_manager.validate_player(play_cap);

    PlayProof {
        balance_manager_id: object::id(balance_manager),
        player: ctx.sender(),
    }
}

/// Deposits the provided balance into the `balance`. Only owner can call this directly.
public fun deposit(
    self: &mut BalanceManager,
    cap: &BalanceManagerCap,
    to_deposit: Coin<SUI>,
    ctx: &mut TxContext,
) {
    let proof = generate_proof_as_owner(self, cap, ctx);

    emit(BalanceEvent {
        balance_manager_id: self.id(),
        amount: to_deposit.value(),
        deposit: true,
    });

    deposit_with_proof(self, &proof, to_deposit.into_balance());
}

/// Withdraw funds from a balance_manager. Only owner can call this directly.
public fun withdraw(
    self: &mut BalanceManager,
    cap: &BalanceManagerCap,
    withdraw_amount: u64,
    ctx: &mut TxContext,
): Coin<SUI> {
    let proof = generate_proof_as_owner(self, cap, ctx);

    emit(BalanceEvent {
        balance_manager_id: self.id(),
        amount: withdraw_amount,
        deposit: false,
    });

    withdraw_with_proof(self, &proof, withdraw_amount).into_coin(ctx)
}

public fun validate_proof(balance_manager: &BalanceManager, proof: &PlayProof) {
    assert!(object::id(balance_manager) == proof.balance_manager_id, EInvalidProof);
}

// === Public-Package Functions ===
/// Withdraws the provided amount from the `balance`. Fails if there are not sufficient funds.
public(package) fun withdraw_with_proof(
    self: &mut BalanceManager,
    proof: &PlayProof,
    withdraw_amount: u64,
): Balance<SUI> {
    self.validate_proof(proof);

    assert!(self.balance.value() >= withdraw_amount, EBalanceTooLow);
    self.balance.split(withdraw_amount)
}

/// Deposits the provided balance into the `balance`.
public(package) fun deposit_with_proof(
    self: &mut BalanceManager,
    proof: &PlayProof,
    to_deposit: Balance<SUI>,
) {
    self.validate_proof(proof);

    self.balance.join(to_deposit);
}

// === Private Functions ===
fun validate_owner(self: &BalanceManager, cap: &BalanceManagerCap) {
    assert!(cap.balance_manager_id == self.id(), EInvalidOwner);
}

fun validate_player(balance_manager: &BalanceManager, trade_cap: &PlayCap) {
    assert!(balance_manager.allow_listed.contains(object::borrow_id(trade_cap)), EInvalidPlayer);
}

// === Test Functions ===
#[test_only]
public fun generate_proof_for_testing(
    balance_manager: &mut BalanceManager,
    ctx: &TxContext,
): PlayProof {
    PlayProof {
        balance_manager_id: object::id(balance_manager),
        player: ctx.sender(),
    }
}
