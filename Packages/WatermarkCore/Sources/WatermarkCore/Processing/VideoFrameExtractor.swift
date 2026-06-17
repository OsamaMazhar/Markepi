import AVFoundation
import CoreGraphics
import Foundation

/// Extracts a static preview frame from a video file.
///
/// Uses `AVAssetImageGenerator` for async, memory-safe frame extraction
/// with automatic orientation correction. Designed for video preview
/// thumbnails — the caller (e.g., ShareExtensionViewModel) can then
/// render watermarks onto the extracted `CGImage` via WatermarkCore
/// compositing (D-03).
///
/// Follows the static struct pattern established by `ImageLoader`:
/// single public method, throws `PipelineError` for failures.
public struct VideoFrameExtractor {

    /// Extracts a single frame from a video at a given time.
    ///
    /// - Parameters:
    ///   - url: File URL to the source video
    ///   - time: The time at which to extract the frame. If `nil`,
    ///           defaults to the video midpoint.
    ///   - maxPixelSize: Maximum pixel dimension for the output image
    ///                   (default: 1920). Preserves aspect ratio — this
    ///                   is an upper bound, not an exact size.
    /// - Returns: A `CGImage` of the extracted frame, correctly oriented
    ///            for portrait video (via `appliesPreferredTrackTransform`).
    /// - Throws: `PipelineError.videoFrameExtractionFailed` if the generator
    ///           returns nil for the CGImage.
    ///
    /// Uses `generateCGImageAsynchronously(for:completionHandler:)` bridged
    /// to async via `withCheckedThrowingContinuation` (Pattern 2).
    public static func extract(
        from url: URL,
        at time: CMTime? = nil,
        maxPixelSize: Int = 1920
    ) async throws -> CGImage {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)

        // Critical for portrait video: applies the preferred transform so the
        // extracted frame matches the user's viewing orientation
        generator.appliesPreferredTrackTransform = true

        // Memory-safe preview size — frame is never decoded at full resolution
        generator.maximumSize = CGSize(width: maxPixelSize, height: maxPixelSize)

        // Determine request time: explicit parameter or video midpoint
        let requestTime: CMTime
        if let time = time {
            requestTime = time
        } else {
            let duration = try await asset.load(.duration)
            requestTime = CMTime(seconds: duration.seconds / 2, preferredTimescale: 600)
        }

        // Bridge completion-handler API to async/await
        return try await withCheckedThrowingContinuation { continuation in
            generator.generateCGImageAsynchronously(for: requestTime) { cgImage, actualTime, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let cgImage = cgImage {
                    continuation.resume(returning: cgImage)
                } else {
                    continuation.resume(throwing: PipelineError.videoFrameExtractionFailed)
                }
            }
        }
    }
}
