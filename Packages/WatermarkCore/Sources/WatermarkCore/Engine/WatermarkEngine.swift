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
        let composited = try buildFilterGraph(
            base: normalized,
            config: config,
            metadata: loaded.metadata
        )

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
    ///   - metadata: Source image metadata dictionary (for device model extraction
    ///               in white frame rendering)
    /// - Returns: Composited CIImage ready for rendering
    ///
    /// Flow:
    ///   1. Normalize orientation again as safety net (Pitfall 3 double-check)
    ///   2. Render white frame below all watermark layers (if enabled)
    ///   3. Build watermark layers from config in order (per D-01)
    ///   4. For each layer: render CIImage → scale → position → collect
    ///   5. Composite all layers onto base via WatermarkRenderer
    ///
    /// Note: Supports both `.text` and `.image` watermark layers (Plan 01 + Plan 02)
    ///       plus white frame compositing (Plan 03).
    private func buildFilterGraph(
        base: CIImage,
        config: WatermarkConfiguration,
        metadata: [String: Any]
    ) throws -> CIImage {
        // Safety net: normalize orientation before positioning (Pitfall 3)
        let normalized = OrientationNormalizer.normalize(base)
        let extent = normalized.extent

        var layers: [(CIImage, CGPoint)] = []

        // White frame rendering (composited below all watermark layers)
        // RED: metadata is passed through but frame is NOT yet rendered.
        // Tests expect white border + metadata text — they will fail until
        // GREEN implementation adds WhiteFrameRenderer compositing here.
        // Framed base will be applied to the compositing chain.

        // Build layers in order: bottom layer first, top layer last (D-01)
        for watermark in config.watermarks {
            let watermarkImage: CIImage

            switch watermark {
            case .text(let textConfig, _, _):
                watermarkImage = TextWatermarkRenderer.render(config: textConfig)

            case .image(let imageConfig, _, _):
                watermarkImage = try ImageWatermarkRenderer.render(config: imageConfig)
            }

            // Scale watermark relative to base image
            let scaled = watermarkImage.transformed(
                by: CGAffineTransform(scaleX: watermark.scale, y: watermark.scale)
            )

            // Calculate position using CIImage bottom-left origin coordinates
            // Uses configurable padding from WatermarkConfiguration (default 20)
            let position = PositionCalculator.position(
                for: watermark.position,
                watermarkExtent: scaled.extent,
                baseExtent: extent,
                padding: config.padding
            )

            layers.append((scaled, position))
        }

        // Composite all layers onto base via CISourceOverCompositing
        return WatermarkRenderer.composite(layers: layers, onto: normalized)
    }
}
