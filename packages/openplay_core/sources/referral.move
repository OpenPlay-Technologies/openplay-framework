module openplay_core::referral;

use std::string::String;
use sui::transfer::share_object;

// === Errors ===


// === Structs ===
public struct Referral has key {
    id: UID,
    name: String,
    project_url: String,
    image_url: String,
}

public struct ReferralAdminCap has key, store {
    id: UID,
    referral_id: ID,
}

// === Public-View Functions ===
public fun id(self: &Referral): ID {
    self.id.to_inner()
}

public fun referral_id(cap: &ReferralAdminCap): ID {
    cap.referral_id
}

// === Public-Mutative Functions ===
/// Creates a new coin flip instance, connected to the provided House (and its coin flip configuration).
public fun new(
    name: String,
    project_url: String,
    image_url: String,
    ctx: &mut TxContext,
): (Referral, ReferralAdminCap) {
    let referral = Referral {
        id: object::new(ctx),
        name,
        project_url,
        image_url,
    };

    let referral_admin_cap = ReferralAdminCap {
        id: object::new(ctx),
        referral_id: referral.id()
    };

    (referral, referral_admin_cap)
}

public fun share (referral: Referral) {
    share_object(referral);
}
