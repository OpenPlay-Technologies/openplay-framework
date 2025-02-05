/// House is responsible for processing and settling transactions between the vault and balance manager.
/// It is responsible for keeping the right amount of fees for stakers, game owners, and referrals.
module openplay_core::house;

use openplay_core::balance_manager::{BalanceManager, PlayCap};
use openplay_core::constants::max_bps;
use openplay_core::participation::{Self, Participation};
use openplay_core::referral::{Self, Referral, ReferralCap, referral_id};
use openplay_core::registry::{Registry, OpenPlayAdminCap};
use openplay_core::state::{Self, State};
use openplay_core::transaction::Transaction;
use openplay_core::vault::{Self, Vault};
use std::option::{some, none};
use std::uq32_32::{UQ32_32, from_quotient};
use sui::coin::Coin;
use sui::sui::SUI;
use sui::transfer::share_object;
use sui::vec_set::{Self, VecSet};
use sui::event::emit;

// === Errors ===
const EInsufficientFunds: u64 = 1;
const EInvalidTxCap: u64 = 2;
const EInvalidParticipation: u64 = 3;
const EHouseNotActive: u64 = 4;
const EReferralNotEnabled: u64 = 5;
const EHouseIsPrivate: u64 = 6;
const EMaxTxCapsReached: u64 = 7;
const EInvalidAdminCap: u64 = 9;
const EInvalidFeeConfiguration: u64 = 10;
const EUnauthorizedGameId: u64 = 11;
const ETxCapNotAllowed: u64 = 12;

// === Constants ===
const MAX_TX_CAPS: u64 = 1000;

// === Structs ===
/// OTW
public struct HOUSE has drop {}

public struct House has key {
    id: UID,
    admin_cap_id: ID,
    private: bool, // Staking becomes an admin-only function
    target_balance: u64,
    house_fee_bps: u64,
    referral_fee_bps: u64,
    tx_allow_listed: VecSet<ID>,
    // Internal props
    vault: Vault,
    state: State,
}

/// The cap that is used to perform administrator functions.
public struct HouseAdminCap has key, store {
    id: UID,
    house_id: ID,
}

/// The cap that is used to execute transaction.
public struct HouseTransactionCap {
    house_id: ID,
    game_id: ID,
}

public struct Fees has copy, drop {
    protocol_fee: u64,
    house_fee: u64,
    referral_fee: u64,
}

public struct HouseCreatedEvent has copy,drop {
    house_id: ID,
    admin_cap_id: ID
}

public struct TransactionsProcessedEvent has copy, drop {
    house_id: ID,
    game_id: ID,
    balance_manager_id: ID,
    referral_id: Option<ID>,
    transactions: vector<Transaction>,
    fees: Fees
}

public struct GameTransactionsAllowedEvent has copy, drop {
    house_id: ID,
    game_id: ID
}

public struct GameTransactionsRevokedEvent has copy, drop {
    house_id: ID,
    game_id: ID
}

public struct ProtocolFeesClaimedEvent has copy, drop {
    house_id: ID,
    amount: u64
}

public struct ReferralFeesClaimedEvent has copy, drop {
    house_id: ID,
    referral_id: ID,
    amount: u64
}

public struct HouseFeesClaimedEvent has copy, drop {
    house_id: ID,
    amount: u64
}

// === Public-View Functions ===
public fun id(self: &House): ID {
    self.id.to_inner()
}

public fun private(self: &House): bool {
    self.private
}

public fun play_balance(self: &mut House, ctx: &mut TxContext): u64 {
    self.process_end_of_day(ctx);
    self.vault.play_balance()
}

public fun reserve_balance(self: &mut House, ctx: &mut TxContext): u64 {
    self.process_end_of_day(ctx);
    self.vault.reserve_balance()
}

public fun referral_fee_factor(self: &House): UQ32_32 {
    from_quotient(self.referral_fee_bps, 10000)
}

public fun house_fee_factor(self: &House): UQ32_32 {
    from_quotient(self.house_fee_bps, 10000)
}

public fun admin_cap_house_id(cap: &HouseAdminCap): ID {
    cap.house_id
}

public fun transaction_cap_house_id(cap: &HouseTransactionCap): ID {
    cap.house_id
}

public fun is_active(self: &mut House, ctx: &TxContext): bool {
    // Make sure the vault and participation are up to date (end of day is processed for previous days)
    self.process_end_of_day(ctx);
    self.state.is_active()
}

// === Public-Mutative Functions ===
/// Creates a new house.
/// Returns (house, admin_cap, tx_cap)
public fun new(
    private: bool,
    target_balance: u64,
    house_fee_bps: u64,
    referral_fee_bps: u64,
    ctx: &mut TxContext,
): (House, HouseAdminCap) {
    assert!(
        house_fee_bps + referral_fee_bps + referral_fee_bps < max_bps(),
        EInvalidFeeConfiguration,
    );
    let admin_cap_id = object::new(ctx);
    let house = House {
        id: object::new(ctx),
        admin_cap_id: admin_cap_id.to_inner(),
        private,
        vault: vault::empty(ctx),
        state: state::new(ctx),
        target_balance,
        house_fee_bps,
        referral_fee_bps,
        tx_allow_listed: vec_set::empty(),
    };
    let admin_cap = HouseAdminCap {
        id: admin_cap_id,
        house_id: house.id(),
    };

    emit(HouseCreatedEvent {
        house_id: house.id(),
        admin_cap_id: admin_cap.id.to_inner()
    });

    (house, admin_cap)
}

public fun share(registry: &mut Registry, house: House) {
    registry.register_house(house.id());
    share_object(house);
}

/// Ensures that the vault can cover `max_payout` with the play balance
public fun ensure_sufficient_funds(self: &mut House, amount: u64, ctx: &TxContext) {
    // Make sure the vault and participation are up to date (end of day is processed for previous days)
    self.process_end_of_day(ctx);

    assert!(self.state.is_active(), EHouseNotActive);
    assert!(self.vault.play_balance() >= amount, EInsufficientFunds)
}

/// Public function to create a new participation. This is only possible if the house is public.
public fun new_participation(self: &House, ctx: &mut TxContext): Participation {
    self.assert_not_private();
    participation::empty(self.id.to_inner(), ctx)
}

/// Stake money in the protocol to participate in the house winnings.
/// The stake is first added to the account's inactive stake, and is only activated in the next epoch.
public fun stake(
    self: &mut House,
    participation: &mut Participation,
    stake: Coin<SUI>,
    ctx: &mut TxContext,
) {
    self.assert_valid_participation(participation);

    // Make sure the vault and participation are up to date (end of day is processed for previous days)
    self.process_end_of_day(ctx);

    // Process the stake in the state
    self.state.process_stake(stake.value(), ctx);

    // Add funds to the participation
    participation.add_stake(stake.value(), self.state.is_active(), ctx);

    // Move funds to the vault
    self.vault.deposit(stake.into_balance());

    // Try to activate the house
    self.activate_if_possible(ctx);
}

/// Refreshes the participation to process any unprocessed profits or losses.
public fun update_participation(
    self: &mut House,
    participation: &mut Participation,
    ctx: &mut TxContext,
) {
    self.assert_valid_participation(participation);

    // Make sure the end of day is processed
    self.process_end_of_day(ctx);

    // Refresh the participation
    self.state.refresh(participation, ctx);
}

/// Withdraws the stake from the current game. This only goes into effect in the next epoch.
public fun unstake(self: &mut House, participation: &mut Participation, ctx: &mut TxContext) {
    self.assert_valid_participation(participation);

    // Make sure the vault and participation are up to date (end of day is processed for previous days)
    self.process_end_of_day(ctx);

    // Unstake the funds in the participation
    let (prev_stake, pending_stake_removed) = participation.unstake(self.state.is_active(), ctx);

    // Process the unstake in the history
    self.state.process_unstake(prev_stake, pending_stake_removed, ctx);
}

public fun claim_all(
    self: &mut House,
    participation: &mut Participation,
    ctx: &mut TxContext,
): Coin<SUI> {
    self.assert_valid_participation(participation);

    // Make sure the vault and participation are up to date (end of day is processed for previous days)
    self.process_end_of_day(ctx);

    // Take the claimable balance from participation
    let claimable = participation.claim_all(ctx);

    // Withdraw from vault
    self.vault.withdraw(claimable).into_coin(ctx)
}

public fun new_referral(self: &House, ctx: &mut TxContext): ReferralCap {
    self.assert_referral_active();
    let (referral, referral_cap) = referral::new(self.id(), ctx);
    referral::share(referral);
    referral_cap
}

public fun borrow_tx_cap(self: &House, game_id: &mut UID): HouseTransactionCap {
    assert!(self.tx_allow_listed.contains(game_id.as_inner()), EUnauthorizedGameId);
    HouseTransactionCap {
        house_id: self.id(),
        game_id: game_id.to_inner(),
    }
}

// === Tx-Admin Functions ===
public fun tx_admin_process_transactions_with_referral(
    self: &mut House,
    registry: &Registry,
    cap: HouseTransactionCap,
    balance_manager: &mut BalanceManager,
    transactions: &vector<Transaction>,
    play_cap: &PlayCap,
    referral: &Referral,
    ctx: &TxContext,
) {
    // Check the tx cap
    let game_id = cap.game_id;
    self.assert_valid_tx_cap(cap);

    // Generate proof
    let play_proof = balance_manager.generate_proof_as_player(play_cap, ctx);

    // Ensure referral is active
    self.assert_referral_active();

    // Make sure the vault and participation are up to date (end of day is processed for previous days)
    self.process_end_of_day(ctx);

    // Process transactions and calculate fees
    let house_fee_factor = self.house_fee_factor();
    let protocol_fee_factor = registry.protocol_fee_factor();
    let referral_fee_factor = self.referral_fee_factor();

    let (credit_balance, debit_balance, house_fee, protocol_fee, referral_fee) = self
        .state
        .process_transactions(
            transactions,
            balance_manager.id(),
            house_fee_factor,
            protocol_fee_factor,
            some(referral_fee_factor),
            ctx,
        );

    // Settle the balances in vault
    self.vault.settle_balance_manager(credit_balance, debit_balance, balance_manager, &play_proof);

    // Process fees
    self.vault.process_house_fee(house_fee);
    self.vault.process_referral_fee(referral.id(), referral_fee);
    self.vault.process_protocol_fee(protocol_fee);

    // Event
    emit(TransactionsProcessedEvent {
        house_id: self.id(),
        game_id: game_id,
        balance_manager_id: balance_manager.id(),
        referral_id: some(referral.id()),
        transactions: *transactions,
        fees: Fees {
            protocol_fee: protocol_fee,
            house_fee: house_fee,
            referral_fee: referral_fee,
        }
    })
}

public fun tx_admin_process_transactions(
    self: &mut House,
    registry: &Registry,
    cap: HouseTransactionCap,
    balance_manager: &mut BalanceManager,
    transactions: &vector<Transaction>,
    play_cap: &PlayCap,
    ctx: &TxContext,
) {
    // Check the tx cap
    let game_id = cap.game_id;
    self.assert_valid_tx_cap(cap);

    // Generate proof
    let play_proof = balance_manager.generate_proof_as_player(play_cap, ctx);

    let house_fee_factor = self.house_fee_factor();
    let protocol_fee_factor = registry.protocol_fee_factor();

    // Make sure the vault and participation are up to date (end of day is processed for previous days)
    self.process_end_of_day(ctx);

    let (credit_balance, debit_balance, house_fee, protocol_fee, _referral_fee) = self
        .state
        .process_transactions(
            transactions,
            balance_manager.id(),
            house_fee_factor,
            protocol_fee_factor,
            none(),
            ctx,
        );

    // Settle the balances in vault
    self.vault.settle_balance_manager(credit_balance, debit_balance, balance_manager, &play_proof);

    // Process fees
    self.vault.process_house_fee(house_fee);
    self.vault.process_protocol_fee(protocol_fee);

    // Event
    emit(TransactionsProcessedEvent {
        house_id: self.id(),
        game_id: game_id,
        balance_manager_id: balance_manager.id(),
        referral_id: none(),
        transactions: *transactions,
        fees: Fees {
            protocol_fee: protocol_fee,
            house_fee: house_fee,
            referral_fee: 0,
        }
    })
}

// === House-Admin Functions ===
/// Priviliged instruction for crceating a new participation. Should be used in case the house is `private`.
public fun admin_new_participation(
    self: &House,
    cap: &HouseAdminCap,
    ctx: &mut TxContext,
): Participation {
    // Check the admin cap
    self.assert_valid_admin_cap(cap);

    participation::empty(self.id.to_inner(), ctx)
}

/// Claims all the house fees for this house. Can only be called by the house admin.
public fun admin_claim_house_fees(
    self: &mut House,
    admin_cap: &HouseAdminCap,
    ctx: &mut TxContext,
): Coin<SUI> {
    self.assert_valid_admin_cap(admin_cap);
    let fee_coin = self.vault.withdraw_house_fees().into_coin(ctx);

    // Event
    emit(HouseFeesClaimedEvent {
        house_id: self.id(),
        amount: fee_coin.value()
    });

    fee_coin
}

/// Adds a `game_id` to the tx allowed list.
public fun admin_add_tx_allowed(self: &mut House, admin_cap: &HouseAdminCap, game_id: ID) {
    // Check if the admin_cap is valid
    self.assert_valid_admin_cap(admin_cap);

    // Check if the max allow listed is reached
    assert!(self.tx_allow_listed.size() < MAX_TX_CAPS, EMaxTxCapsReached);

    self.tx_allow_listed.insert(game_id);

    // Event
    emit(GameTransactionsAllowedEvent {
        house_id: self.id(),
        game_id: game_id
    })
}

/// Revokes tx access for the provided `game_id`.
public fun admin_revoke_tx_allowed(self: &mut House, admin_cap: &HouseAdminCap, game_id: &ID) {
    // Check if the admin_cap is valid
    self.assert_valid_admin_cap(admin_cap);

    assert!(self.tx_allow_listed.contains(game_id), ETxCapNotAllowed);
    self.tx_allow_listed.remove(game_id);

    // Event
    emit(GameTransactionsRevokedEvent {
        house_id: self.id(),
        game_id: *game_id
    })
}

// === Referral-Admin Functions ===
/// Claims all the referral fees for this house. Can only be called by the referral owner.
public fun referral_admin_claim_referral_fees(
    self: &mut House,
    referral_cap: &ReferralCap,
    ctx: &mut TxContext,
): Coin<SUI> {
    let fee_coin = self.vault.withdraw_referral_fees(referral_cap.referral_id()).into_coin(ctx);

    // Event
    emit(ReferralFeesClaimedEvent {
        house_id: self.id(),
        referral_id: referral_cap.referral_id(),
        amount: fee_coin.value()
    });

    fee_coin
}

// === Openplay admin functions ===
/// Claims all the protocol fees for this house. Can only be called by the openplay admin.
public fun openplay_admin_claim_protocol_fees(
    self: &mut House,
    _admin_cap: &OpenPlayAdminCap,
    ctx: &mut TxContext,
): Coin<SUI> {
    let fee_coin = self.vault.withdraw_protocol_fees().into_coin(ctx);

    // Event
    emit(ProtocolFeesClaimedEvent {
        house_id: self.id(),
        amount: fee_coin.value()
    });

    fee_coin
}

// == Private Functions ==
/// The first time this gets called on a new epoch, the end of the day procedure is initiated for the last known epoch.
/// The vault saves the end of day balance for the house and resets to the target balance if there are enough funds available.
/// Note: there can be a number of epochs in between without any activity.
fun process_end_of_day(self: &mut House, ctx: &TxContext) {
    let (epoch_switched, prev_epoch, end_of_day_balance) = self.vault.process_end_of_day(ctx);

    if (epoch_switched) {
        let profits: u64;
        let losses: u64;
        let was_active = self.state.epoch_active(prev_epoch);
        if (was_active) {
            if (end_of_day_balance > self.target_balance) {
                profits = end_of_day_balance - self.target_balance;
                losses = 0;
            } else {
                losses = self.target_balance - end_of_day_balance;
                profits = 0;
            };
        } else {
            // The house was not funded so no profits or losses were made
            profits = 0;
            losses = 0;
        };
        // Process the profits / losses with the state
        self.state.process_end_of_day(prev_epoch, profits, losses, ctx);

        // Check if the house can be activated again (if there is still sufficient stake available)
        self.activate_if_possible(ctx);
    }
}

fun assert_valid_admin_cap(self: &House, house_cap: &HouseAdminCap) {
    assert!(self.id() == house_cap.house_id, EInvalidAdminCap);
}

fun assert_valid_tx_cap(self: &House, tx_cap: HouseTransactionCap) {
    let HouseTransactionCap { house_id, game_id } = tx_cap;
    assert!(self.tx_allow_listed.contains(&game_id), EInvalidTxCap);
    assert!(self.id() == house_id, EInvalidTxCap);
}

fun assert_valid_participation(self: &House, participation: &Participation) {
    assert!(self.id() == participation.house_id(), EInvalidParticipation);
}

fun assert_not_private(self: &House) {
    assert!(self.private() == false, EHouseIsPrivate);
}

fun assert_referral_active(self: &House) {
    assert!(self.referral_fee_bps > 0, EReferralNotEnabled);
}

fun activate_if_possible(self: &mut House, ctx: &TxContext) {
    // Do nothing if the current epoch is already activated
    if (self.state.is_active()) {
        return
    };
    let activated = self.state.maybe_activate(self.target_balance, ctx);
    if (activated) {
        self.vault.fund_play_balance(self.target_balance);
    }
}

// === Test Functions ===
#[test_only]
public fun admin_cap_for_testing(house: &House, ctx: &mut TxContext): HouseAdminCap {
    HouseAdminCap {
        id: object::new(ctx),
        house_id: house.id(),
    }
}
#[test_only]
public fun tx_cap_for_testing(house: &mut House, game_id: ID): HouseTransactionCap {
    if (!house.tx_allow_listed.contains(&game_id)) {
        house.tx_allow_listed.insert(game_id);
    };
    let cap = HouseTransactionCap {
        house_id: house.id(),
        game_id,
    };
    cap
}

#[test_only]
public fun add_referral_fees_for_testing(
    self: &mut House,
    referral: &Referral,
    referral_fee: u64,
    ctx: &TxContext,
) {
    self.process_end_of_day(ctx);
    self.vault.process_referral_fee(referral.id(), referral_fee);
}

#[test_only]
public fun add_house_fees_for_testing(self: &mut House, house_fee: u64, ctx: &TxContext) {
    self.process_end_of_day(ctx);
    self.vault.process_house_fee(house_fee);
}

#[test_only]
public fun referral_for_testing(self: &House, ctx: &mut TxContext): (Referral, ReferralCap) {
    referral::new(self.id(), ctx)
}
