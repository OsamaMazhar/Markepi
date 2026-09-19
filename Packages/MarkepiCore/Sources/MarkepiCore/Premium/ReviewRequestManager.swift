import Foundation

/// Decides *when* to ask the user to rate Markepi, following Apple's guidance
/// for `SKStoreReviewController` / the SwiftUI `requestReview` action.
///
/// Apple's rules (App Store Review Guideline 1.1.7 & HIG "Ratings and Reviews"):
///   - Only prompt at a natural, positive moment — never on launch, never after
///     a failure, never gated behind a custom "do you like the app?" dialog.
///   - Use the system API only; the OS itself caps prompts to 3 per 365 days and
///     may silently show nothing. We must not implement our own rating UI.
///
/// This manager adds conservative gating *on top* of the system throttle so we
/// only *ask* at good moments: after the user has successfully exported a few
/// watermarked results (a real "delight moment"), and at most once per app
/// version. The actual prompt is presented by the system via the SwiftUI
/// `requestReview` action — this type never shows UI itself.
///
/// State is persisted in `UserDefaults`. All access is `@MainActor` because the
/// prompt is driven from SwiftUI view code.
@MainActor
public final class ReviewRequestManager {
    public static let shared = ReviewRequestManager()

    private let defaults: UserDefaults

    private enum Key {
        static let successfulExports = "review.successfulExportCount"
        static let lastPromptedVersion = "review.lastPromptedAppVersion"
        static let lastPromptedDate = "review.lastPromptedDate"
    }

    /// Successful exports before we first consider prompting. Someone who has
    /// exported three watermarked photos/videos has gotten real value and can
    /// form an honest opinion.
    private let minimumSuccessfulExports = 3

    /// Safety net: never re-ask within this many days, even across app versions.
    private let minimumDaysBetweenPrompts = 60

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private var currentAppVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }

    /// Records a completed, user-initiated export/share — the "delight moment".
    /// Call this only when the user actually finished sharing/saving a result,
    /// not merely when the share sheet was presented.
    public func recordSuccessfulExport() {
        let count = defaults.integer(forKey: Key.successfulExports) + 1
        defaults.set(count, forKey: Key.successfulExports)
    }

    /// `true` when it is an appropriate moment to ask the system to show a
    /// review prompt. The system may still choose to show nothing.
    public func shouldRequestReview() -> Bool {
        // Enough successful exports to have formed an opinion.
        guard defaults.integer(forKey: Key.successfulExports) >= minimumSuccessfulExports else {
            return false
        }

        // At most once per app version — avoid re-asking on a version the user
        // has already seen the prompt on.
        if let lastVersion = defaults.string(forKey: Key.lastPromptedVersion),
           lastVersion == currentAppVersion {
            return false
        }

        // Safety-net time gate between prompts.
        if let lastDate = defaults.object(forKey: Key.lastPromptedDate) as? Date {
            let days = Calendar.current.dateComponents([.day], from: lastDate, to: Date()).day ?? 0
            if days < minimumDaysBetweenPrompts { return false }
        }

        return true
    }

    /// Records that we asked the system to present the prompt for this version.
    /// Call immediately after invoking the `requestReview` action.
    public func markReviewRequested() {
        defaults.set(currentAppVersion, forKey: Key.lastPromptedVersion)
        defaults.set(Date(), forKey: Key.lastPromptedDate)
    }
}
