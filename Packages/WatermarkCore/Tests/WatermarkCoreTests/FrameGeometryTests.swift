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

    @Test("Classic mats are uniform when there is no caption to hold")
    func classicIsUniform() {
        let g = FrameGeometry(config: Self.config(style: .classic), sourceSize: Self.portrait,
                              hasCaptionContent: false)
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

    @Test("Classic measures the same on paper at any export size")
    func classicIsPhysicalAcrossResolutions() {
        // Both styles are millimetre-measured now. Classic used to take a
        // percentage of the photo, so the same settings printed a different
        // border for every camera.
        let small = CGSize(width: 1512, height: 2016)
        let large = CGSize(width: 6048, height: 8064)
        let a = FrameGeometry(config: Self.config(style: .classic), sourceSize: small, dpi: 300)
        let b = FrameGeometry(config: Self.config(style: .classic), sourceSize: large, dpi: 300)

        #expect(a.left == b.left, "mat drifted with the pixel count")
        #expect(a.captionFontSize == b.captionFontSize, "caption drifted with the pixel count")
    }

    @Test("Gallery's caption is sized from its physical mat, so the two stay in step")
    func galleryCaptionFollowsItsMat() {
        // Text that kept scaling with pixels would outgrow a millimetre border
        // on a large photo and stop the band tracking the setting.
        // At one pinned resolution, since that is what "physical" means: the
        // same print resolution gives the same millimetres the same pixels.
        let small = FrameGeometry(config: Self.config(style: .gallery),
                                  sourceSize: CGSize(width: 1512, height: 2016), dpi: 300)
        let large = FrameGeometry(config: Self.config(style: .gallery),
                                  sourceSize: CGSize(width: 6048, height: 8064), dpi: 300)
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

    @Test("The keyline scales with the border and is at least a pixel")
    func keylineScales() {
        let thick = FrameGeometry(config: Self.config(keyline: true), sourceSize: Self.portrait, dpi: 600)
        let thin = FrameGeometry(config: Self.config(keyline: true), sourceSize: Self.portrait, dpi: 72)
        // Tied to the photo instead, it came out a hairline on small images.
        #expect(thick.keylineWidth > thin.keylineWidth)
        #expect(thin.keylineWidth >= 1, "a keyline thinner than a pixel would vanish")
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

    @Test("At one resolution, a millimetre border is the same pixel size on any photo")
    func mmIsPhysicalNotProportional() {
        let small = FrameGeometry(config: Self.gallery(),
                                  sourceSize: CGSize(width: 1000, height: 800), dpi: 300)
        let large = FrameGeometry(config: Self.gallery(),
                                  sourceSize: CGSize(width: 8000, height: 6000), dpi: 300)
        // This is the point of a physical unit, and the opposite of how classic
        // behaves: printed at the same resolution, the same border measures the
        // same on paper either way.
        #expect(small.left == large.left)
    }

    @Test("Left to itself, a millimetre border is the same share of any frame")
    func mmIsProportionalWhenTheResolutionIsDerived() {
        // What the user actually sees when they do not pin a resolution. A
        // fixed fallback made the same setting 3.1% of a 12MP photo's short
        // edge but 8.8% of 1080p footage's — the reason video came out framed
        // so much more heavily than stills.
        func share(_ size: CGSize) -> CGFloat {
            FrameGeometry(config: Self.gallery(), sourceSize: size).left / min(size.width, size.height)
        }
        let photo = share(CGSize(width: 3024, height: 4032))
        for other in [CGSize(width: 1080, height: 1920),      // 1080p video
                      CGSize(width: 2160, height: 3840),      // 4K video
                      CGSize(width: 1280, height: 960),       // a small photo
                      CGSize(width: 8000, height: 6000)] {    // a big one
            #expect(abs(share(other) - photo) < 0.002,
                    "\(other) frames at \(share(other) * 100)% against the photo's \(photo * 100)%")
        }
    }

    @Test("Classic honours the millimetre border too")
    func classicFollowsMillimetres() {
        let a = WhiteFrameConfig(isEnabled: true, style: .classic, borderMillimetres: 5)
        let b = WhiteFrameConfig(isEnabled: true, style: .classic, borderMillimetres: 40)
        #expect(FrameGeometry(config: a, sourceSize: Self.portrait).left
                < FrameGeometry(config: b, sourceSize: Self.portrait).left)
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

    static let twelveMP = CGSize(width: 3024, height: 4032)

    @Test("A print-intent resolution in the file is believed")
    func realDPIIsUsed() {
        #expect(FrameGeometry.resolveDPI(from: ["DPIWidth": 600], sourceSize: Self.twelveMP) == 600)
        #expect(FrameGeometry.resolveDPI(from: ["DPIWidth": 150], sourceSize: Self.twelveMP) == 150)
    }

    @Test("The JFIF default of 72 is not treated as a measurement")
    func junkDPIFallsBack() {
        // Almost every phone JPEG says 72 because that is the format default,
        // not because anyone measured. Believing it would make a 5mm border
        // 14px on an 8000px photo — indistinguishable from no border.
        // The fallback is the source's own resolution over a ten-inch print,
        // which for a 12MP photo is the 300 DPI it used to be hardcoded to.
        #expect(abs(FrameGeometry.resolveDPI(
            from: ["DPIWidth": 72], sourceSize: Self.twelveMP) - 302.4) < 0.1)
        #expect(abs(FrameGeometry.resolveDPI(
            from: [:], sourceSize: Self.twelveMP) - 302.4) < 0.1)
        // Degenerate input must not divide by zero.
        #expect(FrameGeometry.resolveDPI(from: [:], sourceSize: .zero) == 300)
    }

    @Test("Height resolution is used when width is missing")
    func fallsBackToHeightDPI() {
        #expect(FrameGeometry.resolveDPI(from: ["DPIHeight": 400], sourceSize: Self.twelveMP) == 400)
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
        let a = FrameGeometry(config: Self.gallery(), sourceSize: Self.small, dpi: 300)
        let b = FrameGeometry(config: Self.gallery(), sourceSize: Self.large, dpi: 300)
        #expect(a.captionFontSize == b.captionFontSize)
        #expect(a.captionFontSize == FrameGeometry.pixels(millimetres: 2.5, dpi: 300))
    }

    @Test("The brand mark is the same physical size whatever the photo's pixels")
    func logoIsPhysical() {
        let a = FrameGeometry(config: Self.gallery(), sourceSize: Self.small, dpi: 300)
        let b = FrameGeometry(config: Self.gallery(), sourceSize: Self.large, dpi: 300)
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

    @Test("Classic measures its border and text in millimetres, and draws no mark")
    func classicIsMetricToo() {
        let config = WhiteFrameConfig(isEnabled: true, style: .classic,
                                      borderMillimetres: 10, captionTextMillimetres: 4,
                                      logoHeightMillimetres: 25)
        let g = FrameGeometry(config: config, sourceSize: Self.large, dpi: 300)
        #expect(g.logoHeight == 0, "only gallery carries a brand mark")
        #expect(g.captionFontSize == FrameGeometry.pixels(millimetres: 4, dpi: 300))
        // A uniform border: the same millimetres on every edge.
        #expect(g.top == g.left)
        #expect(g.left == g.right)
        #expect(g.top == FrameGeometry.pixels(millimetres: 10, dpi: 300)
                + g.keylineWidth)
    }

    @Test("Classic's border stays put when the photo's pixel count changes")
    func classicBorderIsPhysical() {
        let config = WhiteFrameConfig(isEnabled: true, style: .classic, borderMillimetres: 8)
        let small = FrameGeometry(config: config, sourceSize: CGSize(width: 1600, height: 1200), dpi: 300)
        let large = FrameGeometry(config: config, sourceSize: CGSize(width: 6000, height: 4000), dpi: 300)
        // Same millimetres, same pixels — what used to be 4% of the short edge
        // printed a different border for every camera.
        #expect(small.left == large.left)
    }

    @Test("Classic's bottom grows only when the caption outgrows the border")
    func classicBottomHoldsItsCaption() {
        let modest = WhiteFrameConfig(isEnabled: true, style: .classic,
                                      borderMillimetres: 10, captionTextMillimetres: 3)
        let uniform = FrameGeometry(config: modest, sourceSize: Self.large, dpi: 300)
        #expect(uniform.bottom == uniform.top, "a caption that fits leaves the border uniform")

        let oversized = WhiteFrameConfig(isEnabled: true, style: .classic,
                                         borderMillimetres: 3, captionTextMillimetres: 12)
        let stretched = FrameGeometry(config: oversized, sourceSize: Self.large, dpi: 300)
        #expect(stretched.bottom > stretched.top, "the band has to hold the line it is given")
        #expect(stretched.bottom > stretched.captionFontSize)
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

    /// Templates saved before the frame was measured in millimetres carry
    /// `frameWidthRatio`/`textFontSizeRatio`, which nothing reads any more.
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
        // No style key means a classic template, whose caption sits inside the
        // border rather than in gallery's taller band.
        #expect(config.style == .classic)
        #expect(config.captionTextMillimetres == FrameMetrics.defaultClassicCaptionMillimetres)
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
        #expect(FrameGeometry.resolveDPI(from: metadata, config: auto, sourceSize: source) == 600)

        var pinned = auto
        pinned.outputDPI = 150
        #expect(FrameGeometry.resolveDPI(from: metadata, config: pinned, sourceSize: source) == 150)
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

// MARK: - Classic in millimetres

/// Classic used to size its border and caption as percentages of the photo, so
/// the same settings printed a different frame for every camera. Both are
/// physical now; these pin what that means.
@Suite("Classic frame metrics")
struct ClassicMetricTests {

    private let source = CGSize(width: 4032, height: 3024)

    @Test("A classic frame is even at its default settings")
    func defaultsAreEven() {
        let config = WhiteFrameConfig(isEnabled: true, style: .classic)
        let g = FrameGeometry(config: config, sourceSize: source, dpi: 300)
        #expect(g.top == g.left)
        #expect(g.left == g.right)
        #expect(g.bottom == g.top, "the default caption has to fit inside the border")
    }

    @Test("A new classic frame's caption fits its border; gallery's suits its band")
    func captionDefaultFollowsStyle() {
        #expect(WhiteFrameConfig(style: .classic).captionTextMillimetres
                == FrameMetrics.defaultClassicCaptionMillimetres)
        #expect(WhiteFrameConfig(style: .gallery).captionTextMillimetres
                == FrameMetrics.defaultCaptionMillimetres)
        // An explicit size is always taken as given.
        #expect(WhiteFrameConfig(style: .classic, captionTextMillimetres: 9).captionTextMillimetres == 9)
    }

    @Test("The same millimetres print the same border at every export size")
    func borderIsPhysical() {
        let config = WhiteFrameConfig(isEnabled: true, style: .classic, borderMillimetres: 6)
        let phone = FrameGeometry(config: config, sourceSize: CGSize(width: 4032, height: 3024), dpi: 300)
        let medium = FrameGeometry(config: config, sourceSize: CGSize(width: 8000, height: 6000), dpi: 300)
        #expect(phone.left == medium.left)
        #expect(phone.captionFontSize == medium.captionFontSize)
        #expect(phone.left == FrameGeometry.pixels(millimetres: 6, dpi: 300) + phone.keylineWidth)
    }

    @Test("Raising the export DPI puts the same millimetres on more pixels")
    func dpiScalesEverything() {
        let config = WhiteFrameConfig(isEnabled: true, style: .classic, borderMillimetres: 8,
                                      captionTextMillimetres: 4)
        let low = FrameGeometry(config: config, sourceSize: source, dpi: 150)
        let high = FrameGeometry(config: config, sourceSize: source, dpi: 300)
        #expect(high.left > low.left)
        // Doubling the resolution doubles the pixels, give or take the rounding
        // of a millimetre onto a pixel grid.
        #expect(abs(high.captionFontSize - low.captionFontSize * 2) <= 1)
    }
}

// MARK: - Millimetre grid

@Suite("Millimetre sizes sit on a half-millimetre grid")
struct MillimetreGridTests {

    private func isOnGrid(_ value: CGFloat) -> Bool {
        abs(value - WatermarkScaling.snapped(millimetres: value)) < 0.0001
    }

    @Test("Snapping rounds to the nearest half millimetre")
    func snapping() {
        #expect(WatermarkScaling.snapped(millimetres: 10.92) == 11.0)
        #expect(WatermarkScaling.snapped(millimetres: 11.43) == 11.5)
        #expect(WatermarkScaling.snapped(millimetres: 11.24) == 11.0)
        #expect(WatermarkScaling.snapped(millimetres: 11.26) == 11.5)
        #expect(WatermarkScaling.snapped(millimetres: 8) == 8)
    }

    @Test("A layer's size is on the grid however it was set")
    func layerSizesAreOnGrid() {
        // 0.043 of the short edge is 10.92mm — the sort of value the old
        // percentage stepper left behind, which then stepped 10.9, 11.4, 11.9.
        for scale in [0.043, 0.045, 0.15, 0.01, 0.9] as [CGFloat] {
            #expect(isOnGrid(WatermarkScaling.millimetres(forScale: scale)))
        }
        // And what is drawn is what is shown: converting back and forth is
        // stable, so the stepper cannot creep off the grid.
        let scale = WatermarkScaling.scale(forMillimetres: 10.92)
        #expect(WatermarkScaling.millimetres(forScale: scale) == 11.0)
        #expect(WatermarkScaling.scale(forMillimetres: 11.0) == scale)
    }

    @Test("The frame's own defaults are on the grid")
    func frameDefaultsAreOnGrid() {
        // 8 x 0.73 is 5.84mm and 8 x 1.70 is 13.6mm; both used to arrive
        // off-grid, so the sliders opened on a number they could not return to.
        #expect(isOnGrid(FrameMetrics.defaultBorderMillimetres))
        #expect(isOnGrid(FrameMetrics.defaultCaptionMillimetres))
        #expect(isOnGrid(FrameMetrics.defaultMarkMillimetres))
        #expect(FrameMetrics.defaultCaptionMillimetres == 6.0)
        #expect(FrameMetrics.defaultMarkMillimetres == 13.5)
    }

    @Test("Snapping the caption barely moves it off the reference")
    func snappingStaysFaithful() {
        // The grid must not undo the calibration: 5.84 -> 6.0 is under 3%.
        let exact = FrameMetrics.defaultBorderMillimetres * FrameMetrics.reference.captionToBorder
        #expect(abs(FrameMetrics.defaultCaptionMillimetres - exact) / exact < 0.03)
        let mark = FrameMetrics.defaultBorderMillimetres * FrameMetrics.reference.markToBorder
        #expect(abs(FrameMetrics.defaultMarkMillimetres - mark) / mark < 0.03)
    }
}

@Suite("A layer's size number means the same thing on every medium")
struct LayerSizeNumberTests {

    /// What the number promises: the same share of the frame, whatever the
    /// medium or resolution. It deliberately does not promise millimetres on
    /// the exported file, which is why the control shows no unit — a layer's
    /// size does not follow a pinned print resolution the way the frame does.
    @Test("One setting is one share of the frame on any source")
    func sameShareEverywhere() {
        let scale = WatermarkScaling.scale(forMillimetres: 16)
        for size in [CGSize(width: 3024, height: 4032),
                     CGSize(width: 1080, height: 1920),
                     CGSize(width: 3840, height: 2160),
                     CGSize(width: 1280, height: 960)] {
            let drawn = WatermarkScaling.reference(size) * scale
            #expect(abs(drawn / min(size.width, size.height) - scale) < 0.0001, "\(size)")
        }
        // 16 of 254 is 6.3% of the short edge — the measured render was 6.2%.
        #expect(abs(scale - 0.063) < 0.001)
    }

    @Test("The number survives a round trip through the stepper")
    func roundTrips() {
        for value in [2.5, 11, 16, 38, 228.5] as [CGFloat] {
            let scale = WatermarkScaling.scale(forMillimetres: value)
            #expect(WatermarkScaling.millimetres(forScale: scale) == value)
        }
    }
}

@Suite("Dragging picks the layer under the finger")
struct LayerHitTestTests {

    /// Two layers, well apart: one top-left, one bottom-right.
    private let layout = RenderLayout(
        photoRect: CGRect(x: 0, y: 0, width: 1, height: 1),
        layerFrames: [
            0: CGRect(x: 0.05, y: 0.05, width: 0.20, height: 0.10),
            1: CGRect(x: 0.60, y: 0.70, width: 0.30, height: 0.15),
        ])

    @Test("A point on a layer finds that layer")
    func hitsTheLayerUnderIt() {
        #expect(layout.layerIndex(at: CGPoint(x: 0.10, y: 0.08)) == 0)
        #expect(layout.layerIndex(at: CGPoint(x: 0.70, y: 0.75)) == 1)
    }

    @Test("A point on bare photo finds nothing")
    func missesWhenThereIsNothingThere() {
        // The bug: this returned the selected layer, so a drag anywhere on the
        // photo dragged the text.
        #expect(layout.layerIndex(at: CGPoint(x: 0.45, y: 0.45)) == nil)
        #expect(layout.layerIndex(at: CGPoint(x: 0.95, y: 0.05)) == nil)
        #expect(layout.layerIndex(at: CGPoint(x: 0.02, y: 0.98)) == nil)
    }

    @Test("Overlapping layers hand the drag to the topmost")
    func topmostWins() {
        let stacked = RenderLayout(
            photoRect: CGRect(x: 0, y: 0, width: 1, height: 1),
            layerFrames: [
                0: CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5),
                2: CGRect(x: 0.2, y: 0.2, width: 0.5, height: 0.5),
                1: CGRect(x: 0.15, y: 0.15, width: 0.5, height: 0.5),
            ])
        #expect(stacked.layerIndex(at: CGPoint(x: 0.3, y: 0.3)) == 2)
        // Outside the topmost, still inside the bottom one.
        #expect(stacked.layerIndex(at: CGPoint(x: 0.12, y: 0.12)) == 0)
    }

    @Test("Slop makes a thin layer catchable without swallowing the photo")
    func slopIsBounded() {
        // Just outside the frame but within the 2% slop.
        #expect(layout.layerIndex(at: CGPoint(x: 0.04, y: 0.04)) == 0)
        // Beyond it, nothing.
        #expect(layout.layerIndex(at: CGPoint(x: 0.01, y: 0.01)) == nil)
    }

    @Test("An empty layout is never a hit")
    func emptyLayout() {
        let empty = RenderLayout(photoRect: CGRect(x: 0, y: 0, width: 1, height: 1),
                                 layerFrames: [:])
        #expect(empty.layerIndex(at: CGPoint(x: 0.5, y: 0.5)) == nil)
    }
}
