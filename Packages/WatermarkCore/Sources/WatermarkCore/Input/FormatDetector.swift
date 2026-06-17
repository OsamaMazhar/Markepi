import ImageIO
import UniformTypeIdentifiers

/// Detects source image format from a CGImageSource via UTI mapping.
///
/// Maps Core Image format UTIs to UTType for HEIC, JPEG, and PNG detection
/// per D-10 (core supported formats). Throws `.unsupportedFormat` for formats
/// outside the core set.
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
        // STUB — RED phase: always returns JPEG to make tests fail
        return (UTType.jpeg, "public.jpeg" as CFString)
    }

    /// Maps a source UTI CFString to a file extension.
    ///
    /// - Parameter uti: Source format UTI (e.g., "public.heic")
    /// - Returns: File extension without dot (e.g., "heic", "jpg", "png")
    public static func fileExtension(for uti: CFString) -> String {
        let utiString = uti as String
        if utiString == "public.heic" { return "heic" }
        if utiString == "public.jpeg" { return "jpg" }
        if utiString == "public.png" { return "png" }
        return "jpg"  // fallback for RED phase
    }
}
