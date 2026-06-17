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
        default:            return "jpg"
        }
    }
}
