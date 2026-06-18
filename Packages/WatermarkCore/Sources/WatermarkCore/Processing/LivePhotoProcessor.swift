import AVFoundation
import CoreImage
import Foundation
import os.log
import Photos
import UniformTypeIdentifiers

/// Processes Live Photo pairs by watermarking both the still image and video
/// components through the existing WatermarkEngine pipeline.
///
/// The two-phase approach (per RESEARCH.md Pattern 2):
///   1. Watermark the still image via `WatermarkEngine.process()` (reuses
///      the existing CGImageSource → CIImage → CGImageDestination pipeline
///      with metadata/HDR preservation).
///   2. Watermark the video component via `WatermarkEngine.processVideo()`
///      (reuses the existing AVFoundation CALayer overlay pipeline with
///      HDR preservation and audio passthrough).
///   3. Return a `LivePhotoPairResult` with both URLs.
///
/// `PHLivePhotoEditingContext.frameProcessor` is NOT used here because
/// PhotosPicker returns raw URLs, not `PHContentEditingInput`. The
/// frameProcessor approach will be used in the Photo Edit Extension
/// (PHContentEditingController) in a follow-up phase.
///
/// Uses `public struct` with static method pattern matching `VideoProcessor`.
public struct LivePhotoProcessor {

    // MARK: - Result Types

    /// The output of Live Photo pair processing.
    public struct LivePhotoPairResult: Sendable {
        /// File URL to the watermarked still image (temp file)
        public let watermarkedStillURL: URL

        /// File URL to the watermarked video component (temp file)
        public let watermarkedVideoURL: URL

        /// Output UTI of the still image (e.g., "public.heic", "public.jpeg")
        public let stillOutputUTI: String
    }

    // MARK: - Entry Point

    /// Processes a Live Photo pair, watermarking both the still image and
    /// video component.
    ///
    /// Pipeline:
    ///   1. Watermark still frame via `WatermarkEngine.shared.process()`
    ///   2. Watermark video component via `WatermarkEngine.shared.processVideo()`
    ///   3. Return paired result with both URLs
    ///
    /// Per Pitfall 2 (RESEARCH.md): if either processing step fails, the
    /// error propagates to the caller. The ViewModel catches it and falls
    /// back to still-only watermarking with a user alert.
    ///
    /// - Parameters:
    ///   - stillImageURL: File URL to the still image component of the Live Photo
    ///   - videoURL: File URL to the video component of the Live Photo
    ///   - config: Watermark configuration (layers, position, scale, white frame)
    /// - Returns: `LivePhotoPairResult` with both watermarked URLs
    /// - Throws: `PipelineError` for any pipeline stage failure
    @available(iOS 18, macOS 15, *)
    public static func process(
        stillImageURL: URL,
        videoURL: URL,
        config: WatermarkConfiguration
    ) async throws -> LivePhotoPairResult {
        // Step 1: Watermark still frame via existing photo pipeline
        let stillResult = try await WatermarkEngine.shared.process(
            sourceURL: stillImageURL,
            config: config
        )

        // Step 2: Watermark video component via existing video pipeline
        let videoResult = try await WatermarkEngine.shared.processVideo(
            sourceURL: videoURL,
            config: config
        )

        guard let stillURL = stillResult.url else {
            os_log(.error, "WatermarkCore LivePhotoProcessor: Still image processing produced no output URL")
            throw PipelineError.renderFailed
        }

        guard let videoOutputURL = videoResult.url else {
            os_log(.error, "WatermarkCore LivePhotoProcessor: Video processing produced no output URL")
            throw PipelineError.renderFailed
        }

        // Step 3: Return paired result
        return LivePhotoPairResult(
            watermarkedStillURL: stillURL,
            watermarkedVideoURL: videoOutputURL,
            stillOutputUTI: stillResult.outputUTI
        )
    }
}
