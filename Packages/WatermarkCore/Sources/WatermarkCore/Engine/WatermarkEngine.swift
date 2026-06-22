import AVFoundation
import CoreImage
import Foundation
import ImageIO
import os.log
import UniformTypeIdentifiers

private let engineLog = Logger(subsystem: "com.watermark.core", category: "Engine")

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
        case livePhoto
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

        // 3. Build filter graph (pure CIImage ops, no context needed).
        // Inject the source UTI so the white-frame caption's {format} token and
        // detailed-attribution line can show the file format (HEIC/JPEG/…).
        var graphMetadata = loaded.metadata
        graphMetadata["_SourceUTI"] = loaded.sourceUTI
        // Use the true (orientation-normalized) output size for the {dimensions}
        // caption token so it's always present and correct.
        graphMetadata["PixelWidth"] = Int(normalized.extent.width.rounded())
        graphMetadata["PixelHeight"] = Int(normalized.extent.height.rounded())
        let composited = try buildFilterGraph(
            base: normalized,
            config: config,
            metadata: graphMetadata
        )

        // 4. Render via shared CIContext → CGImage.
        // Only honor the source color space when it is RGB; for missing,
        // unknown, or monochrome profiles render into the guaranteed-valid RGB
        // working space (CGColorSpace(name: .displayP3) can fail on Simulator,
        // which left the output space nil and desaturated untagged images).
        let outputColorSpace: CGColorSpace = {
            if let cs = loaded.colorSpace, cs.model == .rgb {
                return cs
            }
            return CIContextProvider.workingColorSpace
        }()
        let srcSample = samplePixel(loaded.ciImage)
        let compSample = samplePixel(composited)
        engineLog.debug(
            "render: uti=\(loaded.sourceUTI, privacy: .public) size=\(Int(composited.extent.width))x\(Int(composited.extent.height)) srcCSModel=\(loaded.colorSpace?.model.rawValue ?? -99) inCIImageCSModel=\(composited.colorSpace?.model.rawValue ?? -99) outCSModel=\(outputColorSpace.model.rawValue) whiteFrame=\(config.whiteFrame?.isEnabled == true) srcRGB=\(srcSample) compRGB=\(compSample)"
        )
        guard let cgImage = context.createCGImage(
            composited,
            from: composited.extent,
            format: .RGBAh,
            colorSpace: outputColorSpace
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

    /// Processes a Live Photo pair (still image + video component),
    /// applying watermark to both via the existing photo and video pipelines.
    ///
    /// Delegates to `LivePhotoProcessor.process(stillImageURL:videoURL:config:)`
    /// for coordinated processing of the paired assets. Returns a
    /// `ProcessingResult` with both the watermarked still URL and a reference
    /// to the watermarked video URL via `livePhotoVideoURL`.
    ///
    /// - Parameters:
    ///   - stillImageURL: File URL to the still image component of the Live Photo
    ///   - videoURL: File URL to the video component of the Live Photo
    ///   - config: Watermark configuration
    /// - Returns: `ProcessingResult` with the watermarked still output URL
    ///            and the watermarked video URL in `livePhotoVideoURL`
    /// - Throws: `PipelineError` for any pipeline stage failure
    @available(iOS 18, macOS 15, *)
    public func processLivePhoto(
        stillImageURL: URL,
        videoURL: URL,
        config: WatermarkConfiguration
    ) async throws -> ProcessingResult {
        let pair = try await LivePhotoProcessor.process(
            stillImageURL: stillImageURL,
            videoURL: videoURL,
            config: config
        )
        // Determine source UTI from still image
        let sourceUTI = (try? stillImageURL.resourceValues(forKeys: [.typeIdentifierKey]).typeIdentifier)
            ?? pair.stillOutputUTI
        return ProcessingResult(
            url: pair.watermarkedStillURL,
            data: nil,
            outputUTI: sourceUTI,
            livePhotoVideoURL: pair.watermarkedVideoURL
        )
    }

    /// Renders the center pixel of a CIImage to RGBA8 for diagnostics. Returns
    /// "r,g,b" so we can tell whether color is intact (r≠g≠b) or crushed to grey
    /// (r≈g≈b) at a given pipeline stage.
    private func samplePixel(_ image: CIImage) -> String {
        let e = image.extent
        guard e.width.isFinite, e.height.isFinite, e.width >= 1, e.height >= 1 else { return "n/a" }
        let rect = CGRect(x: e.midX, y: e.midY, width: 1, height: 1)
        var bytes = [UInt8](repeating: 0, count: 4)
        context.render(
            image,
            toBitmap: &bytes,
            rowBytes: 4,
            bounds: rect,
            format: .RGBA8,
            colorSpace: CIContextProvider.workingColorSpace
        )
        return "\(bytes[0]),\(bytes[1]),\(bytes[2])"
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

        // When the white frame is enabled it is composited as an opaque band on
        // TOP of the watermark layers (see below). If watermarks were positioned
        // against the full image edge, corner/edge placements would be hidden
        // underneath that band. To make the frame respect watermark placement,
        // position watermarks within the inner content rect — inset by the frame
        // width — so edge/corner watermarks land just inside the border and stay
        // fully visible. Frame width matches WhiteFrameRenderer exactly:
        // shorter dimension × frameWidthRatio.
        let frameInset: CGFloat = {
            guard let frame = config.whiteFrame, frame.isEnabled else { return 0 }
            return min(extent.width, extent.height) * frame.frameWidthRatio
        }()
        // Inner rect the watermarks are positioned against. Origin shifts to
        // (frameInset, frameInset); PositionCalculator works in size-relative
        // coordinates so the origin offset is re-applied below.
        let positioningExtent = extent.insetBy(dx: frameInset, dy: frameInset)

        // Edge padding scales with the image instead of being a fixed 20px,
        // which was invisible on multi-thousand-pixel photos. ~4% of the shorter
        // dimension gives a comfortable, resolution-independent margin.
        let effectivePadding = max(config.padding, min(extent.width, extent.height) * 0.04)

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

            case .signature(let signatureInput, _, _, _, _):
                watermarkImage = try SignatureRenderer.render(input: signatureInput)
            }

            // Scale watermark relative to the base image (resolution-independent).
            // Text scales by HEIGHT so editing the text — which changes its width —
            // does not change the apparent font size (scale == font height as a
            // fraction of image height). Image/signature scale by WIDTH, where the
            // aspect ratio is fixed so width is the natural control.
            let factor: CGFloat
            if case .text = watermark {
                factor = WatermarkScaling.transformFactor(
                    layerScale: watermark.scale,
                    naturalWidth: watermarkImage.extent.height,
                    baseWidth: extent.height
                )
            } else {
                factor = WatermarkScaling.transformFactor(
                    layerScale: watermark.scale,
                    naturalWidth: watermarkImage.extent.width,
                    baseWidth: extent.width
                )
            }
            let scaled = watermarkImage.transformed(
                by: CGAffineTransform(scaleX: factor, y: factor)
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
            // Uses configurable padding from WatermarkConfiguration (default 20).
            // Positioned against the (possibly frame-inset) inner content rect.
            var position = PositionCalculator.position(
                for: watermark.position,
                watermarkExtent: opacityAdjusted.extent,
                baseExtent: positioningExtent,
                padding: effectivePadding
            )
            // Re-apply the inner rect's origin offset (PositionCalculator is
            // size-relative and assumes a (0,0) origin). No-op when no frame.
            position.x += positioningExtent.origin.x
            position.y += positioningExtent.origin.y

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
