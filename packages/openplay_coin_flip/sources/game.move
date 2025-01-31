module openplay_coin_flip::game;

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
use openplay_core::balance_manager::{BalanceManager, PlayCap};
use openplay_core::house::{House, HouseTransactionCap};
use openplay_core::referral::Referral;
use openplay_core::registry::Registry;
use openplay_core::transaction::{Transaction, bet, win};
use std::string::String;
use std::uq32_32::{UQ32_32, from_quotient, int_mul};
use sui::random::{Random, RandomGenerator};
use sui::table::{Self, Table};
use sui::transfer::share_object;
use sui::vec_set::{Self, VecSet};
use sui::event::emit;

// === Errors ===
const EUnsupportedHouseEdge: u64 = 1;
const EUnsupportedPayoutFactor: u64 = 2;
const EUnsupportedStake: u64 = 3;
const EUnsupportedPrediction: u64 = 4;
const EUnsupportedAction: u64 = 5;
const EPackageVersionDisabled: u64 = 6;
const EVersionAlreadyAllowed: u64 = 7;
const EVersionAlreadyDisabled: u64 = 8;

// === Structs ===
public struct GAME has drop {}

public struct Game has key {
    id: UID,
    allowed_versions: VecSet<u64>,
    max_stake: u64,
    house_edge_bps: u64, // House bias in basis points (e.g. `100` will give the house a 1% change of winning)
    payout_factor_bps: u64, // Payout factor in basis points (e.g. `20_000` will give 2x or 200% of stake)
    house_tx_cap: HouseTransactionCap,
    contexts: Table<ID, CoinFlipContext>,
    state: CoinFlipState, // Global state specific to the CoinFLip game
}

public struct CoinFlipCap has key, store {
    id: UID,
}

public struct Interaction has copy, drop, store {
    balance_manager_id: ID,
    interact_type: InteractionType,
    transactions: vector<Transaction>,
}

public enum InteractionType has copy, drop, store {
    PLACE_BET { stake: u64, prediction: String },
}


// === Events ===
public struct InteractedWithGame has copy, drop {
    old_balance: u64,
    new_balance: u64,
    context: CoinFlipContext,
    balance_manager_id: ID
}


fun init(_: GAME, ctx: &mut TxContext) {
    let admin = CoinFlipCap { id: object::new(ctx) };
    transfer::public_transfer(admin, ctx.sender());
}

// === Public-View Functions ===
public fun id(self: &Game): ID {
    self.assert_version();
    self.id.to_inner()
}

public fun house_edge_bps(self: &Game): u64 {
    self.assert_version();
    self.house_edge_bps
}

public fun transactions(interaction: &Interaction): vector<Transaction> {
    interaction.transactions
}

public fun get_context(self: &mut Game, balance_manager: &BalanceManager): &CoinFlipContext {
    self.assert_version();
    self.ensure_context(balance_manager.id());
    self.contexts.borrow(balance_manager.id())
}

public fun max_stake(self: &Game): u64 {
    self.assert_version();
    self.max_stake
}

public fun house_id(self: &Game): ID {
    self.assert_version();
    self.house_tx_cap.transaction_cap_house_id()
}

// === Public-Mutative Functions ===
/// Interact entry function with referral
entry fun interact_with_referral(
    self: &mut Game,
    registry: &Registry,
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
    self.assert_version();

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
    let old_balance = balance_manager.balance();
    house.tx_admin_process_transactions_with_referral(
        registry,
        &self.house_tx_cap,
        balance_manager,
        &interact.transactions(),
        play_cap,
        referral,
        ctx,
    );

    // Emit event
    let new_balance = balance_manager.balance();
    emit(InteractedWithGame {
        old_balance,
        new_balance,
        context: *self.get_context(balance_manager)
    })
}

/// Interact entry function without referral
entry fun interact(
    self: &mut Game,
    registry: &Registry,
    balance_manager: &mut BalanceManager,
    house: &mut House,
    play_cap: &PlayCap,
    interact_name: String,
    stake: u64,
    prediction: String,
    random: &Random,
    ctx: &mut TxContext,
) {
    self.assert_version();

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
    let old_balance = balance_manager.balance();
    house.tx_admin_process_transactions(
        registry,
        &self.house_tx_cap,
        balance_manager,
        &interact.transactions(),
        play_cap,
        ctx,
    );

    // Emit event
    let new_balance = balance_manager.balance();
    emit(InteractedWithGame {
        old_balance,
        new_balance,
        context: *self.get_context(balance_manager)
    })
}

public fun share(game: Game) {
    share_object(game);
}

// === Admin Functions ===
public fun admin_create(
    _cap: &CoinFlipCap,
    tx_cap: HouseTransactionCap,
    max_stake: u64,
    house_edge_bps: u64,
    payout_factor_bps: u64,
    ctx: &mut TxContext,
): Game {
    assert!(house_edge_bps < max_house_edge_bps(), EUnsupportedHouseEdge);
    assert!(payout_factor_bps < max_payout_factor_bps(), EUnsupportedPayoutFactor);

    let mut allowed_versions = vec_set::empty();
    allowed_versions.insert(current_version());

    Game {
        id: object::new(ctx),
        allowed_versions: allowed_versions,
        max_stake,
        house_edge_bps,
        payout_factor_bps,
        house_tx_cap: tx_cap,
        contexts: table::new(ctx),
        state: state::empty(),
    }
}

public fun admin_allow_version(self: &mut Game, _cap: &CoinFlipCap, version: u64) {
    assert!(!self.allowed_versions.contains(&version), EVersionAlreadyAllowed);
    self.allowed_versions.insert(version);
}

public fun admin_disallow_version(self: &mut Game, _cap: &CoinFlipCap, version: u64) {
    assert!(self.allowed_versions.contains(&version), EVersionAlreadyDisabled);
    self.allowed_versions.remove(&version);
}

// === Public-Package Functions ===
public(package) fun interact_int(
    self: &mut Game,
    interaction: &mut Interaction,
    rand: &mut RandomGenerator,
) {
    // Validate the interaction
    self.assert_version();
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
fun validate_interact(self: &Game, interaction: &Interaction) {
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

fun ensure_context(self: &mut Game, balance_manager_id: ID) {
    if (!self.contexts.contains(balance_manager_id)) {
        self.contexts.add(balance_manager_id, context::empty());
    };
}

fun payout_factor(self: &Game): UQ32_32 {
    from_quotient(self.payout_factor_bps, 10_000)
}

/// Gets the max payout of the game. This ensures that the vault has sufficient funds to accept the bet.
fun max_payout(self: &Game, stake: u64): u64 {
    int_mul(stake, self.payout_factor())
}

public fun assert_version(self: &Game) {
    let package_version = current_version();
    assert!(self.allowed_versions.contains(&package_version), EPackageVersionDisabled);
}

// === Test Functions ===
#[test_only]
public fun get_admin_cap_for_testing(ctx: &mut TxContext): CoinFlipCap {
    CoinFlipCap { id: object::new(ctx) }
}
