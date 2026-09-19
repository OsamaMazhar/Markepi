import ImageIO
import Foundation

/// Merges rights fields into an ImageIO metadata dict WITHOUT dropping
/// unrelated EXIF/XMP (AUTH-03, D-07). Pure function — returns a new dict,
/// leaving the input untouched.
///
/// IPTC Digital Source Type uses controlled-vocabulary URIs; the writer does
/// not invent local values for AI/source labels. Copyright is also mirrored
/// into TIFF for broad reader compatibility.
public struct IPTCRightsMetadataWriter: Sendable {

    public init() {}

    /// Returns a new metadata dictionary with `rights` merged into `metadata`.
    /// Empty rights fields are skipped (no empty keys written).
    public func merged(into metadata: [String: Any], rights: RightsMetadata) -> [String: Any] {
        var out = metadata

        var iptc = out[kCGImagePropertyIPTCDictionary as String] as? [String: Any] ?? [:]
        if !rights.creator.isEmpty {
            iptc[kCGImagePropertyIPTCByline as String] = [rights.creator]
        }
        if !rights.copyrightNotice.isEmpty {
            iptc[kCGImagePropertyIPTCCopyrightNotice as String] = rights.copyrightNotice
        }
        if !rights.creditLine.isEmpty {
            iptc[kCGImagePropertyIPTCCredit as String] = rights.creditLine
        }
        if !rights.usageTerms.isEmpty {
            iptc[kCGImagePropertyIPTCRightsUsageTerms as String] = rights.usageTerms
        }
        if let dst = rights.digitalSourceType {
            iptc[kCGImagePropertyIPTCExtDigitalSourceType as String] = dst
        }
        out[kCGImagePropertyIPTCDictionary as String] = iptc

        // Copyright also in TIFF for broad reader compatibility.
        if !rights.copyrightNotice.isEmpty {
            var tiff = out[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:]
            tiff[kCGImagePropertyTIFFCopyright as String] = rights.copyrightNotice
            out[kCGImagePropertyTIFFDictionary as String] = tiff
        }

        // Licensor URL goes into IPTC Ext Licensor (when non-empty).
        if !rights.licensorURL.isEmpty {
            // IPTC Ext stores licensor as an array of dicts; we add a single
            // web entry without overwriting existing licensor entries.
            var iptcExt = out[kCGImagePropertyIPTCDictionary as String] as? [String: Any] ?? [:]
            // Reuse the same IPTC dict (kCGImagePropertyIPTCExtDigitalSourceType is in the same namespace)
            var licensors = iptcExt["Licensor"] as? [[String: Any]] ?? []
            licensors.append([
                "LicensorURL": rights.licensorURL
            ])
            iptcExt["Licensor"] = licensors
            out[kCGImagePropertyIPTCDictionary as String] = iptcExt
        }

        return out
    }
}
