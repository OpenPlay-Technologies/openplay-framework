/// Module representing a transaction, the building block for all money transfers.
module openplay_core::transaction;

// === Structs ===
public enum TransactionType has copy, drop, store {
    Bet,
    Win,
}

public struct Transaction has copy, drop, store {
    transaction_type: TransactionType,
    amount: u64,
}

// === Public-View Functions ===
public fun amount(self: &Transaction): u64 {
    self.amount
}

/// Returns true if the transaction type is a credit.
/// Returns false if the transaction type is a debit.
public fun is_credit(self: &Transaction): bool {
    match (self.transaction_type) {
        TransactionType::Win => true,
        TransactionType::Bet => false,
    }
}

/// Returns false if the transaction type is a credit.
/// Returns true if the transaction type is a debit.
public fun is_debit(self: &Transaction): bool {
    !is_credit(self)
}

// === Public-Mutative Functions ===
public fun win(amount: u64): Transaction {
    Transaction {
        transaction_type: TransactionType::Win,
        amount,
    }
}

public fun bet(amount: u64): Transaction {
    Transaction {
        transaction_type: TransactionType::Bet,
        amount: amount,
    }
}
