import CoreImage

/// Configuration for a text-based watermark overlay.
///
/// Uses SF system fonts per D-02 decision. Defaults: system font size 72, white color, opacity 0.8.
/// Rendered via `CIAttributedTextImageGenerator` to stay within the Core Image lazy filter graph.
public struct TextWatermarkInput: Sendable, Codable {
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

    // MARK: - Codable (CGColor)

    enum CodingKeys: String, CodingKey {
        case text, fontSize, colorRGBA, opacity
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decode(String.self, forKey: .text)
        fontSize = try container.decode(CGFloat.self, forKey: .fontSize)
        opacity = try container.decode(CGFloat.self, forKey: .opacity)
        let rgba = try container.decode([CGFloat].self, forKey: .colorRGBA)
        guard rgba.count == 4,
              let cgColor = CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    components: rgba) else {
            throw DecodingError.dataCorruptedError(forKey: .colorRGBA, in: container,
                debugDescription: "Invalid RGBA components for CGColor")
        }
        color = cgColor
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(text, forKey: .text)
        try container.encode(fontSize, forKey: .fontSize)
        try container.encode(opacity, forKey: .opacity)
        let components = color.components ?? [1, 1, 1, 1]
        let rgba: [CGFloat] = components.count >= 4
            ? [components[0], components[1], components[2], components[3]]
            : [1, 1, 1, 1]
        try container.encode(rgba, forKey: .colorRGBA)
    }
}
