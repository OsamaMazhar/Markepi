import CoreImage
import Foundation

/// Immutable value type holding extracted metadata from a source image.
///
/// Extracted BEFORE any pixel processing via `CGImageSourceCopyPropertiesAtIndex`
/// and `CGImageSourceCopyAuxiliaryDataInfoAtIndex`. Preserved through the pipeline
/// and re-attached at output via `CGImageDestinationAddImage` and
/// `CGImageDestinationAddAuxiliaryDataInfo`.
///
/// Metadata dictionary uses `String` keys (converted from `CFString` at the
/// ImageIO boundary) for Swift 6 Sendable conformance. Keys are converted
/// back to `CFString` at output time.
///
/// Marked `@unchecked Sendable` because the metadata dictionaries contain `Any`
/// values (from ImageIO) which are all value types (String, Int, Double, etc.)
/// but the compiler cannot verify this statically.
public struct MediaMetadata: @unchecked Sendable {
    /// Full EXIF/GPS/IPTC/TIFF metadata dictionary from CGImageSource.
    /// Dictionary keys are `String` representations of the original CFString keys.
    /// Values are value types (String, Int, Double, Array, Dictionary).
    public let metadata: [String: Any]

    /// HDR gain map auxiliary data (nil if source has no HDR gain map).
    /// Keys are `String` representations of the original CFString keys.
    /// Values are value types.
    public let gainMapAuxData: [String: Any]?

    /// Source image color space (e.g., displayP3, sRGB)
    public let colorSpace: CGColorSpace?

    /// Source image format UTI (e.g., "public.heic", "public.jpeg")
    public let sourceUTI: String

    public init(
        metadata: [String: Any],
        gainMapAuxData: [String: Any]?,
        colorSpace: CGColorSpace?,
        sourceUTI: String
    ) {
        self.metadata = metadata
        self.gainMapAuxData = gainMapAuxData
        self.colorSpace = colorSpace
        self.sourceUTI = sourceUTI
    }
}
