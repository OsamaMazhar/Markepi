import CoreImage
import Foundation
import Testing
@testable import MarkepiCore

/// `banner` sets a full-bleed photo over a caption bar: no mat on three sides,
/// the maker's mark and credit at the far left of the bar, the shooting values
/// and the device at the far right.
///
/// The geometry half of this suite is the part worth pinning. Every other style
/// surrounds the photo, and several places in the pipeline quietly assumed that
/// — "the canvas is larger than the source in both dimensions" was a committed
/// test before this style existed.
@Suite("Banner style")
struct BannerStyleTests {

    private static let source = CGSize(width: 600, height: 400)

    private func config(captionEnabled: Bool = true) -> WhiteFrameConfig {
        WhiteFrameConfig(isEnabled: true, metadataTextEnabled: captionEnabled,
                         style: .banner, outputDPI: 300)
    }

    /// A photo that names a maker, a model and a lens carrying the model again.
    private func metadata(make: String? = "Apple",
                          model: String? = "iPhone 16 Pro",
                          lens: String? = "iPhone 16 Pro back camera 6.765mm f/1.78") -> [String: Any] {
        var tiff: [String: Any] = [:]
        if let make { tiff["Make"] = make }
        if let model { tiff["Model"] = model }
        var exif: [String: Any] = ["ISOSpeedRatings": [400], "FNumber": 1.78]
        if let lens { exif["LensModel"] = lens }
        return ["{TIFF}": tiff, "{Exif}": exif]
    }

    private func geometry(_ config: WhiteFrameConfig, hasCaption: Bool = true) -> FrameGeometry {
        FrameGeometry(config: config, sourceSize: Self.source, dpi: 300,
                      hasCaptionContent: hasCaption)
    }

    // MARK: - The photo bleeds

    @Test("The photo runs to the top and both edges")
    func noSideMat() {
        let g = geometry(config())
        #expect(g.top == 0)
        #expect(g.left == 0)
        #expect(g.right == 0)
        #expect(g.bottom > 0, "the bar is the whole frame")
        #expect(g.photoRect.origin == .zero)
        // Only the even-rounding pixel may be added to the width.
        #expect(g.framedSize.width - Self.source.width <= 1)
    }

    @Test("The bar tracks the border setting, as gallery's band does")
    func barTracksTheBorder() {
        var narrow = config(); narrow.borderMillimetres = 4
        var wide = config(); wide.borderMillimetres = 16
        #expect(geometry(wide).bottom > geometry(narrow).bottom)
    }

    @Test("Nothing to say leaves no bar at all")
    func emptyCaptionLeavesNoFrame() {
        // A gallery with nothing to say still has its mat; a banner with
        // nothing to say has no frame left, and adding a blank white stripe
        // would be worse than adding nothing.
        let g = geometry(config(captionEnabled: false), hasCaption: false)
        #expect(g.bottom == 0)
        #expect(g.framedSize.height - Self.source.height <= 1)
    }

    @Test("A photo with no metadata at all has nothing to put in the bar")
    func noMetadataNoCaption() {
        #expect(!WhiteFrameRenderer.hasCaptionContent(config: config(), metadata: [:]))
        #expect(WhiteFrameRenderer.hasCaptionContent(config: config(), metadata: metadata()))
    }

    // MARK: - No keyline

    @Test("The keyline is not drawn, whatever the stored preference")
    func neverAKeyline() {
        // There is no mat to stroke it in: it would land on the photograph or
        // off the canvas. The preference itself is left alone.
        var config = config()
        config.keylineEnabled = true
        #expect(!FrameStyle.banner.offersKeyline)
        #expect(geometry(config).keylineWidth == 0)
        #expect(config.keylineEnabled, "the stored preference survives")
    }

    // MARK: - What the bar says

    @Test("The left block credits the maker under a fixed lead-in")
    func leftBlockCreditsTheMaker() {
        let resolved = WhiteFrameRenderer.resolveBannerCaption(
            config: config(), metadata: metadata())
        #expect(resolved.maker == "Apple")
        #expect(resolved.mark != nil, "a recognised maker earns its mark")
    }

    @Test("An unrecognised maker costs the left block, not the bar")
    func unknownMakerDropsTheCredit() {
        let resolved = WhiteFrameRenderer.resolveBannerCaption(
            config: config(), metadata: metadata(make: "Acme Optical Co"))
        #expect(resolved.maker == nil)
        #expect(resolved.mark == nil)
        #expect(resolved.device != nil, "the right block still has the device")
        #expect(!resolved.isEmpty)
    }

    @Test("The device line names the model and its lens, never the model twice")
    func deviceLineTrimsTheLens() {
        // Apple writes the device name into the lens string, so an untrimmed
        // line reads "iPhone 16 Pro • iPhone 16 Pro back camera 6.765mm f/1.78".
        var config = config()
        config.captionFields = [.cameraModel, .lens, .iso]
        let device = WhiteFrameRenderer.resolveBannerCaption(
            config: config, metadata: metadata()).device

        #expect(device?.hasPrefix("iPhone 16 Pro • ") == true, "got: \(device ?? "nil")")
        #expect(device?.dropFirst("iPhone 16 Pro • ".count).contains("iPhone 16 Pro") == false,
                "the model is printed twice: \(device ?? "nil")")
    }

    @Test("The values line carries the exposure, never the equipment")
    func valuesLineExcludesEquipment() {
        var config = config()
        config.captionFields = [.cameraModel, .lens, .iso, .aperture]
        let resolved = WhiteFrameRenderer.resolveBannerCaption(
            config: config, metadata: metadata())
        let values = resolved.values ?? ""

        #expect(values.contains("ISO"))
        #expect(values.contains("f/"))
        #expect(!values.contains("iPhone"), "the equipment belongs on the line below: \(values)")
    }

    @Test("Unticking the equipment fields empties the device line")
    func deviceLineFollowsTheFieldChoice() {
        var config = config()
        config.captionFields = [.iso]
        let resolved = WhiteFrameRenderer.resolveBannerCaption(
            config: config, metadata: metadata())
        #expect(resolved.device == nil)
        #expect(resolved.values != nil, "the values line is still there")
    }

    @Test("Turning the mark off leaves the credit text")
    func markCanBeTurnedOff() {
        var config = config()
        config.logoEnabled = false
        let resolved = WhiteFrameRenderer.resolveBannerCaption(
            config: config, metadata: metadata())
        #expect(resolved.mark == nil)
        #expect(resolved.maker == "Apple")
    }

    @Test("The caption off means no bar, whatever the metadata says")
    func captionOffCollapsesTheBar() {
        #expect(WhiteFrameRenderer.resolveBannerCaption(
            config: config(captionEnabled: false), metadata: metadata()).isEmpty)
    }

    // MARK: - Fill and defaults

    @Test("The bar is flat white, never graduated")
    func flatWhiteBar() {
        var config = config()
        config.gradientEnabled = true   // which banner does not read
        #expect(WhiteFrameRenderer.matFill(for: config)
                == .flat(CGColor(gray: 1.0, alpha: 1.0)))
    }

    @Test("The caption defaults to black, as gallery's does")
    func captionDefaultsToBlack() {
        // Its secondary tone is derived from the primary, so a grey primary
        // would wash the second line out to nearly nothing.
        #expect(WhiteFrameConfig(style: .banner).textColor.components?.first == 0)
    }

    @Test("The bar needs a mark height; the mat styles do not")
    func markHeightPerStyle() {
        for style in FrameStyle.allCases {
            var config = WhiteFrameConfig(isEnabled: true, style: style, outputDPI: 300)
            config.captionFields = [.iso]
            let height = FrameGeometry(config: config, sourceSize: Self.source,
                                       dpi: 300, hasCaptionContent: true).logoHeight
            #expect((height > 0) == style.drawsBrandMark, "\(style.rawValue): \(height)")
        }
    }

    // MARK: - What lands on the pixels

    @Test("Both ends of the bar carry ink, and none of it touches the photo")
    func barIsDrawnAtBothEnds() throws {
        let config = config()
        let meta = metadata()
        let image = try WhiteFrameRenderer.render(
            config: config, sourceSize: Self.source, metadata: meta)
        let context = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])
        let cg = try #require(context.createCGImage(image, from: image.extent))

        let bytesPerRow = 4 * cg.width
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * cg.height)
        bytes.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(
                data: raw.baseAddress, width: cg.width, height: cg.height,
                bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        }
        /// Grey at a point, or nil where the mat is transparent — the photo.
        func grey(_ x: Int, _ y: Int) -> Double? {
            let o = 4 * cg.width * y + 4 * x
            guard bytes[o + 3] > 0 else { return nil }
            return (Double(bytes[o]) + Double(bytes[o + 1]) + Double(bytes[o + 2])) / (3 * 255)
        }

        let g = FrameGeometry(config: config, sourceSize: Self.source, dpi: 300,
                              hasCaptionContent: true)
        let barTop = Int(g.photoRect.maxY)
        var leftInk = 0, rightInk = 0
        for y in barTop..<cg.height {
            for x in 0..<cg.width where (grey(x, y) ?? 1) < 0.6 {
                if x < cg.width / 2 { leftInk += 1 } else { rightInk += 1 }
            }
        }
        #expect(leftInk > 0, "the mark and credit should sit at the left of the bar")
        #expect(rightInk > 0, "the values and device should sit at the right of the bar")

        // The photo's own rows are the hole, all the way to both edges.
        for y in [1, barTop / 2, barTop - 2] {
            #expect(grey(0, y) == nil, "mat covers the photo's left edge at row \(y)")
            #expect(grey(cg.width - 2, y) == nil, "mat covers the photo's right edge at row \(y)")
        }
    }
}
