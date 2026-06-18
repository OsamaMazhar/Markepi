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
    /// Uses `CGImageDestinationAddImage` (NOT `AddImageFromSource`) with the
    /// preserved metadata dictionary. Re-attaches HDR gain map via
    /// `CGImageDestinationAddAuxiliaryDataInfo` when available (Pitfall 1 prevention).
    ///
    /// - Parameters:
    ///   - cgImage: The rendered CGImage to write
    ///   - metadata: Full metadata dictionary (with String keys, converted back to CFString for output)
    ///   - gainMapAuxData: Optional HDR gain map auxiliary data (with String keys)
    ///   - dngMetadata: Optional DNG-specific metadata dictionary (kCGImagePropertyDNGDictionary)
    ///   - destinationUTI: Target format UTI as String (e.g., "public.heic", "public.tiff")
    ///   - quality: Compression quality 0.0–1.0 (maps to kCGImageDestinationLossyCompressionQuality; ignored by lossless formats)
    ///   - url: Output file URL
    /// - Throws: `PipelineError.failedToCreateDestination` or `.failedToFinalize`
    public static func write(
        cgImage: CGImage,
        metadata: [String: Any],
        gainMapAuxData: [String: Any]?,
        dngMetadata: [String: Any]?,
        destinationUTI: String,
        quality: Float = 1.0,
        to url: URL
    ) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, destinationUTI as CFString, 1, nil
        ) else {
            throw PipelineError.failedToCreateDestination
        }

        // Build combined metadata dictionary with DNG metadata if present (D-02)
        var combinedMetadata = metadata
        if let dng = dngMetadata {
            combinedMetadata[kCGImagePropertyDNGDictionary as String] = dng
        }

        // Merge quality into combinedMetadata BEFORE CGImageDestinationAddImage
        // (Pitfall 5: single properties dict avoids overwriting metadata)
        combinedMetadata[kCGImageDestinationLossyCompressionQuality as String] = quality

        // Re-attach metadata (Pattern 2)
        CGImageDestinationAddImage(destination, cgImage, combinedMetadata as CFDictionary)

        // Re-attach HDR gain map if present (Pitfall 1 prevention)
        if let gainMap = gainMapAuxData {
            CGImageDestinationAddAuxiliaryDataInfo(
                destination,
                kCGImageAuxiliaryDataTypeHDRGainMap,
                gainMap as CFDictionary
            )
        }

        guard CGImageDestinationFinalize(destination) else {
            throw PipelineError.failedToFinalize
        }
    }

    /// Writes a CGImage to an in-memory Data buffer with metadata and optional HDR gain map.
    ///
    /// - Parameters same as the file URL variant, but output is `Data` instead of a file URL
    /// - Returns: Encoded image data
    /// - Throws: Same as the URL variant
    public static func write(
        cgImage: CGImage,
        metadata: [String: Any],
        gainMapAuxData: [String: Any]?,
        dngMetadata: [String: Any]?,
        destinationUTI: String,
        quality: Float = 1.0
    ) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, destinationUTI as CFString, 1, nil
        ) else {
            throw PipelineError.failedToCreateDestination
        }

        // Build combined metadata dictionary with DNG metadata if present (D-02)
        var combinedMetadata = metadata
        if let dng = dngMetadata {
            combinedMetadata[kCGImagePropertyDNGDictionary as String] = dng
        }

        // Merge quality into combinedMetadata BEFORE CGImageDestinationAddImage
        // (Pitfall 5: single properties dict avoids overwriting metadata)
        combinedMetadata[kCGImageDestinationLossyCompressionQuality as String] = quality

        CGImageDestinationAddImage(destination, cgImage, combinedMetadata as CFDictionary)

        if let gainMap = gainMapAuxData {
            CGImageDestinationAddAuxiliaryDataInfo(
                destination,
                kCGImageAuxiliaryDataTypeHDRGainMap,
                gainMap as CFDictionary
            )
        }

        guard CGImageDestinationFinalize(destination) else {
            throw PipelineError.failedToFinalize
        }

        return data as Data
    }
}
