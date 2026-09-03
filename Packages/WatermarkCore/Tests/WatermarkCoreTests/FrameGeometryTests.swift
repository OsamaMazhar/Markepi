import CoreGraphics
import ImageIO
import Foundation
import Testing
@testable import WatermarkCore

/// The mat sits outside the photo, so geometry decides the exported size.
/// Both the photo and video paths derive from `FrameGeometry`, which makes
/// these tests the shared contract between them.
@Suite("Frame geometry")
struct FrameGeometryTests {

    static let portrait = CGSize(width: 3024, height: 4032)
    static let landscape = CGSize(width: 4032, height: 3024)

    static func config(style: FrameStyle = .classic, keyline: Bool = false) -> WhiteFrameConfig {
        WhiteFrameConfig(isEnabled: true, style: style, keylineEnabled: keyline)
    }

    // MARK: - Outside, not over

    @Test("The framed canvas is larger than the source in both dimensions")
    func framedCanvasGrows() {
        for style in FrameStyle.allCases {
            for size in [Self.portrait, Self.landscape] {
                let g = FrameGeometry(config: Self.config(style: style), sourceSize: size)
                #expect(g.framedSize.width > size.width, "\(style) \(size) did not grow in width")
                #expect(g.framedSize.height > size.height, "\(style) \(size) did not grow in height")
            }
        }
    }

    @Test("The photo keeps its full size inside the mat")
    func photoIsNeverCropped() {
        for style in FrameStyle.allCases {
            let g = FrameGeometry(config: Self.config(style: style), sourceSize: Self.portrait)
            #expect(g.photoRect.size == Self.portrait)
            // And it sits wholly inside the canvas.
            #expect(g.photoRect.minX >= 0)
            #expect(g.photoRect.minY >= 0)
            #expect(g.photoRect.maxX <= g.framedSize.width)
            #expect(g.photoRect.maxY <= g.framedSize.height)
        }
    }

    // MARK: - Style differences

    @Test("Classic mats are uniform on all four edges")
    func classicIsUniform() {
        let g = FrameGeometry(config: Self.config(style: .classic), sourceSize: Self.portrait)
        #expect(g.top == g.left)
        #expect(g.left == g.right)
        #expect(g.bottom == g.top)
    }

    @Test("Gallery's bottom band is taller than its other edges")
    func galleryBottomIsTaller() {
        for size in [Self.portrait, Self.landscape] {
            let g = FrameGeometry(config: Self.config(style: .gallery), sourceSize: size)
            #expect(g.bottom > g.top, "\(size): bottom \(g.bottom) should exceed top \(g.top)")
            #expect(g.left == g.right)
            #expect(g.top == g.left)
        }
    }

    @Test("Gallery's bottom band is tall enough for two lines of caption")
    func galleryBottomFitsTwoLines() {
        let g = FrameGeometry(config: Self.config(style: .gallery), sourceSize: Self.portrait)
        // Two lines at 1.25x plus the gap between them, with nothing left for
        // padding, is the absolute floor.
        let bareMinimum = g.captionFontSize * (1.25 * 2 + 0.25)
        #expect(g.captionBand.height > bareMinimum)
    }

    // MARK: - Resolution independence

    @Test("Classic proportions hold when the same photo is exported at two sizes")
    func classicProportionsHoldAcrossResolutions() {
        // Classic measures its mat as a proportion of the photo, so a frame
        // looks the same at any export size. Gallery deliberately does not —
        // it measures in millimetres, covered in the millimetre suite.
        let small = CGSize(width: 1512, height: 2016)
        let large = CGSize(width: 6048, height: 8064)
        let a = FrameGeometry(config: Self.config(style: .classic), sourceSize: small)
        let b = FrameGeometry(config: Self.config(style: .classic), sourceSize: large)

        let matRatioA = a.left / min(small.width, small.height)
        let matRatioB = b.left / min(large.width, large.height)
        #expect(abs(matRatioA - matRatioB) < 0.001, "mat ratio drifted")

        let fontRatioA = a.captionFontSize / min(small.width, small.height)
        let fontRatioB = b.captionFontSize / min(large.width, large.height)
        #expect(abs(fontRatioA - fontRatioB) < 0.0001, "font ratio drifted")
    }

    @Test("Gallery's caption is sized from its physical mat, so the two stay in step")
    func galleryCaptionFollowsItsMat() {
        // Text that kept scaling with pixels would outgrow a millimetre border
        // on a large photo and stop the band tracking the setting.
        let small = FrameGeometry(config: Self.config(style: .gallery), sourceSize: CGSize(width: 1512, height: 2016))
        let large = FrameGeometry(config: Self.config(style: .gallery), sourceSize: CGSize(width: 6048, height: 8064))
        #expect(small.captionFontSize == large.captionFontSize)
        #expect(large.captionFontSize < large.bottom, "caption must fit its band")
    }

    // MARK: - Even dimensions

    @Test("The framed canvas is always even, which video encoders require")
    func framedSizeIsEven() {
        // Odd sources, odd mats — the combinations most likely to produce an
        // odd canvas if the rounding were wrong.
        let awkward = [
            CGSize(width: 1001, height: 1333),
            CGSize(width: 999, height: 999),
            CGSize(width: 4001, height: 3001),
            CGSize(width: 100, height: 101),
        ]
        for style in FrameStyle.allCases {
            for size in awkward {
                let g = FrameGeometry(config: Self.config(style: style), sourceSize: size)
                #expect(Int(g.framedSize.width) % 2 == 0, "\(style) \(size): odd width \(g.framedSize.width)")
                #expect(Int(g.framedSize.height) % 2 == 0, "\(style) \(size): odd height \(g.framedSize.height)")
            }
        }
    }

    @Test("Rounding to even steals from the mat, never from the photo")
    func roundingNeverEatsThePhoto() {
        let g = FrameGeometry(config: Self.config(), sourceSize: CGSize(width: 1001, height: 1333))
        #expect(g.photoRect.width == 1001)
        #expect(g.photoRect.height == 1333)
    }

    // MARK: - Keyline

    @Test("The keyline has no thickness when disabled")
    func keylineOffIsZero() {
        #expect(FrameGeometry(config: Self.config(keyline: false), sourceSize: Self.portrait).keylineWidth == 0)
    }

    @Test("The keyline scales with the source and is at least a pixel")
    func keylineScales() {
        let big = FrameGeometry(config: Self.config(keyline: true), sourceSize: Self.portrait)
        let tiny = FrameGeometry(config: Self.config(keyline: true), sourceSize: CGSize(width: 80, height: 60))
        #expect(big.keylineWidth > tiny.keylineWidth)
        #expect(tiny.keylineWidth >= 1, "a keyline thinner than a pixel would vanish")
    }

    @Test("The keyline is stroked outside the photo, so it covers none of it")
    func keylineStaysOffThePhoto() {
        let g = FrameGeometry(config: Self.config(keyline: true), sourceSize: Self.portrait)
        // Stroking `keylineRect` with `keylineWidth` paints from its inner edge
        // outward; the inner edge is exactly the photo boundary.
        let innerEdge = g.keylineRect.insetBy(dx: g.keylineWidth / 2, dy: g.keylineWidth / 2)
        #expect(innerEdge == g.photoRect)
    }

    @Test("The keyline available in every style")
    func keylineAppliesToBothStyles() {
        for style in FrameStyle.allCases {
            let g = FrameGeometry(config: Self.config(style: style, keyline: true), sourceSize: Self.portrait)
            #expect(g.keylineWidth > 0, "\(style) lost its keyline")
        }
    }

    // MARK: - Caption band

    @Test("The caption band clears the photo and sits within the side mats")
    func captionBandIsClearOfThePhoto() {
        let g = FrameGeometry(config: Self.config(style: .gallery, keyline: true), sourceSize: Self.portrait)
        #expect(g.captionBand.minY >= g.photoRect.maxY, "caption band overlaps the photo")
        #expect(g.captionBand.minX == g.left)
        #expect(g.captionBand.maxX <= g.framedSize.width - g.right + 0.001)
        #expect(g.captionBand.height > 0)
    }
}

/// The gallery style sizes its mat in millimetres — a physical size on paper
/// rather than a proportion of the photo.
@Suite("Frame geometry in millimetres")
struct FrameGeometryMillimetreTests {

    static let portrait = CGSize(width: 3024, height: 4032)

    static func gallery(mm: CGFloat = 5.0, keyline: Bool = false) -> WhiteFrameConfig {
        WhiteFrameConfig(isEnabled: true, style: .gallery,
                         borderMillimetres: mm, keylineEnabled: keyline)
    }

    @Test("Millimetres convert against the given resolution")
    func millimetresToPixels() {
        // 5mm at 300dpi = 5/25.4*300 = 59.055... -> 59
        #expect(FrameGeometry.pixels(millimetres: 5, dpi: 300) == 59)
        #expect(FrameGeometry.pixels(millimetres: 25.4, dpi: 300) == 300)
        #expect(FrameGeometry.pixels(millimetres: 10, dpi: 600) == 236)
    }

    @Test("A millimetre border is the same pixel size regardless of photo size")
    func mmIsPhysicalNotProportional() {
        let small = FrameGeometry(config: Self.gallery(), sourceSize: CGSize(width: 1000, height: 800))
        let large = FrameGeometry(config: Self.gallery(), sourceSize: CGSize(width: 8000, height: 6000))
        // This is the point of a physical unit, and the opposite of how classic
        // behaves: the same border measures the same on paper either way.
        #expect(small.left == large.left)
    }

    @Test("Classic stays proportional and ignores the millimetre setting")
    func classicIsUnaffected() {
        let a = WhiteFrameConfig(isEnabled: true, style: .classic, borderMillimetres: 5)
        let b = WhiteFrameConfig(isEnabled: true, style: .classic, borderMillimetres: 40)
        #expect(FrameGeometry(config: a, sourceSize: Self.portrait).left
                == FrameGeometry(config: b, sourceSize: Self.portrait).left)
    }

    @Test("A wider millimetre border widens every edge")
    func widerBorderWidensEdges() {
        let thin = FrameGeometry(config: Self.gallery(mm: 3), sourceSize: Self.portrait)
        let thick = FrameGeometry(config: Self.gallery(mm: 12), sourceSize: Self.portrait)
        #expect(thick.left > thin.left)
        #expect(thick.top > thin.top)
        #expect(thick.right > thin.right)
    }

    @Test("The bottom band tracks the millimetre border")
    func bottomTracksTheBorder() {
        let thin = FrameGeometry(config: Self.gallery(mm: 6), sourceSize: Self.portrait)
        let thick = FrameGeometry(config: Self.gallery(mm: 12), sourceSize: Self.portrait)
        #expect(thick.bottom > thin.bottom, "bottom should grow with the border setting")
        // And it stays the taller edge, which is what makes it a caption bar.
        for g in [thin, thick] {
            #expect(g.bottom > g.top)
        }
    }

    @Test("A very small border still leaves room for the caption")
    func tinyBorderDoesNotCrushTheCaption() {
        let g = FrameGeometry(config: Self.gallery(mm: 0.5), sourceSize: Self.portrait)
        let twoLines = g.captionFontSize * (1.25 * 2 + 0.25)
        #expect(g.captionBand.height > twoLines, "caption would be crushed")
    }

    @Test("Absurd border values are clamped rather than rejected")
    func borderIsClamped() {
        #expect(WhiteFrameConfig(borderMillimetres: -5).borderMillimetres == 0.5)
        #expect(WhiteFrameConfig(borderMillimetres: 500).borderMillimetres == 50)
    }

    // MARK: - Resolving DPI

    @Test("A print-intent resolution in the file is believed")
    func realDPIIsUsed() {
        #expect(FrameGeometry.resolveDPI(from: ["DPIWidth": 600]) == 600)
        #expect(FrameGeometry.resolveDPI(from: ["DPIWidth": 150]) == 150)
    }

    @Test("The JFIF default of 72 is not treated as a measurement")
    func junkDPIFallsBack() {
        // Almost every phone JPEG says 72 because that is the format default,
        // not because anyone measured. Believing it would make a 5mm border
        // 14px on an 8000px photo — indistinguishable from no border.
        #expect(FrameGeometry.resolveDPI(from: ["DPIWidth": 72]) == 300)
        #expect(FrameGeometry.resolveDPI(from: [:]) == 300)
    }

    @Test("Height resolution is used when width is missing")
    func fallsBackToHeightDPI() {
        #expect(FrameGeometry.resolveDPI(from: ["DPIHeight": 400]) == 400)
    }

    @Test("Resolution changes how many pixels a millimetre border takes")
    func dpiChangesPixelBorder() {
        let at300 = FrameGeometry(config: Self.gallery(), sourceSize: Self.portrait, dpi: 300)
        let at600 = FrameGeometry(config: Self.gallery(), sourceSize: Self.portrait, dpi: 600)
        #expect(at600.left > at300.left)
    }
}

/// Everything the gallery style measures is metric — border, caption text and
/// brand mark — so the parts stay in proportion on paper instead of one of
/// them scaling with pixels and outgrowing the others.
@Suite("Gallery metric sizing")
struct GalleryMetricSizingTests {

    static let small = CGSize(width: 1200, height: 900)
    static let large = CGSize(width: 8000, height: 6000)

    static func gallery(border: CGFloat = 5, caption: CGFloat = 2.5, logo: CGFloat = 4) -> WhiteFrameConfig {
        WhiteFrameConfig(isEnabled: true, style: .gallery,
                         borderMillimetres: border,
                         captionTextMillimetres: caption,
                         logoHeightMillimetres: logo)
    }

    @Test("Caption text is the same physical size whatever the photo's pixels")
    func captionIsPhysical() {
        let a = FrameGeometry(config: Self.gallery(), sourceSize: Self.small)
        let b = FrameGeometry(config: Self.gallery(), sourceSize: Self.large)
        #expect(a.captionFontSize == b.captionFontSize)
        #expect(a.captionFontSize == FrameGeometry.pixels(millimetres: 2.5, dpi: 300))
    }

    @Test("The brand mark is the same physical size whatever the photo's pixels")
    func logoIsPhysical() {
        let a = FrameGeometry(config: Self.gallery(), sourceSize: Self.small)
        let b = FrameGeometry(config: Self.gallery(), sourceSize: Self.large)
        #expect(a.logoHeight == b.logoHeight)
        #expect(a.logoHeight == FrameGeometry.pixels(millimetres: 4, dpi: 300))
    }

    @Test("Border, caption and mark scale together with resolution")
    func allThreeScaleTogether() {
        let at300 = FrameGeometry(config: Self.gallery(), sourceSize: Self.large, dpi: 300)
        let at600 = FrameGeometry(config: Self.gallery(), sourceSize: Self.large, dpi: 600)
        // Doubling the resolution doubles every physical measurement, so their
        // ratios to one another are unchanged — which is what stops any one of
        // them outgrowing the band. Compared in pixels with a pixel of slack:
        // each conversion rounds, and at small sizes that rounding is a larger
        // share of a ratio than it is of the measurement.
        #expect(abs(at600.left - at300.left * 2) <= 1)
        #expect(abs(at600.captionFontSize - at300.captionFontSize * 2) <= 1)
        #expect(abs(at600.logoHeight - at300.logoHeight * 2) <= 1)
    }

    @Test("Each metric setting moves only its own element")
    func settingsAreIndependent() {
        let base = FrameGeometry(config: Self.gallery(), sourceSize: Self.large)
        let bigText = FrameGeometry(config: Self.gallery(caption: 6), sourceSize: Self.large)
        let bigLogo = FrameGeometry(config: Self.gallery(logo: 12), sourceSize: Self.large)

        #expect(bigText.captionFontSize > base.captionFontSize)
        #expect(bigText.logoHeight == base.logoHeight)
        #expect(bigLogo.logoHeight > base.logoHeight)
        #expect(bigLogo.captionFontSize == base.captionFontSize)
        // The side mat is the border's business alone.
        #expect(bigText.left == base.left)
        #expect(bigLogo.left == base.left)
    }

    @Test("The band grows to clear an oversized caption or mark")
    func bandClearsItsContents() {
        // A tall mark or large text must not be crushed by a thin border.
        let tallLogo = FrameGeometry(config: Self.gallery(border: 2, logo: 25), sourceSize: Self.large)
        #expect(tallLogo.captionBand.height > tallLogo.logoHeight)

        let bigText = FrameGeometry(config: Self.gallery(border: 2, caption: 15), sourceSize: Self.large)
        #expect(bigText.captionBand.height > bigText.captionFontSize * 2.75)
    }

    @Test("Classic draws no mark and keeps proportional text")
    func classicIsUnaffectedByMetricSettings() {
        let config = WhiteFrameConfig(isEnabled: true, style: .classic,
                                      captionTextMillimetres: 15, logoHeightMillimetres: 25)
        let g = FrameGeometry(config: config, sourceSize: Self.large)
        #expect(g.logoHeight == 0)
        #expect(g.captionFontSize == Self.large.height * config.textFontSizeRatio)
    }

    @Test("Metric settings are clamped and survive a round trip")
    func metricSettingsClampAndPersist() throws {
        #expect(WhiteFrameConfig(captionTextMillimetres: -1).captionTextMillimetres == 0.5)
        #expect(WhiteFrameConfig(captionTextMillimetres: 999).captionTextMillimetres == 20)
        #expect(WhiteFrameConfig(logoHeightMillimetres: 999).logoHeightMillimetres == 30)

        let original = Self.gallery(border: 7, caption: 3, logo: 6)
        let decoded = try JSONDecoder().decode(
            WhiteFrameConfig.self, from: JSONEncoder().encode(original))
        #expect(decoded.borderMillimetres == 7)
        #expect(decoded.captionTextMillimetres == 3)
        #expect(decoded.logoHeightMillimetres == 6)
    }

    @Test("A pre-metric template gets the metric defaults")
    func legacyTemplateGetsDefaults() throws {
        let legacy = """
        {"isEnabled": true, "frameWidthRatio": 0.04, "metadataTextEnabled": true,
         "textFontSizeRatio": 0.018, "textColorRGBA": [0.3, 0.3, 0.3, 1.0]}
        """
        let config = try JSONDecoder().decode(WhiteFrameConfig.self, from: Data(legacy.utf8))
        // The defaults are derived from the measured reference proportions,
        // so they move together if those are retuned.
        #expect(config.borderMillimetres == FrameMetrics.defaultBorderMillimetres)
        #expect(config.captionTextMillimetres == FrameMetrics.defaultCaptionMillimetres)
        #expect(config.logoHeightMillimetres == FrameMetrics.defaultMarkMillimetres)
    }
}

// MARK: - Output DPI

@Suite("Output DPI drives every physical size")
struct OutputDPIGeometryTests {

    private let source = CGSize(width: 3024, height: 4032)

    @Test("An explicit DPI overrides the photo's own resolution")
    func explicitDPIWins() {
        let metadata: [String: Any] = [kCGImagePropertyDPIWidth as String: 600]
        let auto = WhiteFrameConfig(isEnabled: true, style: .gallery)
        #expect(FrameGeometry.resolveDPI(from: metadata, config: auto) == 600)

        var pinned = auto
        pinned.outputDPI = 150
        #expect(FrameGeometry.resolveDPI(from: metadata, config: pinned) == 150)
    }

    @Test("Doubling the DPI doubles the mat, keyline, caption and mark")
    func sizesScaleWithDPI() {
        let config = WhiteFrameConfig(isEnabled: true, style: .gallery)
        let low = FrameGeometry(config: config, sourceSize: source, dpi: 150)
        let high = FrameGeometry(config: config, sourceSize: source, dpi: 300)

        // Each size is rounded to a whole pixel, so doubling is exact to ±1.
        #expect(abs(high.keylineWidth - low.keylineWidth * 2) <= 1)
        #expect(abs(high.captionFontSize - low.captionFontSize * 2) <= 1)
        #expect(abs(high.logoHeight - low.logoHeight * 2) <= 1)
        // 8mm at 150 DPI is 47px a side; at 300 it is 94px.
        #expect(abs((high.framedSize.width - source.width)
                    - (low.framedSize.width - source.width) * 2) <= 2)
    }

    @Test("The DPI is clamped to a printable range")
    func dpiIsClamped() {
        #expect(WhiteFrameConfig(outputDPI: 10_000).outputDPI == 2400)
        #expect(WhiteFrameConfig(outputDPI: 1).outputDPI == 36)
        #expect(WhiteFrameConfig().outputDPI == nil)
    }

    @Test("A saved config restores its DPI and its caption colour unchanged")
    func dpiAndColourSurviveARoundTrip() throws {
        var config = WhiteFrameConfig(isEnabled: true, style: .gallery)
        config.outputDPI = 600
        let restored = try JSONDecoder().decode(
            WhiteFrameConfig.self, from: JSONEncoder().encode(config))

        #expect(restored.outputDPI == 600)
        // Black, not the 0.333 grey the old encoder fell back to for any
        // colour that was not already RGBA.
        let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
        let components = restored.textColor.converted(
            to: sRGB, intent: .defaultIntent, options: nil)?.components
        #expect(components?[0] == 0)
    }
}

// MARK: - Caption tone

@Suite("Gallery caption tone")
struct GalleryCaptionToneTests {

    @Test("The gallery primary is black and the classic one stays grey")
    func perStyleDefaults() {
        let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
        func red(_ color: CGColor) -> CGFloat? {
            color.converted(to: sRGB, intent: .defaultIntent, options: nil)?.components?[0]
        }
        #expect(red(WhiteFrameConfig(style: .gallery).textColor) == 0)
        // Classic keeps its mid grey. Compared as a range, not a number: it is
        // authored in DeviceGray, and converting that to sRGB preserves the
        // appearance rather than the component (0.333 grey reads as 0.41 sRGB).
        let classic = red(WhiteFrameConfig(style: .classic).textColor) ?? 0
        #expect(classic > 0.3 && classic < 0.5)
    }

    @Test("The secondary line is lighter than the primary")
    func secondaryIsLighter() {
        // Regression: `lighten` bailed out on two-component grey colours and
        // returned the primary unchanged, so both caption lines drew identical.
        let mat = WhiteFrameRenderer.matColor(for: .gallery)
        let secondary = WhiteFrameRenderer.lighten(
            CGColor(gray: 0, alpha: 1), towards: mat, by: 0.45)
        let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
        let value = secondary.converted(to: sRGB, intent: .defaultIntent, options: nil)?.components?[0]
        // Black lifted 45% of the way to the mat's 0.651 lands near 0.29.
        #expect(value != nil)
        #expect(value! > 0.2 && value! < 0.4)
    }
}

// MARK: - Brand mark opt-out

@Suite("The brand mark can be turned off")
struct LogoOptOutTests {

    private let metadata: [String: Any] = [
        "{TIFF}": ["Make": "Apple", "Model": "iPhone 15 Pro Max"],
        "{Exif}": ["LensModel": "iPhone 15 Pro Max back triple camera 6.765mm f/1.78",
                   "FocalLength": 6.765, "FocalLenIn35mmFilm": 24],
    ]

    @Test("On by default, and a known maker resolves a mark")
    func markIsOnByDefault() {
        let config = WhiteFrameConfig(isEnabled: true, style: .gallery)
        #expect(config.logoEnabled)
        let caption = WhiteFrameRenderer.resolveGalleryCaption(config: config, metadata: metadata)
        #expect(caption.mark != nil)
    }

    @Test("Off drops the mark but keeps the caption")
    func offDropsOnlyTheMark() {
        var config = WhiteFrameConfig(isEnabled: true, style: .gallery)
        config.logoEnabled = false
        let caption = WhiteFrameRenderer.resolveGalleryCaption(config: config, metadata: metadata)
        #expect(caption.mark == nil)
        #expect(caption.leftPrimary == "iPhone 15 Pro Max")
        #expect(!caption.isEmpty)
    }

    @Test("The choice survives a save and reload")
    func survivesARoundTrip() throws {
        var config = WhiteFrameConfig(isEnabled: true, style: .gallery)
        config.logoEnabled = false
        let restored = try JSONDecoder().decode(
            WhiteFrameConfig.self, from: JSONEncoder().encode(config))
        #expect(restored.logoEnabled == false)
    }

    @Test("A config written before the toggle existed keeps its mark")
    func legacyConfigsDefaultToOn() throws {
        var config = WhiteFrameConfig(isEnabled: true, style: .gallery)
        config.logoEnabled = false
        var json = try JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(config)) as! [String: Any]
        json.removeValue(forKey: "logoEnabled")
        let data = try JSONSerialization.data(withJSONObject: json)
        #expect(try JSONDecoder().decode(WhiteFrameConfig.self, from: data).logoEnabled)
    }
}
