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

    /// The default set of caption fields: camera plus the common shooting
    /// details. Mirrors the previous auto "detailed attribution" caption.
    public static let defaultCaptionFields: [CaptionField] = [
        .cameraModel, .focalLength, .aperture, .shutterSpeed, .iso, .dimensions, .format,
    ]

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
        textFontSizeRatio: CGFloat = 0.018
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
    }

    // MARK: - Codable (CGColor)

    enum CodingKeys: String, CodingKey {
        case isEnabled, frameWidthRatio, metadataTextEnabled
        case captionPrefix, captionFields
        case customAttributionText, textColorRGBA, textFontSizeRatio
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
    }
}
