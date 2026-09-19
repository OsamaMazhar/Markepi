import ImageIO
import UniformTypeIdentifiers

/// Detects source image format from a CGImageSource via UTI mapping.
///
/// Maps CGImageSourceGetType UTIs to UTType for HEIC, JPEG, and PNG detection
/// per D-10 (core supported formats). Throws `.unsupportedFormat` for formats
/// outside the core set.
@available(macOS 11.0, *)
public struct FormatDetector {

    /// Supported source UTIs per D-10 (using String keys for Swift 6 Sendable conformance).
    private static let supportedUTIs: Set<String> = [
        "public.heic",
        "public.jpeg",
        "public.png",
        "public.tiff",
        "com.adobe.raw-image",
    ]

    /// Detects the image format from a CGImageSource.
    ///
    /// - Parameter source: A valid CGImageSource (count ≥ 1)
    /// - Returns: A tuple of `(UTType, CFString)` where the CFString is the raw source UTI
    /// - Throws: `PipelineError.unsupportedFormat` if the source UTI is not in the D-10 set
    public static func detect(from source: CGImageSource) throws -> (UTType, CFString) {
        guard let sourceUTI = CGImageSourceGetType(source) else {
            throw PipelineError.unsupportedFormat("unknown")
        }
        let utiString = sourceUTI as String
        guard supportedUTIs.contains(utiString) else {
            throw PipelineError.unsupportedFormat(utiString)
        }
        let type: UTType
        switch utiString {
        case "public.heic": type = .heic
        case "public.jpeg": type = .jpeg
        case "public.png":  type = .png
        case "public.tiff": type = .tiff
        case "com.adobe.raw-image": type = .rawImage
        default:
            throw PipelineError.unsupportedFormat(utiString)
        }
        return (type, sourceUTI)
    }

    /// Maps a source UTI CFString to a file extension.
    ///
    /// - Parameter uti: Source format UTI (e.g., "public.heic")
    /// - Returns: File extension without dot (e.g., "heic", "jpg", "png")
    public static func fileExtension(for uti: CFString) -> String {
        let utiString = uti as String
        switch utiString {
        case "public.heic": return "heic"
        case "public.jpeg": return "jpg"
        case "public.png":  return "png"
        case "public.tiff": return "tiff"
        case "com.adobe.raw-image": return "dng"
        case "com.apple.quicktime-movie": return "mov"
        case "public.mpeg-4": return "mp4"
        default:
            // Last resort: ask the type system for the real extension before
            // defaulting to jpg — otherwise videos (and other formats) get
            // written with a `.jpg` extension and look like images.
            if let ext = UTType(utiString)?.preferredFilenameExtension {
                return ext
            }
            return "jpg"
        }
    }

    /// Verifies a file is a valid DNG/TIFF by checking the byte-order marker.
    /// DNG files start with "II" (little-endian) or "MM" (big-endian) TIFF header.
    /// - Parameter url: File URL to verify
    /// - Returns: `true` if the file begins with a valid TIFF/DNG byte-order marker
    public static func isDNG(url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let header = handle.readData(ofLength: 4)
        let isII = header.starts(with: Data([0x49, 0x49, 0x2A, 0x00]))
        let isMM = header.starts(with: Data([0x4D, 0x4D, 0x00, 0x2A]))
        return isII || isMM
    }
}
