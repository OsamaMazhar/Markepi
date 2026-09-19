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
    ///   - preserveAlpha: When `true` (default) the CGImage is written as-is, keeping
    ///     any alpha channel. When `false`, the 4th channel is merged onto the RGB
    ///     pixels (flattened over opaque white) and dropped, producing a clean
    ///     opaque image. Pass `false` for sources that had no alpha (JPEG/HEIC/RAW)
    ///     or for formats that cannot store alpha — this avoids ImageIO's
    ///     "opaque image saved with AlphaPremulLast" warning without discarding
    ///     transparency data that mattered.
    ///   - url: Output file URL
    /// - Throws: `PipelineError.failedToCreateDestination` or `.failedToFinalize`
    public static func write(
        cgImage: CGImage,
        metadata: [String: Any],
        gainMapAuxData: [String: Any]?,
        dngMetadata: [String: Any]?,
        destinationUTI: String,
        quality: Float = 1.0,
        preserveAlpha: Bool = true,
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

        // Pixels were normalized to .up before rendering — reset the orientation
        // tag so viewers don't re-rotate upright pixels (the "upside-down" bug).
        resetOrientation(&combinedMetadata)

        // Merge quality into combinedMetadata BEFORE CGImageDestinationAddImage
        // (Pitfall 5: single properties dict avoids overwriting metadata)
        combinedMetadata[kCGImageDestinationLossyCompressionQuality as String] = quality

        // When transparency isn't being preserved, merge the alpha channel onto
        // the RGB pixels (flatten) so the destination receives an opaque image.
        let imageToWrite: CGImage = preserveAlpha ? cgImage : try flattenToOpaque(cgImage)

        // Re-attach metadata (Pattern 2)
        CGImageDestinationAddImage(destination, imageToWrite, combinedMetadata as CFDictionary)

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
        quality: Float = 1.0,
        preserveAlpha: Bool = true
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

        // Pixels were normalized to .up before rendering — reset the orientation
        // tag so viewers don't re-rotate upright pixels (the "upside-down" bug).
        resetOrientation(&combinedMetadata)

        // Merge quality into combinedMetadata BEFORE CGImageDestinationAddImage
        // (Pitfall 5: single properties dict avoids overwriting metadata)
        combinedMetadata[kCGImageDestinationLossyCompressionQuality as String] = quality

        // When transparency isn't being preserved, merge the alpha channel onto
        // the RGB pixels (flatten) so the destination receives an opaque image.
        let imageToWrite: CGImage = preserveAlpha ? cgImage : try flattenToOpaque(cgImage)

        CGImageDestinationAddImage(destination, imageToWrite, combinedMetadata as CFDictionary)

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

    // MARK: - Alpha flatten

    /// Flattens a (possibly alpha-carrying) CGImage onto an opaque white
    /// background and returns a new CGImage with **no alpha channel**
    /// (`noneSkipLast`).
    ///
    /// The 4th channel is *merged* into the RGB pixels via source-over
    /// compositing onto opaque white — partial-alpha pixels blend to white
    /// instead of being truncated or fringing against uninitialized memory.
    /// For an already-opaque image (alpha = 1 everywhere, the normal photo
    /// case) this is an identity pass: the RGB is untouched and only the
    /// redundant channel is dropped. The result is a clean opaque image that
    /// no longer triggers ImageIO's "opaque image saved with AlphaPremulLast"
    /// warning, and is 8-bit-per-channel — matching what JPEG/HEIC can encode.
    ///
    /// Transparency is intentionally discarded only here, and only when the
    /// caller has already decided the source had no alpha (or the format can't
    /// store it). Sources with real alpha take the `preserveAlpha` path and
    /// never reach this function.
    private static func flattenToOpaque(_ image: CGImage) throws -> CGImage {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else {
            throw PipelineError.renderFailed
        }
        let colorSpace = image.colorSpace ?? CIContextProvider.workingColorSpace
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            throw PipelineError.renderFailed
        }
        // Fill opaque white so partial-alpha pixels composite to white
        // (conventional flatten target) rather than against garbage memory.
        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        // Source-over composite — merges the alpha channel into the RGB.
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let opaque = context.makeImage() else {
            throw PipelineError.renderFailed
        }
        return opaque
    }

    // MARK: - Orientation

    /// Forces the orientation metadata to `.up` (1).
    ///
    /// The pipeline normalizes pixels to `.up` via `OrientationNormalizer` before
    /// rendering, but the preserved source metadata still carries the original
    /// EXIF orientation (e.g. 3 = 180°, 6/8 = 90°). If that tag is written
    /// unchanged, viewers apply the rotation a second time and the exported image
    /// (and live preview) appears rotated/upside-down. Resetting both the
    /// top-level and TIFF orientation tags to 1 keeps the upright pixels upright.
    private static func resetOrientation(_ metadata: inout [String: Any]) {
        metadata[kCGImagePropertyOrientation as String] = 1

        var tiff = metadata[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:]
        tiff[kCGImagePropertyTIFFOrientation as String] = 1
        metadata[kCGImagePropertyTIFFDictionary as String] = tiff
    }
}
