import Foundation

/// Output result from the watermark processing pipeline.
///
/// Contains either a temp file URL (when output is written to disk) or an
/// in-memory Data buffer (when output is kept in memory). At least one of
/// `url` or `data` is always non-nil.
///
/// The `outputUTI` identifies the file format (e.g., "public.heic", "public.jpeg").
/// The optional `videoValidation` field carries post-export quality inspection
/// results for video processing (nil for photo processing).
public struct ProcessingResult: Sendable {
    /// Temp file URL when output is written to disk (via TempFileManager)
    public let url: URL?

    /// In-memory data buffer when no file I/O is needed
    public let data: Data?

    /// Output format UTI (from source or explicit override)
    public let outputUTI: String

    /// Optional video validation result (nil for photo processing).
    /// Contains HDR preservation status, audio track count match,
    /// and any warnings from post-export inspection.
    public let videoValidation: ExportValidator.ExportValidationResult?

    /// When non-nil, the processing result represents a Live Photo pair.
    /// This URL points to the watermarked video component of the Live Photo.
    /// The `url` property points to the watermarked still image.
    /// Nil for non-Live-Photo results.
    public let livePhotoVideoURL: URL?

    /// Provenance export receipt (Plan 19-02). Nil when no provenance options
    /// were passed to the engine (today's default behavior — no source analysis,
    /// no IPTC merge, no C2PA signing).
    public let provenanceReceipt: ExportReceipt?

    public init(
        url: URL?,
        data: Data?,
        outputUTI: String,
        videoValidation: ExportValidator.ExportValidationResult? = nil,
        livePhotoVideoURL: URL? = nil,
        provenanceReceipt: ExportReceipt? = nil
    ) {
        self.url = url
        self.data = data
        self.outputUTI = outputUTI
        self.videoValidation = videoValidation
        self.livePhotoVideoURL = livePhotoVideoURL
        self.provenanceReceipt = provenanceReceipt
    }
}

// MARK: - RenderingState

/// Tracks the state of the watermark rendering pipeline for UI feedback.
///
/// Used by both the main app (`WatermarkViewModel`) and the share extension
/// (`ShareExtensionViewModel`) to drive button states, loading indicators,
/// and error presentation. Moved to WatermarkCore so both targets can import it.
public enum RenderingState: Equatable, Sendable {
    /// No render in progress; user can configure and initiate
    case idle

    /// Rendering is in progress; UI should show progress indicator
    case rendering

    /// Video rendering in progress with progress tracking.
    /// - Parameter progress: Export progress from 0.0 to 1.0
    /// - Parameter estimatedTimeRemaining: ETA in seconds, or nil when insufficient data
    case renderingVideo(progress: Double, estimatedTimeRemaining: TimeInterval?)

    /// Batch processing in progress with progress tracking.
    /// - Parameter current: Number of items processed so far
    /// - Parameter total: Total number of items in the batch
    /// - Parameter eta: Estimated time remaining in seconds, or nil when insufficient data
    case batchProcessing(current: Int, total: Int, eta: TimeInterval?)

    /// Rendering completed successfully; ready to present share sheet
    case done

    /// Rendering failed with an error; UI should show error state
    case error(Error)

    public static func == (lhs: RenderingState, rhs: RenderingState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.rendering, .rendering), (.done, .done):
            return true
        case (.renderingVideo(let p1, let e1), .renderingVideo(let p2, let e2)):
            return p1 == p2 && e1 == e2
        case (.batchProcessing(let c1, let t1, let eta1), .batchProcessing(let c2, let t2, let eta2)):
            return c1 == c2 && t1 == t2 && eta1 == eta2
        case (.error, .error):
            return true
        default:
            return false
        }
    }
}
