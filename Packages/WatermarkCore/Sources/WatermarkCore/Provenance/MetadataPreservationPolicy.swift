import ImageIO
import Foundation

/// Privacy profile controlling how much metadata survives export (D-10).
///
/// - `preserveAll`: keep all metadata possible (today's default behavior).
/// - `stripSensitive`: remove GPS/location and device serial-like fields
///   while preserving rights/provenance records (IPTC, copyright, C2PA).
/// - `minimalPublic`: keep only essential rights/provenance records and
///   output technical requirements (dimensions, color profile).
///
/// HDR gain map + color profile preservation does not regress — those are
/// re-attached by `ImageWriter`, not carried through this dict.
public enum MetadataPrivacyProfile: String, Codable, Sendable {
    case preserveAll
    case stripSensitive
    case minimalPublic
}

/// Applies a privacy profile to an ImageIO metadata dictionary. Pure function
/// — returns a new dict, leaving the input untouched.
///
/// Rights/provenance (IPTC, copyright) survive `stripSensitive`; HDR gain map
/// + color profile are untouched because they are re-attached by `ImageWriter`,
/// not carried here.
public struct MetadataPreservationPolicy: Sendable {

    public init() {}

    /// Returns a new metadata dict with the profile applied.
    public func apply(_ profile: MetadataPrivacyProfile, to metadata: [String: Any]) -> [String: Any] {
        switch profile {
        case .preserveAll:
            return metadata

        case .stripSensitive:
            var out = metadata
            // GPS / location (CTRL-04)
            out.removeValue(forKey: kCGImagePropertyGPSDictionary as String)
            // Body + lens serial numbers (device-identifying)
            if var exif = out[kCGImagePropertyExifDictionary as String] as? [String: Any] {
                exif.removeValue(forKey: kCGImagePropertyExifBodySerialNumber as String)
                exif.removeValue(forKey: kCGImagePropertyExifLensSerialNumber as String)
                out[kCGImagePropertyExifDictionary as String] = exif
            }
            // Apple maker note (device-specific metadata blob)
            out.removeValue(forKey: kCGImagePropertyMakerAppleDictionary as String)
            return out

        case .minimalPublic:
            // Keep only rights/provenance + output technical requirements.
            var out: [String: Any] = [:]
            let keepKeys: [CFString] = [
                kCGImagePropertyIPTCDictionary,
                kCGImagePropertyPixelWidth,
                kCGImagePropertyPixelHeight,
                kCGImagePropertyProfileName,
            ]
            for key in keepKeys {
                if let v = metadata[key as String] {
                    out[key as String] = v
                }
            }
            return out
        }
    }
}
