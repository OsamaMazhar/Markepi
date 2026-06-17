import CoreImage
import Foundation

/// Actor-isolated photo watermarking engine (Pattern 3).
///
/// Orchestrates the full input → render → output pipeline:
///   1. Load: `ImageLoader.load(from:)` — extract metadata, HDR, CIImage
///   2. Normalize: `OrientationNormalizer.normalize(_:)` — EXIF → .up
///   3. Build filter graph: composite watermark layers via `WatermarkRenderer`
///   4. Render: `CIContextProvider.shared.createCGImage(...)` — GPU rasterize
///   5. Write: `ImageWriter.write(...)` — re-attach metadata + HDR
///
/// Owns the shared `CIContext` (reused, not created per-operation per Pitfall 4).
/// `CIImage` objects are Sendable-safe and cross actor boundaries.
public actor WatermarkEngine {

    /// Shared CIContext with RGBAh + displayP3 configuration (Pitfall 4)
    private let context = CIContextProvider.shared

    /// Default padding for watermark positioning (configurable in Plan 02)
    private let defaultPadding: CGFloat = 20

    /// Processes a source photo and applies watermark configuration.
    ///
    /// - Parameters:
    ///   - sourceURL: File URL to the source photo
    ///   - config: Watermark configuration (layers, frame, output format)
    /// - Returns: `ProcessingResult` with the output file URL and format info
    /// - Throws: `PipelineError` for any pipeline stage failure
    public func process(
        sourceURL: URL,
        config: WatermarkConfiguration
    ) async throws -> ProcessingResult {
        // STUB — RED phase: throws, tests will fail
        throw PipelineError.invalidSource
    }

    /// Builds the Core Image filter graph for watermark compositing.
    ///
    /// Pure CIImage operations — no CIContext needed. This is synchronous
    /// and called from within the actor-isolated context.
    ///
    /// - Parameters:
    ///   - base: The source CIImage (assumed already orientation-normalized)
    ///   - config: Watermark configuration
    /// - Returns: Composited CIImage ready for rendering
    /// - Note: Normalizes orientation before positioning (Pitfall 3 prevention).
    ///   Image watermark case (.image) is skipped for Plan 01 — Plan 02 implements.
    private func buildFilterGraph(
        base: CIImage,
        config: WatermarkConfiguration
    ) throws -> CIImage {
        // STUB — RED phase: returns identity, tests will fail
        return base
    }
}
