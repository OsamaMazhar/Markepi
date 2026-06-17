import Foundation

/// Configuration for a PNG image-based watermark overlay.
///
/// Full PNG-to-CIImage rendering with alpha compositing is deferred to Plan 02.
/// This stub provides the data model and input validation so the WatermarkConfiguration
/// enum discriminator compiles and multi-layer configs can reference image watermarks.
public struct ImageWatermarkInput: Sendable {
    /// Raw PNG image data (must be non-empty)
    public let pngData: Data

    /// Scale factor relative to base image shorter dimension (0.01–0.90)
    public let scale: CGFloat

    /// Opacity from 0.0 (transparent) to 1.0 (fully opaque)
    public let opacity: CGFloat

    /// Creates an image watermark configuration.
    ///
    /// - Parameters:
    ///   - pngData: Non-empty PNG image data
    ///   - scale: Scale factor 0.01–0.90 (default: 0.15)
    ///   - opacity: 0.0–1.0 alpha (default: 0.8)
    public init(pngData: Data, scale: CGFloat = 0.15, opacity: CGFloat = 0.8) {
        self.pngData = pngData
        self.scale = scale
        self.opacity = opacity
    }
}
