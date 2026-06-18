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

    /// Output quality for lossy formats (0.0–1.0). Default 1.0 (maximum quality).
    /// Maps to kCGImageDestinationLossyCompressionQuality. Ignored by lossless formats (PNG, TIFF).
    public var outputQuality: Float = 1.0

    // MARK: CodingKeys

    enum CodingKeys: String, CodingKey {
        case watermarks, padding, whiteFrame, outputFormat, outputQuality
    }

    /// Creates a watermark configuration.
    ///
    /// - Parameters:
    ///   - watermarks: Ordered watermark layers (bottom → top)
    ///   - whiteFrame: Optional white frame config (default: nil)
    ///   - outputFormat: Output format preference (default: .preserveSource)
    ///   - outputQuality: Output quality 0.0–1.0 (default: 1.0, max quality)
    public init(
        watermarks: [WatermarkLayer] = [],
        whiteFrame: WhiteFrameConfig? = nil,
        outputFormat: OutputFormat = .preserveSource,
        outputQuality: Float = 1.0
    ) {
        self.watermarks = watermarks
        self.whiteFrame = whiteFrame
        self.outputFormat = outputFormat
        self.outputQuality = outputQuality
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.watermarks = try container.decode([WatermarkLayer].self, forKey: .watermarks)
        self.padding = try container.decodeIfPresent(CGFloat.self, forKey: .padding) ?? 20
        self.whiteFrame = try container.decodeIfPresent(WhiteFrameConfig.self, forKey: .whiteFrame)
        self.outputFormat = try container.decodeIfPresent(OutputFormat.self, forKey: .outputFormat) ?? .preserveSource
        self.outputQuality = try container.decodeIfPresent(Float.self, forKey: .outputQuality) ?? 1.0
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(watermarks, forKey: .watermarks)
        try container.encode(padding, forKey: .padding)
        try container.encodeIfPresent(whiteFrame, forKey: .whiteFrame)
        try container.encode(outputFormat, forKey: .outputFormat)
        try container.encode(outputQuality, forKey: .outputQuality)
    }
}

// MARK: - WatermarkLayer

/// Discriminated union representing a single watermark layer in the layer stack.
///
/// Each layer has a type (.text or .image), a position preset, a scale factor,
/// per-layer compositing opacity (0.0–1.0), and a visibility toggle.
/// Layers are composited in array order (index 0 = bottom, last index = top) per D-01.
public enum WatermarkLayer: Sendable {
    /// Text watermark with SF system font rendering
    case text(TextWatermarkInput, position: WatermarkPosition, scale: CGFloat, opacity: CGFloat, isVisible: Bool)

    /// Image/logo watermark (full implementation in Plan 02)
    case image(ImageWatermarkInput, position: WatermarkPosition, scale: CGFloat, opacity: CGFloat, isVisible: Bool)

    /// Signature watermark with PencilKit stroke data
    case signature(SignatureInput, position: WatermarkPosition, scale: CGFloat, opacity: CGFloat, isVisible: Bool)

    /// The position preset for this watermark layer
    public var position: WatermarkPosition {
        switch self {
        case .text(_, let position, _, _, _): return position
        case .image(_, let position, _, _, _): return position
        case .signature(_, let position, _, _, _): return position
        }
    }

    /// The scale factor relative to base image shorter dimension (0.01–0.90)
    public var scale: CGFloat {
        switch self {
        case .text(_, _, let scale, _, _): return scale
        case .image(_, _, let scale, _, _): return scale
        case .signature(_, _, let scale, _, _): return scale
        }
    }

    /// Per-layer compositing opacity (0.0–1.0). Default 1.0.
    /// Applied via CIFilter.colorMatrix alpha modulation at compositing time.
    /// Distinct from per-element opacity (TextWatermarkInput.opacity for text rendering,
    /// ImageWatermarkInput.opacity for PNG alpha).
    public var opacity: CGFloat {
        switch self {
        case .text(_, _, _, let opacity, _): return opacity
        case .image(_, _, _, let opacity, _): return opacity
        case .signature(_, _, _, let opacity, _): return opacity
        }
    }

    /// Per-layer visibility. False → layer is skipped in compositing.
    public var isVisible: Bool {
        switch self {
        case .text(_, _, _, _, let isVisible): return isVisible
        case .image(_, _, _, _, let isVisible): return isVisible
        case .signature(_, _, _, _, let isVisible): return isVisible
        }
    }
}

// MARK: - WatermarkLayer Codable

extension WatermarkLayer: Codable {
    enum CodingKeys: String, CodingKey {
        case type, textConfig, imageConfig, signatureConfig, position, scale, opacity, isVisible
    }

    enum LayerType: String, Codable {
        case text, image, signature
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(LayerType.self, forKey: .type)
        let position = try container.decode(WatermarkPosition.self, forKey: .position)
        let scale = try container.decode(CGFloat.self, forKey: .scale)
        let opacity = try container.decodeIfPresent(CGFloat.self, forKey: .opacity) ?? 1.0
        let isVisible = try container.decodeIfPresent(Bool.self, forKey: .isVisible) ?? true

        switch type {
        case .text:
            let config = try container.decode(TextWatermarkInput.self, forKey: .textConfig)
            self = .text(config, position: position, scale: scale, opacity: opacity, isVisible: isVisible)
        case .image:
            let config = try container.decode(ImageWatermarkInput.self, forKey: .imageConfig)
            self = .image(config, position: position, scale: scale, opacity: opacity, isVisible: isVisible)
        case .signature:
            let config = try container.decode(SignatureInput.self, forKey: .signatureConfig)
            self = .signature(config, position: position, scale: scale, opacity: opacity, isVisible: isVisible)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(position, forKey: .position)
        try container.encode(scale, forKey: .scale)

        switch self {
        case .text(let config, _, _, let opacity, let isVisible):
            try container.encode(LayerType.text, forKey: .type)
            try container.encode(config, forKey: .textConfig)
            try container.encode(opacity, forKey: .opacity)
            try container.encode(isVisible, forKey: .isVisible)
        case .image(let config, _, _, let opacity, let isVisible):
            try container.encode(LayerType.image, forKey: .type)
            try container.encode(config, forKey: .imageConfig)
            try container.encode(opacity, forKey: .opacity)
            try container.encode(isVisible, forKey: .isVisible)
        case .signature(let config, _, _, let opacity, let isVisible):
            try container.encode(LayerType.signature, forKey: .type)
            try container.encode(config, forKey: .signatureConfig)
            try container.encode(opacity, forKey: .opacity)
            try container.encode(isVisible, forKey: .isVisible)
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

    /// Force TIFF output
    case tiff

    /// Returns the Core Graphics / UTType UTI string for this format,
    /// or nil for `.preserveSource` (which means "use the source UTI").
    public var uti: String? {
        switch self {
        case .preserveSource: return nil
        case .heic: return "public.heic"
        case .jpeg: return "public.jpeg"
        case .png: return "public.png"
        case .tiff: return "public.tiff"
        }
    }

    /// Returns true for lossless formats (PNG, TIFF) where quality slider should be disabled.
    public var isLossless: Bool {
        switch self {
        case .png, .tiff: return true
        default: return false
        }
    }

    // MARK: Codable (String raw value)

    enum RawValue: String, Codable {
        case preserveSource, heic, jpeg, png, tiff
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(RawValue.self)
        switch raw {
        case .preserveSource: self = .preserveSource
        case .heic: self = .heic
        case .jpeg: self = .jpeg
        case .png: self = .png
        case .tiff: self = .tiff
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .preserveSource: try container.encode(RawValue.preserveSource)
        case .heic: try container.encode(RawValue.heic)
        case .jpeg: try container.encode(RawValue.jpeg)
        case .png: try container.encode(RawValue.png)
        case .tiff: try container.encode(RawValue.tiff)
        }
    }
}

// MARK: - PHAdjustmentData Image Stripping

extension WatermarkConfiguration {
    /// A valid minimal 1×1 RGBA transparent PNG (67 bytes).
    /// Used as a placeholder for image watermark data when stripping
    /// large PNG blobs before JSON-encoding for PHAdjustmentData.
    ///
    /// PHAdjustmentData has an implicit ~2 MB size limit (Pitfall 1).
    /// Replacing image PNG data with this placeholder keeps serialized
    /// configs safely under that limit. The full PNG data is stored
    /// in App Group UserDefaults for rehydration on re-edit.
    private static let strippedPlaceholderPNG: Data = {
        // Pre-computed valid 1×1 RGBA transparent PNG bytes
        let bytes: [UInt8] = [
            0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
            0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
            0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
            0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
            0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
            0x54, 0x78, 0x9C, 0x62, 0x00, 0x00, 0x00, 0x02,
            0x00, 0x01, 0xE5, 0x27, 0xDE, 0xFC, 0x00, 0x00,
            0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42,
            0x60, 0x82,
        ]
        return Data(bytes)
    }()

    /// Returns a copy of this configuration with all `.image` watermark
    /// layer PNG data replaced by a 1×1 transparent placeholder PNG.
    ///
    /// Text layers, white frame config, output format, and padding are
    /// left unchanged. Layer positions and scales are preserved so that
    /// `rehydrateImageData()` can match layers back to the full config.
    ///
    /// This keeps JSON-encoded configs safely under the PHAdjustmentData
    /// ~2 MB effective size limit (Pitfall 1, T-04-09).
    ///
    /// - Returns: A copy with image PNG data replaced by minimal placeholders
    public func strippingImageData() -> WatermarkConfiguration {
        var copy = self

        // Replace image watermark PNG data with 1×1 transparent placeholder
        copy.watermarks = watermarks.map { layer in
            switch layer {
            case .image(let input, let position, let scale, let opacity, let isVisible):
                // Preserve position and scale for rehydration matching (T-04-08)
                // Replace pngData with minimal placeholder (~67 bytes vs original)
                if let strippedInput = try? ImageWatermarkInput(
                    pngData: Self.strippedPlaceholderPNG,
                    scale: input.scale,
                    opacity: input.opacity
                ) {
                    return .image(strippedInput, position: position, scale: scale, opacity: opacity, isVisible: isVisible)
                }
                // Fallback: if placeholder fails (shouldn't), keep original as text marker
                return .text(
                    TextWatermarkInput(text: "[Image]", fontSize: 12,
                                       color: CGColor(gray: 0.5, alpha: 1), opacity: 0.5),
                    position: position,
                    scale: scale,
                    opacity: 0.5,
                    isVisible: true
                )
            case .text:
                return layer
            case .signature:
                return layer
            }
        }

        return copy
    }

    /// Restores image watermark PNG data from the full configuration
    /// stored in App Group UserDefaults.
    ///
    /// Matches `.image` layers in this (stripped) config to their
    /// counterparts in the full config by position AND scale (T-04-08:
    /// both must match to prevent tampering). If no match is found,
    /// the layer keeps its placeholder — the engine will use it as-is
    /// or fall back gracefully.
    ///
    /// - Note: This mutates `self.watermarks` in place. Call after
    ///   decoding a stripped config from PHAdjustmentData JSON.
    public mutating func rehydrateImageData() {
        // Load the full config (with real image data) from App Group storage
        guard let fullConfig = AppGroupConfigSync.load() else {
            return // No full config available — keep stripped placeholders
        }

        // Build lookup: (position, scale) → ImageWatermarkInput from full config
        var fullImageLayers: [(WatermarkPosition, CGFloat, ImageWatermarkInput)] = []
        for layer in fullConfig.watermarks {
            if case .image(let input, let position, let scale, _, _) = layer {
                fullImageLayers.append((position, scale, input))
            }
        }

        // Rehydrate each image layer in self by matching position + scale
        watermarks = watermarks.map { layer in
            switch layer {
            case .image(let strippedInput, let position, let scale, let opacity, let isVisible):
                // T-04-08: match by position AND scale
                if let match = fullImageLayers.first(where: { $0.0 == position && abs($0.1 - scale) < 0.001 }),
                   !match.2.pngData.isEmpty {
                    // Validate rehydrated data (non-empty check per threat model)
                    if let rehydrated = try? ImageWatermarkInput(
                        pngData: match.2.pngData,
                        scale: strippedInput.scale,
                        opacity: strippedInput.opacity
                    ) {
                        return .image(rehydrated, position: position, scale: scale, opacity: opacity, isVisible: isVisible)
                    }
                }
                // No match found or invalid data — keep the stripped placeholder
                return layer
            case .text:
                return layer
            case .signature:
                return layer
            }
        }
    }
}