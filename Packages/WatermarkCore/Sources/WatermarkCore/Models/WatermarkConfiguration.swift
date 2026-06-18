import CoreImage

/// Top-level configuration for a watermark processing operation.
///
/// Specifies which watermarks to apply, in what order (D-01: ordered layer stack),
/// optional white frame settings, and output format preferences.
///
/// Consumed by `WatermarkEngine.process(url:config:)` to build the filter graph.
public struct WatermarkConfiguration: Sendable, Codable {
    /// Ordered array of watermark layers composited from bottom to top (per D-01)
    public var watermarks: [WatermarkLayer]

    /// Padding between watermark and image edges, in points (default: 20)
    public var padding: CGFloat = 20

    /// Optional white frame configuration (full implementation in Plan 03)
    public var whiteFrame: WhiteFrameConfig?

    /// Output format preference
    public var outputFormat: OutputFormat

    /// Creates a watermark configuration.
    ///
    /// - Parameters:
    ///   - watermarks: Ordered watermark layers (bottom → top)
    ///   - whiteFrame: Optional white frame config (default: nil)
    ///   - outputFormat: Output format preference (default: .preserveSource)
    public init(
        watermarks: [WatermarkLayer] = [],
        whiteFrame: WhiteFrameConfig? = nil,
        outputFormat: OutputFormat = .preserveSource
    ) {
        self.watermarks = watermarks
        self.whiteFrame = whiteFrame
        self.outputFormat = outputFormat
    }
}

// MARK: - WatermarkLayer

/// Discriminated union representing a single watermark layer in the layer stack.
///
/// Each layer has a type (.text or .image), a position preset, and a scale factor.
/// Layers are composited in array order (index 0 = bottom, last index = top) per D-01.
public enum WatermarkLayer: Sendable {
    /// Text watermark with SF system font rendering
    case text(TextWatermarkInput, position: WatermarkPosition, scale: CGFloat)

    /// Image/logo watermark (full implementation in Plan 02)
    case image(ImageWatermarkInput, position: WatermarkPosition, scale: CGFloat)

    /// The position preset for this watermark layer
    public var position: WatermarkPosition {
        switch self {
        case .text(_, let position, _): return position
        case .image(_, let position, _): return position
        }
    }

    /// The scale factor relative to base image shorter dimension (0.01–0.90)
    public var scale: CGFloat {
        switch self {
        case .text(_, _, let scale): return scale
        case .image(_, _, let scale): return scale
        }
    }
}

// MARK: - WatermarkLayer Codable

extension WatermarkLayer: Codable {
    enum CodingKeys: String, CodingKey {
        case type, textConfig, imageConfig, position, scale
    }

    enum LayerType: String, Codable {
        case text, image
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(LayerType.self, forKey: .type)
        let position = try container.decode(WatermarkPosition.self, forKey: .position)
        let scale = try container.decode(CGFloat.self, forKey: .scale)

        switch type {
        case .text:
            let config = try container.decode(TextWatermarkInput.self, forKey: .textConfig)
            self = .text(config, position: position, scale: scale)
        case .image:
            let config = try container.decode(ImageWatermarkInput.self, forKey: .imageConfig)
            self = .image(config, position: position, scale: scale)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(position, forKey: .position)
        try container.encode(scale, forKey: .scale)

        switch self {
        case .text(let config, _, _):
            try container.encode(LayerType.text, forKey: .type)
            try container.encode(config, forKey: .textConfig)
        case .image(let config, _, _):
            try container.encode(LayerType.image, forKey: .type)
            try container.encode(config, forKey: .imageConfig)
        }
    }
}

// MARK: - OutputFormat

/// Output image format preference.
///
/// `.preserveSource` (default per D-09) keeps the source format (HEIC→HEIC, JPEG→JPEG).
/// Explicit overrides allow forcing a specific format when needed.
public enum OutputFormat: Sendable, Codable {
    /// Match the source image format (default per D-09)
    case preserveSource

    /// Force HEIC output
    case heic

    /// Force JPEG output
    case jpeg

    /// Force PNG output
    case png

    // MARK: Codable (String raw value)

    enum RawValue: String, Codable {
        case preserveSource, heic, jpeg, png
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(RawValue.self)
        switch raw {
        case .preserveSource: self = .preserveSource
        case .heic: self = .heic
        case .jpeg: self = .jpeg
        case .png: self = .png
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .preserveSource: try container.encode(RawValue.preserveSource)
        case .heic: try container.encode(RawValue.heic)
        case .jpeg: try container.encode(RawValue.jpeg)
            case .png: try container.encode(RawValue.png)
        }
    }
}

// MARK: - PHAdjustmentData Image Stripping (stubs — RED phase)

extension WatermarkConfiguration {
    /// Returns a copy with image watermark PNG data replaced by a minimal
    /// placeholder, keeping the serialized config under PHAdjustmentData
    /// size limits.
    ///
    /// - RED stub: returns self unchanged. Will be properly implemented
    ///   in Task 3.
    public func strippingImageData() -> WatermarkConfiguration {
        // RED: stub — returns self, not yet stripping image data
        return self
    }

    /// Restores image watermark PNG data from the full config stored in
    /// App Group UserDefaults.
    ///
    /// - RED stub: no-op. Will be properly implemented in Task 3.
    public mutating func rehydrateImageData() {
        // RED: stub — no-op, not yet rehydrating
    }
}