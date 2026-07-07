import Foundation

/// Tracks the free tier's **daily export allowance**, shared between the main
/// app and the Share Extension via App Group `UserDefaults`.
///
/// Free users may export up to `freePhotoLimit` photos **and** `freeVideoLimit`
/// videos each calendar day. The two buckets are independent — exporting a
/// photo never consumes the video allowance and vice-versa. Premium users
/// bypass all of this; the combined premium-or-quota decision lives in
/// ``ExportGate``.
///
/// The counters live in the same App Group suite as ``AppGroupConfigSync`` so
/// that exports made from the Share Extension count against the same budget as
/// exports made from the app. The bucket auto-resets when the calendar day
/// changes in the device's local time zone: every read compares today's
/// `yyyy-MM-dd` key against the stored day and treats a mismatch as a clean
/// slate. `record(_:)` then persists the new day alongside the incremented
/// counts.
public struct ExportQuota: Sendable {

    // MARK: - Limits

    /// Photos a free user may export per day.
    public static let freePhotoLimit = 3

    /// Videos a free user may export per day.
    public static let freeVideoLimit = 1

    // MARK: - Snapshot

    /// Today's counts. Zeroed automatically once the calendar day rolls over.
    public struct Usage: Sendable, Equatable {
        public var photos: Int
        public var videos: Int
        public init(photos: Int, videos: Int) {
            self.photos = photos
            self.videos = videos
        }
    }

    // MARK: - Storage

    private let suiteName: String
    private let dayKey = "exportQuota.day"
    private let photoKey = "exportQuota.photoCount"
    private let videoKey = "exportQuota.videoCount"

    /// - Parameter suiteName: App Group suite to persist into. Defaults to the
    ///   shared Markepi suite; tests inject a throwaway suite to stay isolated.
    public init(suiteName: String = AppGroupConfigSync.suiteName) {
        self.suiteName = suiteName
    }

    /// Shared instance bound to the app's App Group suite.
    public static let shared = ExportQuota()

    private var defaults: UserDefaults? { UserDefaults(suiteName: suiteName) }

    /// Today's `yyyy-MM-dd` bucket key in the device's local calendar.
    private func dayString(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    // MARK: - Reads

    /// Usage recorded for today. Returns zeroes if the stored day is not today
    /// (the counters are treated as reset without writing until the next
    /// `record(_:)`).
    public func usage(now: Date = Date()) -> Usage {
        guard let defaults, defaults.string(forKey: dayKey) == dayString(now) else {
            return Usage(photos: 0, videos: 0)
        }
        return Usage(photos: defaults.integer(forKey: photoKey),
                     videos: defaults.integer(forKey: videoKey))
    }

    /// Photos the free user may still export today.
    public func remainingPhotos(now: Date = Date()) -> Int {
        max(0, Self.freePhotoLimit - usage(now: now).photos)
    }

    /// Videos the free user may still export today.
    public func remainingVideos(now: Date = Date()) -> Int {
        max(0, Self.freeVideoLimit - usage(now: now).videos)
    }

    /// Whether a free user may export `photos` photos and `videos` videos right
    /// now. A request is allowed only if *both* buckets have room for it.
    public func canExport(photos: Int = 0, videos: Int = 0, now: Date = Date()) -> Bool {
        photos <= remainingPhotos(now: now) && videos <= remainingVideos(now: now)
    }

    // MARK: - Writes

    /// Records a completed free-tier export, rolling the day bucket forward if
    /// the calendar day changed since the last write.
    public func record(photos: Int = 0, videos: Int = 0, now: Date = Date()) {
        guard let defaults, photos > 0 || videos > 0 else { return }
        var current = usage(now: now)   // already zeroed if the day rolled over
        current.photos += photos
        current.videos += videos
        defaults.set(dayString(now), forKey: dayKey)
        defaults.set(current.photos, forKey: photoKey)
        defaults.set(current.videos, forKey: videoKey)
    }

    /// Wipes the stored counters. Used by tests and by "reset" debugging tools.
    public func reset() {
        guard let defaults else { return }
        defaults.removeObject(forKey: dayKey)
        defaults.removeObject(forKey: photoKey)
        defaults.removeObject(forKey: videoKey)
    }
}
