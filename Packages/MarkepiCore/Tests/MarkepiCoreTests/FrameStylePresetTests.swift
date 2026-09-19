import Foundation
import Testing
@testable import MarkepiCore

/// Each frame style keeps its own settings, so a strip showing one photo in
/// every style shows four different frames rather than the same one four times.
///
/// The rule lives on `WatermarkConfiguration` rather than in a view because two
/// surfaces drive it — the style dropdown and the style strip — and a third
/// (the share extension) shares the settings rows.
@Suite("Per-style frame settings")
struct FrameStylePresetTests {

    private func enabled(_ style: FrameStyle = .classic) -> WatermarkConfiguration {
        WatermarkConfiguration(whiteFrame: WhiteFrameConfig(isEnabled: true, style: style))
    }

    // MARK: - Switching

    @Test("Switching style remembers what the last one was set to")
    func switchingRemembers() {
        var config = enabled(.classic)
        config.editFrame { $0.borderMillimetres = 14 }
        config.selectFrameStyle(.gallery)
        config.editFrame { $0.borderMillimetres = 4 }

        #expect(config.whiteFrame?.borderMillimetres == 4)
        config.selectFrameStyle(.classic)
        #expect(config.whiteFrame?.borderMillimetres == 14, "classic's own border came back")
        #expect(config.frameConfig(for: .gallery).borderMillimetres == 4)
    }

    @Test("A style nobody has visited inherits what is on screen")
    func unvisitedStyleInherits() {
        // This is what makes the strip worth looking at on first open: the
        // user's own border and caption, drawn in each frame.
        var config = enabled(.classic)
        config.editFrame { $0.borderMillimetres = 11 }

        for style in FrameStyle.allCases {
            #expect(config.frameConfig(for: style).borderMillimetres == 11,
                    "\(style.rawValue) should start from the settings on screen")
            #expect(config.frameConfig(for: style).style == style)
        }
    }

    @Test("An inherited style takes its own default caption size")
    func inheritedCaptionFollowsTheStyle() {
        // Classic's caption sits inside the border and gallery's in a band
        // three times as thick, so a default-sized caption follows the style.
        var config = enabled(.classic)
        #expect(config.frameConfig(for: .print).captionTextMillimetres
                == WhiteFrameConfig.defaultCaptionMillimetres(for: .print))

        // A size the user actually chose is carried across untouched.
        config.editFrame { $0.captionTextMillimetres = 9 }
        #expect(config.frameConfig(for: .print).captionTextMillimetres == 9)
    }

    @Test("Switching to the style already on screen changes nothing")
    func switchingToTheSameStyleIsANoOp() {
        var config = enabled(.gallery)
        config.editFrame { $0.borderMillimetres = 6 }
        config.selectFrameStyle(.gallery)
        #expect(config.whiteFrame?.borderMillimetres == 6)
        #expect(config.frameStylePresets.isEmpty, "nothing was left behind")
    }

    // MARK: - Apply to all

    @Test("With apply-to-all off an edit reaches only the style on screen")
    func editIsStyleLocal() {
        var config = enabled(.classic)
        config.applyFrameEditsToAllStyles = false
        config.selectFrameStyle(.gallery)      // classic remembered at its defaults
        config.editFrame { $0.borderMillimetres = 20 }

        #expect(config.frameConfig(for: .gallery).borderMillimetres == 20)
        #expect(config.frameConfig(for: .classic).borderMillimetres != 20)
    }

    @Test("With apply-to-all on an edit reaches every style")
    func editReachesEveryStyle() {
        var config = enabled(.classic)
        config.applyFrameEditsToAllStyles = true
        config.editFrame { $0.borderMillimetres = 20 }

        for style in FrameStyle.allCases {
            #expect(config.frameConfig(for: style).borderMillimetres == 20,
                    "\(style.rawValue) missed the edit")
        }
    }

    @Test("Applying to all does not apply the edit twice")
    func noDoubleApplication() {
        // The trap: a style nobody has visited derives from the style on
        // screen. Derive it *after* the edit and it takes the edit again —
        // which for anything that toggles lands back where it started.
        var config = enabled(.classic)
        config.applyFrameEditsToAllStyles = true
        let before = config.frameConfig(for: .gallery).keylineEnabled

        config.editFrame { $0.keylineEnabled.toggle() }

        #expect(config.whiteFrame?.keylineEnabled == !before)
        #expect(config.frameConfig(for: .gallery).keylineEnabled == !before,
                "gallery's keyline was toggled twice and came back")
    }

    @Test("Applying to all keeps each style's identity")
    func applyingToAllKeepsTheStyle() {
        var config = enabled(.classic)
        config.applyFrameEditsToAllStyles = true
        config.editFrame { $0.borderMillimetres = 12 }
        for style in FrameStyle.allCases {
            #expect(config.frameConfig(for: style).style == style)
        }
    }

    @Test("An edit never changes which style is on screen")
    func editCannotChangeTheStyle() {
        // Style changes have to go through `selectFrameStyle`, which is what
        // stores the settings of the style being left.
        var config = enabled(.gallery)
        config.editFrame { $0.style = .print }
        #expect(config.whiteFrame?.style == .gallery)
    }

    // MARK: - The frame's own switch

    @Test("Turning the frame off stays off across a style change")
    func disabledStaysDisabled() {
        // `isEnabled` is the feature's switch, not a per-style memory: stored
        // per style, switching style would silently turn the frame back on.
        var config = enabled(.classic)
        config.selectFrameStyle(.gallery)      // classic remembered while enabled
        config.editFrame { $0.isEnabled = false }
        config.selectFrameStyle(.classic)

        #expect(config.whiteFrame?.isEnabled == false)
        for style in FrameStyle.allCases {
            #expect(config.frameConfig(for: style).isEnabled == false)
        }
    }

    // MARK: - Persistence

    @Test("Per-style settings survive a saved template")
    func presetsRoundTrip() throws {
        var config = enabled(.classic)
        config.editFrame { $0.borderMillimetres = 15 }
        config.selectFrameStyle(.banner)
        config.editFrame { $0.borderMillimetres = 3 }
        config.applyFrameEditsToAllStyles = true

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(WatermarkConfiguration.self, from: data)

        #expect(decoded.whiteFrame?.style == .banner)
        #expect(decoded.whiteFrame?.borderMillimetres == 3)
        #expect(decoded.frameConfig(for: .classic).borderMillimetres == 15)
        #expect(decoded.applyFrameEditsToAllStyles)
    }

    @Test("A template saved before per-style settings existed still loads")
    func legacyTemplateDecodes() throws {
        // Built by stripping the new keys out of a real encode, so it stays a
        // true "older build wrote this" payload rather than hand-written JSON
        // that might not match the encoder at all.
        var config = enabled(.gallery)
        config.applyFrameEditsToAllStyles = true
        config.selectFrameStyle(.print)
        var json = try #require(try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(config)) as? [String: Any])
        json.removeValue(forKey: "frameStylePresets")
        json.removeValue(forKey: "applyFrameEditsToAllStyles")

        let decoded = try JSONDecoder().decode(
            WatermarkConfiguration.self,
            from: try JSONSerialization.data(withJSONObject: json))

        #expect(decoded.frameStylePresets.isEmpty)
        #expect(!decoded.applyFrameEditsToAllStyles, "an older template edits one style at a time")
        // And the style it was saved in is still the style it opens in.
        #expect(decoded.whiteFrame?.style == .print)
    }

    @Test("A config that never left its first style writes no presets")
    func noPresetsNoPayload() throws {
        let data = try JSONEncoder().encode(enabled(.classic))
        let json = String(decoding: data, as: UTF8.self)
        #expect(!json.contains("frameStylePresets"))
    }
}
