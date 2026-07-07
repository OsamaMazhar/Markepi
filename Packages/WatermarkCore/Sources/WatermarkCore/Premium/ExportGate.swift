import Foundation

/// The single decision point that combines **premium entitlement** with the
/// **free daily quota**.
///
/// Both the app and the Share Extension route every export through an
/// `ExportGate` so the rule is defined in exactly one place:
///
/// * Premium users always pass and never consume quota.
/// * Free users pass only while the relevant daily bucket has room, and each
///   completed export is recorded against ``ExportQuota``.
///
/// The gate reads premium status from ``PremiumStatusStore`` (the App
/// Group-cached flag), so it works identically in the app and the extension.
/// In the app, `StoreManager` keeps that cache in lock-step with the live
/// StoreKit entitlement.
public struct ExportGate: Sendable {
    private let quota: ExportQuota
    private let status: PremiumStatusStore

    public init(quota: ExportQuota = .shared, status: PremiumStatusStore = .shared) {
        self.quota = quota
        self.status = status
    }

    /// Whether the user currently holds a premium entitlement.
    public var isPremium: Bool { status.isPremium }

    /// Whether the user may export `photos` photos and `videos` videos right
    /// now. Premium always returns `true`; free users are checked against the
    /// remaining daily allowance in ``ExportQuota``.
    public func canExport(photos: Int = 0, videos: Int = 0) -> Bool {
        if status.isPremium { return true }
        return quota.canExport(photos: photos, videos: videos)
    }

    /// Records a completed export against the free quota. A no-op for premium
    /// users, who have no limit to track.
    public func record(photos: Int = 0, videos: Int = 0) {
        guard !status.isPremium else { return }
        quota.record(photos: photos, videos: videos)
    }

    /// Photos a free user may still export today (0 shown as "limit reached").
    public func remainingPhotos() -> Int {
        status.isPremium ? .max : quota.remainingPhotos()
    }

    /// Videos a free user may still export today.
    public func remainingVideos() -> Int {
        status.isPremium ? .max : quota.remainingVideos()
    }
}
