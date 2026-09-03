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
        case dimensions, format
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
        var result = text
        for token in Token.allCases {
            let pattern = "{\(token.rawValue)}"
            guard result.contains(pattern) else { continue }
            let replacement = value(for: token, metadata: metadata)
            result = result.replacingOccurrences(of: pattern, with: replacement)
        }
        return result
    }

    // MARK: - Token Value Resolvers

    /// Resolves a token to its formatted EXIF value, or "--" if missing.
    private static func value(for token: Token, metadata: [String: Any]) -> String {
        switch token {
        case .camera_model:
            let tiff = metadata[tiffDictKey] as? [String: Any]
            if let model = tiff?["Model"] as? String, !model.isEmpty {
                return model
            }
            return "--"

        case .lens:
            let exif = metadata[exifDictKey] as? [String: Any]
            if let lensModel = exif?["LensModel"] as? String, !lensModel.isEmpty {
                return lensModel
            }
            return "--"

        case .aperture:
            let exif = metadata[exifDictKey] as? [String: Any]
            guard let fNumber = exif?["FNumber"] as? Double else { return "--" }
            return String(format: "f/%.1f", fNumber)

        case .focal_length:
            let exif = metadata[exifDictKey] as? [String: Any]
            // Photos app shows the 35mm-equivalent ("24mm"), not the optical
            // focal ("6.765mm") — the number every user expects to see. Fall
            // back to the optical focal for sources without the field.
            if let equivalent = exif?["FocalLenIn35mmFilm"] as? Int, equivalent > 0 {
                return "\(equivalent)mm"
            }
            guard let focal = exif?["FocalLength"] as? Double else { return "--" }
            return String(format: "%.0fmm", focal)

        case .shutter_speed:
            let exif = metadata[exifDictKey] as? [String: Any]
            guard let apexValue = exif?["ShutterSpeedValue"] as? Double else { return "--" }
            let exposureTime = pow(2.0, -apexValue)  // APEX to seconds
            if exposureTime < 1.0 {
                let denominator = Int(round(1.0 / exposureTime))
                return "1/\(denominator)"
            } else {
                return String(format: "%.1fs", exposureTime)
            }

        case .iso:
            let exif = metadata[exifDictKey] as? [String: Any]
            let isoValue: Int? = {
                // Handle both [Int] array (take first) and Int scalar (Research A4)
                if let ratings = exif?["ISOSpeedRatings"] as? [Int], let first = ratings.first {
                    return first
                }
                if let rating = exif?["ISOSpeedRatings"] as? Int {
                    return rating
                }
                return nil
            }()
            guard let iso = isoValue else { return "--" }
            return "ISO \(iso)"

        case .date:
            let exif = metadata[exifDictKey] as? [String: Any]
            let dateString = (exif?["DateTimeOriginal"] as? String)
                ?? (exif?["DateTimeDigitized"] as? String)
                ?? (exif?["DateTime"] as? String)
            guard let dateString = dateString else { return "--" }
            return formatDate(dateString)

        case .gps:
            return formatGPS(from: metadata)

        case .dimensions:
            guard let w = intValue(metadata["PixelWidth"]),
                  let h = intValue(metadata["PixelHeight"]),
                  w > 0, h > 0 else { return "--" }
            return "\(w) × \(h)"

        case .format:
            // Source UTI is injected by WatermarkEngine as "_SourceUTI".
            guard let uti = metadata["_SourceUTI"] as? String,
                  let label = formatLabel(forUTI: uti) else { return "--" }
            return label
        }
    }

    // MARK: - Shared metadata helpers

    /// Reads an integer from a metadata value that may be an Int, Double, or NSNumber.
    static func intValue(_ any: Any?) -> Int? {
        if let i = any as? Int { return i }
        if let n = any as? NSNumber { return n.intValue }
        if let d = any as? Double { return Int(d) }
        return nil
    }

    /// Maps a source UTI to a short, human-readable format label.
    static func formatLabel(forUTI uti: String) -> String? {
        switch uti.lowercased() {
        case "public.heic", "public.heif": return "HEIC"
        case "public.jpeg": return "JPEG"
        case "public.png": return "PNG"
        case "public.tiff": return "TIFF"
        case "com.adobe.raw-image", "com.adobe.dng": return "DNG"
        case "com.apple.quicktime-movie": return "MOV"
        case "public.mpeg-4": return "MP4"
        default:
            // Best-effort: last path component of the UTI, uppercased.
            return uti.split(separator: ".").last.map { $0.uppercased() }
        }
    }

    // MARK: - Formatters

    /// Formats an EXIF date string (yyyy:MM:dd HH:mm:ss) to locale-aware short date.
    ///
    /// - Parameter exifDateString: EXIF-format date string
    /// - Returns: Locale-aware short date (e.g., "Jun 18, 2026") or "--" if parsing fails
    private static func formatDate(_ exifDateString: String) -> String {
        let inputFormatter = DateFormatter()
        inputFormatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        guard let date = inputFormatter.date(from: exifDateString) else { return "--" }

        // Medium date plus the time, without seconds — "16 Dec 2018 at 09:50".
        // Styles rather than a fixed pattern, so month names and time order
        // follow the reader's locale instead of being hardcoded English.
        let outputFormatter = DateFormatter()
        outputFormatter.dateStyle = .medium
        outputFormatter.timeStyle = .short
        return outputFormatter.string(from: date)
    }

    /// Formats GPS latitude/longitude from metadata GPS dictionary.
    ///
    /// - Parameter metadata: Source metadata dictionary containing "{GPS}" sub-dict
    /// - Returns: Formatted GPS string like "37.7749° N, 122.4194° W" or "--" if missing
    private static func formatGPS(from metadata: [String: Any]) -> String {
        guard let gps = metadata[gpsDictKey] as? [String: Any],
              let lat = gps["Latitude"] as? Double,
              let lon = gps["Longitude"] as? Double else {
            return "--"
        }
        let latRef = gps["LatitudeRef"] as? String ?? (lat >= 0 ? "N" : "S")
        let lonRef = gps["LongitudeRef"] as? String ?? (lon >= 0 ? "E" : "W")
        return String(format: "%.4f° %@, %.4f° %@",
                      abs(lat), latRef, abs(lon), lonRef)
    }
}
