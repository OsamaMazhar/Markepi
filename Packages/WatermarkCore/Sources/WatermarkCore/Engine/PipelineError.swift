import Foundation

/// Typed error enum for all photo pipeline failure modes.
///
/// Each case corresponds to a specific failure point in the
/// input → render → output pipeline. Conforms to `LocalizedError`
/// for human-readable error descriptions.
public enum PipelineError: Error, LocalizedError, Sendable {
    /// The source URL does not contain valid image data
    case invalidSource

    /// Failed to create a CIImage from the source
    case failedToCreateCIImage

    /// CIContext rendering failed
    case renderFailed

    /// Failed to create CGImageDestination
    case failedToCreateDestination

    /// CGImageDestinationFinalize returned false
    case failedToFinalize

    /// Data buffer was empty or corrupt
    case invalidImageData

    /// Data size exceeded maximum allowed (500 MB)
    case dataTooLarge

    /// Image pixel dimensions exceeded maximum allowed (100 MP)
    case imageTooLarge

    /// Watermark scale out of valid range (0.01–0.90)
    case invalidScale(Double)

    /// White frame rendering failed
    case frameRenderFailed

    /// Source format not in supported set (HEIC, JPEG, PNG)
    case unsupportedFormat(String)

    /// Empty data was provided where image data was expected
    case emptyData

    public var errorDescription: String? {
        switch self {
        case .invalidSource:
            return "The source file does not contain valid image data."
        case .failedToCreateCIImage:
            return "Failed to create a CIImage from the source. The format may be unsupported or the file may be corrupt."
        case .renderFailed:
            return "Failed to render the composited image via CIContext."
        case .failedToCreateDestination:
            return "Failed to create the output destination for writing."
        case .failedToFinalize:
            return "Failed to finalize the output image file."
        case .invalidImageData:
            return "The image data is empty or corrupt."
        case .dataTooLarge:
            return "The image data exceeds the maximum allowed size of 500 MB."
        case .imageTooLarge:
            return "The image exceeds the maximum allowed resolution of 100 megapixels."
        case .invalidScale(let scale):
            return "Invalid watermark scale \(scale). Must be between 0.01 and 0.90."
        case .frameRenderFailed:
            return "Failed to render the white frame overlay."
        case .unsupportedFormat(let uti):
            return "Unsupported image format: \(uti). Supported formats are HEIC, JPEG, and PNG."
        case .emptyData:
            return "No image data was provided."
        }
    }
}
