import CoreGraphics
import Foundation

/// Date format options for the retro date stamp, mirroring the look of an
/// old film-camera databack. The `displayName` is the human-readable token
/// pattern shown in the picker; `dateFormat` is the `DateFormatter` pattern.
public enum DateStampFormat: String, Codable, CaseIterable, Sendable, Identifiable {
    /// 24 06 2026 — day first, spaced (classic databack default)
    case dayMonthYear
    /// 24-06-2026 — day first, dashed
    case dayMonthYearDash
    /// 2026-06-24 — ISO order, sortable
    case yearMonthDay
    /// 06-24-2026 — month first (US)
    case monthDayYear
    /// '26 06 24 — two-digit year with apostrophe (most authentic point-and-shoot)
    case classicShortYear
    /// 24 JUN 2026 — day with abbreviated month name
    case dayMonthText

    public var id: String { rawValue }

    /// The `DateFormatter` pattern. A doubled `''` is an escaped literal
    /// apostrophe; `en_US_POSIX` keeps the numerics/locale stable.
    public var dateFormat: String {
        switch self {
        case .dayMonthYear:     return "dd MM yyyy"
        case .dayMonthYearDash: return "dd-MM-yyyy"
        case .yearMonthDay:     return "yyyy-MM-dd"
        case .monthDayYear:     return "MM-dd-yyyy"
        case .classicShortYear: return "''yy MM dd"
        case .dayMonthText:     return "dd MMM yyyy"
        }
    }

    /// Token pattern shown in the format picker.
    public var displayName: String {
        switch self {
        case .dayMonthYear:     return "DD MM YYYY"
        case .dayMonthYearDash: return "DD-MM-YYYY"
        case .yearMonthDay:     return "YYYY-MM-DD"
        case .monthDayYear:     return "MM-DD-YYYY"
        case .classicShortYear: return "'YY MM DD"
        case .dayMonthText:     return "DD MMM YYYY"
        }
    }
}

/// Configuration for the retro date stamp overlay — the orange, slightly
/// glowing date burned into a corner of the image like an old film camera's
/// databack.
///
/// A configuration-level overlay (like `WhiteFrameConfig`), not an entry in the
/// `watermarks` layer stack: there is at most one date stamp, it is always
/// auto-populated from the source's capture date, and it is rendered by
/// `DateStampRenderer` and composited by both `WatermarkEngine.buildFilterGraph`
/// (photos) and `VideoLayerBuilder` (videos).
public struct DateStampConfig: Sendable, Codable {
    /// Whether the date stamp is rendered.
    public var isEnabled: Bool

    /// The date format pattern.
    public var format: DateStampFormat

    /// Digit height as a fraction of the image's shorter dimension.
    /// Clamped to 0.02–0.08. Default 0.035 (~3.5%).
    public var sizeRatio: CGFloat

    /// Which corner the stamp sits in. Restricted to the two lower corners in
    /// the UI (where film cameras printed the date); defaults to `.bottomLeft`.
    public var position: WatermarkPosition

    /// Default digit height fraction.
    public static let defaultSizeRatio: CGFloat = 0.035

    public init(
        isEnabled: Bool = false,
        format: DateStampFormat = .dayMonthYear,
        sizeRatio: CGFloat = DateStampConfig.defaultSizeRatio,
        position: WatermarkPosition = .bottomLeft
    ) {
        self.isEnabled = isEnabled
        self.format = format
        self.sizeRatio = min(0.12, max(0.015, sizeRatio))
        self.position = position
    }

    // MARK: - Codable (forward-compatible defaults)

    enum CodingKeys: String, CodingKey {
        case isEnabled, format, sizeRatio, position
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        format = try c.decodeIfPresent(DateStampFormat.self, forKey: .format) ?? .dayMonthYear
        let size = try c.decodeIfPresent(CGFloat.self, forKey: .sizeRatio) ?? DateStampConfig.defaultSizeRatio
        sizeRatio = min(0.08, max(0.02, size))
        position = try c.decodeIfPresent(WatermarkPosition.self, forKey: .position) ?? .bottomLeft
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(isEnabled, forKey: .isEnabled)
        try c.encode(format, forKey: .format)
        try c.encode(sizeRatio, forKey: .sizeRatio)
        try c.encode(position, forKey: .position)
    }
}
