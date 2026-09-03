import CoreGraphics
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

    /// Where the photo and each watermark layer landed in the rendered output.
    /// Lets the editor drag a layer around the preview with exact geometry.
    public let previewLayout: RenderLayout?

    public init(
        url: URL?,
        data: Data?,
        outputUTI: String,
        videoValidation: ExportValidator.ExportValidationResult? = nil,
        livePhotoVideoURL: URL? = nil,
        provenanceReceipt: ExportReceipt? = nil,
        previewLayout: RenderLayout? = nil
    ) {
        self.url = url
        self.data = data
        self.outputUTI = outputUTI
        self.videoValidation = videoValidation
        self.livePhotoVideoURL = livePhotoVideoURL
        self.provenanceReceipt = provenanceReceipt
        self.previewLayout = previewLayout
    }
}

// MARK: - RenderLayout

/// Geometry of a rendered composite, in normalized coordinates of the whole
/// output image: origin top-left, y running DOWN, sizes as fractions of the
/// output's width/height.
///
/// The photo is not always the whole output — a white frame mats it — so
/// `photoRect` is what watermark positions are relative to, and `layerFrames`
/// says where each layer actually landed. `layerFrames` is keyed by the layer's
/// index in `WatermarkConfiguration.watermarks`; hidden layers are absent.
public struct RenderLayout: Sendable, Equatable {
    public var photoRect: CGRect
    public var layerFrames: [Int: CGRect]

    public init(photoRect: CGRect, layerFrames: [Int: CGRect]) {
        self.photoRect = photoRect
        self.layerFrames = layerFrames
    }

    /// The topmost layer under `point`, or nil if the point is on bare photo.
    ///
    /// Nil genuinely means "nothing here": a drag that misses every layer must
    /// move nothing. Treating a miss as "whichever layer is selected" meant a
    /// drag across empty sky picked up the text and carried it off.
    ///
    /// `point` is normalised to the rendered canvas, the same space
    /// `layerFrames` uses. `slop` widens each frame so a layer stays catchable
    /// at the edges of thin glyphs, where the drawn frame is barely a line.
    ///
    /// Highest index wins, which is the layer drawn last and so the one on top.
    public func layerIndex(at point: CGPoint, slop: CGFloat = 0.02) -> Int? {
        layerFrames
            .filter { $0.value.insetBy(dx: -slop, dy: -slop).contains(point) }
            .keys
            .max()
    }

    /// The layer's placement expressed as `WatermarkPosition.custom` fractions:
    /// how far along the space it can travel inside the photo it sits, y DOWN.
    /// Nil when the layer was not rendered (hidden, or no preview yet).
    public func travelFraction(ofLayer index: Int) -> CGPoint? {
        guard let frame = layerFrames[index] else { return nil }
        let travelX = photoRect.width - frame.width
        let travelY = photoRect.height - frame.height
        return CGPoint(
            x: travelX > 0 ? min(max((frame.minX - photoRect.minX) / travelX, 0), 1) : 0.5,
            y: travelY > 0 ? min(max((frame.minY - photoRect.minY) / travelY, 0), 1) : 0.5
        )
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
