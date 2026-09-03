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

        /// Which gain-map flavor `gainMapAuxData` came from (nil if no gain map).
        public let gainMapType: GainMapType?

        /// The source's EXIF orientation (the transform the base pixels received
        /// to become upright). Needed to rotate the gain map into alignment.
        public let sourceOrientation: CGImagePropertyOrientation

        /// DNG-specific metadata dictionary (kCGImagePropertyDNGDictionary).
        /// Non-nil only for ProRAW/DNG source images.
        public let dngMetadata: [String: Any]?

        /// Source color space from profile name
        public let colorSpace: CGColorSpace?

        /// Source image format UTI (e.g., "public.heic")
        public let sourceUTI: String

        /// True iff the source image carries a real alpha/transparency channel
        /// (PNG/TIFF/WebP with transparency). False for opaque sources
        /// (JPEG/HEIC/RAW). Drives whether the export keeps the 4th (alpha)
        /// channel or flattens it onto the RGB pixels — see `WatermarkEngine`
        /// and `ImageWriter.flattenToOpaque`.
        public let sourceHasAlpha: Bool
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

        // Extract HDR gain map auxiliary data (Pitfall 1 prevention).
        // Prefer Apple's HDRGainMap; fall back to the ISO 21496-1 gain map that
        // iOS 18+ captures can carry instead. Remember which flavor so the
        // GainMapProcessor knows whether it may fabricate frame-band samples.
        let (gainMapAuxData, gainMapType): ([String: Any]?, GainMapType?) = {
            if let auxData = CGImageSourceCopyAuxiliaryDataInfoAtIndex(
                source, 0, kCGImageAuxiliaryDataTypeHDRGainMap
            ) as? [CFString: Any] {
                return (convertCFDictionary(auxData), .appleHDR)
            }
            if let auxData = CGImageSourceCopyAuxiliaryDataInfoAtIndex(
                source, 0, kCGImageAuxiliaryDataTypeISOGainMap
            ) as? [CFString: Any] {
                return (convertCFDictionary(auxData), .iso)
            }
            return (nil, nil)
        }()

        // Source EXIF orientation — the geometric transform the base pixels get
        // to become upright, which the gain map must match on re-attach.
        let orientationRaw = (props[kCGImagePropertyOrientation] as? NSNumber)?.uint32Value ?? 1
        let sourceOrientation = CGImagePropertyOrientation(rawValue: orientationRaw) ?? .up

        // Extract DNG-specific metadata (ProRAW support per D-02)
        let dngMetadata: [String: Any]? = {
            if let dng = props[kCGImagePropertyDNGDictionary] as? [CFString: Any] {
                return convertCFDictionary(dng)
            }
            return nil
        }()

        // Color space is resolved AFTER loading the CIImage — see below.

        // Detect source UTI via FormatDetector
        let (_, sourceUTI) = try FormatDetector.detect(from: source)
        let sourceUTIString = sourceUTI as String

        // DNG resolution validation per Pitfall 1: ProRAW photos should be >= 4000px
        // on the short side to confirm we're processing RAW data, not the embedded
        // JPEG preview (which is typically ~12MP / ~4000px long side)
        if sourceUTIString == "com.adobe.raw-image" {
            let minDimension = min(width, height)
            if minDimension < 4000 {
                #if DEBUG
                os_log(.default, "[WatermarkCore] DNG image has short-side dimension %d px — may have loaded embedded JPEG preview instead of full RAW data", minDimension)
                #endif
            }
        }

        // Detect whether the source carries a real alpha channel. JPEG/HEIC
        // never do (fast path); for everything else (PNG/TIFF/WebP/RAW) probe a
        // tiny thumbnail — its alphaInfo reflects the source's alpha presence
        // cheaply, without forcing a full-resolution decode.
        let sourceHasAlpha = Self.detectAlpha(source: source, sourceUTI: sourceUTIString)

        // Load the SDR pixels directly — do NOT use `.expandToHDR`. On some
        // environments (observed on Simulator, where "CGColorSpaceCreateWithName
        // failed for Display P3" also appears) expandToHDR returns a DESATURATED
        // buffer (center pixel r==g==b), turning color photos grey. HDR is still
        // preserved end-to-end because the gain map is extracted above and
        // re-attached by ImageWriter on output (SDR base + gain map = HDR on
        // capable displays). `.applyOrientationProperty` is required so rotated
        // sources (EXIF 5–8) load upright with correct dimensions.
        guard let ciImage = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else {
            throw PipelineError.failedToCreateCIImage
        }

        // Resolve the source color space from the CIImage, NOT from the
        // profile-NAME string. `kCGImagePropertyProfileName` returns the ICC
        // profile's human-readable name (e.g. "Adobe RGB (1998)", "Display P3"),
        // which is NOT one of CGColorSpace's canonical identifiers — passing it
        // to `CGColorSpace(name:)` is rejected and logs
        // "CGColorSpaceCreateWithName failed for Adobe RGB (1998)". CIImage has
        // already resolved the embedded ICC profile into a valid CGColorSpace,
        // so we reuse it: the output keeps the source profile (faithful) and the
        // create-failure is gone.
        let colorSpace: CGColorSpace? = ciImage.colorSpace
        #if DEBUG
        os_log(.debug, "[WatermarkCore] loaded image: hasGainMap=%{public}@ ciColorSpaceModel=%{public}d profileName=%{public}@",
               gainMapAuxData != nil ? "yes" : "no",
               colorSpace?.model.rawValue ?? -99,
               (props[kCGImagePropertyProfileName] as? String) ?? "nil")
        #endif

        return LoadedImage(
            ciImage: ciImage,
            metadata: metadata,
            gainMapAuxData: gainMapAuxData,
            gainMapType: gainMapType,
            sourceOrientation: sourceOrientation,
            dngMetadata: dngMetadata,
            colorSpace: colorSpace,
            sourceUTI: sourceUTIString,
            sourceHasAlpha: sourceHasAlpha
        )
    }

    /// The image-properties dictionary in the `[String: Any]` shape the caption
    /// builders and renderers read. Used by the live-preview path, which reads
    /// properties without decoding the image.
    public static func metadata(from properties: [CFString: Any]) -> [String: Any] {
        convertCFDictionary(properties)
    }

    /// Converts a [CFString: Any] dictionary to [String: Any] for Sendable conformance.
    private static func convertCFDictionary(_ dict: [CFString: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, value) in dict {
            result[key as String] = value
        }
        return result
    }

    /// Returns true iff the source image carries a real alpha/transparency channel.
    ///
    /// JPEG/HEIC are structurally opaque (no probe needed). For other formats
    /// we read the `alphaInfo` of a tiny (8px) thumbnail: `none`/`noneSkip*` ⇒
    /// opaque padding only; `premultiplied*`/`first`/`last`/`alphaOnly` ⇒ a real
    /// alpha channel the export must preserve. On any failure we assume opaque
    /// (the photo-dominant case) rather than risk writing spurious alpha.
    private static func detectAlpha(source: CGImageSource, sourceUTI: String) -> Bool {
        switch sourceUTI {
        case "public.jpeg", "public.heic", "public.heif":
            return false
        default:
            break
        }
        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: 8,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: false,
        ]
        guard
            let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else {
            return false
        }
        return alphaInfoIndicatesAlpha(thumbnail.alphaInfo)
    }

    /// Maps a `CGImageAlphaInfo` to "does this image have a usable alpha channel".
    private static func alphaInfoIndicatesAlpha(_ alphaInfo: CGImageAlphaInfo) -> Bool {
        switch alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast:
            return false
        case .premultipliedLast, .premultipliedFirst, .last, .first, .alphaOnly:
            return true
        @unknown default:
            return false
        }
    }
}
