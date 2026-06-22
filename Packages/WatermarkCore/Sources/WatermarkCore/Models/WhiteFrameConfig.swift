import CoreImage

/// Configuration for the white frame border overlay.
///
/// Fully implemented in Plan 03. The white frame is a uniform 4-sided border
/// with proportional width (3-5% of shorter image dimension per D-05) and
/// a centered "Taken by: [Device Model]" attribution text on the bottom
/// portion of the frame (D-06).
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

    /// Whether to render the "Taken by: [Model]" attribution text on the
    /// bottom portion of the white frame. When true, text is drawn centered
    /// horizontally on the bottom frame border.
    /// Default: true
    public var metadataTextEnabled: Bool

    /// Custom attribution text override. When non-nil, this text is used
    /// instead of the auto-generated "Taken by: [Device Model]" from
    /// `DeviceMetadataProvider.attributionText(from:)`.
    /// When nil, the device model is extracted from metadata automatically.
    /// Default: nil (auto-generate from metadata)
    public var customAttributionText: String?

    /// Text color for the metadata text rendered on the white frame.
    /// Default: dark gray (CGColor(gray: 0.333, alpha: 1.0))
    public var textColor: CGColor

    /// Text font size as proportion of the image's shorter dimension.
    /// 0.018 = 1.8% of shorter dimension (e.g., 54pt for a 3000px image).
    /// Default: 0.018
    public var textFontSizeRatio: CGFloat

    /// Creates a white frame configuration.
    ///
    /// - Parameters:
    ///   - isEnabled: Whether to apply the white frame (default: false)
    ///   - frameWidthRatio: Proportion of shorter image dimension 0.03–0.05 (default: 0.04)
    ///   - metadataTextEnabled: Whether to render device metadata text (default: true)
    ///   - customAttributionText: Custom text override, nil = auto-generate (default: nil)
    ///   - textColor: CGColor for the metadata text (default: dark gray)
    ///   - textFontSizeRatio: Font size as proportion of image shorter dimension (default: 0.018)
    public init(
        isEnabled: Bool = false,
        frameWidthRatio: CGFloat = 0.04,
        metadataTextEnabled: Bool = true,
        customAttributionText: String? = nil,
        textColor: CGColor = CGColor(gray: 0.333, alpha: 1.0),
        textFontSizeRatio: CGFloat = 0.018
    ) {
        self.isEnabled = isEnabled
        // Clamp to 0.03–0.05 per D-05 (warning-level tolerance, not a throw)
        self.frameWidthRatio = min(0.05, max(0.03, frameWidthRatio))
        self.metadataTextEnabled = metadataTextEnabled
        self.customAttributionText = customAttributionText
        self.textColor = textColor
        self.textFontSizeRatio = textFontSizeRatio
    }

    // MARK: - Codable (CGColor)

    enum CodingKeys: String, CodingKey {
        case isEnabled, frameWidthRatio, metadataTextEnabled
        case customAttributionText, textColorRGBA, textFontSizeRatio
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        frameWidthRatio = try container.decode(CGFloat.self, forKey: .frameWidthRatio)
        metadataTextEnabled = try container.decode(Bool.self, forKey: .metadataTextEnabled)
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
        try container.encodeIfPresent(customAttributionText, forKey: .customAttributionText)
        try container.encode(textFontSizeRatio, forKey: .textFontSizeRatio)
        let components = textColor.components ?? [0.333, 0.333, 0.333, 1.0]
        let rgba: [CGFloat] = components.count >= 4
            ? [components[0], components[1], components[2], components[3]]
            : [0.333, 0.333, 0.333, 1.0]
        try container.encode(rgba, forKey: .textColorRGBA)
    }
}
