import CoreGraphics
import Foundation
import Testing
@testable import MarkepiCore

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

    @Test("Only the device heads a line by default; the list fills the rest")
    func defaultSlotsLeaveRoomForTheList() {
        // Pinning entries to lines fought the Include list: a pinned date drew
        // even when the exposure it stands in for was there, and a pinned place
        // sat across the band from the device it belongs beside.
        let config = WhiteFrameConfig()
        #expect(config.leftPrimary == .field(.cameraModel))
        #expect(config.leftSecondary == .empty)
        #expect(config.rightPrimary == .empty)
        #expect(config.rightSecondary == .empty)
    }

    @Test("A new frame captions where the photo was taken")
    func locationIsOnByDefault() {
        // Reported as "I can't see the location pin and flag anywhere": it
        // rendered correctly everywhere, but no default turned it on, so it was
        // only ever visible to someone who went looking for the checkbox.
        #expect(WhiteFrameConfig.defaultCaptionFields.contains(.gps))
        #expect(WhiteFrameConfig().captionFields.contains(.gps))

        // It reaches the caption through the list rather than a pinned slot,
        // which is what puts it under the device rather than across from it.
        let meta: [String: Any] = [
            "{TIFF}": ["Make": "Apple", "Model": "iPhone 16 Pro"],
            "{GPS}": ["Latitude": 48.8566, "LatitudeRef": "N",
                      "Longitude": 2.3522, "LongitudeRef": "E"] as [String: Any],
        ]
        #expect(WhiteFrameRenderer.resolveGalleryCaption(
            config: WhiteFrameConfig(isEnabled: true), metadata: meta)
            .leftSecondary?.contains("🇫🇷") == true)
    }

    @Test("The pixel dimensions are not a default; the date is")
    func defaultFieldsFavourTheDate() {
        // "Instead of size, add date properly by default": when a photo was
        // taken is part of what a caption is for; how many pixels wide it is
        // is a fact about the file.
        #expect(WhiteFrameConfig.defaultCaptionFields.contains(.date))
        #expect(!WhiteFrameConfig.defaultCaptionFields.contains(.dimensions))
    }

    // MARK: - CaptionSlot

    @Test("Every CaptionSlot case survives a Codable round trip")
    func captionSlotRoundTrips() throws {
        let cases: [CaptionSlot] = [
            .field(.cameraModel),
            .field(.gps),
            .text("@a_handle"),
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

/// The live preview re-renders only when its identifier changes, so a frame
/// field missing from `previewKey` edits a config the user never sees applied.
/// One case per field, because the failure is silent: the control moves, the
/// picture does not.
@Suite("Frame preview freshness")
struct FramePreviewKeyTests {

    /// Every render-affecting field, paired with a mutation that changes it.
    private static let mutations: [(String, @Sendable (inout WhiteFrameConfig) -> Void)] = [
        ("isEnabled", { $0.isEnabled.toggle() }),
        ("metadataTextEnabled", { $0.metadataTextEnabled.toggle() }),
        ("captionPrefix", { $0.captionPrefix = "Shot on" }),
        ("captionFields", { $0.captionFields = [.iso] }),
        ("customAttributionText", { $0.customAttributionText = "verbatim" }),
        ("textColor", { $0.textColor = CGColor(red: 1, green: 0, blue: 0, alpha: 1) }),
        ("style", { $0.style = $0.style == .classic ? .gallery : .classic }),
        ("logoEnabled", { $0.logoEnabled.toggle() }),
        ("outputDPI", { $0.outputDPI = 600 }),
        ("borderMillimetres", { $0.borderMillimetres += 1 }),
        ("captionTextMillimetres", { $0.captionTextMillimetres += 1 }),
        ("logoHeightMillimetres", { $0.logoHeightMillimetres += 1 }),
        ("keylineEnabled", { $0.keylineEnabled.toggle() }),
        ("logoVariant", { $0.logoVariant = .monochrome }),
        ("shadow", { $0.shadow = .all }),
        ("gradientEnabled", { $0.gradientEnabled.toggle() }),
        ("creditPrefixText", { $0.creditPrefixText = "© Someone" }),
        ("creditSuffixText", { $0.creditSuffixText = "2026" }),
        ("leftPrimary", { $0.leftPrimary = .field(.iso) }),
        ("leftSecondary", { $0.leftSecondary = .field(.date) }),
        ("rightPrimary", { $0.rightPrimary = .text("@handle") }),
        ("rightSecondary", { $0.rightSecondary = .field(.format) }),
    ]

    @Test("Changing any frame field changes the preview key",
          arguments: FramePreviewKeyTests.mutations.indices)
    func everyFieldIsCovered(index: Int) {
        let (name, mutate) = Self.mutations[index]
        let base = WhiteFrameConfig(isEnabled: true)
        var changed = base
        mutate(&changed)
        #expect(changed.previewKey != base.previewKey,
                "\(name) does not reach previewKey, so the preview will go stale when it changes")
    }

    @Test("A wider mat carries the caption and the mark with it")
    func sizesFollowTheMat() {
        var config = WhiteFrameConfig(isEnabled: true)
        let caption = config.captionTextMillimetres
        let mark = config.logoHeightMillimetres

        config.borderMillimetres *= 2
        #expect(config.captionTextMillimetres == caption * 2)
        #expect(config.logoHeightMillimetres == mark * 2)
        // And the preview knows, or it would show the old size.
        #expect(config.previewKey != WhiteFrameConfig(isEnabled: true).previewKey)
    }

    @Test("A size the user set is carried by the mat, not left behind")
    func aSetSizeRidesAlong() {
        // "It should also be increased according to the frame width unless the
        // user later reduces it manually": a number chosen for a narrow mat is
        // a number for that mat, so it keeps its proportion rather than
        // staying put while everything around it grows.
        var config = WhiteFrameConfig(isEnabled: true)
        config.captionTextMillimetres = 7
        config.borderMillimetres *= 2
        #expect(config.captionTextMillimetres == 14)
        #expect(config.logoHeightMillimetres > FrameMetrics.defaultMarkMillimetres,
                "the mark they did not touch follows too")

        // And setting it again is what re-fixes the proportion.
        config.captionTextMillimetres = 5
        #expect(config.captionTextMillimetres == 5)
    }

    @Test("Switching style keeps a set size and re-derives an unset one")
    func styleChangeRespectsWhoSetIt() {
        var settings = WatermarkConfiguration(watermarks: [],
                                              whiteFrame: WhiteFrameConfig(isEnabled: true, style: .gallery))
        settings.selectFrameStyle(.classic)
        #expect(settings.whiteFrame?.captionTextMillimetres
                == WhiteFrameConfig.defaultCaptionMillimetres(for: .classic))

        settings.editFrame { $0.captionTextMillimetres = 9 }
        settings.selectFrameStyle(.gallery)
        settings.selectFrameStyle(.classic)
        #expect(settings.whiteFrame?.captionTextMillimetres == 9)
    }

    @Test("A template written before sizes followed the mat is not frozen")
    func legacyTemplateStillFollows() throws {
        // Every old template names a size. Read as hand-set, the caption would
        // never move again — so a size still at its default reads as untouched.
        let config = WhiteFrameConfig(isEnabled: true, style: .gallery)
        var json = try JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(config)) as! [String: Any]
        json.removeValue(forKey: "captionMillimetresManual")
        json.removeValue(forKey: "logoMillimetresManual")

        var decoded = try JSONDecoder().decode(
            WhiteFrameConfig.self, from: try JSONSerialization.data(withJSONObject: json))
        decoded.borderMillimetres *= 2
        #expect(decoded.captionTextMillimetres == config.captionTextMillimetres * 2)

        // But one that names a size of its own keeps it.
        json["captionTextMillimetres"] = 11.0
        var custom = try JSONDecoder().decode(
            WhiteFrameConfig.self, from: try JSONSerialization.data(withJSONObject: json))
        #expect(custom.captionTextMillimetres == 11)
        // Carried by the mat like any other size the user chose.
        custom.borderMillimetres *= 2
        #expect(custom.captionTextMillimetres == 20, "clamped at the ceiling")
    }

    @Test("An untouched config keys the same twice")
    func keyIsStable() {
        let config = WhiteFrameConfig(isEnabled: true)
        #expect(config.previewKey == config.previewKey)
    }

    @Test("Every stored field appears in the key")
    func mutationListCoversTheStruct() throws {
        // Catches a field added to the config but not to the list above: the
        // encoded form is the field inventory, so compare against it.
        let json = try JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(WhiteFrameConfig(isEnabled: true))) as? [String: Any]
        let encodedKeys = Set((json ?? [:]).keys)
            .subtracting(["textColorRGBA"])  // covered as "textColor"
            // The "did the user set this" flags are the encoded half of the
            // two sizes: setting either size raises its flag, and the key
            // carries the millimetres that result, not the flag.
            .subtracting(["captionMillimetresManual", "logoMillimetresManual"])
            .union(["textColor"])
        let covered = Set(Self.mutations.map(\.0))
        #expect(encodedKeys.subtracting(covered).isEmpty,
                "frame fields with no preview-key case: \(encodedKeys.subtracting(covered).sorted())")
    }
}
