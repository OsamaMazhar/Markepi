import Testing
import CoreImage
import ImageIO
import Foundation
@testable import WatermarkCore

/// Tests for `DeviceMetadataProvider.caption(prefix:fields:metadata:)`, the
/// structured white-frame caption builder that assembles a prefix plus the
/// user-selected metadata fields.
@Suite("Caption builder")
struct CaptionBuilderTests {

    /// Metadata with a camera model plus a couple of EXIF shooting values.
    private func richMetadata() -> [String: Any] {
        let tiffKey = kCGImagePropertyTIFFDictionary as String
        let modelKey = kCGImagePropertyTIFFModel as String
        let exifKey = kCGImagePropertyExifDictionary as String
        return [
            tiffKey: [modelKey: "iPhone 16 Pro"],
            exifKey: [
                "FNumber": 1.8 as Double,
                "FocalLength": 24.0 as Double,
                "ISOSpeedRatings": [100],
            ],
        ]
    }

    @Test("Prefix is placed before the selected fields")
    func prefixPrecedesFields() {
        let caption = DeviceMetadataProvider.caption(
            prefix: "Shot on",
            fields: [.cameraModel],
            metadata: richMetadata()
        )
        #expect(caption == "Shot on · iPhone 16 Pro")
    }

    @Test("Fields render in canonical order regardless of selection order")
    func canonicalFieldOrder() {
        // Selected out of order: aperture before camera model.
        let caption = DeviceMetadataProvider.caption(
            prefix: "",
            fields: [.aperture, .cameraModel, .focalLength],
            metadata: richMetadata()
        )
        // Canonical order is cameraModel, focalLength, aperture.
        #expect(caption == "iPhone 16 Pro · 24mm · f/1.8")
    }

    @Test("Missing metadata fields are dropped, not shown as --")
    func missingFieldsDropped() {
        // Request a field with no backing metadata (GPS) alongside present ones.
        let caption = DeviceMetadataProvider.caption(
            prefix: "",
            fields: [.cameraModel, .gps],
            metadata: richMetadata()
        )
        #expect(caption == "iPhone 16 Pro")
        #expect(!caption.contains("--"))
    }

    @Test("Empty prefix and no resolvable fields yields an empty caption")
    func emptyCaption() {
        let caption = DeviceMetadataProvider.caption(
            prefix: "   ",
            fields: [.gps],
            metadata: [:]
        )
        #expect(caption.isEmpty)
    }

    @Test("Prefix-only caption renders just the prefix")
    func prefixOnly() {
        let caption = DeviceMetadataProvider.caption(
            prefix: "© 2026 Osama",
            fields: [],
            metadata: [:]
        )
        #expect(caption == "© 2026 Osama")
    }

    @Test("Prefix supports EXIF token substitution")
    func prefixTokenSubstitution() {
        let caption = DeviceMetadataProvider.caption(
            prefix: "{camera_model} —",
            fields: [.aperture],
            metadata: richMetadata()
        )
        #expect(caption == "iPhone 16 Pro — · f/1.8")
    }

    @Test("Default config caption fields match the shooting-details set")
    func defaultFields() {
        let config = WhiteFrameConfig(isEnabled: true)
        #expect(config.captionFields == WhiteFrameConfig.defaultCaptionFields)
        #expect(config.captionPrefix.isEmpty)
    }

    @Test("WhiteFrameConfig round-trips caption prefix and fields via Codable")
    func codableRoundTrip() throws {
        let original = WhiteFrameConfig(
            isEnabled: true,
            captionPrefix: "Shot on",
            captionFields: [.cameraModel, .date]
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WhiteFrameConfig.self, from: data)
        #expect(decoded.captionPrefix == "Shot on")
        #expect(decoded.captionFields == [.cameraModel, .date])
    }

    @Test("Legacy config JSON without caption keys decodes with default fields")
    func legacyDecodeFallback() throws {
        // Simulate a saved config from before captionPrefix/captionFields existed.
        let legacyJSON = """
        {
          "isEnabled": true,
          "frameWidthRatio": 0.04,
          "metadataTextEnabled": true,
          "textFontSizeRatio": 0.018,
          "textColorRGBA": [0.333, 0.333, 0.333, 1.0]
        }
        """
        let data = Data(legacyJSON.utf8)
        let decoded = try JSONDecoder().decode(WhiteFrameConfig.self, from: data)
        #expect(decoded.captionPrefix.isEmpty)
        #expect(decoded.captionFields == WhiteFrameConfig.defaultCaptionFields)
    }
}
