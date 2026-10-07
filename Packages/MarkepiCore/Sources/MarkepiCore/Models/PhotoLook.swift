import Foundation

/// A colour look applied to the photo itself — never to the frame, the
/// watermarks or the caption. Shown to users as "Looks", a name of Markepi's
/// own (not Apple's "Photographic Styles", and not the frame *styles*).
///
/// Names are deliberately free of film-maker and camera-maker trademarks.
public enum PhotoLook: String, Codable, CaseIterable, Sendable, Identifiable {
    case original
    // Moods
    case vibrant, natural, luminous, dramatic, quiet, cozy, ethereal, mutedBW, starkBW
    // Undertones — skin-aware
    case neutral, coolRose, roseGold, gold, amber
    // Film
    case pastel400, golden200, chrome100, velvet50, classicNeg, tungsten800, silver400, faded

    public enum Family: String, CaseIterable, Sendable, Identifiable {
        case mood, undertone, film
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .mood: return "Moods"
            case .undertone: return "Undertones"
            case .film: return "Film"
            }
        }
        /// The looks offered under this family's pill, Original first.
        public var looks: [PhotoLook] { [.original] + PhotoLook.allCases.filter { $0.family == self } }
    }

    public var id: String { rawValue }

    /// Nil for `.original`, which belongs to every family.
    public var family: Family? {
        switch self {
        case .original: return nil
        case .vibrant, .natural, .luminous, .dramatic, .quiet, .cozy, .ethereal, .mutedBW, .starkBW: return .mood
        case .neutral, .coolRose, .roseGold, .gold, .amber: return .undertone
        case .pastel400, .golden200, .chrome100, .velvet50, .classicNeg, .tungsten800, .silver400, .faded: return .film
        }
    }

    public var title: String {
        switch self {
        case .original: return "Original"
        case .vibrant: return "Vibrant"
        case .natural: return "Natural"
        case .luminous: return "Luminous"
        case .dramatic: return "Dramatic"
        case .quiet: return "Quiet"
        case .cozy: return "Cozy"
        case .ethereal: return "Ethereal"
        case .mutedBW: return "Muted B&W"
        case .starkBW: return "Stark B&W"
        case .neutral: return "Neutral"
        case .coolRose: return "Cool Rose"
        case .roseGold: return "Rose Gold"
        case .gold: return "Gold"
        case .amber: return "Amber"
        case .pastel400: return "Pastel 400"
        case .golden200: return "Golden 200"
        case .chrome100: return "Chrome 100"
        case .velvet50: return "Velvet 50"
        case .classicNeg: return "Classic Neg"
        case .tungsten800: return "Tungsten 800"
        case .silver400: return "Silver 400"
        case .faded: return "Faded"
        }
    }

    /// Looks a free user may export (at default tuning).
    public var isFree: Bool { [.original, .vibrant, .natural, .neutral].contains(self) }

    public var isUndertone: Bool { family == .undertone }
    /// Black-and-white looks (rendered as RGB with equal channels).
    public var isMonochrome: Bool { [.mutedBW, .starkBW, .silver400].contains(self) }
    public var isFilm: Bool { family == .film }

    /// Unknown raw values (a look from a newer build) decode as `.original`.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = PhotoLook(rawValue: raw) ?? .original
    }
}

/// The chosen look and its user tuning. Persisted in `WatermarkConfiguration`.
public struct PhotoLookSettings: Codable, Sendable, Equatable {
    public var look: PhotoLook = .original
    /// 0…1. 0 equals Original.
    public var intensity: Double = 1
    /// −1 (darker) … 1 (brighter). 0 leaves the look as designed.
    public var tone: Double = 0
    /// −1 (cooler) … 1 (warmer). 0 leaves the look as designed.
    public var color: Double = 0
    /// 0…1 film grain override; nil uses the film's own amount. Film looks only.
    public var grain: Double?

    public init(look: PhotoLook = .original, intensity: Double = 1, tone: Double = 0, color: Double = 0, grain: Double? = nil) {
        self.look = look
        self.intensity = intensity
        self.tone = tone
        self.color = color
        self.grain = grain
    }

    /// Picking a look resets the tuning to that look's defaults.
    public static func choosing(_ look: PhotoLook) -> PhotoLookSettings { PhotoLookSettings(look: look) }

    /// Picking a look from these settings: the tuning resets, except a grain
    /// the user set, which carries from one film look to the next.
    public func choosing(_ look: PhotoLook) -> PhotoLookSettings {
        var next = PhotoLookSettings(look: look)
        if look.isFilm, self.look.isFilm { next.grain = grain }
        return next
    }

    /// True when the render would differ from the untouched photo.
    public var isActive: Bool { look != .original && intensity > 0 }

    /// Intensity, pad and grain all at their defaults.
    public var isDefaultTuning: Bool { intensity == 1 && tone == 0 && color == 0 && grain == nil }

    /// Every render-affecting field, for preview invalidation.
    public var previewKey: String {
        guard isActive else { return "lk:none" }
        return "lk:\(look.rawValue)|i:\(String(format: "%.3f", intensity))|t:\(String(format: "%.3f", tone))"
            + "|c:\(String(format: "%.3f", color))|g:\(grain.map { String(format: "%.3f", $0) } ?? "d")"
    }

    private enum CodingKeys: String, CodingKey { case look, intensity, tone, color, grain }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        look = try c.decodeIfPresent(PhotoLook.self, forKey: .look) ?? .original
        intensity = Self.clamp(try c.decodeIfPresent(Double.self, forKey: .intensity) ?? 1, 0, 1)
        tone = Self.clamp(try c.decodeIfPresent(Double.self, forKey: .tone) ?? 0, -1, 1)
        color = Self.clamp(try c.decodeIfPresent(Double.self, forKey: .color) ?? 0, -1, 1)
        grain = try c.decodeIfPresent(Double.self, forKey: .grain).map { Self.clamp($0, 0, 1) }
    }

    private static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { min(max(v, lo), hi) }
}
