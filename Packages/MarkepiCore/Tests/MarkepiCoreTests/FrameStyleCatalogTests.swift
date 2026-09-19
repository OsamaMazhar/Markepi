import CoreImage
import Foundation
import ImageIO
import Testing
@testable import MarkepiCore

/// Covers what the catalogue added on top of `classic` and `gallery`: the
/// gradient toggle that replaced a style of its own, and the centred credit
/// caption `print` draws.
///
/// The mat-fill checks here are deliberately *not* byte-comparisons against a
/// stored image. Core Text rasterises differently across OS versions and
/// hardware, so a stored PNG would rot into a flake; what the refactor can
/// actually break is which fill a style uses, and a two-pixel probe pins that
/// without depending on glyph rendering at all.
@Suite("Frame style catalogue")
struct FrameStyleCatalogTests {

    // MARK: - Helpers

    private static let source = CGSize(width: 600, height: 400)

    private func config(_ style: FrameStyle, captionEnabled: Bool = true,
                        gradient: Bool = false) -> WhiteFrameConfig {
        WhiteFrameConfig(
            isEnabled: true,
            metadataTextEnabled: captionEnabled,
            style: style,
            outputDPI: 300,
            gradientEnabled: gradient
        )
    }

    /// Metadata naming both a maker and a model, the way a real file does.
    private func metadata(make: String? = "Apple", model: String? = "iPhone 16 Pro") -> [String: Any] {
        var tiff: [String: Any] = [:]
        if let make { tiff["Make"] = make }
        if let model { tiff["Model"] = model }
        return tiff.isEmpty ? [:] : ["{TIFF}": tiff]
    }

    /// A rendered frame's pixels, rasterised once so a scan is array indexing
    /// rather than one full redraw per pixel.
    private struct Bitmap {
        let width: Int
        let height: Int
        let bytes: [UInt8]

        /// The grey level at a point in top-left coordinates, or nil where the
        /// mat is transparent — that is the photo's hole.
        func grey(x: Int, y: Int) -> Double? {
            guard x >= 0, x < width, y >= 0, y < height else { return nil }
            // A bitmap context stores its rows top-down even though its user
            // space is y-up, so memory row `y` already *is* the image's row `y`
            // from the top. Flipping here as well reads the frame upside down,
            // which is how this first reported gallery's gradient inverted.
            let offset = 4 * width * y + 4 * x
            guard bytes[offset + 3] > 0 else { return nil }
            return (Double(bytes[offset]) + Double(bytes[offset + 1]) + Double(bytes[offset + 2])) / (3 * 255)
        }
    }

    /// Renders a frame and hands back its pixels, top-left origin.
    private func rendered(_ config: WhiteFrameConfig,
                          metadata: [String: Any] = [:]) throws -> Bitmap {
        let image = try WhiteFrameRenderer.render(
            config: config, sourceSize: Self.source, metadata: metadata
        )
        let context = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])
        let cgImage = try #require(context.createCGImage(image, from: image.extent))

        let bytesPerRow = 4 * cgImage.width
        var data = [UInt8](repeating: 0, count: bytesPerRow * cgImage.height)
        data.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(
                data: raw.baseAddress, width: cgImage.width, height: cgImage.height,
                bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        }
        return Bitmap(width: cgImage.width, height: cgImage.height, bytes: data)
    }

    // MARK: - Mat fill

    // `print` is absent on purpose: its shadow darkens the mat near the photo,
    // so a two-pixel probe would read that as a gradient. Its fill is asserted
    // directly in `printMatIsFlatWhite` instead.
    @Test("Only gallery grades its mat, and only with the gradient on",
          arguments: [(FrameStyle.classic, true, false), (.gallery, true, true),
                      (.gallery, false, false)])
    func matFillPerStyle(style: FrameStyle, gradientOn: Bool, expectedGradient: Bool) throws {
        // Caption off, so the probe reads mat and never a glyph.
        var config = config(style, captionEnabled: false)
        config.gradientEnabled = gradientOn
        let image = try rendered(config)
        let midX = image.width / 2

        let top = try #require(image.grey(x: midX, y: 2))
        let bottom = try #require(image.grey(x: midX, y: image.height - 3))

        if expectedGradient {
            #expect(top - bottom > 0.05,
                    "\(style.rawValue) should grade lighter at the top, got \(top) vs \(bottom)")
        } else {
            #expect(abs(top - bottom) < 0.01,
                    "\(style.rawValue) should be one flat tone, got \(top) vs \(bottom)")
        }
    }

    @Test("With the gradient off the mat is plain white, like every other style")
    func flatGalleryIsWhite() {
        var flat = config(.gallery); flat.gradientEnabled = false
        let white = WhiteFrameRenderer.MatFill.flat(CGColor(gray: 1, alpha: 1))

        #expect(WhiteFrameRenderer.matFill(for: flat) == white)
        #expect(WhiteFrameRenderer.matFill(for: config(.classic)) == white)
        // Graduated is still darker at the caption, which is the whole
        // difference between the two settings.
        #expect(WhiteFrameRenderer.matColor(for: config(.gallery, gradient: true))
                != WhiteFrameRenderer.matColor(for: flat))
    }

    @Test("A new gallery frame starts white, and the gradient is the choice")
    func whiteIsTheDefault() {
        #expect(!WhiteFrameConfig(style: .gallery).gradientEnabled)
        #expect(WhiteFrameRenderer.matFill(for: WhiteFrameConfig(style: .gallery))
                == .flat(CGColor(gray: 1, alpha: 1)))
    }

    // MARK: - The keyline

    @Test("Classic's keyline is the user's to turn off",
          arguments: [true, false])
    func classicKeylineIsOptional(on: Bool) throws {
        // Reported as a black line that looked baked into the style. It is not:
        // the same switch every style but `print` offers drives it, and with it
        // off the mat runs unbroken up to the photo's edge.
        var config = config(.classic, captionEnabled: false)
        config.keylineEnabled = on
        let geometry = FrameGeometry(config: config, sourceSize: Self.source,
                                     dpi: 300, hasCaptionContent: false)
        #expect((geometry.keylineWidth > 0) == on)

        let image = try rendered(config)
        // Two pixels above the photo: inside the stroke when there is one.
        let justOutside = try #require(
            image.grey(x: Int(geometry.photoRect.midX), y: Int(geometry.photoRect.minY) - 2))
        if on {
            #expect(justOutside < 0.2, "the keyline should be a dark rule, read \(justOutside)")
        } else {
            #expect(justOutside > 0.95, "the mat should run clear to the photo, read \(justOutside)")
        }
    }

    // MARK: - The gradient toggle changes nothing else

    @Test("Turning the gradient off leaves the caption identical")
    func gradientDoesNotTouchTheCaption() {
        let meta = metadata()
        var flat = config(.gallery); flat.gradientEnabled = false
        let graduated = config(.gallery)

        let a = WhiteFrameRenderer.resolveGalleryCaption(config: graduated, metadata: meta)
        let b = WhiteFrameRenderer.resolveGalleryCaption(config: flat, metadata: meta)
        #expect(b.leftPrimary == a.leftPrimary)
        #expect(b.leftSecondary == a.leftSecondary)
        #expect(b.rightPrimary == a.rightPrimary)
        #expect(b.rightSecondary == a.rightSecondary)
        #expect((b.mark == nil) == (a.mark == nil))
    }

    @Test("Turning the gradient off leaves the layout identical")
    func gradientDoesNotTouchTheLayout() {
        let meta = metadata()
        func geometry(_ gradient: Bool) -> FrameGeometry {
            var c = config(.gallery); c.gradientEnabled = gradient
            return FrameGeometry(
                config: c, sourceSize: Self.source, dpi: 300,
                hasCaptionContent: WhiteFrameRenderer.hasCaptionContent(config: c, metadata: meta))
        }
        let graduated = geometry(true)
        let flat = geometry(false)

        #expect(flat.framedSize == graduated.framedSize)
        #expect(flat.photoRect == graduated.photoRect)
        #expect(flat.captionBand == graduated.captionBand)
        #expect(flat.keylineWidth == graduated.keylineWidth)
        #expect(flat.logoHeight == graduated.logoHeight)
        #expect(flat.logoHeight > 0, "gallery draws a brand mark, so it needs a mark height")
    }

    @Test("Either way, nothing to say collapses the band")
    func collapsesEmptyBandEitherWay() {
        for gradient in [true, false] {
            var c = config(.gallery, captionEnabled: false)
            c.gradientEnabled = gradient
            let geometry = FrameGeometry(config: c, sourceSize: Self.source,
                                         dpi: 300, hasCaptionContent: false)
            #expect(geometry.bottom == geometry.top,
                    "gradient=\(gradient) should collapse to a uniform mat")
        }
    }

    @Test("The gradient choice survives a saved template")
    func gradientRoundTrips() throws {
        var flat = config(.gallery); flat.gradientEnabled = false
        let data = try JSONEncoder().encode(flat)
        #expect(try JSONDecoder().decode(WhiteFrameConfig.self, from: data).gradientEnabled == false)
        // A template written before the toggle existed keeps the graduated mat
        // it was authored against.
        let legacy = #"{"isEnabled":true,"metadataTextEnabled":true,"textColorRGBA":[0,0,0,1]}"#
        #expect(try JSONDecoder().decode(
            WhiteFrameConfig.self, from: Data(legacy.utf8)).gradientEnabled)
    }

    // MARK: - The centred credit line

    @Test("The credit line names the device, drawn heavier than its lead-in")
    func creditLine() {
        let resolved = WhiteFrameRenderer.resolveCreditCaption(
            config: config(.print), metadata: metadata())

        #expect(resolved.credit == [
            WhiteFrameRenderer.CaptionRun("Shot on "),
            WhiteFrameRenderer.CaptionRun("iPhone 16 Pro", weight: .semibold),
        ])
    }

    @Test("With no device model there is no credit line at all")
    func creditNeedsADevice() {
        // "Shot on" with nothing after it is worse than saying nothing.
        let resolved = WhiteFrameRenderer.resolveCreditCaption(
            config: config(.print), metadata: metadata(make: "Apple", model: nil))
        #expect(resolved.credit.isEmpty)
    }

    @Test("An unrecognised maker costs the name, not the credit")
    func unknownMaker() {
        let resolved = WhiteFrameRenderer.resolveCreditCaption(
            config: config(.print), metadata: metadata(make: "Acme Optical Co", model: "AX-1"))

        #expect(resolved.credit.last?.text == "AX-1")
        #expect(resolved.details?.contains("Acme") != true,
                "an unrecognised maker should be dropped, not printed raw")
    }

    // MARK: - The detail line

    @Test("The maker leads the detail line, ahead of the chosen fields")
    func detailLineLeadsWithMaker() {
        var config = config(.print)
        config.captionFields = [.maker, .iso, .aperture]
        let meta = EXIFMetadataFactory.realisticMetadata(model: "iPhone 16 Pro")
            .merging(metadata()) { _, new in new }

        let details = try? #require(
            WhiteFrameRenderer.resolveCreditCaption(config: config, metadata: meta).details)
        let line = details ?? ""

        #expect(line.hasPrefix("Apple"), "maker leads the second line, got: \(line)")
        // Canonical field order, not the order they were ticked.
        let aperture = try? #require(line.range(of: "f/"))
        let iso = try? #require(line.range(of: "ISO"))
        if let aperture, let iso { #expect(aperture.lowerBound < iso.lowerBound) }
        #expect(!line.contains(" · "), "the credit caption joins with plain spacing, not classic's dot")
    }

    @Test("The device is not printed twice when the credit line already has it")
    func creditDoesNotRepeatTheDevice() {
        var config = config(.print)
        config.captionFields = [.cameraModel, .iso]
        let meta = EXIFMetadataFactory.realisticMetadata(model: "iPhone 16 Pro")
            .merging(metadata()) { _, new in new }

        let resolved = WhiteFrameRenderer.resolveCreditCaption(config: config, metadata: meta)
        #expect(resolved.credit.last?.text == "iPhone 16 Pro")
        #expect(resolved.details?.contains("iPhone 16 Pro") == false,
                "the camera field belongs to the credit line, not the details")
    }

    @Test("Nothing resolvable means no caption, and the band gives its room back")
    func creditEmptyCaption() {
        var config = config(.print)
        config.captionFields = [.iso]
        let resolved = WhiteFrameRenderer.resolveCreditCaption(config: config, metadata: [:])

        #expect(resolved.isEmpty)
        #expect(resolved.lines.isEmpty)
        #expect(!WhiteFrameRenderer.hasCaptionContent(config: config, metadata: [:]))

        func bottom(_ hasCaption: Bool) -> FrameGeometry {
            FrameGeometry(config: config, sourceSize: Self.source,
                          dpi: 300, hasCaptionContent: hasCaption)
        }
        let empty = bottom(false)
        #expect(empty.bottom < bottom(true).bottom)
        // Down to what the shadow needs, which is print's floor rather than a
        // uniform mat — the photo still has to be lifted off something.
        #expect(empty.bottom == max(empty.top, empty.shadowBlur + empty.shadowOffset))
    }

    // MARK: - The Include list is the master switch

    @Test("Unticking an entry drops it from gallery, wherever it sits")
    func galleryHonoursTheIncludeList() {
        // Gallery's four lines say where an entry sits; the Include list says
        // whether it appears at all. Before this, gallery ignored the list
        // entirely and the only way to drop a line was to set it to None.
        var config = config(.gallery)
        config.leftPrimary = .field(.cameraModel)
        config.rightPrimary = .field(.gps)
        config.captionFields = [.cameraModel]      // location unticked

        let meta: [String: Any] = [
            "{TIFF}": ["Make": "Apple", "Model": "iPhone 16 Pro"],
            "{GPS}": ["Latitude": 48.8566, "LatitudeRef": "N",
                      "Longitude": 2.3522, "LongitudeRef": "E"] as [String: Any],
        ]
        let resolved = WhiteFrameRenderer.resolveGalleryCaption(config: config, metadata: meta)

        #expect(resolved.leftPrimary == "iPhone 16 Pro", "a ticked entry still draws")
        #expect(resolved.rightPrimary == nil, "an unticked entry goes quiet where it sat")
    }

    @Test("Ticking it back brings the line back")
    func galleryLineReturns() {
        var config = config(.gallery)
        config.rightPrimary = .field(.gps)
        config.captionFields = [.gps]
        let meta: [String: Any] = ["{GPS}": [
            "Latitude": 48.8566, "LatitudeRef": "N",
            "Longitude": 2.3522, "LongitudeRef": "E"] as [String: Any]]

        #expect(WhiteFrameRenderer.resolveGalleryCaption(
            config: config, metadata: meta).rightPrimary?.contains("🇫🇷") == true)
    }

    @Test("A ticked entry no line names still shows")
    func gallerySpareFieldsLand() {
        // Gallery has four lines and the list has ten entries, so most ticks
        // name nothing. They used to draw nothing at all: the whole grid could
        // be ticked and the caption still read "iPhone 16 Pro" alone.
        var config = config(.gallery)
        config.leftPrimary = .field(.cameraModel)
        config.leftSecondary = .empty
        config.rightPrimary = .text("@osama")
        config.rightSecondary = .empty
        config.captionFields = [.cameraModel, .aperture, .iso, .format, .gps]

        let meta: [String: Any] = [
            "{TIFF}": ["Make": "Apple", "Model": "iPhone 16 Pro"],
            "{Exif}": ["FNumber": 1.8, "ISOSpeedRatings": [64]] as [String: Any],
            "PixelWidth": 4032, "PixelHeight": 3024,
            "{GPS}": ["Latitude": 48.8566, "LatitudeRef": "N",
                      "Longitude": 2.3522, "LongitudeRef": "E"] as [String: Any],
        ]
        let resolved = WhiteFrameRenderer.resolveGalleryCaption(config: config, metadata: meta)

        // Where it was taken sits under the device that was carried there;
        // what the camera was doing goes to the other column.
        #expect(resolved.leftSecondary?.contains("🇫🇷") == true)
        #expect(resolved.rightSecondary?.contains("f/1.8") == true)
        #expect(resolved.rightSecondary?.contains("64") == true)
        #expect(resolved.leftSecondary?.contains("f/1.8") == false)
        // The camera already has a line of its own and is not repeated.
        #expect(resolved.leftSecondary?.contains("iPhone") == false)
        #expect(resolved.rightPrimary == "@osama", "the user's own line is untouched")
    }

    @Test("Unticking a spare entry takes it back off the line")
    func gallerySpareFieldsLeave() {
        var config = config(.gallery)
        config.rightSecondary = .empty
        config.captionFields = [.cameraModel]
        let meta: [String: Any] = [
            "{TIFF}": ["Make": "Apple", "Model": "iPhone 16 Pro"],
            "{Exif}": ["FNumber": 1.8] as [String: Any],
        ]
        #expect(WhiteFrameRenderer.resolveGalleryCaption(
            config: config, metadata: meta).rightSecondary == nil)
    }

    @Test("A slot's own value keeps its place ahead of the spares")
    func gallerySlotLeadsItsLine() {
        var config = config(.gallery)
        config.rightSecondary = .field(.shutterSpeed)
        config.captionFields = [.shutterSpeed, .aperture]
        let meta: [String: Any] = [
            "{Exif}": ["ShutterSpeedValue": 6.0, "FNumber": 1.8] as [String: Any],
        ]
        let line = WhiteFrameRenderer.resolveGalleryCaption(
            config: config, metadata: meta).rightSecondary
        #expect(line?.hasPrefix("f/1.8") == false, "the assigned entry leads")
        #expect(line?.contains("f/1.8") == true, "and the spare follows it")
    }

    /// A phone's lens string, which is a spec rather than a name.
    private func phoneLens() -> [String: Any] {
        [
            "{TIFF}": ["Make": "Apple", "Model": "iPhone 15 Pro Max"],
            "{Exif}": [
                "LensModel": "iPhone 15 Pro Max back triple camera 6.765mm f/1.78",
                "FocalLength": 6.765, "FocalLenIn35mmFilm": 24,
                "FNumber": 1.8, "ISOSpeedRatings": [64],
            ] as [String: Any],
        ]
    }

    @Test("The lens does not repeat what its neighbours already say",
          arguments: FrameStyle.allCases)
    func lensDoesNotDuplicate(style: FrameStyle) {
        // "iPhone 15 Pro Max back triple camera 24mm f/1.78" beside "24mm"
        // and "f/1.8" printed the same three readings twice over.
        var config = config(style)
        config.captionFields = [.cameraModel, .lens, .focalLength, .aperture]
        let meta = phoneLens()

        let drawn: String
        switch style {
        case .gallery:
            let c = WhiteFrameRenderer.resolveGalleryCaption(config: config, metadata: meta)
            drawn = [c.leftPrimary, c.leftSecondary, c.rightPrimary, c.rightSecondary]
                .compactMap { $0 }.joined(separator: " ")
        case .print:
            let c = WhiteFrameRenderer.resolveCreditCaption(config: config, metadata: meta)
            drawn = c.lines.flatMap { $0 }.map(\.text).joined(separator: " ")
        case .banner:
            let c = WhiteFrameRenderer.resolveBannerCaption(config: config, metadata: meta)
            drawn = [c.maker, c.values, c.device].compactMap { $0 }.joined(separator: " ")
        case .classic:
            drawn = WhiteFrameRenderer.resolveCaption(config: config, metadata: meta) ?? ""
        }

        #expect(drawn.contains("back triple camera"), "\(style): the lens is still named")
        #expect(drawn.components(separatedBy: "iPhone 15 Pro Max").count == 2,
                "\(style): the device is named once, not twice — \(drawn)")
        #expect(drawn.components(separatedBy: "24mm").count == 2,
                "\(style): the focal length is printed once — \(drawn)")
        #expect(!drawn.contains("f/1.78"),
                "\(style): the lens's f-number duplicates the aperture — \(drawn)")
    }

    @Test("A lens keeps its readings when nothing else prints them")
    func lensKeepsItsOwnReadings() {
        #expect(EXIFTokenParser.lensText(metadata: phoneLens()) == "back triple camera 24mm f/1.78")
    }

    @Test("A camera lens keeps its product name intact")
    func productNameIsNotTrimmed() {
        // The millimetres and the f-number are part of what this lens is
        // called; dropping them names a lens that does not exist.
        let meta: [String: Any] = [
            "{TIFF}": ["Make": "Canon", "Model": "Canon EOS R5"],
            "{Exif}": [
                "LensModel": "RF24-70mm F2.8 L IS USM",
                "FocalLength": 50.0, "FocalLenIn35mmFilm": 50, "FNumber": 2.8,
            ] as [String: Any],
        ]
        #expect(EXIFTokenParser.lensText(metadata: meta, omitFocal: true, omitAperture: true)
                == "RF24-70mm F2.8 L IS USM")
    }

    // MARK: - The brand answers to the list like everything else

    @Test("Unticking every entry leaves the caption with nothing to say",
          arguments: FrameStyle.allCases)
    func nothingTickedDrawsNothing(style: FrameStyle) {
        // Reported against `print`: with the caption on and every box cleared,
        // "Apple" stayed on the mat. The maker was pushed onto the line ahead
        // of the entries rather than being one of them, so no box governed it.
        var config = config(style)
        config.captionFields = []
        let meta = EXIFMetadataFactory.realisticMetadata(model: "iPhone 16 Pro")
            .merging(metadata()) { _, new in new }

        let drawn = captionText(config, meta)
        #expect(drawn.isEmpty, "\(style): nothing is ticked, yet it drew — \(drawn)")

        // The brand *mark* keeps its own switch, which is visible in the same
        // panel: with the artwork turned off as well, there is nothing left and
        // the band collapses rather than sitting empty.
        config.logoEnabled = false
        #expect(!WhiteFrameRenderer.hasCaptionContent(config: config, metadata: meta),
                "\(style): the band should collapse rather than sit empty")
    }

    @Test("Ticking the brand brings it back", arguments: FrameStyle.allCases)
    func makerReturnsWhenTicked(style: FrameStyle) {
        var config = config(style)
        config.captionFields = [.maker]
        let meta = EXIFMetadataFactory.realisticMetadata(model: "iPhone 16 Pro")
            .merging(metadata()) { _, new in new }

        #expect(captionText(config, meta).contains("Apple"), "\(style): the brand is an entry now")
    }

    @Test("An unrecognised maker still draws nothing")
    func unknownMakerStaysQuiet() {
        // It resolves the same way the mark does, so a brand with no mark has
        // no name either — which is what it did before, and still does.
        var config = config(.print)
        config.captionFields = [.maker]
        let meta: [String: Any] = ["{TIFF}": ["Make": "Nobody", "Model": "Nothing"]]
        #expect(!captionText(config, meta).contains("Nobody"))
    }

    // MARK: - A video's caption

    @Test("A video names its maker, so it earns the same mark a photo does")
    func videoCarriesTheMake() {
        let meta = VideoProcessor.captionMetadata(
            model: "iPhone 15 Pro Max", make: "Apple", creationDate: nil, locationISO6709: nil)

        #expect(BrandMarkRegistry.brandKey(metadata: meta) == "apple",
                "the make was dropped, so the bar drew no logo and no maker")
        #expect(BrandMarkRegistry.displayName(metadata: meta) == "Apple")
        #expect(WhiteFrameRenderer.resolveSlot(.field(.cameraModel), metadata: meta)
                == "iPhone 15 Pro Max")
    }

    @Test("A video with no maker is not invented one")
    func videoWithoutMake() {
        let meta = VideoProcessor.captionMetadata(
            model: "Some Camera", make: nil, creationDate: nil, locationISO6709: nil)
        #expect(BrandMarkRegistry.brandKey(metadata: meta) == nil)
    }

    // MARK: - The date stands in for a missing exposure

    /// A video's metadata: a device and a date, and no exposure at all.
    private func videoMetadata() -> [String: Any] {
        VideoProcessor.captionMetadata(
            model: "iPhone 15 Pro Max", make: "Apple",
            creationDate: Date(timeIntervalSince1970: 1_757_000_000), locationISO6709: nil)
    }

    @Test("With no exposure to show, the date takes its place", arguments: FrameStyle.allCases)
    func dateFillsTheGap(style: FrameStyle) {
        var config = config(style)
        config.captionFields = WhiteFrameConfig.defaultCaptionFields
        let drawn = captionText(config, videoMetadata())
        #expect(drawn.contains("Sep 2025"), "\(style): nothing stood where the readings would be — \(drawn)")
    }

    @Test("Unticking the date removes it, exposure or not", arguments: FrameStyle.allCases)
    func untickingTheDateRemovesIt(style: FrameStyle) {
        var config = config(style)
        config.captionFields = WhiteFrameConfig.defaultCaptionFields.filter { $0 != .date }
        let drawn = captionText(config, videoMetadata())
        #expect(!drawn.contains("Sep 2025"), "\(style): the date ignored its checkbox — \(drawn)")
    }

    @Test("Ticking the date shows it even when the exposure is there",
          arguments: FrameStyle.allCases)
    func aTickedDateShowsBesideTheExposure(style: FrameStyle) {
        var config = config(style)
        config.captionFields = WhiteFrameConfig.defaultCaptionFields
        var meta = videoMetadata()
        meta["{Exif}"] = ["DateTimeOriginal": "2026:09:04 10:00:00",
                          "FNumber": 1.8, "ISOSpeedRatings": [64]] as [String: Any]

        let drawn = captionText(config, meta)
        #expect(drawn.contains("f/1.8"))
        #expect(drawn.contains("Sep 2026"), "\(style): the date ignored its checkbox — \(drawn)")
    }

    @Test("Date and time are separate entries", arguments: FrameStyle.allCases)
    func timeTicksApartFromTheDate(style: FrameStyle) {
        var meta = videoMetadata()
        meta["{Exif}"] = ["DateTimeOriginal": "2026:09:04 10:35:00"] as [String: Any]

        var dateOnly = config(style)
        dateOnly.captionFields = [.date]
        let withoutTime = captionText(dateOnly, meta)
        #expect(withoutTime.contains("Sep 2026"))
        #expect(!withoutTime.contains("10:35"), "\(style): the date dragged the time along — \(withoutTime)")

        var timeOnly = config(style)
        timeOnly.captionFields = [.time]
        let withoutDate = captionText(timeOnly, meta)
        #expect(withoutDate.contains("10:35"), "\(style): the time never appeared — \(withoutDate)")
        #expect(!withoutDate.contains("Sep 2026"), "\(style): the time dragged the date along — \(withoutDate)")
    }

    @Test("A day with no clock reading leaves the time quiet")
    func aDateOnlyStampHasNoTime() {
        let meta: [String: Any] = ["{Exif}": ["DateTimeOriginal": "2026:09:04"]]
        #expect(EXIFTokenParser.substitute("{date}", metadata: meta).contains("Sep 2026"))
        #expect(EXIFTokenParser.substitute("{time}", metadata: meta) == "--")
    }

    @Test("A line pointed at the date always shows it")
    func anAssignedDateAlwaysShows() {
        var config = config(.gallery)
        config.leftSecondary = .field(.date)
        config.captionFields = WhiteFrameConfig.defaultCaptionFields
        var meta = videoMetadata()
        meta["{Exif}"] = ["DateTimeOriginal": "2026:09:04 10:00:00", "FNumber": 1.8] as [String: Any]

        #expect(WhiteFrameRenderer.resolveGalleryCaption(config: config, metadata: meta)
            .leftSecondary?.contains("Sep 2026") == true)
    }

    /// Every line a style draws, run together — for asking whether a value
    /// appears at all, whatever the layout does with it.
    private func captionText(_ config: WhiteFrameConfig, _ meta: [String: Any]) -> String {
        switch config.style {
        case .gallery:
            let c = WhiteFrameRenderer.resolveGalleryCaption(config: config, metadata: meta)
            return [c.leftPrimary, c.leftSecondary, c.rightPrimary, c.rightSecondary]
                .compactMap { $0 }.joined(separator: " ")
        case .print:
            let c = WhiteFrameRenderer.resolveCreditCaption(config: config, metadata: meta)
            return c.lines.flatMap { $0 }.map(\.text).joined(separator: " ")
        case .banner:
            let c = WhiteFrameRenderer.resolveBannerCaption(config: config, metadata: meta)
            return [c.maker, c.values, c.device].compactMap { $0 }.joined(separator: " ")
        case .classic:
            return WhiteFrameRenderer.resolveCaption(config: config, metadata: meta) ?? ""
        }
    }

    // MARK: - A detail line breaks before it shrinks

    /// One unit of width per character, so the expected breaks are countable.
    private func measure(_ text: String) -> CGFloat { CGFloat(text.count) }

    @Test("A long detail line breaks at its gaps rather than shrinking")
    func detailLineWraps() {
        let gap = WhiteFrameRenderer.runGap
        let text = ["back dual camera", "26mm", "f/1.8", "1/25", "ISO 640"].joined(separator: gap)
        let lines = WhiteFrameRenderer.wrappedRuns(text, width: 25, limit: 3, measure: measure)

        #expect(lines.count > 1, "it did not fit on one line at this width")
        #expect(lines.allSatisfy { !$0.hasPrefix(" ") && !$0.hasSuffix(" ") })
        // Every reading survives, in order, and none is split.
        #expect(lines.joined(separator: gap) == text)
        for line in lines.dropLast() {
            #expect(measure(line) <= 25, "a line was left over its width with room to break: \(line)")
        }
    }

    @Test("The last line takes the remainder rather than growing the band")
    func wrapStopsAtTheLimit() {
        let gap = WhiteFrameRenderer.runGap
        let text = ["one", "two", "three", "four", "five"].joined(separator: gap)
        let lines = WhiteFrameRenderer.wrappedRuns(text, width: 3, limit: 2, measure: measure)

        #expect(lines.count == 2, "a band with room for two lines never gets a third")
        #expect(lines.joined(separator: gap) == text)
    }

    @Test("A line that fits is left alone")
    func shortLineIsNotWrapped() {
        #expect(WhiteFrameRenderer.wrappedRuns("f/1.8", width: 100, limit: 3, measure: measure) == ["f/1.8"])
    }

    @Test("Free text is nobody's field and is never filtered")
    func customTextSurvivesTheFilter() {
        var config = config(.gallery)
        config.rightPrimary = .text("@osama")
        config.captionFields = []
        #expect(WhiteFrameRenderer.resolveGalleryCaption(
            config: config, metadata: [:]).rightPrimary == "@osama")
    }

    @Test("Unticking the camera drops print's \"Shot on\" line too")
    func printHonoursTheIncludeList() {
        // The one place the checkbox used to mean something different: print
        // dropped the camera from its detail line but kept crediting it above.
        var config = config(.print)
        config.captionFields = [.iso]
        let resolved = WhiteFrameRenderer.resolveCreditCaption(
            config: config, metadata: metadata())
        #expect(resolved.credit.isEmpty)
    }

    // MARK: - The user's own credit

    /// The runs of the credit line as plain text, for comparing a whole line.
    private func creditText(_ config: WhiteFrameConfig, _ meta: [String: Any]) -> String {
        WhiteFrameRenderer.resolveCreditCaption(config: config, metadata: meta)
            .credit.map(\.text).joined()
    }

    @Test("The user's credit sits on the same line as the device")
    func creditWrapsTheDeviceLine() {
        // Not a third line: a signature belongs beside the credit it signs,
        // and three centred lines read as three rows of equipment data.
        var config = config(.print)
        config.creditPrefixText = "© Osama"
        let resolved = WhiteFrameRenderer.resolveCreditCaption(
            config: config, metadata: metadata())

        #expect(resolved.lines.count == 2)
        #expect(creditText(config, metadata()) == "© Osama Shot on iPhone 16 Pro")
    }

    @Test("It can follow the device as well as lead it")
    func creditCanTrail() {
        var config = config(.print)
        config.creditSuffixText = "2026"
        #expect(creditText(config, metadata()) == "Shot on iPhone 16 Pro 2026")
    }

    @Test("Both sides at once")
    func creditOnBothSides() {
        var config = config(.print)
        config.creditPrefixText = "© Osama"
        config.creditSuffixText = "2026"
        #expect(creditText(config, metadata()) == "© Osama Shot on iPhone 16 Pro 2026")
    }

    @Test("The device stays the only emphasised run")
    func onlyTheDeviceIsEmphasised() {
        var config = config(.print)
        config.creditPrefixText = "© Osama"
        config.creditSuffixText = "2026"
        let runs = WhiteFrameRenderer.resolveCreditCaption(
            config: config, metadata: metadata()).credit

        let heavy = runs.filter { $0.weight == .semibold }
        #expect(heavy.count == 1, "two focal points on one line and neither reads")
        #expect(heavy.first?.text == "iPhone 16 Pro")
    }

    @Test("Credit text made only of whitespace adds nothing")
    func blankCreditIsDropped() {
        var config = config(.print)
        config.creditPrefixText = "   "
        config.creditSuffixText = ""
        #expect(creditText(config, metadata()) == "Shot on iPhone 16 Pro")
    }

    @Test("Credit text substitutes tokens like any other caption text")
    func creditSubstitutesTokens() {
        var config = config(.print)
        config.creditPrefixText = "© {camera_model}"
        #expect(creditText(config, metadata()).hasPrefix("© iPhone 16 Pro Shot on"))
    }

    @Test("A photo with no device is still signed")
    func creditStandsAlone() {
        // "Shot on" needs a model, but the user's own text does not: this is
        // what lets a scan or an export with no metadata still carry a name.
        var config = config(.print)
        config.captionFields = []
        config.creditPrefixText = "© Osama"
        let resolved = WhiteFrameRenderer.resolveCreditCaption(config: config, metadata: [:])

        #expect(creditText(config, [:]) == "© Osama")
        #expect(!resolved.credit.contains { $0.text.contains("Shot on") })
        #expect(WhiteFrameRenderer.hasCaptionContent(config: config, metadata: [:]))
    }

    @Test("The band still holds two lines, not three")
    func bandIsUnchangedByTheCredit() {
        func bottom(_ credit: String) -> CGFloat {
            var c = config(.print)
            c.creditPrefixText = credit
            return FrameGeometry(config: c, sourceSize: Self.source,
                                 dpi: 300, hasCaptionContent: true).bottom
        }
        #expect(bottom("© Osama") == bottom(""))
    }

    @Test("The credit survives a saved template")
    func creditRoundTrips() throws {
        var config = config(.print)
        config.creditPrefixText = "© Osama"
        config.creditSuffixText = "2026"
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(WhiteFrameConfig.self, from: data)
        #expect(decoded.creditPrefixText == "© Osama")
        #expect(decoded.creditSuffixText == "2026")
    }

    @Test("Only print offers it")
    func onlyPrintOffersIt() {
        for style in FrameStyle.allCases {
            #expect(style.offersCreditText == (style == .print), "\(style.rawValue)")
        }
    }

    // MARK: - Drawing

    @Test("The credit caption lands in the bottom band, upright and inside the mat")
    func creditCaptionLandsInTheBand() throws {
        // The macOS Core Text path positions every line on its own baseline;
        // get that wrong and the text draws mirrored or outside the band, which
        // this catches without comparing a single glyph.
        var config = config(.print)
        // The camera has to be ticked for the credit line to draw at all: the
        // Include list is the master switch in every style.
        config.captionFields = [.cameraModel, .iso]
        let meta = EXIFMetadataFactory.realisticMetadata(model: "iPhone 16 Pro")
            .merging(metadata()) { _, new in new }
        let image = try rendered(config, metadata: meta)

        let geometry = FrameGeometry(
            config: config, sourceSize: Self.source,
            dpi: FrameGeometry.resolveDPI(from: meta, config: config, sourceSize: Self.source),
            hasCaptionContent: true)
        let band = geometry.captionBand

        // Ink is text, not shadow. Measured on this fixture the caption reads
        // 0.41 and the shadow's densest row 0.61, so the threshold between them
        // is what keeps this a test of the text.
        var inkRows: [Int] = []
        for y in 0..<image.height {
            for x in 0..<image.width where (image.grey(x: x, y: y) ?? 1) < 0.5 {
                inkRows.append(y)
                break
            }
        }
        let captionInk = inkRows.filter { CGFloat($0) >= band.minY && CGFloat($0) <= band.maxY }
        #expect(!captionInk.isEmpty, "the credit caption drew no ink in its band")

        // Two centred lines, so the ink spans more than one line's height.
        let span = CGFloat((captionInk.max() ?? 0) - (captionInk.min() ?? 0))
        #expect(span > geometry.captionFontSize,
                "expected two stacked lines, ink spans only \(span)pt")
    }

    // MARK: - Config

    @Test("Every style round-trips through a saved template",
          arguments: FrameStyle.allCases)
    func newStylesRoundTrip(style: FrameStyle) throws {
        let data = try JSONEncoder().encode(config(style))
        #expect(try JSONDecoder().decode(WhiteFrameConfig.self, from: data).style == style)
    }

    @Test("A style from a newer build still falls back to classic")
    func unknownStyleStillFallsBack() throws {
        let json = #"{"isEnabled":true,"metadataTextEnabled":true,"style":"holographic","textColorRGBA":[0,0,0,1]}"#
        #expect(try JSONDecoder().decode(WhiteFrameConfig.self, from: Data(json.utf8)).style == .classic)
    }

    @Test("A centred caption takes classic's grey; gallery keeps its darker tone")
    func defaultCaptionColourFollowsTheLayout() {
        func luminance(_ style: FrameStyle) -> CGFloat {
            WhiteFrameConfig(style: style).textColor.components?.first ?? 1
        }
        #expect(luminance(.print) == luminance(.classic))
        #expect(luminance(.gallery) < luminance(.classic),
                "the gallery caption is darker, to read on its mat")
    }
}

/// The maker's name shown on the credit caption's detail line, resolved through the same
/// path that picks `gallery`'s brand mark so the two can never disagree.
@Suite("Brand display names")
struct BrandDisplayNameTests {

    @Test("Every shipped brand produces a usable name")
    func everyBrandHasAName() {
        for key in BrandMarkRegistry.brandKeys {
            let name = BrandMarkRegistry.displayName(brandKey: key)
            #expect(!name.isEmpty)
            #expect(name.lowercased().replacingOccurrences(of: " ", with: "") == key,
                    "\(key) should differ from its key only in casing, got \(name)")
        }
    }

    @Test("Brands that style themselves unusually keep their own casing",
          arguments: [("dji", "DJI"), ("gopro", "GoPro"), ("oneplus", "OnePlus"),
                      ("oppo", "OPPO"), ("honor", "HONOR"), ("canon", "Canon"),
                      ("fujifilm", "Fujifilm")])
    func knownCasings(key: String, expected: String) {
        #expect(BrandMarkRegistry.displayName(brandKey: key) == expected)
    }

    @Test("A photo that earns a mark names the same maker")
    func nameAgreesWithTheMark() {
        let meta: [String: Any] = ["{TIFF}": ["Make": "NIKON CORPORATION", "Model": "NIKON Z 6"]]
        #expect(BrandMarkRegistry.brandKey(metadata: meta) == "nikon")
        #expect(BrandMarkRegistry.displayName(metadata: meta) == "Nikon")
    }

    @Test("An unrecognised maker has no name rather than a guessed one")
    func unknownMakerHasNoName() {
        #expect(BrandMarkRegistry.displayName(metadata: ["{TIFF}": ["Make": "Acme Optical"]]) == nil)
        #expect(BrandMarkRegistry.displayName(metadata: [:]) == nil)
    }
}

/// `print` lifts the photo off the mat with a drop shadow. Two variants: cast
/// downwards, so the photo rests on the mat, or even on all sides, so it floats.
@Suite("Print style")
struct PrintStyleTests {

    private static let source = CGSize(width: 600, height: 400)

    private func config(_ shadow: FrameShadow, captionEnabled: Bool = true) -> WhiteFrameConfig {
        WhiteFrameConfig(isEnabled: true, metadataTextEnabled: captionEnabled,
                         style: .print, outputDPI: 300, shadow: shadow)
    }

    private func geometry(_ config: WhiteFrameConfig, hasCaption: Bool = true) -> FrameGeometry {
        FrameGeometry(config: config, sourceSize: Self.source, dpi: 300,
                      hasCaptionContent: hasCaption)
    }

    // MARK: - Which styles cast a shadow

    @Test("Only print casts a shadow")
    func onlyPrintCastsAShadow() {
        for style in FrameStyle.allCases {
            var config = WhiteFrameConfig(isEnabled: true, style: style, outputDPI: 300)
            config.shadow = .bottom
            let blur = FrameGeometry(config: config, sourceSize: Self.source,
                                     dpi: 300, hasCaptionContent: true).shadowBlur
            #expect((blur > 0) == (style == .print), "\(style.rawValue) shadow blur: \(blur)")
        }
    }

    @Test("Bottom offsets the shadow downwards; all sides does not")
    func offsetPerVariant() {
        // The offset is the whole difference between the two looks: one rests
        // on the mat, the other floats parallel to it.
        #expect(geometry(config(.bottom)).shadowOffset > 0)
        #expect(geometry(config(.all)).shadowOffset == 0)
        #expect(geometry(config(.bottom)).shadowBlur == geometry(config(.all)).shadowBlur)
    }

    @Test("The shadow scales with the mat, like the keyline")
    func shadowScalesWithTheBorder() {
        var narrow = config(.bottom); narrow.borderMillimetres = 4
        var wide = config(.bottom); wide.borderMillimetres = 16
        #expect(geometry(wide).shadowBlur > geometry(narrow).shadowBlur)
    }

    @Test("The mat leaves room for the shadow and the caption, stacked")
    func bottomHoldsShadowAndCaption() {
        // Sharing the room rather than stacking it would print the caption on
        // top of the shadow.
        let withCaption = geometry(config(.bottom), hasCaption: true)
        let withoutCaption = geometry(config(.bottom, captionEnabled: false), hasCaption: false)
        #expect(withCaption.bottom > withoutCaption.bottom)
        #expect(withoutCaption.bottom >= withoutCaption.shadowBlur + withoutCaption.shadowOffset)
    }

    // MARK: - Fill and caption

    @Test("The print mat is one flat white, never graduated")
    func printMatIsFlatWhite() {
        // Even with the gradient flag set, which print does not read.
        var config = config(.bottom)
        config.gradientEnabled = true
        #expect(WhiteFrameRenderer.matFill(for: config)
                == .flat(CGColor(gray: 1.0, alpha: 1.0)))
    }

    @Test("Print's credit caption has every part optional")
    func printSharesTheCreditCaption() {
        let metadata: [String: Any] = ["{TIFF}": ["Make": "Apple", "Model": "iPhone 15 Pro Max"]]
        let resolved = WhiteFrameRenderer.resolveCreditCaption(
            config: config(.bottom), metadata: metadata)
        #expect(resolved.credit.last?.text == "iPhone 15 Pro Max")
        #expect(resolved.details?.hasPrefix("Apple") == true)

        // Nothing to say is a valid state, exactly as in every other style.
        #expect(WhiteFrameRenderer.resolveCreditCaption(
            config: config(.bottom), metadata: [:]).isEmpty)
        #expect(!WhiteFrameRenderer.hasCaptionContent(config: config(.bottom), metadata: [:]))
    }

    @Test("Both shadow variants round-trip through a saved template",
          arguments: [FrameShadow.bottom, .all])
    func shadowRoundTrips(shadow: FrameShadow) throws {
        let data = try JSONEncoder().encode(config(shadow))
        #expect(try JSONDecoder().decode(WhiteFrameConfig.self, from: data).shadow == shadow)
    }

    @Test("A template written before the shadow existed still decodes")
    func legacyTemplateGetsADefaultShadow() throws {
        let legacy = #"{"isEnabled":true,"metadataTextEnabled":true,"textColorRGBA":[0,0,0,1]}"#
        let decoded = try JSONDecoder().decode(WhiteFrameConfig.self, from: Data(legacy.utf8))
        #expect(decoded.shadow == .bottom)
    }

    @Test("A shadow value from a newer build falls back rather than failing")
    func unknownShadowFallsBack() throws {
        let json = #"{"isEnabled":true,"metadataTextEnabled":true,"textColorRGBA":[0,0,0,1],"shadow":"neon"}"#
        #expect(try JSONDecoder().decode(WhiteFrameConfig.self, from: Data(json.utf8)).shadow == .bottom)
    }

    // MARK: - What actually lands on the pixels

    /// The rendered mat, rasterised once, top-left origin.
    private func rendered(_ config: WhiteFrameConfig) throws -> (bytes: [UInt8], w: Int, h: Int) {
        let image = try WhiteFrameRenderer.render(
            config: config, sourceSize: Self.source, metadata: [:])
        let context = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])
        let cg = try #require(context.createCGImage(image, from: image.extent))
        let bytesPerRow = 4 * cg.width
        var data = [UInt8](repeating: 0, count: bytesPerRow * cg.height)
        data.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(
                data: raw.baseAddress, width: cg.width, height: cg.height,
                bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        }
        return (data, cg.width, cg.height)
    }

    /// Grey level at a point, or nil where the mat is transparent.
    private func grey(_ b: (bytes: [UInt8], w: Int, h: Int), _ x: Int, _ y: Int) -> Double? {
        guard x >= 0, x < b.w, y >= 0, y < b.h else { return nil }
        let o = 4 * b.w * y + 4 * x
        guard b.bytes[o + 3] > 0 else { return nil }
        return (Double(b.bytes[o]) + Double(b.bytes[o + 1]) + Double(b.bytes[o + 2])) / (3 * 255)
    }

    @Test("The shadow darkens the mat just below the photo")
    func shadowLandsBelowThePhoto() throws {
        let config = config(.bottom, captionEnabled: false)
        let g = geometry(config, hasCaption: false)
        let image = try rendered(config)
        let midX = Int(g.photoRect.midX)

        let justBelow = try #require(grey(image, midX, Int(g.photoRect.maxY) + 3))
        let farCorner = try #require(grey(image, 2, 2))
        #expect(justBelow < farCorner - 0.02,
                "expected shadow under the photo: \(justBelow) vs mat \(farCorner)")
    }

    @Test("Bottom keeps the mat above the photo clean; all sides darkens it too")
    func variantsDifferAboveThePhoto() throws {
        func aboveVsCorner(_ shadow: FrameShadow) throws -> (Double, Double) {
            let config = config(shadow, captionEnabled: false)
            let g = geometry(config, hasCaption: false)
            let image = try rendered(config)
            let above = try #require(grey(image, Int(g.photoRect.midX), Int(g.photoRect.minY) - 3))
            let corner = try #require(grey(image, 2, 2))
            return (above, corner)
        }
        let (bottomAbove, bottomCorner) = try aboveVsCorner(.bottom)
        let (allAbove, allCorner) = try aboveVsCorner(.all)

        // Offset downwards, so far less reaches above the photo than an even
        // shadow does — that contrast is what makes them two distinct looks.
        #expect(bottomCorner - bottomAbove < allCorner - allAbove)
        #expect(allCorner - allAbove > 0.02, "an all-sides shadow should reach above the photo")
    }

    @Test("The shadow never darkens the photograph itself")
    func shadowStaysOffThePhoto() throws {
        // The mat is composited over the photo, so a shadow that leaked into
        // the hole would wash over the picture. The hole must stay clear.
        let config = config(.all, captionEnabled: false)
        let g = geometry(config, hasCaption: false)
        let image = try rendered(config)
        for (x, y) in [(Int(g.photoRect.midX), Int(g.photoRect.midY)),
                       (Int(g.photoRect.minX) + 3, Int(g.photoRect.minY) + 3),
                       (Int(g.photoRect.maxX) - 3, Int(g.photoRect.maxY) - 3)] {
            #expect(grey(image, x, y) == nil, "the photo hole is opaque at (\(x), \(y))")
        }
    }

    // MARK: - Corners

    @Test("The photo's corners stay square",
          arguments: [FrameShadow.bottom, .all])
    func cornersAreNeverRounded(shadow: FrameShadow) throws {
        // Reported as rounded corners on an export. They are not: the hole is
        // a plain rect and its alpha steps straight from opaque to clear with
        // no intermediate value anywhere. What read as a curve was the shadow
        // hugging all four edges at once and doubling up where two met, which
        // is why it is now pushed downwards instead.
        //
        // No corner radius has ever been asked for, so this pins its absence.
        let config = config(shadow, captionEnabled: false)
        let g = geometry(config, hasCaption: false)
        let image = try rendered(config)

        let corners = [
            (Int(g.photoRect.minX), Int(g.photoRect.minY)),
            (Int(g.photoRect.maxX) - 1, Int(g.photoRect.minY)),
            (Int(g.photoRect.minX), Int(g.photoRect.maxY) - 1),
            (Int(g.photoRect.maxX) - 1, Int(g.photoRect.maxY) - 1),
        ]
        for (cx, cy) in corners {
            // The corner pixel itself belongs to the photo, so it is clear...
            #expect(grey(image, cx, cy) == nil,
                    "photo corner (\(cx), \(cy)) is covered by mat — that is a rounded corner")
        }

        // ...and no pixel along the top edge is partly covered, which is what a
        // rounded or antialiased corner would look like.
        let y = Int(g.photoRect.minY) + 1
        for x in Int(g.photoRect.minX)..<(Int(g.photoRect.minX) + 12) {
            #expect(grey(image, x, y) == nil, "mat intrudes into the photo at (\(x), \(y))")
        }
    }

    @Test("Print's caption is larger than classic's and its band has more air")
    func printCaptionIsGenerous() {
        #expect(WhiteFrameConfig.defaultCaptionMillimetres(for: .print)
                > WhiteFrameConfig.defaultCaptionMillimetres(for: .classic))
        #expect(FrameMetrics.reference.printCaptionBlockPaddingLines
                > FrameMetrics.reference.captionBlockPaddingLines)

        // Both together, at the same border: print's band clears classic's.
        func bottom(_ style: FrameStyle) -> CGFloat {
            var c = WhiteFrameConfig(isEnabled: true, style: style, outputDPI: 300)
            c.captionTextMillimetres = WhiteFrameConfig.defaultCaptionMillimetres(for: style)
            return FrameGeometry(config: c, sourceSize: Self.source,
                                 dpi: 300, hasCaptionContent: true).bottom
        }
        #expect(bottom(.print) > bottom(.classic))
    }

    @Test("The shadow is dark enough to read as depth")
    func shadowIsProminent() {
        // A shadow on a white mat carries the whole three-dimensional reading
        // with no perspective or highlight to help it.
        #expect(FrameMetrics.reference.shadowOpacity >= 0.4)
        // And directional rather than an even halo, or it wraps the corners.
        #expect(FrameMetrics.reference.shadowOffsetToBlur >= 0.4)
    }
}

/// The photo has to land exactly in the mat's hole.
///
/// It did not: the canvas is rounded up to an even height and that spare row
/// goes to the mat, but the photo was placed at the bottom mat's height, so it
/// sat one row low and left a transparent line along its top edge. Against a
/// pale mat that exported as an invisible hairline; against `print`'s dark
/// all-round shadow it was plainly a bright line.
@Suite("Photo aligns with the mat hole")
struct FramedPhotoAlignmentTests {

    /// A source size whose framed height is odd before rounding, so the
    /// even-rounding actually has a row to add — without that this passes
    /// whatever the alignment.
    private func sizesForcingOddRounding() -> [CGSize] {
        var sizes: [CGSize] = []
        for height in 400...460 {
            let source = CGSize(width: 600, height: CGFloat(height))
            let config = WhiteFrameConfig(isEnabled: true, metadataTextEnabled: false,
                                          style: .print, outputDPI: 300)
            let g = FrameGeometry(config: config, sourceSize: source,
                                  dpi: 300, hasCaptionContent: false)
            let raw = source.height + g.top + g.bottom
            if g.framedSize.height > raw { sizes.append(source) }
            if sizes.count == 3 { break }
        }
        return sizes
    }

    @Test("Rounding a canvas up never opens a gap above the photo")
    func noGapAboveThePhoto() throws {
        let sizes = sizesForcingOddRounding()
        #expect(!sizes.isEmpty, "no source size exercised the even-rounding path")

        for source in sizes {
            let config = WhiteFrameConfig(isEnabled: true, metadataTextEnabled: false,
                                          style: .print, outputDPI: 300)
            let g = FrameGeometry(config: config, sourceSize: source,
                                  dpi: 300, hasCaptionContent: false)

            let rounding = g.framedSize.height - (source.height + g.top + g.bottom)
            #expect(rounding > 0, "this size was chosen to exercise rounding")

            // Where the hole is, in Core Image's bottom-left space.
            let holeOriginY = g.framedSize.height - g.photoRect.maxY
            // What the engine used to use, and why it was wrong.
            let oldPlacement = g.bottom

            #expect(holeOriginY != oldPlacement,
                    "this size should expose the difference the rounding makes")
            #expect(holeOriginY == g.bottom + rounding,
                    "the spare row belongs to the bottom mat, under the photo")
        }
    }

    @Test("Every style composites the photo flush with its hole")
    func photoIsFlushInEveryStyle() throws {
        // End to end through the real graph: a solid red source, framed, then
        // read back at the photo's top edge. A misplacement shows as mat or
        // transparency where red should be.
        for style in FrameStyle.allCases {
            var frame = WhiteFrameConfig(isEnabled: true, metadataTextEnabled: false,
                                         style: style, outputDPI: 300)
            frame.shadow = .all

            let source = CGSize(width: 601, height: 401)
            let g = FrameGeometry(config: frame, sourceSize: source,
                                  dpi: 300, hasCaptionContent: false)
            let mat = try WhiteFrameRenderer.render(
                config: frame, geometry: g, metadata: [:], scale: 1)

            let photo = CIImage(color: CIColor(red: 1, green: 0, blue: 0))
                .cropped(to: CGRect(origin: .zero, size: source))
            let placed = photo.transformed(by: CGAffineTransform(
                translationX: g.photoRect.minX,
                y: g.framedSize.height - g.photoRect.maxY))
            let framed = mat.composited(over: placed)
                .cropped(to: CGRect(origin: .zero, size: g.framedSize))

            let ctx = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])
            let cg = try #require(ctx.createCGImage(framed, from: framed.extent))
            let bpr = 4 * cg.width
            var px = [UInt8](repeating: 0, count: bpr * cg.height)
            px.withUnsafeMutableBytes { raw in
                guard let c = CGContext(data: raw.baseAddress, width: cg.width, height: cg.height,
                                        bitsPerComponent: 8, bytesPerRow: bpr,
                                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
                c.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
            }

            // The first row of the photo, and the last, must both be red.
            let x = Int(g.photoRect.midX)
            for (label, y) in [("top", Int(g.photoRect.minY)),
                               ("bottom", Int(g.photoRect.maxY) - 1)] {
                let o = bpr * y + 4 * x
                let (r, gc, b) = (Int(px[o]), Int(px[o + 1]), Int(px[o + 2]))
                #expect(r > 200 && gc < 80 && b < 80,
                        "\(style.rawValue): \(label) row of the photo is (\(r), \(gc), \(b)), not the photo")
            }
        }
    }
}

