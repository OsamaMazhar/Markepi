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
    private static let iptcDictKey = "{IPTC}"       // kCGImagePropertyIPTCDictionary

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
                return restatingFocalAsEquivalent(in: lensModel, exif: exif)
            }
            return "--"

        case .aperture:
            let exif = metadata[exifDictKey] as? [String: Any]
            guard let fNumber = exif?["FNumber"] as? Double else { return "--" }
            return String(format: "f/%.1f", fNumber)

        case .focal_length:
            let exif = metadata[exifDictKey] as? [String: Any]
            if let equivalent = equivalentFocalLength(exif: exif) { return "\(equivalent)mm" }
            // No equivalent to be had: show the optical focal, labelled as it
            // is rather than dressed up as an equivalent.
            guard let focal = exif?["FocalLength"] as? Double, focal > 0 else { return "--" }
            return String(format: "%.2fmm", focal)
                .replacingOccurrences(of: #"\.?0+mm$"#, with: "mm", options: .regularExpression)

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
            // Where the capture date lives varies by writer: phones fill the
            // Exif dictionary, some cameras and most re-encoders leave only
            // TIFF's DateTime, and edited files can carry it in IPTC alone.
            // Reading Exif only is why the date silently dropped out of the
            // caption on files that plainly had one.
            let exif = metadata[exifDictKey] as? [String: Any]
            let tiff = metadata[tiffDictKey] as? [String: Any]
            let dateString = (exif?["DateTimeOriginal"] as? String)
                ?? (exif?["DateTimeDigitized"] as? String)
                ?? (exif?["DateTime"] as? String)
                ?? (tiff?["DateTime"] as? String)
            if let dateString, let formatted = formatDate(dateString) { return formatted }
            if let iptc = metadata[iptcDictKey] as? [String: Any],
               let created = iptc["DateCreated"] as? String {
                // IPTC splits the stamp: yyyyMMdd plus an optional HHmmss.
                let time = (iptc["TimeCreated"] as? String) ?? ""
                if let formatted = formatIPTCDate(created, time: time) { return formatted }
            }
            return "--"

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
    // MARK: - Focal length

    /// Rewrites the optical focal length inside a lens name as its 35mm
    /// equivalent — but only where that is what the name is describing.
    ///
    /// A phone writes a spec ("back triple camera 6.765mm f/1.78"), where the
    /// millimetres mean nothing to a reader and Photos shows the equivalent.
    /// A camera lens writes a *product name* ("RF24-70mm F2.8 L IS USM",
    /// "XF35mmF1.4 R"), where the millimetres are part of what the lens is
    /// called; rewriting those renamed the lens to one that does not exist.
    ///
    /// Two guards keep them apart: the sensor must be phone-class (a crop
    /// factor of 2.5 or more, which no interchangeable-lens format reaches),
    /// and only the number matching the optical focal is touched — so the "24"
    /// and "70" of a zoom range are never mistaken for it.
    private static func restatingFocalAsEquivalent(in lensModel: String, exif: [String: Any]?) -> String {
        guard let optical = (exif?["FocalLength"] as? Double), optical > 0,
              let equivalent = equivalentFocalLength(exif: exif),
              Double(equivalent) / optical >= 2.5 else { return lensModel }

        guard let regex = try? NSRegularExpression(pattern: #"[0-9]+(\.[0-9]+)?mm"#) else {
            return lensModel
        }
        let text = lensModel as NSString
        var result = lensModel
        // Back to front, so earlier matches keep their ranges as we replace.
        for match in regex.matches(in: lensModel, range: NSRange(location: 0, length: text.length)).reversed() {
            let token = text.substring(with: match.range)
            guard let value = Double(token.dropLast(2)), abs(value - optical) < 0.05 else { continue }
            result = (result as NSString).replacingCharacters(in: match.range, with: "\(equivalent)mm")
        }
        return result
    }


    /// Physical focal length → 35mm equivalent, for Apple's camera modules.
    ///
    /// Consulted only when the file's own `FocalLenIn35mmFilm` cannot be
    /// trusted (see `equivalentFocalLength`), never in place of a sound one.
    /// Keyed on the optical focal length rather than the device name because
    /// one module appears across several models, and the optical focal is what
    /// identifies it.
    private static let appleEquivalents: [(optical: Double, equivalent: Int)] = [
        (1.54, 13), (2.22, 13),          // ultra-wide
        (3.99, 28), (4.15, 29), (4.25, 26), (5.70, 26),
        (6.765, 24), (6.86, 24),         // main
        (6.00, 52), (9.00, 77), (15.66, 120), // telephoto
    ]

    /// The 35mm-equivalent focal length, as the Photos app reports it.
    ///
    /// `FocalLenIn35mmFilm` describes the *framing*, so on a cropped or
    /// digitally-zoomed shot it climbs far above the lens's own equivalent —
    /// a 15 Pro Max frame at 5x records 121mm while Photos still says 24mm,
    /// because Photos names the lens. Where the recorded value implies a crop
    /// factor no phone sensor has, it is treated as zoom-inflated: the optical
    /// focal is matched against the known modules, and failing that the
    /// recorded digital zoom is divided back out.
    static func equivalentFocalLength(exif: [String: Any]?) -> Int? {
        let optical = (exif?["FocalLength"] as? Double).flatMap { $0 > 0 ? $0 : nil }
        let recorded = (exif?["FocalLenIn35mmFilm"] as? Int).flatMap { $0 > 0 ? $0 : nil }
        let zoom = (exif?["DigitalZoomRatio"] as? Double).flatMap { $0 > 1 ? $0 : nil }

        guard let optical else {
            return recorded
        }
        guard let recorded else {
            // Nothing recorded: the module may still be known, but the optical
            // focal must not be passed off as an equivalent — rounding 6.86mm
            // to "7mm" states a focal length the camera never had.
            return appleEquivalents.first { abs($0.optical - optical) < 0.05 }?.equivalent
        }

        // No phone sensor has a crop factor past about 9; beyond that the
        // recorded equivalent is describing a crop, not the lens.
        let impliedCropFactor = Double(recorded) / optical
        guard impliedCropFactor > 9 || zoom != nil else { return recorded }

        if let match = appleEquivalents.first(where: { abs($0.optical - optical) < 0.05 }) {
            return match.equivalent
        }
        // Unknown module: at least undo the zoom the file did record.
        guard let zoom else { return recorded }
        return Int((Double(recorded) / zoom).rounded())
    }

    private static func formatDate(_ exifDateString: String) -> String? {
        let inputFormatter = DateFormatter()
        inputFormatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        // Some writers use dashes, and a few omit the time entirely.
        inputFormatter.locale = Locale(identifier: "en_US_POSIX")
        let date = ["yyyy:MM:dd HH:mm:ss", "yyyy-MM-dd HH:mm:ss", "yyyy:MM:dd"]
            .lazy
            .compactMap { format -> Date? in
                inputFormatter.dateFormat = format
                return inputFormatter.date(from: exifDateString)
            }
            .first
        guard let date else { return nil }

        // Medium date plus the time, without seconds — "16 Dec 2018 at 09:50".
        // Styles rather than a fixed pattern, so month names and time order
        // follow the reader's locale instead of being hardcoded English.
        let outputFormatter = DateFormatter()
        outputFormatter.dateStyle = .medium
        outputFormatter.timeStyle = .short
        return outputFormatter.string(from: date)
    }

    /// IPTC keeps the date as `yyyyMMdd` and the time separately as `HHmmss`
    /// (optionally with a zone suffix), so it needs its own parse.
    private static func formatIPTCDate(_ date: String, time: String) -> String? {
        let digits = time.prefix(while: \.isNumber)
        let combined = digits.count >= 6 ? "\(date) \(digits.prefix(6))" : date
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = digits.count >= 6 ? "yyyyMMdd HHmmss" : "yyyyMMdd"
        guard let parsed = formatter.date(from: combined) else { return nil }
        let output = DateFormatter()
        output.dateStyle = .medium
        output.timeStyle = digits.count >= 6 ? .short : .none
        return output.string(from: parsed)
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
