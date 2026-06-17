import CoreImage

/// Configuration for a text-based watermark overlay.
///
/// Uses SF system fonts per D-02 decision. Defaults: system font size 72, white color, opacity 0.8.
/// Rendered via `CIAttributedTextImageGenerator` to stay within the Core Image lazy filter graph.
public struct TextWatermarkInput: Sendable {
    /// The text string to render as a watermark
    public let text: String

    /// System font size in points (default: 72)
    public let fontSize: CGFloat

    /// Text color as CGColor (default: white)
    public let color: CGColor

    /// Opacity from 0.0 (transparent) to 1.0 (fully opaque). Default: 0.8
    public let opacity: CGFloat

    /// Creates a text watermark configuration.
    ///
    /// - Parameters:
    ///   - text: The watermark text (must be non-empty)
    ///   - fontSize: System font point size (default: 72)
    ///   - color: CGColor for the text (default: white)
    ///   - opacity: 0.0–1.0 alpha (default: 0.8)
    public init(
        text: String,
        fontSize: CGFloat = 72,
        color: CGColor = CGColor(red: 1, green: 1, blue: 1, alpha: 1),
        opacity: CGFloat = 0.8
    ) {
        self.text = text
        self.fontSize = fontSize
        self.color = color
        self.opacity = opacity
    }
}
