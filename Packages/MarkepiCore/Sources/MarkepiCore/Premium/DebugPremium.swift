import Foundation

#if DEBUG
/// Debug-only premium override.
///
/// Turning ``isForced`` on grants the full "Markepi Pro" entitlement
/// everywhere — the paywall, the export gate, and the Share Extension — **with
/// no real StoreKit purchase**, so premium-gated features can be exercised while
/// developing. Turning it off restores the real entitlement state.
///
/// **Why it is fool-proof:** this entire type is wrapped in `#if DEBUG`, so it
/// does not exist in a Release build. There is no compiled code path — and
/// nothing reads the UserDefaults key — in the shipping app, so it is physically
/// impossible to ship with premium force-unlocked. Every reader
/// (``PremiumStatusStore``, ``StoreManager``) also gates its use of this flag
/// behind `#if DEBUG`, so the release binary never references it.
///
/// The flag lives in the shared App Group suite so a single toggle in the app
/// also unlocks the Share Extension, which reads premium status from the same
/// cache rather than running its own StoreKit listener.
public enum DebugPremium {
    private static let key = "debug.forcePremium"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: AppGroupConfigSync.suiteName)
    }

    /// Whether premium is currently being force-granted for debugging.
    public static var isForced: Bool {
        get { defaults?.bool(forKey: key) ?? false }
        set { defaults?.set(newValue, forKey: key) }
    }
}
#endif
