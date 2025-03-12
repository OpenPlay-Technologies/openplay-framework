module openplay_piggy_bank::game;

use openplay_core::balance_manager::{BalanceManager, PlayCap};
use openplay_core::constants::max_bps;
use openplay_core::house::House;
use openplay_core::registry::Registry;
use openplay_core::transaction::{Transaction, bet, win};
use openplay_piggy_bank::constants::{
    current_version,
    advance_action,
    cash_out_action,
    start_game_action,
    new_status,
    game_ongoing_status,
    game_finished_status,
    empty_position,
    max_steps,
    max_payout_factor_bps
};
use openplay_piggy_bank::context::{Self, PiggyBankContext};
use std::string::String;
use std::uq32_32::{UQ32_32, from_quotient, int_mul};
use sui::event::emit;
use sui::random::{Random, RandomGenerator};
use sui::table::{Self, Table};
use sui::transfer::share_object;
use sui::vec_set::{Self, VecSet};

// === Errors ===
const EInvalidSuccessRate: u64 = 1;
const EInvalidSteps: u64 = 2;
const EUnsupportedStake: u64 = 3;
const EInvalidCashOut: u64 = 3;
const EGameAlreadyOngoing: u64 = 4;
const EGameNotInProgress: u64 = 5;
const EUnsupportedAction: u64 = 6;
const ECannotAdvanceFurther: u64 = 7;
const EPackageVersionDisabled: u64 = 8;
const EVersionAlreadyAllowed: u64 = 9;
const EVersionAlreadyDisabled: u64 = 10;
const EContextAlreadyExists: u64 = 11;

// === Structs ===
public struct GAME has drop {}

public struct Game has key {
    id: UID,
    allowed_versions: VecSet<u64>,
    min_stake: u64,
    max_stake: u64,
    steps_payout_bps: vector<u64>,
    success_rate_bps: u64,
    contexts: Table<ID, PiggyBankContext>,
}

public struct PiggyBankCap has key, store {
    id: UID,
}

public struct Interaction has copy, drop, store {
    balance_manager_id: ID,
    interact_type: InteractionType,
    transactions: vector<Transaction>,
}

public enum InteractionType has copy, drop, store {
    START_GAME { stake: u64 },
    ADVANCE,
    CASH_OUT,
}

// === Events ===
public struct InteractedWithGame has copy, drop {
    old_balance: u64,
    new_balance: u64,
    context: PiggyBankContext,
    balance_manager_id: ID,
}

fun init(_: GAME, ctx: &mut TxContext) {
    let admin = PiggyBankCap { id: object::new(ctx) };
    transfer::public_transfer(admin, ctx.sender());
}

// === Public-View Functions ===
public fun id(self: &Game): ID {
    self.assert_version();
    self.id.to_inner()
}

public fun transactions(interaction: &Interaction): vector<Transaction> {
    interaction.transactions
}

public fun get_context_ref(self: &mut Game, balance_manager: &BalanceManager): &PiggyBankContext {
    self.assert_version();
    self.ensure_context(balance_manager.id());
    self.contexts.borrow(balance_manager.id())
}

public fun max_stake(self: &Game): u64 {
    self.assert_version();
    self.max_stake
}

public fun min_stake(self: &Game): u64 {
    self.assert_version();
    self.min_stake
}

public fun max_step_index(self: &Game): u8 {
    (self.steps_payout_bps.length() - 1) as u8
}

public fun payout_factor(self: &Game, position: u8): UQ32_32 {
    let payout_bps;
    if (position == empty_position() || position > self.max_step_index()) {
        payout_bps = 0;
    } else {
        payout_bps = self.steps_payout_bps[position as u64];
    };
    from_quotient(payout_bps, max_bps())
}

// === Public-Mutative Functions ===
/// Interact entry function without referral
entry fun interact(
    self: &mut Game,
    registry: &Registry,
    balance_manager: &mut BalanceManager,
    house: &mut House,
    play_cap: &PlayCap,
    interact_name: String,
    stake: u64,
    random: &Random,
    ctx: &mut TxContext,
) {
    self.assert_version();

    let house_tx_cap = house.borrow_tx_cap(&mut self.id);

    // Make sure we have enough funds in the house to play this game
    house.ensure_sufficient_funds(self.max_payout(stake), ctx);

    // Interact with coin flip game and record any transactions made
    let mut interact = new_interact(
        interact_name,
        balance_manager.id(),
        stake,
    );
    let mut random_generator = random.new_generator(ctx);
    self.interact_int(&mut interact, &mut random_generator);

    // Process transactions by house
    let old_balance = balance_manager.balance();
    house.tx_admin_process_transactions(
        registry,
        house_tx_cap,
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
        context: *self.get_context_ref(balance_manager),
        balance_manager_id: balance_manager.id(),
    })
}

public fun share(game: Game) {
    share_object(game);
}

// === Admin Functions ===
public fun admin_create(
    _cap: &PiggyBankCap,
    min_stake: u64,
    max_stake: u64,
    success_rate_bps: u64,
    steps_payout_bps: vector<u64>,
    ctx: &mut TxContext,
): Game {
    assert!(success_rate_bps <= max_bps(), EInvalidSuccessRate);

    let number_of_steps = steps_payout_bps.length();
    assert!(number_of_steps > 0 && number_of_steps <= (max_steps() as u64), EInvalidSteps);
    steps_payout_bps.do_ref!(
        |payout_bps| assert!(*payout_bps < max_payout_factor_bps(), EInvalidSteps),
    );

    let mut allowed_versions = vec_set::empty();
    allowed_versions.insert(current_version());

    Game {
        id: object::new(ctx),
        allowed_versions: allowed_versions,
        min_stake,
        max_stake,
        steps_payout_bps,
        success_rate_bps,
        contexts: table::new(ctx),
    }
}

public fun admin_allow_version(self: &mut Game, _cap: &PiggyBankCap, version: u64) {
    assert!(!self.allowed_versions.contains(&version), EVersionAlreadyAllowed);
    self.allowed_versions.insert(version);
}

public fun admin_disallow_version(self: &mut Game, _cap: &PiggyBankCap, version: u64) {
    assert!(self.allowed_versions.contains(&version), EVersionAlreadyDisabled);
    self.allowed_versions.remove(&version);
}

/// Gets the max payout of the game. This ensures that the vault has sufficient funds to accept the bet.
public fun max_payout(self: &Game, stake: u64): u64 {
    let payout_factor = self.payout_factor(self.max_step_index());
    int_mul(stake, payout_factor)
}

// === Public-Package Functions ===
public(package) fun interact_int(
    self: &mut Game,
    interaction: &mut Interaction,
    rand: &mut RandomGenerator,
) {
    self.assert_version();

    // Get context
    let mut context = self.take_context(interaction.balance_manager_id);

    // Validate the interaction
    self.validate_interact(&context, interaction);

    match (interaction.interact_type) {
        // 1. Start Game
        InteractionType::START_GAME { stake } => {
            // Place bet and deduct stake
            interaction.transactions.push_back(bet(stake));
            context.start_game(stake);

            self.advance_internal(&mut context, &mut interaction.transactions, rand);
        },
        // 2. Advance
        InteractionType::ADVANCE => {
            self.advance_internal(&mut context, &mut interaction.transactions, rand);
        },
        // 3. Cash out
        InteractionType::CASH_OUT => {
            self.win_internal(&mut context, &mut interaction.transactions);
        },
    };

    // Save context
    self.save_context(interaction.balance_manager_id, context);
}

public(package) fun new_interact(
    interact_name: String,
    balance_manager_id: ID,
    stake: u64,
): Interaction {
    // Transaction vec
    let transactions = vector::empty<Transaction>();
    // Construct the correct interact type
    let interact_type;
    if (interact_name == start_game_action()) {
        interact_type = InteractionType::START_GAME { stake };
    } else if (interact_name == advance_action()) {
        interact_type = InteractionType::ADVANCE;
    } else if (interact_name == cash_out_action()) {
        interact_type = InteractionType::CASH_OUT;
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
fun validate_interact(self: &Game, context: &PiggyBankContext, interaction: &Interaction) {
    match (interaction.interact_type) {
        InteractionType::START_GAME { stake } => {
            assert!(
                context.status() == new_status() || 
            context.status() == game_finished_status(),
                EGameAlreadyOngoing,
            );
            assert!(stake >= self.min_stake, EUnsupportedStake);
            assert!(stake <= self.max_stake, EUnsupportedStake);
        },
        InteractionType::CASH_OUT => {
            assert!(context.status() == game_ongoing_status(), EGameNotInProgress);
            assert!(context.current_position() != empty_position(), EInvalidCashOut);
        },
        InteractionType::ADVANCE => {
            assert!(context.status() == game_ongoing_status(), EGameNotInProgress);
            assert!(
                context.current_position() == empty_position() || 
            context.current_position() < self.max_step_index(),
                ECannotAdvanceFurther,
            );
        },
    }
}

fun take_context(self: &mut Game, balance_manager_id: ID): PiggyBankContext {
    self.ensure_context(balance_manager_id);
    self.contexts.remove(balance_manager_id)
}

fun save_context(self: &mut Game, balance_manager_id: ID, context: PiggyBankContext) {
    assert!(!self.contexts.contains(balance_manager_id), EContextAlreadyExists);
    self.contexts.add(balance_manager_id, context);
}

fun ensure_context(self: &mut Game, balance_manager_id: ID) {
    if (!self.contexts.contains(balance_manager_id)) {
        self.save_context(balance_manager_id, context::empty());
    };
}

fun assert_version(self: &Game) {
    let package_version = current_version();
    assert!(self.allowed_versions.contains(&package_version), EPackageVersionDisabled);
}

fun advance_internal(
    self: &Game,
    context: &mut PiggyBankContext,
    transactions: &mut vector<Transaction>,
    rand: &mut RandomGenerator,
) {
    let x = rand.generate_u64_in_range(0, max_bps() - 1);
    if (x < self.success_rate_bps) {
        // Advance the position
        context.advance_position();

        // Trigger win if the max position is reached
        if (context.current_position() == self.max_step_index()) {
            self.win_internal(context, transactions);
        }
    } else {
        // End game with loss
        context.die();
    };
}

fun win_internal(
    self: &Game,
    context: &mut PiggyBankContext,
    transactions: &mut vector<Transaction>,
) {
    let payout_factor = self.payout_factor(context.current_position());
    let payout = int_mul(context.stake(), payout_factor);
    context.process_win(payout);
    transactions.push_back(win(payout));
}

// === Test Functions ===
#[test_only]
public fun get_admin_cap_for_testing(ctx: &mut TxContext): PiggyBankCap {
    PiggyBankCap { id: object::new(ctx) }
}

#[test_only]
public fun fix_context_for_testing(self: &mut Game, bm_id: ID, context: PiggyBankContext) {
    if (self.contexts.contains(bm_id)) {
        self.contexts.remove(bm_id);
    };
    self.save_context(bm_id, context);
}
