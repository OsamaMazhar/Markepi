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
public struct WhiteFrameConfig: Sendable {
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

    /// Text font size as proportion of frame width.
    /// 0.4 = 40% of frame width, per RESEARCH.md example.
    /// Default: 0.4
    public var textFontSizeRatio: CGFloat

    /// Creates a white frame configuration.
    ///
    /// - Parameters:
    ///   - isEnabled: Whether to apply the white frame (default: false)
    ///   - frameWidthRatio: Proportion of shorter image dimension 0.03–0.05 (default: 0.04)
    ///   - metadataTextEnabled: Whether to render device metadata text (default: true)
    ///   - customAttributionText: Custom text override, nil = auto-generate (default: nil)
    ///   - textColor: CGColor for the metadata text (default: dark gray)
    ///   - textFontSizeRatio: Font size as proportion of frame width (default: 0.4)
    public init(
        isEnabled: Bool = false,
        frameWidthRatio: CGFloat = 0.04,
        metadataTextEnabled: Bool = true,
        customAttributionText: String? = nil,
        textColor: CGColor = CGColor(gray: 0.333, alpha: 1.0),
        textFontSizeRatio: CGFloat = 0.4
    ) {
        self.isEnabled = isEnabled
        // Clamp to 0.03–0.05 per D-05 (warning-level tolerance, not a throw)
        self.frameWidthRatio = min(0.05, max(0.03, frameWidthRatio))
        self.metadataTextEnabled = metadataTextEnabled
        self.customAttributionText = customAttributionText
        self.textColor = textColor
        self.textFontSizeRatio = textFontSizeRatio
    }
}
