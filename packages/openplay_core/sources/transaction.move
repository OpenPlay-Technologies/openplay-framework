/// Module representing a transaction, the building block for all money transfers.
module openplay_core::transaction;

use std::string::String;
use openplay_core::constants::{tx_type_bet, tx_type_win};

// === Errors ===
const EUnknownTxType: u64 = 1;

// === Structs ===
public struct Transaction has copy, drop, store {
    transaction_type: String,
    amount: u64,
}

// === Public-View Functions ===
public fun amount(self: &Transaction): u64 {
    self.amount
}

/// Returns true if the transaction type is a credit.
/// Returns false if the transaction type is a debit.
public fun is_credit(self: &Transaction): bool {
    if (self.transaction_type == tx_type_win()){
        return true
    };
    if (self.transaction_type == tx_type_bet()){
        return false
    };
    abort EUnknownTxType
}

/// Returns false if the transaction type is a credit.
/// Returns true if the transaction type is a debit.
public fun is_debit(self: &Transaction): bool {
    !is_credit(self)
}

// === Public-Mutative Functions ===
public fun win(amount: u64): Transaction {
    Transaction {
        transaction_type: tx_type_win(),
        amount,
    }
}

public fun bet(amount: u64): Transaction {
    Transaction {
        transaction_type: tx_type_bet(),
        amount: amount,
    }
}
