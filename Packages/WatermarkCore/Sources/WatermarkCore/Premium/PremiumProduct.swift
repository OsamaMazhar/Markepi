import Foundation

/// The catalog of "Markepi Pro" products.
///
/// Every identifier here **must** match, byte-for-byte, both the `.storekit`
/// configuration file used for local testing and the products configured in
/// App Store Connect. A typo means `Product.products(for:)` silently drops the
/// product and the paywall renders an empty slot.
///
/// All three products grant the *same* entitlement — unlimited exports. The
/// lifetime unlock is a one-time non-consumable; monthly and annual are
/// auto-renewable subscriptions in a single subscription group so StoreKit
/// treats them as upgrade/downgrade/crossgrade of one another.
public enum PremiumProduct: String, CaseIterable, Sendable {
    /// One-time non-consumable unlock — lifts the daily limit forever.
    case lifetime = "markepi.pro.lifetime"

    /// Auto-renewable monthly subscription.
    case monthly = "markepi.pro.monthly"

    /// Auto-renewable annual subscription (best value).
    ///
    /// - Note: The identifier is `markepi.pro.annua` (no trailing "l") because
    ///   that is exactly how it is registered in App Store Connect and in the
    ///   synced `Markepi.storekit` file. Product IDs are immutable once created,
    ///   so the code must match the registered ID byte-for-byte even though it
    ///   looks like a typo. If you recreate the product as `markepi.pro.annual`
    ///   in App Store Connect, re-sync the `.storekit` file and update this line.
    case annual = "markepi.pro.annua"

    public var id: String { rawValue }

    /// Whether this product is one of the auto-renewable subscriptions. Used to
    /// decide when the paywall must show the auto-renew legal disclosure.
    public var isSubscription: Bool { self != .lifetime }

    /// All product identifiers, for `Product.products(for:)`.
    public static var allIdentifiers: [String] { allCases.map(\.rawValue) }

    /// The subscription group shared by `monthly` and `annual`, matching the
    /// group name in the `.storekit` file ("Markepi Pro") and App Store Connect.
    public static let subscriptionGroupID = "Markepi Pro"
}
