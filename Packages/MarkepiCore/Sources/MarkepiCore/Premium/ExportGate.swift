import AVFoundation
import CoreGraphics
import Foundation

/// Which kind of file an export produces. Every export is unlimited; the tier
/// only decides quality (see ``ExportPolicy``).
public enum ExportTier: Sendable, Equatable {
    /// No Markepi Pro entitlement: reduced size, SDR, Markepi mark.
    case free
    /// Markepi Pro: full resolution, HDR kept, no mark.
    case pro
}

/// What an export of a given tier produces. One value so the photo, Live Photo,
/// video and batch paths all read the same rule.
public struct ExportPolicy: Sendable, Equatable {
    /// Longest output side in pixels, or nil for the source's own size.
    public let maxPixelDimension: CGFloat?
    /// Upper bound on lossy compression quality (0…1), or nil for the user's setting.
    public let lossyQualityCap: Float?
    /// Whether an HDR gain map is carried over to photos.
    public let keepsGainMap: Bool
    /// Preferred `AVAssetExportSession` preset for video, or nil for the source-matched choice.
    public let videoPreset: String?
    /// Whether HDR video is tone-mapped to SDR Rec. 709.
    public let forcesSDRVideo: Bool
    /// Whether the export carries the automatic "Markepi" mark.
    public let brandMark: Bool

    public static let freePhotoLongestSide: CGFloat = 2048
    public static let freeLossyQuality: Float = 0.7

    public init(tier: ExportTier) {
        switch tier {
        case .pro:
            maxPixelDimension = nil
            lossyQualityCap = nil
            keepsGainMap = true
            videoPreset = nil
            forcesSDRVideo = false
            brandMark = false
        case .free:
            maxPixelDimension = Self.freePhotoLongestSide
            lossyQualityCap = Self.freeLossyQuality
            keepsGainMap = false
            videoPreset = AVAssetExportPreset1920x1080
            forcesSDRVideo = true
            brandMark = true
        }
    }
}

/// The single place that turns the premium entitlement into an ``ExportTier``.
///
/// Reads the App Group-cached flag from ``PremiumStatusStore`` (kept current by
/// `StoreManager`), so the tier is the same wherever it is asked. Exports are
/// never refused: a free user simply gets the free tier.
public struct ExportGate: Sendable {
    private let status: PremiumStatusStore

    public init(status: PremiumStatusStore = .shared) {
        self.status = status
    }

    /// Whether the user currently holds a premium entitlement.
    public var isPremium: Bool { status.isPremium }

    /// The tier an export started now is produced in.
    public var tier: ExportTier { status.isPremium ? .pro : .free }

    /// Removes the counters left by the retired free daily quota (3 photos +
    /// 1 video). Idempotent; called once at launch.
    public static func removeLegacyQuotaKeys(suiteName: String = AppGroupConfigSync.suiteName) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        for key in ["exportQuota.day", "exportQuota.photoCount", "exportQuota.videoCount"] {
            defaults.removeObject(forKey: key)
        }
    }
}
