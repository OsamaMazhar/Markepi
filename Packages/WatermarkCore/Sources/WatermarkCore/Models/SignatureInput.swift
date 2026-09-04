import CoreImage

/// Configuration for a signature-based watermark overlay.
///
/// Stores PencilKit stroke data (vector, typically <100KB), ink color,
/// and stroke width. The actual rendering is done by SignatureRenderer
/// which rasterizes the PKDrawing to a CIImage with the configured ink color.
///
/// CGColor Codable pattern matches TextWatermarkInput exactly: encode as
/// `colorRGBA: [CGFloat]` array, decode via `CGColor(sRGB, components:)`.
public struct SignatureInput: Sendable, Codable {
    /// Raw PKDrawing.dataRepresentation() bytes (vector, typically <100KB)
    public let strokeData: Data

    /// Ink color for the rendered signature (default: white)
    public let inkColor: CGColor

    /// Stroke width in points (default: 3.0)
    public let strokeWidth: CGFloat

    /// Creates a signature watermark configuration.
    ///
    /// - Parameters:
    ///   - strokeData: Raw PKDrawing.dataRepresentation() bytes
    ///   - inkColor: CGColor for the ink (default: white)
    ///   - strokeWidth: Stroke width in points (default: 3.0)
    public init(
        strokeData: Data,
        inkColor: CGColor = CGColor(red: 1, green: 1, blue: 1, alpha: 1),
        strokeWidth: CGFloat = 3.0
    ) {
        self.strokeData = strokeData
        self.inkColor = inkColor
        self.strokeWidth = strokeWidth
    }

    // MARK: - Codable (CGColor)

    enum CodingKeys: String, CodingKey {
        case strokeData, colorRGBA, strokeWidth
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        strokeData = try container.decode(Data.self, forKey: .strokeData)
        strokeWidth = try container.decode(CGFloat.self, forKey: .strokeWidth)
        let rgba = try container.decode([CGFloat].self, forKey: .colorRGBA)
        guard rgba.count == 4,
              let cgColor = CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    components: rgba) else {
            throw DecodingError.dataCorruptedError(forKey: .colorRGBA, in: container,
                debugDescription: "Invalid RGBA components for CGColor")
        }
        inkColor = cgColor
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(strokeData, forKey: .strokeData)
        try container.encode(strokeWidth, forKey: .strokeWidth)
        let components = inkColor.components ?? [0, 0, 0, 1]
        let rgba: [CGFloat] = components.count >= 4
            ? [components[0], components[1], components[2], components[3]]
            : [0, 0, 0, 1]
        try container.encode(rgba, forKey: .colorRGBA)
    }
}
