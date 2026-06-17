import CoreImage

/// Top-level configuration for a watermark processing operation.
///
/// Specifies which watermarks to apply, in what order (D-01: ordered layer stack),
/// optional white frame settings, and output format preferences.
///
/// Consumed by `WatermarkEngine.process(url:config:)` to build the filter graph.
public struct WatermarkConfiguration: Sendable {
    /// Ordered array of watermark layers composited from bottom to top (per D-01)
    public var watermarks: [WatermarkLayer]

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

// MARK: - OutputFormat

/// Output image format preference.
///
/// `.preserveSource` (default per D-09) keeps the source format (HEIC→HEIC, JPEG→JPEG).
/// Explicit overrides allow forcing a specific format when needed.
public enum OutputFormat: Sendable {
    /// Match the source image format (default per D-09)
    case preserveSource

    /// Force HEIC output
    case heic

    /// Force JPEG output
    case jpeg

    /// Force PNG output
    case png
}
