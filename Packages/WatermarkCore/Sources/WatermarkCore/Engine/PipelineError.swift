import Foundation

/// Typed error enum for all photo pipeline failure modes.
///
/// Each case corresponds to a specific failure point in the
/// input → render → output pipeline. Conforms to `LocalizedError`
/// for human-readable error descriptions.
public enum PipelineError: Error, LocalizedError, Sendable, Equatable {
    /// The source URL does not contain valid image data
    case invalidSource

    /// Failed to create a CIImage from the source
    case failedToCreateCIImage

    /// CIContext rendering failed
    case renderFailed

    /// Failed to create CGImageDestination
    case failedToCreateDestination

    /// CGImageDestinationFinalize returned false
    case failedToFinalize

    /// Data buffer was empty or corrupt
    case invalidImageData

    /// Data size exceeded maximum allowed (500 MB)
    case dataTooLarge

    /// Image pixel dimensions exceeded maximum allowed (100 MP)
    case imageTooLarge

    /// Watermark scale out of valid range (0.01–0.90)
    case invalidScale(Double)

    /// White frame rendering failed
    case frameRenderFailed

    /// Source format not in supported set (HEIC, JPEG, PNG)
    case unsupportedFormat(String)

    /// Empty data was provided where image data was expected
    case emptyData

    /// Token substitution failed unexpectedly
    case tokenSubstitutionFailed(String)

    // MARK: - Forward-declared ProRAW errors (Plan 05-03)

    /// ProRAW gain map was expected but not found in DNG file
    case proRawGainMapMissing

    /// DNG/ProRAW output write failed
    case proRawWriteFailed

    // MARK: - Video Pipeline Errors

    /// No video track found in source asset
    case videoTrackNotFound

    /// Failed to insert audio track into composition
    case videoAudioTrackInsertionFailed

    /// AVAssetExportSession init returned nil
    case videoExportSessionCreationFailed

    /// Export completed with error
    case videoExportFailed(Error?)

    /// AVAssetImageGenerator returned nil CGImage
    case videoFrameExtractionFailed

    /// HDR was expected but not found in output
    case videoHDRPreservationFailed

    /// Post-export validation found issues
    case videoValidationFailed(String)

    /// Source codec not supported for watermarking
    case videoUnsupportedCodec(String)

    /// Export was cancelled by user
    case videoCancelled

    // MARK: - LocalizedError

    public var errorDescription: String? {
        switch self {
        case .invalidSource:
            return "The source file does not contain valid image data."
        case .failedToCreateCIImage:
            return "Failed to create a CIImage from the source. The format may be unsupported or the file may be corrupt."
        case .renderFailed:
            return "Failed to render the composited image via CIContext."
        case .failedToCreateDestination:
            return "Failed to create the output destination for writing."
        case .failedToFinalize:
            return "Failed to finalize the output image file."
        case .invalidImageData:
            return "The image data is empty or corrupt."
        case .dataTooLarge:
            return "The image data exceeds the maximum allowed size of 500 MB."
        case .imageTooLarge:
            return "The image exceeds the maximum allowed resolution of 100 megapixels."
        case .invalidScale(let scale):
            return "Invalid watermark scale \(scale). Must be between 0.01 and 0.90."
        case .frameRenderFailed:
            return "Failed to render the white frame overlay."
        case .unsupportedFormat(let uti):
            return "Unsupported image format: \(uti). Supported formats are HEIC, JPEG, and PNG."
        case .emptyData:
            return "No image data was provided."
        case .tokenSubstitutionFailed(let token):
            return "Failed to substitute token in watermark text: \(token)"
        case .proRawGainMapMissing:
            return "ProRAW gain map was expected but not found in the DNG file."
        case .proRawWriteFailed:
            return "Failed to write ProRAW/DNG output."
        case .videoTrackNotFound:
            return "The source video does not contain a video track."
        case .videoAudioTrackInsertionFailed:
            return "Failed to insert audio tracks into the composition."
        case .videoExportSessionCreationFailed:
            return "Failed to create the video export session."
        case .videoExportFailed(let error):
            return "Video export failed: \(error?.localizedDescription ?? "unknown error")."
        case .videoFrameExtractionFailed:
            return "Failed to extract a preview frame from the video."
        case .videoHDRPreservationFailed:
            return "HDR could not be preserved in the output video. The video was exported in SDR."
        case .videoValidationFailed(let message):
            return "Video export validation failed: \(message)."
        case .videoUnsupportedCodec(let codec):
            return "Unsupported video codec: \(codec)."
        case .videoCancelled:
            return "Video export was cancelled."
        }
    }

    // MARK: - Equatable

    /// Custom Equatable conformance — needed because `videoExportFailed(Error?)`
    /// has a non-Equatable associated value.
    ///
    /// `.videoExportFailed` compares as equal regardless of the underlying
    /// error value. The error is only surfaced via `errorDescription`.
    public static func == (lhs: PipelineError, rhs: PipelineError) -> Bool {
        switch (lhs, rhs) {
        case (.videoExportFailed, .videoExportFailed):
            return true
        default:
            // Fall through to compiler-synthesized Equatable for all other cases
            // (all other associated values are Equatable: String, Double, etc.)
            return lhs._isEqual(rhs)
        }
    }

    /// Compiler-synthesized comparison helper. All cases except
    /// `.videoExportFailed` are handled by automatic Equatable synthesis.
    private func _isEqual(_ other: PipelineError) -> Bool {
        switch (self, other) {
        case (.invalidSource, .invalidSource): return true
        case (.failedToCreateCIImage, .failedToCreateCIImage): return true
        case (.renderFailed, .renderFailed): return true
        case (.failedToCreateDestination, .failedToCreateDestination): return true
        case (.failedToFinalize, .failedToFinalize): return true
        case (.invalidImageData, .invalidImageData): return true
        case (.dataTooLarge, .dataTooLarge): return true
        case (.imageTooLarge, .imageTooLarge): return true
        case (.invalidScale(let a), .invalidScale(let b)): return a == b
        case (.frameRenderFailed, .frameRenderFailed): return true
        case (.unsupportedFormat(let a), .unsupportedFormat(let b)): return a == b
        case (.emptyData, .emptyData): return true
        case (.tokenSubstitutionFailed(let a), .tokenSubstitutionFailed(let b)): return a == b
        case (.proRawGainMapMissing, .proRawGainMapMissing): return true
        case (.proRawWriteFailed, .proRawWriteFailed): return true
        case (.videoTrackNotFound, .videoTrackNotFound): return true
        case (.videoAudioTrackInsertionFailed, .videoAudioTrackInsertionFailed): return true
        case (.videoExportSessionCreationFailed, .videoExportSessionCreationFailed): return true
        case (.videoExportFailed, .videoExportFailed): return true
        case (.videoFrameExtractionFailed, .videoFrameExtractionFailed): return true
        case (.videoHDRPreservationFailed, .videoHDRPreservationFailed): return true
        case (.videoValidationFailed(let a), .videoValidationFailed(let b)): return a == b
        case (.videoUnsupportedCodec(let a), .videoUnsupportedCodec(let b)): return a == b
        case (.videoCancelled, .videoCancelled): return true
        default: return false
        }
    }
}
