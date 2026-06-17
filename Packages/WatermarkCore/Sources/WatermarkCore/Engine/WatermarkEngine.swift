import CoreImage
import Foundation
import ImageIO

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
/// `CIFilter` instances are NOT thread-safe and are created fresh per call.
public actor WatermarkEngine {

    /// Shared CIContext with RGBAh + displayP3 configuration (Pitfall 4)
    private let context = CIContextProvider.shared

    /// Default padding for watermark positioning (hardcoded to 20 for Plan 01,
    /// configurable in Plan 02)
    private let defaultPadding: CGFloat = 20

    /// Processes a source photo and applies watermark configuration.
    ///
    /// - Parameters:
    ///   - sourceURL: File URL to the source photo
    ///   - config: Watermark configuration (layers, frame, output format)
    /// - Returns: `ProcessingResult` with the output file URL and format info
    /// - Throws: `PipelineError` for any pipeline stage failure
    ///
    /// Pipeline stages:
    ///   a. Load from URL with metadata/HDR extraction
    ///   b. Normalize EXIF orientation to .up
    ///   c. Build Core Image filter graph (watermark layers composited)
    ///   d. Render via shared CIContext to CGImage
    ///   e. Write to temp file with metadata + HDR re-attached
    ///   f. Return ProcessingResult with temp file URL
    public func process(
        sourceURL: URL,
        config: WatermarkConfiguration
    ) async throws -> ProcessingResult {
        // 1. Load (validates size, extracts metadata + HDR + CIImage)
        let loaded = try ImageLoader.load(from: sourceURL)

        // 2. Normalize orientation (Pitfall 3 prevention)
        let normalized = OrientationNormalizer.normalize(loaded.ciImage)

        // 3. Build filter graph (pure CIImage ops, no context needed)
        let composited = try buildFilterGraph(base: normalized, config: config)

        // 4. Render via shared CIContext → CGImage
        guard let cgImage = context.createCGImage(
            composited,
            from: composited.extent,
            format: .RGBAh,
            colorSpace: loaded.colorSpace
        ) else {
            throw PipelineError.renderFailed
        }

        // 5. Write to temp file with metadata + HDR re-attached
        let outputURL = try TempFileManager.createTempFile(uti: loaded.sourceUTI as CFString)
        try ImageWriter.write(
            cgImage: cgImage,
            metadata: loaded.metadata,
            gainMapAuxData: loaded.gainMapAuxData,
            sourceUTI: loaded.sourceUTI,
            to: outputURL
        )

        // 6. Return result
        return ProcessingResult(url: outputURL, data: nil, outputUTI: loaded.sourceUTI)
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
    ///
    /// Flow:
    ///   1. Normalize orientation again as safety net (Pitfall 3 double-check)
    ///   2. Build watermark layers from config in order (per D-01)
    ///   3. For each layer: render CIImage → scale → position → collect
    ///   4. Composite all layers onto base via WatermarkRenderer
    ///
    /// Note: `.image` watermark case is skipped for Plan 01 — Plan 02 implements.
    private func buildFilterGraph(
        base: CIImage,
        config: WatermarkConfiguration
    ) throws -> CIImage {
        // Safety net: normalize orientation before positioning (Pitfall 3)
        let normalized = OrientationNormalizer.normalize(base)
        let extent = normalized.extent

        var layers: [(CIImage, CGPoint)] = []

        // Build layers in order: bottom layer first, top layer last (D-01)
        for watermark in config.watermarks {
            let watermarkImage: CIImage

            switch watermark {
            case .text(let textConfig, _, _):
                watermarkImage = TextWatermarkRenderer.render(config: textConfig)

            case .image(_, _, _):
                // Image watermark rendering deferred to Plan 02 (stub)
                continue
            }

            // Scale watermark relative to base image
            let scaled = watermarkImage.transformed(
                by: CGAffineTransform(scaleX: watermark.scale, y: watermark.scale)
            )

            // Calculate position using CIImage bottom-left origin coordinates
            let position = PositionCalculator.position(
                for: watermark.position,
                watermarkExtent: scaled.extent,
                baseExtent: extent,
                padding: defaultPadding
            )

            layers.append((scaled, position))
        }

        // Composite all layers onto base via CISourceOverCompositing
        return WatermarkRenderer.composite(layers: layers, onto: normalized)
    }
}
