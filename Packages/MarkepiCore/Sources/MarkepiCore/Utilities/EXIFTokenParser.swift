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
        case make, camera_model, lens, aperture, focal_length
        case shutter_speed, iso, date, time, gps
        case dimensions, format
    }

    /// How `{gps}` renders.
    ///
    /// Two formats, because `{gps}` has two consumers and only one of them can
    /// draw a colour emoji. `TextWatermarkRenderer` draws every glyph white as
    /// an alpha mask and tints it, so a flag pushed through it comes out a
    /// solid tinted rectangle and the pin comes out a blob. That path keeps
    /// `.coordinates`; only the frame caption, which draws into a context with
    /// a real foreground colour, asks for `.place`.
    public enum GPSFormat: Sendable {
        /// "37.7749° N, 122.4194° W" — the default, and what every existing
        /// caller keeps getting.
        case coordinates
        /// "📍 France 🇫🇷" — the country the photo was taken in.
        case place
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
    public static func substitute(
        _ text: String,
        metadata: [String: Any],
        gpsFormat: GPSFormat = .coordinates
    ) -> String {
        var result = text
        for token in Token.allCases {
            let pattern = "{\(token.rawValue)}"
            guard result.contains(pattern) else { continue }
            let replacement = value(for: token, metadata: metadata, gpsFormat: gpsFormat)
            result = result.replacingOccurrences(of: pattern, with: replacement)
        }
        return result
    }

    // MARK: - Token Value Resolvers

    /// Resolves a token to its formatted EXIF value, or "--" if missing.
    private static func value(
        for token: Token,
        metadata: [String: Any],
        gpsFormat: GPSFormat = .coordinates
    ) -> String {
        switch token {
        case .make:
            // Through the same resolution that picks the brand mark, so the
            // name and the logo beside it can never disagree, and a make the
            // file spells oddly ("dji", "NIKON CORPORATION") is spoken the way
            // the brand spells it. An unrecognised maker resolves to nothing,
            // exactly as it draws no mark.
            return BrandMarkRegistry.displayName(metadata: metadata) ?? "--"

        case .camera_model:
            let tiff = metadata[tiffDictKey] as? [String: Any]
            if let model = tiff?["Model"] as? String, !model.isEmpty {
                return model
            }
            return "--"

        case .lens:
            return lensText(metadata: metadata, omitDevice: false)

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
            guard let moment = captureMoment(metadata: metadata) else { return "--" }
            return format(moment.date, dateStyle: .medium, timeStyle: .none)

        case .time:
            // A file that recorded only the day has no clock reading to show.
            guard let moment = captureMoment(metadata: metadata), moment.hasTime else { return "--" }
            return format(moment.date, dateStyle: .none, timeStyle: .short)

        case .gps:
            switch gpsFormat {
            case .coordinates: return formatGPS(from: metadata)
            case .place: return formatGPSAsPlace(from: metadata)
            }

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
    /// The lens, as it should be printed beside whatever else the caption says.
    ///
    /// Three things are stripped, each because another entry already says it:
    ///
    /// - The device name. Apple writes it into the lens too ("iPhone 15 Pro Max
    ///   back triple camera 48mm f/1.78"), and the lens entry is about the lens.
    /// - The millimetres, when Focal length is ticked.
    /// - The f-number, when Aperture is ticked.
    ///
    /// The last two only on a phone spec, and for the same reason
    /// `restatingFocalAsEquivalent` guards its rewrite: a camera lens is a
    /// product name — "RF24-70mm F2.8 L IS USM" — where the numbers are part
    /// of what the lens is called, and removing them names a lens that does
    /// not exist. A phone's "back triple camera 48mm f/1.78" is a spec, and a
    /// caption that prints "48mm f/1.8" a word later is printing it twice.
    ///
    /// Returns "--" when the file names no lens, like every other token.
    /// - Parameter omitDevice: false for the bare `{lens}` token, which a user
    ///   may type on its own in a free-text watermark and expect the whole
    ///   string the file carries. The frame captions always strip it.
    public static func lensText(
        metadata: [String: Any],
        omitFocal: Bool = false,
        omitAperture: Bool = false,
        omitDevice: Bool = true
    ) -> String {
        let exif = metadata[exifDictKey] as? [String: Any]
        guard let lensModel = exif?["LensModel"] as? String, !lensModel.isEmpty else { return "--" }
        var text = restatingFocalAsEquivalent(in: lensModel, exif: exif)

        if omitDevice,
           let model = (metadata[tiffDictKey] as? [String: Any])?["Model"] as? String,
           !model.isEmpty, text != model,
           text.lowercased().hasPrefix(model.lowercased() + " ") {
            let stripped = String(text.dropFirst(model.count)).trimmingCharacters(in: .whitespaces)
            if !stripped.isEmpty { text = stripped }
        }

        guard isPhoneSpec(exif: exif), omitFocal || omitAperture else { return text }
        // Whole words only: this drops "48mm" standing on its own, never the
        // "24-70mm" inside a name.
        let kept = text.split(separator: " ").filter { word in
            if omitFocal, word.hasSuffix("mm"), Double(word.dropLast(2)) != nil { return false }
            if omitAperture, word.lowercased().hasPrefix("f/"),
               Double(word.dropFirst(2)) != nil { return false }
            return true
        }
        let trimmed = kept.joined(separator: " ")
        // A lens whose every word was a reading has nothing left to add.
        return trimmed.isEmpty ? "--" : trimmed
    }

    /// Whether this file's lens string is a phone spec rather than a product
    /// name, judged by a crop factor no interchangeable-lens format reaches.
    private static func isPhoneSpec(exif: [String: Any]?) -> Bool {
        guard let optical = exif?["FocalLength"] as? Double, optical > 0,
              let equivalent = equivalentFocalLength(exif: exif) else { return false }
        return Double(equivalent) / optical >= 2.5
    }

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

    /// When the file says it was taken, and whether it recorded a clock
    /// reading as well as a day.
    ///
    /// Where the capture stamp lives varies by writer: phones fill the Exif
    /// dictionary, some cameras and most re-encoders leave only TIFF's
    /// DateTime, and edited files can carry it in IPTC alone. Reading Exif
    /// only is why the date silently dropped out of the caption on files that
    /// plainly had one.
    static func captureMoment(metadata: [String: Any]) -> (date: Date, hasTime: Bool)? {
        let exif = metadata[exifDictKey] as? [String: Any]
        let tiff = metadata[tiffDictKey] as? [String: Any]
        let stamp = (exif?["DateTimeOriginal"] as? String)
            ?? (exif?["DateTimeDigitized"] as? String)
            ?? (exif?["DateTime"] as? String)
            ?? (tiff?["DateTime"] as? String)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        // Some writers use dashes, and a few omit the time entirely.
        let patterns = ["yyyy:MM:dd HH:mm:ss", "yyyy-MM-dd HH:mm:ss", "yyyy:MM:dd"]
        if let stamp {
            for pattern in patterns {
                formatter.dateFormat = pattern
                if let date = formatter.date(from: stamp) {
                    return (date, pattern.contains("HH"))
                }
            }
        }

        // IPTC splits the stamp: yyyyMMdd plus an optional HHmmss (sometimes
        // with a zone suffix), so it needs its own parse.
        guard let iptc = metadata[iptcDictKey] as? [String: Any],
              let created = iptc["DateCreated"] as? String else { return nil }
        let digits = ((iptc["TimeCreated"] as? String) ?? "").prefix(while: \.isNumber)
        let hasTime = digits.count >= 6
        formatter.dateFormat = hasTime ? "yyyyMMdd HHmmss" : "yyyyMMdd"
        guard let date = formatter.date(from: hasTime ? "\(created) \(digits.prefix(6))" : created)
        else { return nil }
        return (date, hasTime)
    }

    /// Styles rather than a fixed pattern, so month names and time order follow
    /// the reader's locale instead of being hardcoded English.
    private static func format(_ date: Date,
                               dateStyle: DateFormatter.Style,
                               timeStyle: DateFormatter.Style) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = dateStyle
        formatter.timeStyle = timeStyle
        return formatter.string(from: date)
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

    /// The `{GPS}` dictionary's coordinate as *signed* degrees.
    ///
    /// EXIF stores latitude and longitude as unsigned magnitudes with the
    /// hemisphere in a separate reference tag, and the app's own video path
    /// writes them the same way. Everything geometric expects signed degrees,
    /// so the refs have to be applied before the coordinate goes anywhere.
    ///
    /// Getting this wrong is silent and total: every southern photo lands in
    /// the northern hemisphere and every western one in the east, with nothing
    /// to crash or warn. Sydney would come back as open Pacific.
    ///
    /// Where a ref is absent the stored sign is used, matching what
    /// `formatGPS` already assumes.
    static func signedCoordinate(from metadata: [String: Any]) -> (latitude: Double, longitude: Double)? {
        guard let gps = metadata[gpsDictKey] as? [String: Any],
              let lat = gps["Latitude"] as? Double,
              let lon = gps["Longitude"] as? Double else {
            return nil
        }
        let latRef = (gps["LatitudeRef"] as? String)?.uppercased()
        let lonRef = (gps["LongitudeRef"] as? String)?.uppercased()
        let signedLat = latRef == "S" ? -abs(lat) : (latRef == "N" ? abs(lat) : lat)
        let signedLon = lonRef == "W" ? -abs(lon) : (lonRef == "E" ? abs(lon) : lon)
        return (signedLat, signedLon)
    }

    /// The coordinate rendered as the place it is — pin, country, flag.
    ///
    /// "--" both when there is no GPS at all and when the coordinate resolves
    /// to no country (open ocean), so the caption's existing missing-field
    /// handling elides the line either way rather than falling back to raw
    /// coordinates or inventing a country.
    private static func formatGPSAsPlace(from metadata: [String: Any]) -> String {
        guard let coordinate = signedCoordinate(from: metadata),
              let place = CountryResolver.placeDescription(latitude: coordinate.latitude,
                                                           longitude: coordinate.longitude) else {
            return "--"
        }
        return place
    }
}
