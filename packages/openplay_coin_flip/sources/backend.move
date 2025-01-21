module openplay_coin_flip::backend;

use openplay_coin_flip::constants::{
    head_result,
    tail_result,
    house_bias_result,
    place_bet_action,
    current_version,
    max_house_edge_bps,
    max_payout_factor_bps
};
use openplay_coin_flip::context::{Self, CoinFlipContext};
use openplay_coin_flip::state::{Self, CoinFlipState};
use openplay_core::balance_manager::{BalanceManager, PlayCap, generate_proof_as_player};
use openplay_core::house::{Self, House, HouseAdminCap, cap_house_id};
use openplay_core::referral::Referral;
use openplay_core::transaction::{Transaction, bet, win};
use std::string::String;
use std::uq32_32::{UQ32_32, from_quotient, int_mul};
use sui::random::{Random, RandomGenerator};
use sui::table::{Self, Table};
use sui::vec_set::{Self, VecSet};
use sui::versioned::{Self, Versioned};

// === Errors ===
const EUnsupportedHouseEdge: u64 = 1;
const EUnsupportedPayoutFactor: u64 = 2;
const EUnsupportedStake: u64 = 3;
const EUnsupportedPrediction: u64 = 4;
const EUnsupportedAction: u64 = 5;
const EPackageVersionDisabled: u64 = 6;
const EVersionAlreadyAllowed: u64 = 7;
const EVersionAlreadyDisallowed: u64 = 8;
const EUnauthorized: u64 = 9;

// === Structs ===
public struct Backend has key {
    id: UID,
    inner: Versioned,
}

public struct BackendAdminCap has key, store {
    id: UID,
    backend_id: ID,
}

public struct BackendInner has store {
    allowed_versions: VecSet<u64>,
    max_stake: u64,
    house_edge_bps: u64, // House bias in basis points (e.g. `100` will give the house a 1% change of winning)
    payout_factor_bps: u64, // Payout factor in basis points (e.g. `20_000` will give 2x or 200% of stake)
    house_cap: HouseAdminCap,
    contexts: Table<ID, CoinFlipContext>,
    state: CoinFlipState, // Global state specific to the CoinFLip game
}

public struct Interaction has copy, drop, store {
    balance_manager_id: ID,
    interact_type: InteractionType,
    transactions: vector<Transaction>,
}

public enum InteractionType has copy, drop, store {
    PLACE_BET { stake: u64, prediction: String },
}

// === Public-View Functions ===
public fun id(self: &Backend): ID {
    self.id.to_inner()
}

public fun house_edge_bps(self: &Backend): u64 {
    let self = self.load_inner();
    self.house_edge_bps
}

public fun transactions(interaction: &Interaction): vector<Transaction> {
    interaction.transactions
}

public fun get_context(self: &mut Backend, balance_manager: &BalanceManager): &CoinFlipContext {
    let self = self.load_inner_mut();
    self.ensure_context(balance_manager.id());
    self.contexts.borrow(balance_manager.id())
}

public fun max_stake(self: &Backend): u64 {
    let self = self.load_inner();
    self.max_stake
}

public fun house_id(self: &Backend): ID {
    let self = self.load_inner();
    self.house_cap.cap_house_id()
}

// === Public-Mutative Functions ===
public fun new(
    max_stake: u64,
    house_edge_bps: u64,
    payout_factor_bps: u64,
    target_balance: u64,
    referral_fee: u64,
    ctx: &mut TxContext,
): (Backend, BackendAdminCap, House) {
    assert!(house_edge_bps < max_house_edge_bps(), EUnsupportedHouseEdge);
    assert!(payout_factor_bps < max_payout_factor_bps(), EUnsupportedPayoutFactor);

    let mut allowed_versions = vec_set::empty();
    allowed_versions.insert(current_version());

    let (house, house_cap) = house::new(target_balance, referral_fee, ctx);

    let backend_inner = BackendInner {
        allowed_versions: allowed_versions,
        max_stake,
        house_edge_bps,
        payout_factor_bps,
        house_cap,
        contexts: table::new(ctx),
        state: state::empty(),
    };

    let backend_id = object::new(ctx);
    let backend_admin_cap = BackendAdminCap {
        id: object::new(ctx),
        backend_id: backend_id.to_inner(),
    };
    let backend = Backend {
        id: backend_id,
        inner: versioned::create(current_version(), backend_inner, ctx),
    };

    (backend, backend_admin_cap, house)
}

/// Interact entry function with referral
entry fun interact_with_referral(
    self: &mut Backend,
    balance_manager: &mut BalanceManager,
    house: &mut House,
    referral: &Referral,
    play_cap: &PlayCap,
    interact_name: String,
    stake: u64,
    prediction: String,
    random: &Random,
    ctx: &mut TxContext,
) {
    let self = self.load_inner_mut();

    // Generate proof
    let play_proof = balance_manager.generate_proof_as_player(play_cap, ctx);

    // Make sure we have enough funds in the house to play this game
    house.ensure_sufficient_funds(self.max_payout(stake), ctx);

    // Interact with coin flip game and record any transactions made
    let mut interact = new_interact(
        interact_name,
        balance_manager.id(),
        prediction,
        stake,
    );
    let mut random_generator = random.new_generator(ctx);
    self.interact_int(&mut interact, &mut random_generator);

    // Process transactions by house
    house.admin_process_transactions_with_referral(
        &self.house_cap,
        balance_manager,
        &interact.transactions(),
        &play_proof,
        referral,
        ctx,
    );
}

/// Interact entry function without referral
entry fun interact(
    self: &mut Backend,
    balance_manager: &mut BalanceManager,
    house: &mut House,
    play_cap: &PlayCap,
    interact_name: String,
    stake: u64,
    prediction: String,
    random: &Random,
    ctx: &mut TxContext,
) {
    let self = self.load_inner_mut();
    // Generate proof
    let play_proof = balance_manager.generate_proof_as_player(play_cap, ctx);

    // Make sure we have enough funds in the house to play this game
    house.ensure_sufficient_funds(self.max_payout(stake), ctx);

    // Interact with coin flip game and record any transactions made
    let mut interact = new_interact(
        interact_name,
        balance_manager.id(),
        prediction,
        stake,
    );
    let mut random_generator = random.new_generator(ctx);
    self.interact_int(&mut interact, &mut random_generator);

    // Process transactions by house
    house.admin_process_transactions(
        &self.house_cap,
        balance_manager,
        &interact.transactions(),
        &play_proof,
        ctx,
    );
}

// === Admin Functions ===
public fun admin_allow_version(self: &mut Backend, cap: &BackendAdminCap, version: u64) {
    self.validate_admin(cap);

    let self = self.load_inner_mut();
    assert!(!self.allowed_versions.contains(&version), EVersionAlreadyAllowed);
    self.allowed_versions.insert(version);
}

public fun admin_disallow_version(self: &mut Backend, cap: &BackendAdminCap, version: u64) {
    self.validate_admin(cap);

    let self = self.load_inner_mut();
    assert!(self.allowed_versions.contains(&version), EVersionAlreadyDisallowed);
    self.allowed_versions.remove(&version);
}

// === Public-Package Functions ===
public(package) fun load_inner(self: &Backend): &BackendInner {
    let inner: &BackendInner = self.inner.load_value();
    let package_version = current_version();
    assert!(inner.allowed_versions.contains(&package_version), EPackageVersionDisabled);

    inner
}

public(package) fun load_inner_mut(self: &mut Backend): &mut BackendInner {
    let inner: &mut BackendInner = self.inner.load_value_mut();
    let package_version = current_version();
    assert!(inner.allowed_versions.contains(&package_version), EPackageVersionDisabled);

    inner
}

public(package) fun interact_int(
    self: &mut BackendInner,
    interaction: &mut Interaction,
    rand: &mut RandomGenerator,
) {
    // Validate the interaction
    self.validate_interact(interaction);

    let payout_factor = self.payout_factor();
    let house_edge_bps = self.house_edge_bps;

    // Ensure context
    self.ensure_context(interaction.balance_manager_id);
    let context = self.contexts.borrow_mut(interaction.balance_manager_id);

    match (interaction.interact_type) {
        InteractionType::PLACE_BET { stake, prediction } => {
            // Place bet and deduct stake
            interaction.transactions.push_back(bet(stake));
            context.bet(stake, prediction);
            // Generate result
            let x = rand.generate_u64_in_range(0, 10_000);
            let result;
            if (x < house_edge_bps) {
                result = house_bias_result();
            } else if (x % 2 == 0) {
                result = head_result();
            } else {
                result = tail_result();
            };
            // Pay out winnings, or zero win if player lost
            let payout;
            if (prediction == result) {
                payout = int_mul(stake, payout_factor);
            } else {
                payout = 0
            };
            interaction.transactions.push_back(win(payout));
            // Update context
            context.settle(result, payout);
        },
    };

    // Update the state
    self.state.process_context(context);
}

public(package) fun new_interact(
    interact_name: String,
    balance_manager_id: ID,
    prediction: String,
    stake: u64,
): Interaction {
    // Transaction vec
    let transactions = vector::empty<Transaction>();
    // Construct the correct interact type
    let interact_type;
    if (interact_name == place_bet_action()) {
        interact_type = InteractionType::PLACE_BET { stake, prediction: prediction };
    } else {
        abort EUnsupportedAction
    };
    Interaction {
        balance_manager_id,
        transactions,
        interact_type,
    }
}

// === Private Functions ===
fun validate_interact(self: &BackendInner, interaction: &Interaction) {
    match (interaction.interact_type) {
        InteractionType::PLACE_BET { stake, prediction: prediction } => {
            assert!(stake < self.max_stake, EUnsupportedStake);
            assert!(
                prediction == head_result() || prediction == tail_result(),
                EUnsupportedPrediction,
            );
        },
    }
}

fun ensure_context(self: &mut BackendInner, balance_manager_id: ID) {
    if (!self.contexts.contains(balance_manager_id)) {
        self.contexts.add(balance_manager_id, context::empty());
    };
}

fun validate_admin(self: &Backend, cap: &BackendAdminCap) {
    assert!(self.id.to_inner() == cap.backend_id, EUnauthorized);
}

fun payout_factor(self: &BackendInner): UQ32_32 {
    from_quotient(self.payout_factor_bps, 10_000)
}

/// Gets the max payout of the game. This ensures that the vault has sufficient funds to accept the bet.
fun max_payout(self: &BackendInner, stake: u64): u64 {
    int_mul(stake, self.payout_factor())
}
