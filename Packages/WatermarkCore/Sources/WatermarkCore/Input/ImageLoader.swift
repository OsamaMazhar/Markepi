import CoreImage
import ImageIO
import Foundation
import os.log

/// Loads a photo from a file URL, extracting metadata, HDR gain map,
/// color space, and format information BEFORE creating the CIImage.
///
/// Uses CGImageSource for metadata extraction and CIImage for pixel data,
/// following Pattern 2 (CGImageSource → CGImageDestination metadata pipeline).
/// Never uses UIImage in the processing path.
@available(macOS 11.0, *)
public struct ImageLoader {

    /// Result of loading an image — contains the CIImage and all extracted metadata.
    public struct LoadedImage: @unchecked Sendable {
        /// The loaded CIImage with HDR and gain map options enabled
        public let ciImage: CIImage

        /// Full metadata dictionary (EXIF, GPS, TIFF, IPTC, etc.) with String keys
        public let metadata: [String: Any]

        /// HDR gain map auxiliary data (nil if no gain map)
        public let gainMapAuxData: [String: Any]?

        /// DNG-specific metadata dictionary (kCGImagePropertyDNGDictionary).
        /// Non-nil only for ProRAW/DNG source images.
        public let dngMetadata: [String: Any]?

        /// Source color space from profile name
        public let colorSpace: CGColorSpace?

        /// Source image format UTI (e.g., "public.heic")
        public let sourceUTI: String
    }

    /// Maximum file size in bytes (500 MB) — security validation per T-01-01
    private static let maxFileSize: Int64 = 500_000_000

    /// Maximum pixel count (100 MP) — security validation per T-01-01
    private static let maxMegapixels: Int = 100

    /// Loads an image from a file URL with full metadata and HDR extraction.
    ///
    /// Performs security validation: file size ≤ 500MB, pixel count ≤ 100MP.
    ///
    /// - Parameter url: File URL to a supported image format
    /// - Returns: `LoadedImage` with CIImage, metadata, and format info
    /// - Throws: `PipelineError` for invalid source, oversized images, or format issues
    public static func load(from url: URL) throws -> LoadedImage {
        // Security: validate file exists and size (T-01-01)
        let fileAttributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = (fileAttributes?[.size] as? Int64) ?? 0
        guard fileSize > 0 else {
            throw PipelineError.invalidSource
        }
        guard fileSize <= maxFileSize else {
            throw PipelineError.dataTooLarge
        }

        // Create CGImageSource
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw PipelineError.invalidSource
        }
        guard CGImageSourceGetCount(source) > 0 else {
            throw PipelineError.invalidImageData
        }

        // Security: validate pixel dimensions (T-01-01)
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        let width = (props[kCGImagePropertyPixelWidth] as? Int) ?? 0
        let height = (props[kCGImagePropertyPixelHeight] as? Int) ?? 0
        let megapixels = (width * height) / 1_000_000
        guard megapixels <= maxMegapixels else {
            throw PipelineError.imageTooLarge
        }

        // Extract metadata dictionary BEFORE any CIImage creation (Pattern 2)
        let metadata = convertCFDictionary(props)

        // Extract HDR gain map auxiliary data (Pitfall 1 prevention)
        let gainMapAuxData: [String: Any]? = {
            if let auxData = CGImageSourceCopyAuxiliaryDataInfoAtIndex(
                source, 0, kCGImageAuxiliaryDataTypeHDRGainMap
            ) as? [CFString: Any] {
                return convertCFDictionary(auxData)
            }
            return nil
        }()

        // Extract DNG-specific metadata (ProRAW support per D-02)
        let dngMetadata: [String: Any]? = {
            if let dng = props[kCGImagePropertyDNGDictionary] as? [CFString: Any] {
                return convertCFDictionary(dng)
            }
            return nil
        }()

        // Extract color space from profile name
        let colorSpace: CGColorSpace? = {
            guard let profileName = props[kCGImagePropertyProfileName] as? String else {
                return nil
            }
            return CGColorSpace(name: profileName as CFString)
        }()

        // Detect source UTI via FormatDetector
        let (_, sourceUTI) = try FormatDetector.detect(from: source)
        let sourceUTIString = sourceUTI as String

        // DNG resolution validation per Pitfall 1: ProRAW photos should be >= 4000px
        // on the short side to confirm we're processing RAW data, not the embedded
        // JPEG preview (which is typically ~12MP / ~4000px long side)
        if sourceUTIString == "com.adobe.raw-image" {
            let minDimension = min(width, height)
            if minDimension < 4000 {
                os_log(.default, "[WatermarkCore] DNG image has short-side dimension %d px — may have loaded embedded JPEG preview instead of full RAW data", minDimension)
            }
        }

        // Create CIImage. Only opt into HDR expansion when the source actually
        // carries an HDR gain map. `.expandToHDR` on plain SDR images (notably
        // small, untagged JPEGs) can tone-map them into an extended range that
        // renders desaturated/grey once composited and written back to SDR — the
        // "photo turns grey" bug. SDR images load with orientation only, which
        // preserves their color exactly.
        let hasGainMap = gainMapAuxData != nil
        let options: [CIImageOption: Any] = hasGainMap
            ? [.expandToHDR: true, .auxiliaryHDRGainMap: true, .applyOrientationProperty: true]
            : [.applyOrientationProperty: true]
        var ciImage = CIImage(contentsOf: url, options: options)
        if ciImage == nil {
            // Fallback for platforms where the options are not supported.
            // Orientation MUST still be applied here — otherwise a rotated source
            // loads with swapped dimensions and the watermark is positioned in
            // the wrong place (EXIF orientation 5–8).
            ciImage = CIImage(contentsOf: url, options: [.applyOrientationProperty: true])
        }
        guard let ciImage = ciImage else {
            throw PipelineError.failedToCreateCIImage
        }
        os_log(.debug, "[WatermarkCore] loaded image: hasGainMap=%{public}@ ciColorSpaceModel=%{public}d profileName=%{public}@",
               hasGainMap ? "yes" : "no",
               ciImage.colorSpace?.model.rawValue ?? -99,
               (props[kCGImagePropertyProfileName] as? String) ?? "nil")

        return LoadedImage(
            ciImage: ciImage,
            metadata: metadata,
            gainMapAuxData: gainMapAuxData,
            dngMetadata: dngMetadata,
            colorSpace: colorSpace,
            sourceUTI: sourceUTIString
        )
    }

    /// Converts a [CFString: Any] dictionary to [String: Any] for Sendable conformance.
    private static func convertCFDictionary(_ dict: [CFString: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, value) in dict {
            result[key as String] = value
        }
        return result
    }
}
