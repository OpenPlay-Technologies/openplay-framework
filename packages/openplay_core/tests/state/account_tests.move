#[test_only]
module openplay_core::account_tests;

use openplay_core::account;
use sui::test_utils::destroy;

#[test]
public fun settle_ok() {
    // Create account
    let mut account = account::empty();

    // Debit 10, Credit 20
    account.debit(10);
    account.credit(20);

    let (credit, debit) = account.settle();
    assert!(credit == 20);
    assert!(debit == 10);

    // Now do it twice
    account.debit(10);
    account.credit(20);
    account.debit(10);
    account.credit(20);
    let (credit, debit) = account.settle();
    assert!(credit == 40);
    assert!(debit == 20);

    destroy(account);
}
