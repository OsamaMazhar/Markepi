import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import MarkepiCore

/// Putting a coordinate back into a photo whose copy arrived without one.
///
/// The case this exists for: iOS's photo picker strips location from the copy
/// it hands an app that has no library access, so a frame caption asking where
/// the photo was taken had nothing to answer with — while the same photo
/// captioned correctly when the file came from anywhere else.
@Suite("Location metadata repair")
struct LocationMetadataWriterTests {

    private func plainJPEG() -> Data {
        TestImageFactory.solidColorImage(
            color: CGColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1),
            size: CGSize(width: 64, height: 48)).1
    }

    private func gpsDictionary(of data: Data) -> [String: Any] {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let gps = properties[kCGImagePropertyGPSDictionary] else { return [:] }
        return ["{GPS}": gps]
    }

    @Test("A photo with no coordinate is recognised as having none")
    func plainImageHasNoCoordinate() {
        #expect(!LocationMetadataWriter.hasCoordinate(in: plainJPEG()))
    }

    @Test("A written coordinate reads back where the caption looks for it",
          arguments: [
            (48.8566, 2.3522, "FR", "Paris"),
            (-33.8688, 151.2093, "AU", "Sydney"),
            (-23.5505, -46.6333, "BR", "São Paulo"),
            (37.7749, -122.4194, "US", "San Francisco"),
          ])
    func writtenCoordinateRoundTrips(lat: Double, lon: Double, code: String, place: String) throws {
        let repaired = try #require(
            LocationMetadataWriter.data(plainJPEG(), addingLatitude: lat, longitude: lon))

        #expect(LocationMetadataWriter.hasCoordinate(in: repaired))
        let signed = try #require(EXIFTokenParser.signedCoordinate(from: gpsDictionary(of: repaired)))
        // Every hemisphere: EXIF stores magnitudes plus a ref, and a lost ref
        // puts Sydney in the open Pacific without anything failing.
        #expect(abs(signed.latitude - lat) < 1e-4, "\(place) latitude")
        #expect(abs(signed.longitude - lon) < 1e-4, "\(place) longitude")
        #expect(CountryResolver.countryCode(latitude: signed.latitude,
                                            longitude: signed.longitude) == code)
    }

    @Test("The repaired photo captions the place")
    func captionsThePlace() throws {
        // The whole point, end to end: the caption the user could not see.
        let repaired = try #require(
            LocationMetadataWriter.data(plainJPEG(), addingLatitude: 48.8566, longitude: 2.3522))
        let caption = EXIFTokenParser.substitute(
            "{gps}", metadata: gpsDictionary(of: repaired), gpsFormat: .place)

        #expect(caption.hasPrefix("📍 "))
        #expect(caption.hasSuffix("🇫🇷"))
    }

    @Test("Nothing else about the file changes")
    func otherMetadataSurvives() throws {
        // Lossless by construction — the compressed image, the gain map and
        // every other auxiliary image are copied rather than re-encoded — so
        // the pixels and the rest of the metadata have to come through intact.
        let original = plainJPEG()
        let repaired = try #require(
            LocationMetadataWriter.data(original, addingLatitude: 10, longitude: 20))

        func properties(_ data: Data) -> [CFString: Any] {
            let source = CGImageSourceCreateWithData(data as CFData, nil)!
            return CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        }
        let before = properties(original)
        let after = properties(repaired)
        #expect(after[kCGImagePropertyPixelWidth] as? Int == before[kCGImagePropertyPixelWidth] as? Int)
        #expect(after[kCGImagePropertyPixelHeight] as? Int == before[kCGImagePropertyPixelHeight] as? Int)
        #expect(CGImageSourceGetType(CGImageSourceCreateWithData(repaired as CFData, nil)!)
                == CGImageSourceGetType(CGImageSourceCreateWithData(original as CFData, nil)!))
    }

    @Test("An impossible coordinate is refused rather than written",
          arguments: [(91.0, 0.0), (-91.0, 0.0), (0.0, 181.0), (Double.nan, 0.0),
                      (0.0, Double.infinity)])
    func refusesNonsense(lat: Double, lon: Double) {
        #expect(LocationMetadataWriter.data(plainJPEG(), addingLatitude: lat, longitude: lon) == nil)
    }

    @Test("Data that is not an image is refused")
    func refusesNonImage() {
        #expect(LocationMetadataWriter.data(
            Data("not an image".utf8), addingLatitude: 10, longitude: 20) == nil)
    }

    @Test("A photo that already has a coordinate is left alone")
    func existingCoordinateIsDetected() throws {
        let once = try #require(
            LocationMetadataWriter.data(plainJPEG(), addingLatitude: 35.6762, longitude: 139.6503))
        #expect(LocationMetadataWriter.hasCoordinate(in: once),
                "the caller skips the library lookup entirely for this file")
    }

    /// A JPEG carrying `properties`, the way a camera or an editing app writes one.
    private func jpeg(_ properties: [CFString: Any]) -> Data {
        let image = TestImageFactory.solidColorImage(
            color: CGColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1), size: CGSize(width: 64, height: 48)).0
        let out = NSMutableData()
        let dest = CGImageDestinationCreateWithData(out, "public.jpeg" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, properties as CFDictionary)
        CGImageDestinationFinalize(dest)
        return out as Data
    }

    private func properties(of data: Data) -> [CFString: Any] {
        CGImageSourceCreateWithData(data as CFData, nil)
            .flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any] } ?? [:]
    }

    @Test("An edit that lost its EXIF gets the camera back from the original")
    func fillsCameraFromOriginal() throws {
        // What Photos shows for an edited photo comes from the library; the
        // picked copy of some apps' edits has none of it.
        let original = jpeg([
            kCGImagePropertyOrientation: 6,
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "Apple", kCGImagePropertyTIFFModel: "iPhone XS"],
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifFNumber: 1.8, kCGImagePropertyExifISOSpeedRatings: [25]],
        ])
        let edit = jpeg([kCGImagePropertyOrientation: 1])
        #expect(!LocationMetadataWriter.hasCameraInfo(in: edit))

        let repaired = try #require(LocationMetadataWriter.data(edit, fillingMetadataFrom: original))
        #expect(LocationMetadataWriter.hasCameraInfo(in: repaired))
        let p = properties(of: repaired)
        let tiff = try #require(p[kCGImagePropertyTIFFDictionary] as? [CFString: Any])
        #expect(tiff[kCGImagePropertyTIFFModel] as? String == "iPhone XS")
        let exif = try #require(p[kCGImagePropertyExifDictionary] as? [CFString: Any])
        #expect(exif[kCGImagePropertyExifFNumber] as? Double == 1.8)
        // The edit's own pixels decide which way up it is, never the original's.
        #expect(p[kCGImagePropertyOrientation] as? Int == 1)
    }

    @Test("Nothing to fill leaves the caller's bytes alone")
    func nothingToFill() {
        let both = jpeg([kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFModel: "iPhone XS"]])
        #expect(LocationMetadataWriter.data(both, fillingMetadataFrom: both) == nil)
    }
}
