import AVFoundation
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

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

    public static let shared = WatermarkEngine()

    /// Shared CIContext with RGBAh + displayP3 configuration (Pitfall 4)
    private let context = CIContextProvider.shared

    // MARK: - Media Type Detection

    /// Detects whether a URL points to a photo, video, or unknown media type.
    public enum MediaType: Sendable {
        case photo
        case video
        case unknown
    }

    /// Detects the media type of a file URL by inspecting its UTI.
    ///
    /// - Parameter url: File URL to inspect
    /// - Returns: `.photo`, `.video`, or `.unknown`
    public static func mediaType(for url: URL) -> MediaType {
        guard let uti = try? url.resourceValues(forKeys: [.typeIdentifierKey]).typeIdentifier,
              let type = UTType(uti) else {
            return .unknown
        }

        if type.conforms(to: .movie) || type.conforms(to: .audiovisualContent) {
            return .video
        }

        if type.conforms(to: .image) {
            return .photo
        }

        return .unknown
    }

    // MARK: - Photo Processing
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
        let destinationUTI = config.outputFormat.uti ?? loaded.sourceUTI
        let outputURL = try TempFileManager.createTempFile(uti: destinationUTI as CFString)
        try ImageWriter.write(
            cgImage: cgImage,
            metadata: loaded.metadata,
            gainMapAuxData: loaded.gainMapAuxData,
            dngMetadata: loaded.dngMetadata,
            destinationUTI: destinationUTI,
            quality: config.outputQuality,
            to: outputURL
        )

        // 6. Return result
        return ProcessingResult(url: outputURL, data: nil, outputUTI: destinationUTI)
    }

    /// Processes a video file, applying watermark via AVFoundation CALayer overlay.
    ///
    /// Delegates to `VideoProcessor.process(sourceURL:config:onProgress:)` for the full
    /// AVFoundation pipeline: load → compose → CALayer overlay → export → validate.
    /// Returns a `ProcessingResult` with the output URL, source UTI, and
    /// post-export validation data (HDR preservation, audio track count).
    ///
    /// - Parameters:
    ///   - sourceURL: File URL to the source video
    ///   - config: Watermark configuration (layers, frame, output format)
    ///   - onProgress: Optional callback for export progress (0.0–1.0) and
    ///     estimated time remaining in seconds. Passed through to VideoProcessor.
    /// - Returns: `ProcessingResult` with the output file URL and video validation
    /// - Throws: `PipelineError` for any pipeline stage failure
    public func processVideo(
        sourceURL: URL,
        config: WatermarkConfiguration,
        onProgress: (@Sendable (Double, TimeInterval?) -> Void)? = nil
    ) async throws -> ProcessingResult {
        let (outputURL, validation) = try await VideoProcessor.process(
            sourceURL: sourceURL,
            config: config,
            onProgress: onProgress
        )

        let sourceUTI = (try? sourceURL.resourceValues(forKeys: [.typeIdentifierKey]).typeIdentifier)
            ?? "public.mpeg-4"

        return ProcessingResult(
            url: outputURL,
            data: nil,
            outputUTI: sourceUTI,
            videoValidation: validation
        )
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

        var composited = normalized

        var layers: [(CIImage, CGPoint)] = []
        let extent = composited.extent

        // Build layers in order: bottom layer first, top layer last (D-01)
        for watermark in config.watermarks {
            // MULT-02: Skip hidden layers
            guard watermark.isVisible else { continue }

            let watermarkImage: CIImage

            switch watermark {
            case .text(let textConfig, _, _, _, _):
                // EXIF-01: Token substitution before rendering (Plan 05-02 integration)
                watermarkImage = TextWatermarkRenderer.render(config: textConfig, metadata: metadata)

            case .image(let imageConfig, _, _, _, _):
                watermarkImage = try ImageWatermarkRenderer.render(config: imageConfig)
            }

            // Scale watermark relative to base image
            let scaled = watermarkImage.transformed(
                by: CGAffineTransform(scaleX: watermark.scale, y: watermark.scale)
            )

            // MULT-02: Per-layer opacity via CIFilter.colorMatrix
            let opacityAdjusted: CIImage
            if watermark.opacity < 1.0 {
                let matrix = CIFilter.colorMatrix()
                matrix.inputImage = scaled
                matrix.aVector = CIVector(x: 0, y: 0, z: 0, w: CGFloat(watermark.opacity))
                matrix.biasVector = CIVector(x: 0, y: 0, z: 0, w: 0)
                opacityAdjusted = matrix.outputImage ?? scaled
            } else {
                opacityAdjusted = scaled
            }

            // Calculate position using CIImage bottom-left origin coordinates
            // Uses configurable padding from WatermarkConfiguration (default 20)
            let position = PositionCalculator.position(
                for: watermark.position,
                watermarkExtent: opacityAdjusted.extent,
                baseExtent: extent,
                padding: config.padding
            )

            layers.append((opacityAdjusted, position))
        }

        // D-12: Composite watermark layers onto base (text → image, bottom to top)
        let watermarkedResult = WatermarkRenderer.composite(layers: layers, onto: composited)

        // D-12: White frame composited ON TOP (outermost layer)
        if let frameConfig = config.whiteFrame, frameConfig.isEnabled {
            let frameCIImage = try WhiteFrameRenderer.render(
                config: frameConfig,
                baseExtent: watermarkedResult.extent,
                metadata: metadata,
                scale: 1.0
            )
            let frameFilter = CIFilter.sourceOverCompositing()
            frameFilter.inputImage = frameCIImage
            frameFilter.backgroundImage = watermarkedResult
            return frameFilter.outputImage ?? watermarkedResult
        }

        return watermarkedResult
    }
}
