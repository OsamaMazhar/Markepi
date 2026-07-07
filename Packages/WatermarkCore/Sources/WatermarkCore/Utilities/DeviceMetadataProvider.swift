import Foundation
import ImageIO

/// Extracts device model information from EXIF metadata and formats
/// attribution text for the white frame overlay.
///
/// Tries the EXIF TIFF model tag first (most iPhone photos), then the
/// EXIF lens model tag, falling back to `UIDevice.current.model` per D-07.
/// Formats attribution as "Taken by: {model}" per D-08.
///
/// The attribution text is consumed by the white frame renderer (Plan 03).
/// In Plan 01, the method exists and is testable; the text is not yet
/// rendered onto output.
public struct DeviceMetadataProvider {

    /// CFString keys used for EXIF metadata dictionary access.
    /// Using raw string representations for Sendable-compatible lookups.
    private static let tiffDictionaryKey = "{TIFF}"
    private static let tiffModelKey = "Model"
    private static let exifDictionaryKey = "{Exif}"
    private static let exifLensModelKey = "LensModel"

    /// Extracts the device model name from EXIF metadata.
    ///
    /// Priority order per D-07:
    ///   1. TIFF Model tag (`kCGImagePropertyTIFFModel`) — most iPhone photos
    ///   2. EXIF LensModel tag (`kCGImagePropertyExifLensModel`) — secondary
    ///   3. `UIDevice.current.model` on iOS / "Unknown" on macOS
    ///
    /// - Parameter metadata: Source image metadata dictionary (with String keys
    ///   converted from CFString at the ImageIO boundary)
    /// - Returns: Device model string (e.g., "iPhone 16 Pro", "iPad")
    public static func deviceModel(from metadata: [String: Any]) -> String {
        // 1. Try TIFF dictionary → Model tag
        if let tiff = metadata[tiffDictionaryKey] as? [String: Any],
           let model = tiff[tiffModelKey] as? String,
           !model.isEmpty {
            return model
        }

        // 2. Try EXIF dictionary → LensModel tag
        if let exif = metadata[exifDictionaryKey] as? [String: Any],
           let lensModel = exif[exifLensModelKey] as? String,
           !lensModel.isEmpty {
            return lensModel
        }

        // 3. Fallback to the current device's generic model name.
        //
        // Derived from the hardware identifier via `uname` rather than
        // `UIDevice.current.model`: this method runs off the main actor during
        // rendering, and `UIDevice` is main-actor isolated. The hardware
        // identifier is thread-safe and gives us the same "iPhone"/"iPad"
        // granularity the white-frame attribution needs.
        return Self.hardwareModelName()
    }

    /// The generic device family ("iPhone" / "iPad" / "iPod touch") derived from
    /// the hardware identifier, or "Unknown" off-device (e.g. macOS tests).
    /// Thread-safe and free of any main-actor-isolated UIKit access.
    private static func hardwareModelName() -> String {
        let identifier: String
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            identifier = simulated
        } else {
            var sysinfo = utsname()
            uname(&sysinfo)
            identifier = withUnsafeBytes(of: &sysinfo.machine) { raw in
                String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
            }
        }

        if identifier.hasPrefix("iPad") { return "iPad" }
        if identifier.hasPrefix("iPod") { return "iPod touch" }
        if identifier.hasPrefix("iPhone") { return "iPhone" }
        return "Unknown"
    }

    /// Formats the attribution text for the white frame overlay.
    ///
    /// Single line only per D-08: "Taken by: {model}"
    /// - Parameter metadata: Source image metadata dictionary
    /// - Returns: Formatted attribution string
    public static func attributionText(from metadata: [String: Any]) -> String {
        return "Taken by: \(deviceModel(from: metadata))"
    }

    /// Builds a rich, single-line shooting-details caption from the available
    /// metadata — camera, focal length, aperture, shutter speed, ISO, pixel
    /// dimensions, and file format — including only the fields that are present
    /// (missing fields are dropped rather than shown as "--").
    ///
    /// Reuses `EXIFTokenParser` so formatting (f/1.8, 1/120s, ISO 100, 6000 × 4000,
    /// HEIC …) stays consistent with custom token templates. Falls back to the
    /// simple "Taken by: {model}" line when no shooting metadata is available.
    public static func detailedAttribution(from metadata: [String: Any]) -> String {
        let tokens = [
            "{camera_model}", "{lens}", "{focal_length}", "{aperture}",
            "{shutter_speed}", "{iso}", "{dimensions}", "{format}",
        ]
        // Avoid showing both the lens and a bare focal length when the lens
        // string already conveys the focal range — keep it simple: include lens
        // only if focal length is missing.
        let focal = EXIFTokenParser.substitute("{focal_length}", metadata: metadata)
        var parts: [String] = []
        for token in tokens {
            if token == "{lens}", focal != "--" { continue }
            let value = EXIFTokenParser.substitute(token, metadata: metadata)
            if value != "--" && !value.isEmpty {
                parts.append(value)
            }
        }
        if parts.isEmpty {
            return attributionText(from: metadata)
        }
        return parts.joined(separator: "   ·   ")
    }

    /// Builds the white-frame caption from a free-text prefix plus the
    /// user-selected metadata fields.
    ///
    /// Fields are resolved via `EXIFTokenParser` and emitted in canonical
    /// `CaptionField.allCases` order, joined by " · ". Fields whose metadata is
    /// missing (parser returns "--") are dropped rather than shown. The prefix,
    /// which may itself contain `{token}` patterns, is substituted and placed
    /// first. Returns an empty string when neither the prefix nor any selected
    /// field yields content — the renderer treats that as "no caption".
    ///
    /// - Parameters:
    ///   - prefix: Free text shown before the fields (may be empty).
    ///   - fields: Metadata fields to include.
    ///   - metadata: Source image metadata dictionary.
    /// - Returns: The assembled caption, or "" when nothing renders.
    public static func caption(
        prefix: String,
        fields: [CaptionField],
        metadata: [String: Any]
    ) -> String {
        var parts: [String] = []

        let trimmedPrefix = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPrefix.isEmpty {
            parts.append(EXIFTokenParser.substitute(trimmedPrefix, metadata: metadata))
        }

        // Render in canonical declaration order, not tick order, and de-dupe.
        for field in CaptionField.allCases where fields.contains(field) {
            let value = EXIFTokenParser.substitute(field.token, metadata: metadata)
            if value != "--" && !value.isEmpty {
                parts.append(value)
            }
        }

        return parts.joined(separator: " · ")
    }
}
