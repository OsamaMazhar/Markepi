import Foundation
import ImageIO
#if canImport(UIKit)
import UIKit
#endif

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

        // 3. Fallback to current device model
        #if canImport(UIKit)
        return UIDevice.current.model  // "iPhone", "iPad"
        #else
        return "Unknown"  // macOS testing fallback
        #endif
    }

    /// Formats the attribution text for the white frame overlay.
    ///
    /// Single line only per D-08: "Taken by: {model}"
    /// - Parameter metadata: Source image metadata dictionary
    /// - Returns: Formatted attribution string
    public static func attributionText(from metadata: [String: Any]) -> String {
        return "Taken by: \(deviceModel(from: metadata))"
    }
}
