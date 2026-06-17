import CoreImage
import ImageIO
import Foundation

/// Loads a photo from a file URL, extracting metadata, HDR gain map,
/// color space, and format information BEFORE creating the CIImage.
///
/// Uses CGImageSource for metadata extraction and CIImage for pixel data,
/// following Pattern 2 (CGImageSource → CGImageDestination metadata pipeline).
/// Never uses UIImage in the processing path.
public struct ImageLoader {

    /// Result of loading an image — contains the CIImage and all extracted metadata.
    public struct LoadedImage: @unchecked Sendable {
        /// The loaded CIImage with HDR and gain map options enabled
        public let ciImage: CIImage

        /// Full metadata dictionary (EXIF, GPS, TIFF, IPTC, etc.)
        public let metadata: [String: Any]

        /// HDR gain map auxiliary data (nil if no gain map)
        public let gainMapAuxData: [String: Any]?

        /// Source color space from profile name
        public let colorSpace: CGColorSpace?

        /// Source image format UTI (e.g., "public.heic")
        public let sourceUTI: String
    }

    /// Loads an image from a file URL with full metadata and HDR extraction.
    ///
    /// Performs security validation: file size ≤ 500MB, pixel count ≤ 100MP.
    ///
    /// - Parameter url: File URL to a supported image format
    /// - Returns: `LoadedImage` with CIImage, metadata, and format info
    /// - Throws: `PipelineError` for invalid source, oversized images, or format issues
    public static func load(from url: URL) throws -> LoadedImage {
        // STUB — RED phase: throw not implemented, tests will fail
        throw PipelineError.invalidSource
    }
}
