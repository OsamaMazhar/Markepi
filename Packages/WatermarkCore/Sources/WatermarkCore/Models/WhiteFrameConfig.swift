import CoreImage

/// A single metadata field that can be toggled on/off in the white-frame caption.
///
/// Each case maps to an `EXIFTokenParser` token so the caption is assembled by
/// substituting the selected fields against the source image's metadata. The
/// declaration order is the canonical render order: enabled fields are always
/// shown in this order regardless of the order the user ticked them.
public enum CaptionField: String, Codable, CaseIterable, Sendable, Identifiable {
    case cameraModel
    case lens
    case focalLength
    case aperture
    case shutterSpeed
    case iso
    case date
    case dimensions
    case format
    case gps

    public var id: String { rawValue }

    /// The `EXIFTokenParser` token this field resolves to.
    public var token: String {
        switch self {
        case .cameraModel:  return "{camera_model}"
        case .lens:         return "{lens}"
        case .focalLength:  return "{focal_length}"
        case .aperture:     return "{aperture}"
        case .shutterSpeed: return "{shutter_speed}"
        case .iso:          return "{iso}"
        case .date:         return "{date}"
        case .dimensions:   return "{dimensions}"
        case .format:       return "{format}"
        case .gps:          return "{gps}"
        }
    }

    /// Human-readable label shown next to the field's checkbox.
    public var displayName: String {
        switch self {
        case .cameraModel:  return "Camera / Device"
        case .lens:         return "Lens"
        case .focalLength:  return "Focal length"
        case .aperture:     return "Aperture"
        case .shutterSpeed: return "Shutter speed"
        case .iso:          return "ISO"
        case .date:         return "Date"
        case .dimensions:   return "Dimensions"
        case .format:       return "Format"
        case .gps:          return "Location"
        }
    }
}

/// The visual style of the frame: what shape the mat takes and how the caption
/// is laid out on it.
///
/// `classic` is the original look — a uniform border with one centred caption
/// line. `gallery` is the two-column caption bar: device and date on the left,
/// a brand mark and the photographer's details on the right.
public enum FrameStyle: String, Codable, CaseIterable, Sendable, Identifiable {
    case classic
    case gallery

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .classic: return "Classic"
        case .gallery: return "Gallery"
        }
    }

    public var summary: String {
        switch self {
        case .classic: return "An even border with one centred line of text"
        case .gallery: return "A gallery mat with device details and a brand mark"
        }
    }

    /// Decodes leniently: a style written by a newer build falls back to
    /// `classic` rather than failing the whole config, so a template can move
    /// backwards between versions.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = FrameStyle(rawValue: raw) ?? .classic
    }
}

/// What one line of the `gallery` caption says.
///
/// A slot is either a metadata field picked from `CaptionField`, free text the
/// user typed, or nothing. Free text goes through `EXIFTokenParser`, so
/// `"{lens} {focal_length}"` works there too — which is how a single line can
/// carry several metadata values, as the reference layout's lens line does.
public enum CaptionSlot: Sendable, Codable, Equatable {
    case field(CaptionField)
    case text(String)
    case empty

    /// True when this slot can never produce text, regardless of metadata.
    public var isEmpty: Bool {
        switch self {
        case .empty: return true
        case .text(let t): return t.trimmingCharacters(in: .whitespaces).isEmpty
        case .field: return false
        }
    }

    // MARK: Codable

    // Encoded as one tagged string rather than a nested object, so a slot
    // round-trips through a single value and stays readable in a saved template.
    private static let fieldPrefix = "field:"
    private static let textPrefix = "text:"

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        if raw.isEmpty {
            self = .empty
        } else if raw.hasPrefix(Self.fieldPrefix) {
            let name = String(raw.dropFirst(Self.fieldPrefix.count))
            // An unknown field name means a newer build wrote it; drop the slot
            // rather than failing the whole config.
            self = CaptionField(rawValue: name).map { .field($0) } ?? .empty
        } else if raw.hasPrefix(Self.textPrefix) {
            self = .text(String(raw.dropFirst(Self.textPrefix.count)))
        } else {
            // Untagged legacy value: treat it as what the user typed.
            self = .text(raw)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .empty: try container.encode("")
        case .field(let f): try container.encode(Self.fieldPrefix + f.rawValue)
        case .text(let t): try container.encode(Self.textPrefix + t)
        }
    }
}

/// Whether the brand mark is drawn in colour or as a single tone.
///
/// Which single tone — the dark or the light rendition — is not a user choice:
/// the renderer picks whichever contrasts with the mat.
public enum LogoVariant: String, Codable, CaseIterable, Sendable, Identifiable {
    case color
    case monochrome

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .color: return "Colour"
        case .monochrome: return "Monochrome"
        }
    }
}

/// Configuration for the white frame border overlay.
///
/// The white frame is a uniform 4-sided border with proportional width
/// (3-5% of shorter image dimension per D-05) and an optional caption rendered
/// on the bottom portion of the frame.
///
/// The caption is assembled from `captionPrefix` (free text the user types)
/// followed by the metadata fields the user has ticked in `captionFields`
/// (in canonical `CaptionField.allCases` order). `customAttributionText`
/// remains as a legacy/advanced override: when non-nil it takes precedence and
/// is rendered verbatim (after `{token}` substitution).
///
/// Consumed by `WhiteFrameRenderer` for Core Graphics → Core Image rendering
/// and by `WatermarkEngine.buildFilterGraph` to composite the frame below
/// all watermark layers.
public struct WhiteFrameConfig: Sendable, Codable {
    /// Whether the white frame overlay is enabled
    public var isEnabled: Bool

    /// Proportion of shorter image dimension used as frame width.
    /// Clamped to 0.03–0.05 per D-05 at init time (warning-level tolerance).
    /// Default: 0.04 (4% of shorter dimension)
    public var frameWidthRatio: CGFloat

    /// Master switch for the bottom-frame caption. When false, no text is
    /// rendered regardless of `captionPrefix`/`captionFields`.
    /// Default: true
    public var metadataTextEnabled: Bool

    /// Free-text prefix shown before the selected metadata fields, e.g.
    /// "Shot on". May be empty. `{token}` patterns are substituted.
    /// Default: "" (no prefix)
    public var captionPrefix: String

    /// Metadata fields to include in the caption, after `captionPrefix`.
    /// Rendered in canonical `CaptionField.allCases` order joined by " · ".
    /// Default: camera + shooting details.
    public var captionFields: [CaptionField]

    /// Legacy/advanced override. When non-nil, this text is rendered verbatim
    /// (after `{token}` substitution) instead of the prefix + fields caption.
    /// The current UI never sets this; it exists for backward compatibility
    /// with older saved templates.
    /// Default: nil
    public var customAttributionText: String?

    /// Text color for the metadata text rendered on the white frame.
    /// Default: dark gray (CGColor(gray: 0.333, alpha: 1.0))
    public var textColor: CGColor

    /// Text font size as proportion of the image's shorter dimension.
    /// 0.018 = 1.8% of shorter dimension (e.g., 54pt for a 3000px image).
    /// Default: 0.018
    public var textFontSizeRatio: CGFloat

    /// Which frame look to render. Default: `.classic`, so a config that
    /// predates styles keeps the border it always had.
    public var style: FrameStyle

    /// Mat thickness in millimetres, used by `gallery`.
    ///
    /// A physical size rather than a proportion: 5mm is 5mm on paper whatever
    /// the photo's pixel dimensions. `classic` keeps `frameWidthRatio`, which
    /// is proportional — the two styles genuinely mean different things by
    /// "border", and existing templates keep the ratio they were saved with.
    ///
    /// Converted to pixels against the photo's own resolution; see
    /// `FrameGeometry.resolveDPI`.
    public var borderMillimetres: CGFloat

    /// Caption text size in millimetres, used by `gallery`.
    ///
    /// Physical like the border it sits in. If the text were sized as a
    /// proportion of the photo instead, a large photo would grow text that a
    /// millimetre border could not hold — the two units would fight.
    /// `classic` keeps `textFontSizeRatio`.
    public var captionTextMillimetres: CGFloat

    /// Brand mark height in millimetres, used by `gallery`.
    ///
    /// Height, not width: these marks are mostly wordmarks whose aspect ratios
    /// run from about 10:1 to taller-than-wide, so a width-based size would
    /// make a wordmark microscopic and a square glyph enormous.
    public var logoHeightMillimetres: CGFloat

    /// Thin black stroke between the photo and the mat. Applies to every
    /// style, not just `gallery`. Default: false
    public var keylineEnabled: Bool

    /// Colour or monochrome for the brand mark. The brand itself is never
    /// configured — it is resolved from the photo's metadata.
    /// Default: `.color`
    public var logoVariant: LogoVariant

    // The four `gallery` caption lines. Unused by `classic`, which renders the
    // single centred caption built from `captionPrefix` + `captionFields`.

    /// Upper-left caption line, drawn bold and dark. Default: camera model.
    public var leftPrimary: CaptionSlot

    /// Lower-left caption line, drawn lighter. Default: capture date.
    public var leftSecondary: CaptionSlot

    /// Upper-right caption line, drawn bold and dark. Default: empty free
    /// text — this is where the photographer types their handle.
    public var rightPrimary: CaptionSlot

    /// Lower-right caption line, drawn lighter. Default: the lens line from
    /// the reference layout, which needs three metadata values on one line and
    /// so is expressed as tokens rather than a single field.
    public var rightSecondary: CaptionSlot

    /// The default set of caption fields: camera plus the common shooting
    /// details. Mirrors the previous auto "detailed attribution" caption.
    public static let defaultCaptionFields: [CaptionField] = [
        .cameraModel, .focalLength, .aperture, .shutterSpeed, .iso, .dimensions, .format,
    ]

    /// The `gallery` caption defaults, reproducing the reference layout.
    public static let defaultLeftPrimary: CaptionSlot = .field(.cameraModel)
    public static let defaultLeftSecondary: CaptionSlot = .field(.date)
    public static let defaultRightPrimary: CaptionSlot = .text("")
    public static let defaultRightSecondary: CaptionSlot = .text("{lens} {focal_length} {aperture}")

    /// Creates a white frame configuration.
    ///
    /// - Parameters:
    ///   - isEnabled: Whether to apply the white frame (default: false)
    ///   - frameWidthRatio: Proportion of shorter image dimension 0.03–0.05 (default: 0.04)
    ///   - metadataTextEnabled: Whether to render the caption (default: true)
    ///   - captionPrefix: Free text shown before the fields (default: "")
    ///   - captionFields: Metadata fields to include (default: camera + shooting details)
    ///   - customAttributionText: Legacy verbatim override, nil = use prefix+fields (default: nil)
    ///   - textColor: CGColor for the metadata text (default: dark gray)
    ///   - textFontSizeRatio: Font size as proportion of image shorter dimension (default: 0.018)
    public init(
        isEnabled: Bool = false,
        frameWidthRatio: CGFloat = 0.04,
        metadataTextEnabled: Bool = true,
        captionPrefix: String = "",
        captionFields: [CaptionField] = WhiteFrameConfig.defaultCaptionFields,
        customAttributionText: String? = nil,
        textColor: CGColor = CGColor(gray: 0.333, alpha: 1.0),
        textFontSizeRatio: CGFloat = 0.018,
        style: FrameStyle = .classic,
        borderMillimetres: CGFloat = 5.0,
        captionTextMillimetres: CGFloat = 2.5,
        logoHeightMillimetres: CGFloat = 4.0,
        keylineEnabled: Bool = false,
        logoVariant: LogoVariant = .color,
        leftPrimary: CaptionSlot = WhiteFrameConfig.defaultLeftPrimary,
        leftSecondary: CaptionSlot = WhiteFrameConfig.defaultLeftSecondary,
        rightPrimary: CaptionSlot = WhiteFrameConfig.defaultRightPrimary,
        rightSecondary: CaptionSlot = WhiteFrameConfig.defaultRightSecondary
    ) {
        self.isEnabled = isEnabled
        // Clamp to 0.03–0.05 per D-05 (warning-level tolerance, not a throw)
        self.frameWidthRatio = min(0.05, max(0.03, frameWidthRatio))
        self.metadataTextEnabled = metadataTextEnabled
        self.captionPrefix = captionPrefix
        self.captionFields = captionFields
        self.customAttributionText = customAttributionText
        self.textColor = textColor
        self.textFontSizeRatio = textFontSizeRatio
        self.style = style
        // A hairline mat is a rendering bug waiting to happen, and nobody
        // frames a print with a 10cm border; clamp rather than throw.
        self.borderMillimetres = min(50, max(0.5, borderMillimetres))
        self.captionTextMillimetres = min(20, max(0.5, captionTextMillimetres))
        self.logoHeightMillimetres = min(30, max(0.5, logoHeightMillimetres))
        self.keylineEnabled = keylineEnabled
        self.logoVariant = logoVariant
        self.leftPrimary = leftPrimary
        self.leftSecondary = leftSecondary
        self.rightPrimary = rightPrimary
        self.rightSecondary = rightSecondary
    }

    // MARK: - Codable (CGColor)

    enum CodingKeys: String, CodingKey {
        case isEnabled, frameWidthRatio, metadataTextEnabled
        case captionPrefix, captionFields
        case customAttributionText, textColorRGBA, textFontSizeRatio
        case style, borderMillimetres, captionTextMillimetres, logoHeightMillimetres
        case keylineEnabled, logoVariant
        case leftPrimary, leftSecondary, rightPrimary, rightSecondary
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        frameWidthRatio = try container.decode(CGFloat.self, forKey: .frameWidthRatio)
        metadataTextEnabled = try container.decode(Bool.self, forKey: .metadataTextEnabled)
        // New fields are optional so older saved configs keep decoding: absent
        // captionFields fall back to the default shooting-details set, matching
        // the prior auto-caption behavior.
        captionPrefix = try container.decodeIfPresent(String.self, forKey: .captionPrefix) ?? ""
        captionFields = try container.decodeIfPresent([CaptionField].self, forKey: .captionFields)
            ?? WhiteFrameConfig.defaultCaptionFields
        customAttributionText = try container.decodeIfPresent(String.self, forKey: .customAttributionText)
        textFontSizeRatio = try container.decode(CGFloat.self, forKey: .textFontSizeRatio)
        let rgba = try container.decode([CGFloat].self, forKey: .textColorRGBA)
        guard rgba.count == 4,
              let cgColor = CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    components: rgba) else {
            throw DecodingError.dataCorruptedError(forKey: .textColorRGBA, in: container,
                debugDescription: "Invalid RGBA components for CGColor")
        }
        textColor = cgColor
        // All new as of frame styles. Absent means a template written before
        // styles existed: it gets the classic border, no keyline, and the
        // reference gallery defaults it will only use if switched to gallery.
        style = try container.decodeIfPresent(FrameStyle.self, forKey: .style) ?? .classic
        borderMillimetres = min(50, max(0.5,
            try container.decodeIfPresent(CGFloat.self, forKey: .borderMillimetres) ?? 5.0))
        captionTextMillimetres = min(20, max(0.5,
            try container.decodeIfPresent(CGFloat.self, forKey: .captionTextMillimetres) ?? 2.5))
        logoHeightMillimetres = min(30, max(0.5,
            try container.decodeIfPresent(CGFloat.self, forKey: .logoHeightMillimetres) ?? 4.0))
        keylineEnabled = try container.decodeIfPresent(Bool.self, forKey: .keylineEnabled) ?? false
        logoVariant = try container.decodeIfPresent(LogoVariant.self, forKey: .logoVariant) ?? .color
        leftPrimary = try container.decodeIfPresent(CaptionSlot.self, forKey: .leftPrimary)
            ?? WhiteFrameConfig.defaultLeftPrimary
        leftSecondary = try container.decodeIfPresent(CaptionSlot.self, forKey: .leftSecondary)
            ?? WhiteFrameConfig.defaultLeftSecondary
        rightPrimary = try container.decodeIfPresent(CaptionSlot.self, forKey: .rightPrimary)
            ?? WhiteFrameConfig.defaultRightPrimary
        rightSecondary = try container.decodeIfPresent(CaptionSlot.self, forKey: .rightSecondary)
            ?? WhiteFrameConfig.defaultRightSecondary
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(frameWidthRatio, forKey: .frameWidthRatio)
        try container.encode(metadataTextEnabled, forKey: .metadataTextEnabled)
        try container.encode(captionPrefix, forKey: .captionPrefix)
        try container.encode(captionFields, forKey: .captionFields)
        try container.encodeIfPresent(customAttributionText, forKey: .customAttributionText)
        try container.encode(textFontSizeRatio, forKey: .textFontSizeRatio)
        let components = textColor.components ?? [0.333, 0.333, 0.333, 1.0]
        let rgba: [CGFloat] = components.count >= 4
            ? [components[0], components[1], components[2], components[3]]
            : [0.333, 0.333, 0.333, 1.0]
        try container.encode(rgba, forKey: .textColorRGBA)
        try container.encode(style, forKey: .style)
        try container.encode(borderMillimetres, forKey: .borderMillimetres)
        try container.encode(captionTextMillimetres, forKey: .captionTextMillimetres)
        try container.encode(logoHeightMillimetres, forKey: .logoHeightMillimetres)
        try container.encode(keylineEnabled, forKey: .keylineEnabled)
        try container.encode(logoVariant, forKey: .logoVariant)
        try container.encode(leftPrimary, forKey: .leftPrimary)
        try container.encode(leftSecondary, forKey: .leftSecondary)
        try container.encode(rightPrimary, forKey: .rightPrimary)
        try container.encode(rightSecondary, forKey: .rightSecondary)
    }
}
