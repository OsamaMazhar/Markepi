import Foundation

/// IPTC rights metadata fields (D-07, AUTH-03). Merged into an ImageIO
/// metadata dictionary by `IPTCRightsMetadataWriter` without dropping
/// unrelated EXIF/XMP.
///
/// `digitalSourceType` uses IPTC controlled-vocabulary URIs — do not invent
/// local values for AI/source labels. Known values include:
/// - `http://cv.iptc.org/newscodes/digitalsourcetype/photoCapture`
/// - `http://cv.iptc.org/newscodes/digitalsourcetype/trainedAlgorithmicMedia`
/// - `http://cv.iptc.org/newscodes/digitalsourcetype/compositeWithTrainedAlgorithmicMedia`
/// - `http://cv.iptc.org/newscodes/digitalsourcetype/algorithmicMedia`
public struct RightsMetadata: Codable, Equatable, Sendable {
    /// Creator / byline name (sealed author assertion enforced at C2PA layer — D-26).
    public var creator: String = ""
    /// IPTC copyright notice (also mirrored to TIFF Copyright for broad compatibility).
    public var copyrightNotice: String = ""
    /// IPTC credit line.
    public var creditLine: String = ""
    /// IPTC rights usage terms (free-text license/usage description).
    public var usageTerms: String = ""
    /// Licensor contact URL.
    public var licensorURL: String = ""
    /// IPTC controlled-vocabulary Digital Source Type URI; nil leaves any
    /// source value untouched.
    public var digitalSourceType: String?

    public init() {}
}
