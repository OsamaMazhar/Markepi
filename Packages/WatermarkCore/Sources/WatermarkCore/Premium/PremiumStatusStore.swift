import Foundation

/// A cached snapshot of the user's premium entitlement, shared between the main
/// app and the Share Extension via App Group `UserDefaults`.
///
/// The main app is the source of truth: ``StoreManager`` writes here whenever
/// the live StoreKit entitlement changes (at launch, after a purchase, after a
/// restore, and on any `Transaction.updates` event). The Share Extension — which
/// has a constrained lifecycle and minimal UI — reads this cached flag
/// *synchronously* to decide whether to enforce the free daily limit, instead of
/// spinning up its own StoreKit transaction listener.
///
/// The cache defaults to `false` (free tier) when unset, which is the safe
/// default: a not-yet-synced device is treated as free until StoreKit confirms
/// otherwise.
public struct PremiumStatusStore: Sendable {
    private let suiteName: String
    private let key = "premium.isActive"

    public init(suiteName: String = AppGroupConfigSync.suiteName) {
        self.suiteName = suiteName
    }

    /// Shared instance bound to the app's App Group suite.
    public static let shared = PremiumStatusStore()

    private var defaults: UserDefaults? { UserDefaults(suiteName: suiteName) }

    /// Whether the user currently holds any premium entitlement.
    public var isPremium: Bool {
        #if DEBUG
        // Debug-only override; compiled out of Release builds entirely.
        if DebugPremium.isForced { return true }
        #endif
        return defaults?.bool(forKey: key) ?? false
    }

    /// Updates the cached entitlement. Called only by ``StoreManager``.
    public func set(_ isPremium: Bool) {
        defaults?.set(isPremium, forKey: key)
    }
}
