import CoreImage
import ImageIO
import Foundation

/// Writes a rendered CGImage to disk or in-memory data with full metadata
/// and HDR gain map preservation.
///
/// Uses CGImageDestination to re-attach the metadata dictionary and HDR gain map
/// auxiliary data that were extracted during loading (Pattern 2).
/// Preserves source UTI per D-09 (no unnecessary format conversion).
public struct ImageWriter {

    /// Writes a CGImage to a file URL with metadata and optional HDR gain map.
    ///
    /// - Parameters:
    ///   - cgImage: The rendered CGImage to write
    ///   - metadata: Full metadata dictionary (with String keys)
    ///   - gainMapAuxData: Optional HDR gain map auxiliary data (with String keys)
    ///   - sourceUTI: Source format UTI as String (e.g., "public.heic")
    ///   - url: Output file URL
    /// - Throws: `PipelineError.failedToCreateDestination` or `.failedToFinalize`
    public static func write(
        cgImage: CGImage,
        metadata: [String: Any],
        gainMapAuxData: [String: Any]?,
        sourceUTI: String,
        to url: URL
    ) throws {
        // STUB — RED phase: throws, tests will fail
        throw PipelineError.failedToCreateDestination
    }

    /// Writes a CGImage to an in-memory Data buffer with metadata and optional HDR gain map.
    ///
    /// - Parameters same as above, but output is `Data` instead of a file URL
    /// - Returns: Encoded image data
    /// - Throws: Same as the URL variant
    public static func write(
        cgImage: CGImage,
        metadata: [String: Any],
        gainMapAuxData: [String: Any]?,
        sourceUTI: String
    ) throws -> Data {
        // STUB — RED phase: throws, tests will fail
        throw PipelineError.failedToCreateDestination
    }
}
