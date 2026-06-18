import Foundation

/// Test helper for creating synthetic EXIF metadata dictionaries with known
/// values for EXIFTokenParser unit tests.
///
/// Provides realistic metadata (iPhone 16 Pro defaults) and minimal metadata
/// (for testing "--" fallback behavior). All values are controlled so tests
/// can assert exact formatted output.
///
/// Follows the `TestImageFactory.swift` pattern (public struct, static factory methods).
public struct EXIFMetadataFactory {

    /// Creates a realistic metadata dictionary with known EXIF/GPS/TIFF values.
    ///
    /// - Parameters:
    ///   - model: Camera model name (TIFF Model tag)
    ///   - lens: Lens model string (EXIF LensModel tag)
    ///   - aperture: Aperture f-number (EXIF FNumber)
    ///   - focalLength: Focal length in mm (EXIF FocalLength)
    ///   - shutterSpeedAPEX: Shutter speed in APEX units (EXIF ShutterSpeedValue)
    ///   - iso: ISO sensitivity (EXIF ISOSpeedRatings)
    ///   - dateTime: Date/time string in EXIF format "yyyy:MM:dd HH:mm:ss"
    ///   - lat: GPS latitude in decimal degrees
    ///   - lon: GPS longitude in decimal degrees
    /// - Returns: A [String: Any] dictionary with "{TIFF}", "{Exif}", and "{GPS}" sub-dictionaries
    public static func realisticMetadata(
        model: String = "iPhone 16 Pro",
        lens: String = "iPhone 16 Pro back triple camera 6.86mm f/1.78",
        aperture: Double = 1.78,
        focalLength: Double = 6.86,
        shutterSpeedAPEX: Double = 6.906,
        iso: Int = 400,
        dateTime: String = "2026:06:18 14:30:00",
        lat: Double = 37.7749,
        lon: Double = -122.4194
    ) -> [String: Any] {
        return [
            "{TIFF}": [
                "Model": model
            ] as [String: Any],
            "{Exif}": [
                "LensModel": lens,
                "FNumber": aperture,
                "FocalLength": focalLength,
                "ShutterSpeedValue": shutterSpeedAPEX,
                "ISOSpeedRatings": [iso],
                "DateTimeOriginal": dateTime
            ] as [String: Any],
            "{GPS}": [
                "Latitude": abs(lat),
                "LatitudeRef": lat >= 0 ? "N" : "S",
                "Longitude": abs(lon),
                "LongitudeRef": lon >= 0 ? "E" : "W"
            ] as [String: Any]
        ]
    }

    /// Creates an empty metadata dictionary for testing fallback behavior.
    ///
    /// All token substitutions should return "--" when metadata is empty.
    public static func minimalMetadata() -> [String: Any] {
        return [:]
    }

    /// Creates metadata with only TIFF Model present (no EXIF, no GPS).
    /// Useful for testing partial metadata resolution.
    public static func tiffOnlyMetadata(model: String = "iPhone 16 Pro") -> [String: Any] {
        return [
            "{TIFF}": [
                "Model": model
            ] as [String: Any]
        ]
    }

    /// Creates metadata where ISOSpeedRatings is a scalar Int instead of an array.
    /// Useful for testing dual-type handling per Research A4.
    public static func scalarISOMetadata(iso: Int = 400) -> [String: Any] {
        return [
            "{Exif}": [
                "ISOSpeedRatings": iso
            ] as [String: Any]
        ]
    }

    /// Creates metadata where ISOSpeedRatings is an array of Ints.
    /// Useful for testing array-first-element extraction.
    public static func arrayISOMetadata(isoValues: [Int] = [400, 800]) -> [String: Any] {
        return [
            "{Exif}": [
                "ISOSpeedRatings": isoValues
            ] as [String: Any]
        ]
    }
}
