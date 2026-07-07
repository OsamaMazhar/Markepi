import Foundation

/// Configuration for a PNG image-based watermark overlay.
///
/// Validates PNG data and scale range on init. Opacity is clamped to 0.0–1.0.
/// The data model carries the configuration to ImageWatermarkRenderer for
/// CIImage creation, scaling, rotation, and opacity application.
public struct ImageWatermarkInput: Sendable, Codable {
    /// Raw PNG image data (must be non-empty)
    public let pngData: Data

    /// Scale factor relative to base image shorter dimension (0.01–0.90)
    public let scale: CGFloat

    /// Opacity from 0.0 (transparent) to 1.0 (fully opaque), clamped to valid range
    public let opacity: CGFloat

    /// Clockwise rotation applied to the logo, in degrees, normalized to [0, 360).
    /// 0 means upright. Applied at render time after scaling.
    public let rotationDegrees: CGFloat

    /// Creates an image watermark configuration.
    ///
    /// - Parameters:
    ///   - pngData: Non-empty PNG image data
    ///   - scale: Scale factor 0.01–0.90 (default: 0.15)
    ///   - opacity: 0.0–1.0 alpha (default: 0.8), clamped to valid range
    ///   - rotationDegrees: Clockwise rotation in degrees (default: 0),
    ///     normalized to [0, 360)
    /// - Throws: `PipelineError.invalidImageData` if pngData is empty
    /// - Throws: `PipelineError.invalidScale` if scale is outside 0.01–0.90
    public init(pngData: Data, scale: CGFloat = 0.15, opacity: CGFloat = 0.8, rotationDegrees: CGFloat = 0) throws {
        // Validate PNG data is non-empty (full format validation deferred to
        // CIImage(data:) in ImageWatermarkRenderer — non-PNG data returns nil)
        guard !pngData.isEmpty else {
            throw PipelineError.invalidImageData
        }

        // Validate scale range (T-02-02: prevents enormous CIImage extents)
        let minScale: CGFloat = 0.01
        let maxScale: CGFloat = 0.90
        guard scale >= minScale && scale <= maxScale else {
            throw PipelineError.invalidScale(Double(scale))
        }

        self.pngData = pngData
        self.scale = scale
        // Clamp opacity to 0.0–1.0 (non-fatal — silently corrected)
        self.opacity = max(0.0, min(1.0, opacity))
        self.rotationDegrees = Self.normalizeDegrees(rotationDegrees)
    }

    /// Non-throwing copy constructor for already-validated inputs (rotation
    /// edits reuse the validated `pngData`/`scale`, so re-validation is moot).
    private init(validated pngData: Data, scale: CGFloat, opacity: CGFloat, rotationDegrees: CGFloat) {
        self.pngData = pngData
        self.scale = scale
        self.opacity = opacity
        self.rotationDegrees = Self.normalizeDegrees(rotationDegrees)
    }

    /// Returns a copy with a new clockwise rotation (degrees), normalized to
    /// [0, 360). All other parameters are preserved.
    public func withRotationDegrees(_ degrees: CGFloat) -> ImageWatermarkInput {
        ImageWatermarkInput(validated: pngData, scale: scale, opacity: opacity, rotationDegrees: degrees)
    }

    /// Returns a copy with a new opacity (clamped to 0...1), preserving the
    /// logo image, scale, and rotation.
    public func withOpacity(_ opacity: CGFloat) -> ImageWatermarkInput {
        ImageWatermarkInput(
            validated: pngData,
            scale: scale,
            opacity: max(0.0, min(1.0, opacity)),
            rotationDegrees: rotationDegrees
        )
    }

    /// Wraps an arbitrary degree value into the canonical [0, 360) range.
    /// Non-finite inputs collapse to 0.
    static func normalizeDegrees(_ degrees: CGFloat) -> CGFloat {
        guard degrees.isFinite else { return 0 }
        let remainder = degrees.truncatingRemainder(dividingBy: 360)
        return remainder < 0 ? remainder + 360 : remainder
    }

    // MARK: - Codable (backward compatible)

    // Explicit keys so configs/templates encoded before `rotationDegrees`
    // existed still decode — the missing key falls back to 0 (upright).
    enum CodingKeys: String, CodingKey {
        case pngData, scale, opacity, rotationDegrees
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.pngData = try container.decode(Data.self, forKey: .pngData)
        self.scale = try container.decode(CGFloat.self, forKey: .scale)
        self.opacity = try container.decode(CGFloat.self, forKey: .opacity)
        self.rotationDegrees = Self.normalizeDegrees(
            try container.decodeIfPresent(CGFloat.self, forKey: .rotationDegrees) ?? 0
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pngData, forKey: .pngData)
        try container.encode(scale, forKey: .scale)
        try container.encode(opacity, forKey: .opacity)
        try container.encode(rotationDegrees, forKey: .rotationDegrees)
    }
}
