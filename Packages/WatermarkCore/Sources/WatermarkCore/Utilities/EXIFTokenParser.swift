import Foundation
import ImageIO

/// Stateless utility for substituting EXIF-based tokens in text strings.
///
/// Scans input text for `{token_name}` patterns (8 supported tokens),
/// extracts the corresponding value from EXIF/GPS/TIFF metadata dictionaries,
/// formats the value per token-type rules, and replaces the token in the string.
///
/// Missing EXIF fields render as "--" (double em dash) per D-08.
/// Unrecognized tokens are left as-is in the output.
///
/// Follows the `DeviceMetadataProvider` struct pattern:
/// public struct with static methods only, no stored state, String-keyed dict access.
///
/// - Note: Token substitution happens BEFORE rendering — see D-07.
/// - Note: All 8 tokens have no substring overlap, so simple `replacingOccurrences` is safe
///   (no regex needed per RESEARCH.md Pitfall 4 prevention).
public struct EXIFTokenParser {

    // MARK: - Dictionary Key Constants

    /// CFString keys used for EXIF metadata dictionary access.
    /// Using raw string representations for Sendable-compatible lookups.
    private static let exifDictKey = "{Exif}"       // kCGImagePropertyExifDictionary
    private static let tiffDictKey = "{TIFF}"       // kCGImagePropertyTIFFDictionary
    private static let gpsDictKey = "{GPS}"         // kCGImagePropertyGPSDictionary

    // MARK: - Token Definitions

    /// Supported EXIF token identifiers.
    /// Case names match the token syntax: `{camera_model}`, `{aperture}`, etc.
    private enum Token: String, CaseIterable {
        case camera_model, lens, aperture, focal_length
        case shutter_speed, iso, date, gps
    }

    // MARK: - Public API

    /// Substitutes all recognized EXIF tokens in the input text with formatted values.
    ///
    /// Iterates over the 8 fixed `Token` cases, checks if `{token}` appears in the text,
    /// resolves the token to its formatted EXIF value (or "--" if missing), and replaces
    /// all occurrences.
    ///
    /// - Parameters:
    ///   - text: Input string potentially containing `{token}` patterns
    ///   - metadata: Source image metadata dictionary (with String keys)
    /// - Returns: Text with all recognized tokens replaced; unrecognized tokens left as-is;
    ///   missing EXIF fields render as "--" per D-08
    public static func substitute(_ text: String, metadata: [String: Any]) -> String {
        // RED phase stub: returns input unchanged (tests will fail)
        return text
    }

    // MARK: - Token Value Resolvers

    /// Resolves a token to its formatted EXIF value, or "--" if missing.
    private static func value(for token: Token, metadata: [String: Any]) -> String {
        // RED phase stub: returns "--" for all tokens
        return "--"
    }

    // MARK: - Formatters

    /// Formats an EXIF date string (yyyy:MM:dd HH:mm:ss) to locale-aware short date.
    private static func formatDate(_ exifDateString: String) -> String {
        // RED phase stub
        return "--"
    }

    /// Formats GPS latitude/longitude from metadata GPS dictionary.
    private static func formatGPS(from metadata: [String: Any]) -> String {
        // RED phase stub
        return "--"
    }
}
