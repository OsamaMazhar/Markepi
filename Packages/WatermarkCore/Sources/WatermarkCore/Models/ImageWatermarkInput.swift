import Foundation

/// Configuration for a PNG image-based watermark overlay.
///
/// Validates PNG data and scale range on init. Opacity is clamped to 0.0–1.0.
/// The data model carries the configuration to ImageWatermarkRenderer for
/// CIImage creation, scaling, and opacity application.
public struct ImageWatermarkInput: Sendable {
    /// Raw PNG image data (must be non-empty)
    public let pngData: Data

    /// Scale factor relative to base image shorter dimension (0.01–0.90)
    public let scale: CGFloat

    /// Opacity from 0.0 (transparent) to 1.0 (fully opaque), clamped to valid range
    public let opacity: CGFloat

    /// Creates an image watermark configuration.
    ///
    /// - Parameters:
    ///   - pngData: Non-empty PNG image data
    ///   - scale: Scale factor 0.01–0.90 (default: 0.15)
    ///   - opacity: 0.0–1.0 alpha (default: 0.8), clamped to valid range
    /// - Throws: `PipelineError.invalidImageData` if pngData is empty
    /// - Throws: `PipelineError.invalidScale` if scale is outside 0.01–0.90
    public init(pngData: Data, scale: CGFloat = 0.15, opacity: CGFloat = 0.8) throws {
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
    }
}
