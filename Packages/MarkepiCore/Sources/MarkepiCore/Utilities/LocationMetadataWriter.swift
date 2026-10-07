import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Puts a coordinate back into image data that has had one removed.
///
/// iOS's photo picker hands an app a *copy* of the chosen photo, and that copy
/// has its location stripped unless the app has been granted access to the
/// library. The photo in the library still has it, and the app can ask for it
/// through `PHAsset.location` — but every downstream stage here reads metadata
/// from the file, so the tidiest place to put it back is the file itself,
/// before anything else sees it.
///
/// Deliberately `CGImageDestinationCopyImageSource` rather than re-encoding:
/// the compressed image data, the HDR gain map and every other auxiliary image
/// are copied untouched, and only the metadata changes. Re-encoding would cost
/// a generation of quality to add two numbers.
public enum LocationMetadataWriter {

    /// Whether this image data already carries a usable coordinate.
    public static func hasCoordinate(in data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any] else { return false }
        let metadata = [String: Any]("{GPS}", properties[kCGImagePropertyGPSDictionary])
        return EXIFTokenParser.signedCoordinate(from: metadata) != nil
    }

    /// `data` with `latitude` and `longitude` written into its GPS metadata.
    ///
    /// Returns nil when the container cannot be rewritten, in which case the
    /// caller keeps the original bytes: a caption without a place is a much
    /// smaller loss than a photo that failed to import.
    public static func data(
        _ data: Data,
        addingLatitude latitude: Double,
        longitude: Double,
        altitude: Double? = nil,
        timestamp: Date? = nil
    ) -> Data? {
        guard latitude.isFinite, longitude.isFinite,
              abs(latitude) <= 90, abs(longitude) <= 180 else { return nil }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source) else { return nil }

        // Merged into the source's own metadata, so nothing else is disturbed.
        let existing = CGImageSourceCopyMetadataAtIndex(source, 0, nil)
        let metadata = existing.flatMap { CGImageMetadataCreateMutableCopy($0) }
            ?? CGImageMetadataCreateMutable()

        // EXIF stores unsigned magnitudes plus a hemisphere ref, which is what
        // `EXIFTokenParser.signedCoordinate` expects to read back.
        func set(_ key: CFString, _ value: CFTypeRef) -> Bool {
            CGImageMetadataSetValueMatchingImageProperty(
                metadata, kCGImagePropertyGPSDictionary, key, value)
        }
        guard set(kCGImagePropertyGPSLatitude, abs(latitude) as CFNumber),
              set(kCGImagePropertyGPSLatitudeRef, (latitude >= 0 ? "N" : "S") as CFString),
              set(kCGImagePropertyGPSLongitude, abs(longitude) as CFNumber),
              set(kCGImagePropertyGPSLongitudeRef, (longitude >= 0 ? "E" : "W") as CFString)
        else { return nil }

        if let altitude, altitude.isFinite {
            _ = set(kCGImagePropertyGPSAltitude, abs(altitude) as CFNumber)
            _ = set(kCGImagePropertyGPSAltitudeRef, (altitude >= 0 ? 0 : 1) as CFNumber)
        }
        if let timestamp {
            let day = DateFormatter()
            day.locale = Locale(identifier: "en_US_POSIX")
            day.timeZone = TimeZone(identifier: "UTC")
            day.dateFormat = "yyyy:MM:dd"
            let clock = DateFormatter()
            clock.locale = day.locale
            clock.timeZone = day.timeZone
            clock.dateFormat = "HH:mm:ss"
            _ = set(kCGImagePropertyGPSDateStamp, day.string(from: timestamp) as CFString)
            _ = set(kCGImagePropertyGPSTimeStamp, clock.string(from: timestamp) as CFString)
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type, 1, nil) else {
            return nil
        }
        var error: Unmanaged<CFError>?
        let options: [CFString: Any] = [
            kCGImageDestinationMetadata: metadata,
            kCGImageDestinationMergeMetadata: true,
        ]
        guard CGImageDestinationCopyImageSource(
            destination, source, options as CFDictionary, &error) else { return nil }
        return output as Data
    }
}

public extension LocationMetadataWriter {

    /// Whether this image data says which camera took it.
    static func hasCameraInfo(in data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any] else { return false }
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        return (tiff?[kCGImagePropertyTIFFModel] as? String)?.isEmpty == false
    }

    /// `data` with every metadata tag it lacks copied from `original`.
    ///
    /// An edit saved by some apps keeps the pixels and drops the EXIF, while
    /// the library still holds the original with all of it — which is why
    /// Photos shows a camera and lens that the picked copy no longer has.
    /// Tags `data` already has win, and the ones describing the pixels
    /// themselves (orientation, size) are never taken from the original,
    /// because an edit may have rotated or cropped it. Only metadata changes:
    /// the image data and any gain map are copied untouched.
    static func data(_ data: Data, fillingMetadataFrom original: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source),
              let originalSource = CGImageSourceCreateWithData(original as CFData, nil),
              let donor = CGImageSourceCopyMetadataAtIndex(originalSource, 0, nil) else { return nil }
        let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil)
            .flatMap { CGImageMetadataCreateMutableCopy($0) } ?? CGImageMetadataCreateMutable()
        let pixelTags: Set<String> = ["tiff:Orientation", "exif:PixelXDimension", "exif:PixelYDimension",
                                      "tiff:ImageWidth", "tiff:ImageLength"]
        var added = 0
        CGImageMetadataEnumerateTagsUsingBlock(donor, nil, nil) { path, tag in
            let key = path as String
            if !pixelTags.contains(key), CGImageMetadataCopyTagWithPath(metadata, nil, path) == nil,
               CGImageMetadataSetTagWithPath(metadata, nil, path, tag) { added += 1 }
            return true
        }
        guard added > 0 else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type, 1, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageDestinationMetadata: metadata, kCGImageDestinationMergeMetadata: true]
        guard CGImageDestinationCopyImageSource(destination, source, options as CFDictionary, nil) else { return nil }
        return output as Data
    }
}

private extension Dictionary where Key == String, Value == Any {
    /// One-entry dictionary, or an empty one when the value is absent — just
    /// enough to hand `EXIFTokenParser` the shape it reads.
    init(_ key: String, _ value: Any?) {
        self = value.map { [key: $0] } ?? [:]
    }
}
