import CoreGraphics
import Foundation
import Testing
@testable import WatermarkCore

/// Covers the frame-style additions to `WhiteFrameConfig`: the style itself,
/// the four gallery caption slots, the keyline, the logo variant, and — the
/// part most likely to bite — that a template saved before any of this existed
/// still decodes.
@Suite("Frame style config")
struct FrameStyleConfigTests {

    // MARK: - Defaults

    @Test("A fresh frame is the gallery style")
    func defaultStyleIsGallery() {
        #expect(WhiteFrameConfig().style == .gallery)
    }

    @Test("A template saved before styles existed still decodes to classic")
    func legacyTemplateStaysClassic() throws {
        // It was authored against the old look, so promoting it to gallery
        // would silently restyle someone's saved work.
        let legacy = """
        {"isEnabled": true, "frameWidthRatio": 0.04, "metadataTextEnabled": true,
         "textFontSizeRatio": 0.018, "textColorRGBA": [0.3, 0.3, 0.3, 1.0]}
        """
        #expect(try JSONDecoder().decode(WhiteFrameConfig.self, from: Data(legacy.utf8)).style == .classic)
    }

    @Test("Keyline is on and the mark is colour by default")
    func defaultKeylineAndVariant() {
        let config = WhiteFrameConfig()
        #expect(config.keylineEnabled)
        #expect(config.logoVariant == .color)
    }

    @Test("Gallery slot defaults reproduce the reference layout")
    func defaultSlotsMatchReference() {
        let config = WhiteFrameConfig()
        #expect(config.leftPrimary == .field(.cameraModel))
        #expect(config.leftSecondary == .field(.date))
        // The handle is the photographer's to type, so it starts as empty free
        // text rather than a metadata field.
        #expect(config.rightPrimary == .text(""))
        // The EXIF lens string already carries focal length and aperture, so
        // composing it with those fields as well printed both twice.
        #expect(config.rightSecondary == .field(.lens))
    }

    // MARK: - CaptionSlot

    @Test("Every CaptionSlot case survives a Codable round trip")
    func captionSlotRoundTrips() throws {
        let cases: [CaptionSlot] = [
            .field(.cameraModel),
            .field(.gps),
            .text("@the_casual_iphonographer"),
            .text("{lens} {focal_length} {aperture}"),
            .text(""),
            .empty,
        ]
        for slot in cases {
            let data = try JSONEncoder().encode(slot)
            let decoded = try JSONDecoder().decode(CaptionSlot.self, from: data)
            #expect(decoded == slot, "\(slot) did not round trip")
        }
    }

    @Test("A slot naming a field this build does not know is dropped, not fatal")
    func unknownFieldDecodesToEmpty() throws {
        let data = Data("\"field:teleporter\"".utf8)
        #expect(try JSONDecoder().decode(CaptionSlot.self, from: data) == .empty)
    }

    @Test("An untagged legacy value is read as typed text")
    func untaggedValueDecodesAsText() throws {
        let data = Data("\"Shot on my phone\"".utf8)
        #expect(try JSONDecoder().decode(CaptionSlot.self, from: data) == .text("Shot on my phone"))
    }

    @Test("isEmpty distinguishes a slot that can never render from one that can")
    func isEmptyIsAboutRenderability() {
        #expect(CaptionSlot.empty.isEmpty)
        #expect(CaptionSlot.text("").isEmpty)
        #expect(CaptionSlot.text("   ").isEmpty)
        #expect(!CaptionSlot.text("@handle").isEmpty)
        // A field is never empty by configuration — whether it renders depends
        // on the photo's metadata, which is resolved later.
        #expect(!CaptionSlot.field(.iso).isEmpty)
    }

    // MARK: - Enums

    @Test("LogoVariant round trips")
    func logoVariantRoundTrips() throws {
        for variant in LogoVariant.allCases {
            let data = try JSONEncoder().encode(variant)
            #expect(try JSONDecoder().decode(LogoVariant.self, from: data) == variant)
        }
    }

    @Test("A style written by a newer build falls back to classic")
    func unknownStyleFallsBackToClassic() throws {
        let data = Data("\"holographic\"".utf8)
        #expect(try JSONDecoder().decode(FrameStyle.self, from: data) == .classic)
    }

    // MARK: - Backward compatibility

    @Test("A template saved before frame styles existed still decodes")
    func legacyTemplateDecodes() throws {
        // Exactly the keys a pre-styles build wrote — no style, no slots, no
        // keyline, no variant.
        let legacy = """
        {
          "isEnabled": true,
          "frameWidthRatio": 0.04,
          "metadataTextEnabled": true,
          "textFontSizeRatio": 0.018,
          "textColorRGBA": [0.333, 0.333, 0.333, 1.0]
        }
        """
        let config = try JSONDecoder().decode(WhiteFrameConfig.self, from: Data(legacy.utf8))

        #expect(config.isEnabled)
        #expect(config.style == .classic)
        // Absent in the saved JSON, so it decodes to false rather than picking
        // up today's default — the template was authored without one.
        #expect(config.keylineEnabled == false)
        #expect(config.logoVariant == .color)
        // The gallery slots come back at their defaults, ready if the user ever
        // switches this template to gallery.
        #expect(config.leftPrimary == WhiteFrameConfig.defaultLeftPrimary)
        #expect(config.rightSecondary == WhiteFrameConfig.defaultRightSecondary)
    }

    @Test("A full config round trips with every new field intact")
    func fullConfigRoundTrips() throws {
        let original = WhiteFrameConfig(
            isEnabled: true,
            style: .gallery,
            keylineEnabled: true,
            logoVariant: .monochrome,
            leftPrimary: .field(.lens),
            leftSecondary: .empty,
            rightPrimary: .text("@someone"),
            rightSecondary: .text("{iso}")
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WhiteFrameConfig.self, from: data)

        #expect(decoded.style == .gallery)
        #expect(decoded.keylineEnabled)
        #expect(decoded.logoVariant == .monochrome)
        #expect(decoded.leftPrimary == .field(.lens))
        #expect(decoded.leftSecondary == .empty)
        #expect(decoded.rightPrimary == .text("@someone"))
        #expect(decoded.rightSecondary == .text("{iso}"))
    }
}
