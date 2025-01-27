module openplay_core::referral;

use sui::transfer::share_object;

// === Structs ===
public struct Referral has key {
    id: UID,
    house_id: ID,
    cap_id: ID,
}

public struct ReferralCap has key, store {
    id: UID,
    referral_id: ID,
}

// === Public-View Functions ===
public fun id(self: &Referral): ID {
    self.id.to_inner()
}

public fun referral_id(cap: &ReferralCap): ID {
    cap.referral_id
}

// === Public-Package Functions ===
/// Creates a new coin flip instance, connected to the provided House (and its coin flip configuration).
public(package) fun new(house_id: ID, ctx: &mut TxContext): (Referral, ReferralCap) {
    let referral_cap_id = object::new(ctx);

    let referral = Referral {
        id: object::new(ctx),
        house_id,
        cap_id: referral_cap_id.to_inner(),
    };

    let referral_cap = ReferralCap {
        id: referral_cap_id,
        referral_id: referral.id(),
    };

    (referral, referral_cap)
}

public fun share(referral: Referral) {
    share_object(referral);
}
