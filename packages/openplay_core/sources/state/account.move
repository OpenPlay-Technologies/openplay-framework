/// The account module maintains all the account data for each player.
/// Keeps things like loyalty rank and gameplay statistics.
/// Each balance manager has 1 account.
module openplay_core::account;

// === Imports ===

// == Errors ==

// === Structs ===
public struct Account has store {
    lifetime_total_bets: u64,
    lifetime_total_wins: u64,
    debit_balance: u64,
    credit_balance: u64,
}

// === Public-View Functions ===

// === Public-Package Functions ===
public(package) fun empty(): Account {
    Account {
        lifetime_total_bets: 0,
        lifetime_total_wins: 0,
        debit_balance: 0,
        credit_balance: 0,
    }
}

/// Returns a tuple (credit_balance, debit_balance) and resets their values.
/// The Vault uses thes values to perform any necessary transfers in the balance manager.
public(package) fun settle(self: &mut Account): (u64, u64) {
    let old_credit = self.credit_balance;
    let old_debit = self.debit_balance;
    self.reset_balances();
    (old_credit, old_debit)
}

public(package) fun credit(self: &mut Account, amount: u64) {
    self.credit_balance = self.credit_balance + amount;
}

public(package) fun debit(self: &mut Account, amount: u64) {
    self.debit_balance = self.debit_balance + amount
}

// === Private Functions ===
fun reset_balances(self: &mut Account) {
    self.credit_balance = 0;
    self.debit_balance = 0;
}
