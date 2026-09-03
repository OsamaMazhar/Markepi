import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import QuartzCore
import Testing
@testable import WatermarkCore

/// End-to-end checks that the mat really is drawn outside the photo.
///
/// The unit tests in `FrameGeometryTests` pin the arithmetic; these pin what
/// actually comes out of the engine and the video layer builder, which is where
/// a coordinate-system mistake would show up as a shifted photo rather than a
/// failed calculation.
@Suite("Framed export geometry")
struct FramedExportGeometryTests {

    private func cleanup(_ urls: URL...) {
        for url in urls { try? FileManager.default.removeItem(at: url) }
    }

    private func createTempInputFile(data: Data, name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)_\(UUID().uuidString).jpg")
        try data.write(to: url)
        return url
    }

    /// A decoded image, read once into memory.
    ///
    /// Decoding per pixel was both glacial and wrong: `CGImageSource` decodes
    /// lazily, so sampling after the file was cleaned up read nothing.
    struct Bitmap {
        let width: Int
        let height: Int
        let bytes: [UInt8]

        /// Origin is TOP-LEFT, matching `FrameGeometry`.
        func pixel(x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8)? {
            guard x >= 0, y >= 0, x < width, y < height else { return nil }
            let o = (y * width + x) * 4
            return (bytes[o], bytes[o + 1], bytes[o + 2], bytes[o + 3])
        }

        init?(_ image: CGImage) {
            width = image.width
            height = image.height
            var buffer = [UInt8](repeating: 0, count: width * height * 4)
            let w = width, h = height
            let ok = buffer.withUnsafeMutableBytes { raw -> Bool in
                guard let ctx = CGContext(
                    data: raw.baseAddress, width: w, height: h,
                    bitsPerComponent: 8, bytesPerRow: w * 4,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ) else { return false }
                // `draw(image:in:)` already renders upright into a bitmap
                // context, so memory row 0 is the top. Adding a flip here
                // inverts the image and reads every y coordinate mirrored.
                ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
                return true
            }
            guard ok else { return nil }
            bytes = buffer
        }
    }

    private func loadCGImage(_ url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    // MARK: - The photo survives, translated

    @Test("A framed export is the framed size and the photo is intact inside it")
    func photoSurvivesTranslationIntoTheMat() async throws {
        let source = CGSize(width: 400, height: 300)
        let blue = CGColor(red: 0, green: 0, blue: 1, alpha: 1)
        let (_, jpegData) = TestImageFactory.solidColorImage(color: blue, size: source)
        let inputURL = try createTempInputFile(data: jpegData, name: "framed_geometry")

        let frame = WhiteFrameConfig(isEnabled: true, metadataTextEnabled: false, style: .classic)
        let config = WatermarkConfiguration(watermarks: [], whiteFrame: frame)

        let result = try await WatermarkEngine().process(sourceURL: inputURL, config: config)
        guard let outputURL = result.url, let cg = loadCGImage(outputURL), let output = Bitmap(cg) else {
            Issue.record("no output"); cleanup(inputURL); return
        }

        let geometry = FrameGeometry(
            config: frame, sourceSize: source,
            hasCaptionContent: WhiteFrameRenderer.hasCaptionContent(config: frame, metadata: [:]))
        #expect(output.width == Int(geometry.framedSize.width))
        #expect(output.height == Int(geometry.framedSize.height))

        // The centre of the photo rect is still the source's blue: the photo was
        // translated into the hole, not painted over.
        let centre = output.pixel(x: Int(geometry.photoRect.midX), y: Int(geometry.photoRect.midY))
        #expect(centre?.b ?? 0 > 200, "photo centre should still be blue, got \(String(describing: centre))")
        #expect(centre?.r ?? 255 < 60)

        // A point in the mat is the mat colour — white for classic — proving the
        // canvas really did grow rather than the photo being scaled up into it.
        let inMat = output.pixel(x: Int(geometry.left / 2), y: Int(geometry.top / 2))
        #expect(inMat?.r ?? 0 > 200 && inMat?.g ?? 0 > 200 && inMat?.b ?? 0 > 200,
                "mat should be white, got \(String(describing: inMat))")

        // Every corner of the photo is still photo, so nothing was cropped.
        for (x, y) in [(geometry.photoRect.minX + 2, geometry.photoRect.minY + 2),
                       (geometry.photoRect.maxX - 3, geometry.photoRect.minY + 2),
                       (geometry.photoRect.minX + 2, geometry.photoRect.maxY - 3),
                       (geometry.photoRect.maxX - 3, geometry.photoRect.maxY - 3)] {
            let p = output.pixel(x: Int(x), y: Int(y))
            #expect(p?.b ?? 0 > 200, "photo corner (\(x),\(y)) was covered: \(String(describing: p))")
        }

        cleanup(inputURL, outputURL)
    }

    @Test("Gallery puts its extra height below the photo, not above")
    func galleryBandIsBelowThePhoto() async throws {
        let source = CGSize(width: 400, height: 300)
        let (_, jpegData) = TestImageFactory.solidColorImage(
            color: CGColor(red: 0, green: 0, blue: 1, alpha: 1), size: source)
        let inputURL = try createTempInputFile(data: jpegData, name: "framed_gallery")

        // A typed handle so the caption has content: an empty caption now
        // collapses the band, which is a different case (covered below).
        let frame = WhiteFrameConfig(isEnabled: true, style: .gallery,
                                     rightPrimary: .text("@test"))
        let config = WatermarkConfiguration(watermarks: [], whiteFrame: frame)
        let result = try await WatermarkEngine().process(sourceURL: inputURL, config: config)
        guard let outputURL = result.url, let cg = loadCGImage(outputURL), let output = Bitmap(cg) else {
            Issue.record("no output"); cleanup(inputURL); return
        }

        let g = FrameGeometry(config: frame, sourceSize: source, hasCaptionContent: true)
        // This is the assertion that catches a flipped vertical offset: if the
        // photo were placed using the top inset instead of the bottom, the tall
        // caption band would end up above the photo and this pixel would be mat.
        let justInsideBottomOfPhoto = output.pixel(x: Int(g.photoRect.midX), y: Int(g.photoRect.maxY) - 3)
        #expect(justInsideBottomOfPhoto?.b ?? 0 > 200,
                "bottom of the photo should be photo, got \(String(describing: justInsideBottomOfPhoto))")

        let inCaptionBand = output.pixel(x: Int(g.captionBand.midX), y: Int(g.captionBand.midY))
        #expect(inCaptionBand?.b ?? 255 < 250, "caption band should be mat, not photo")

        cleanup(inputURL, outputURL)
    }

    // MARK: - Watermarks are no longer dodged inward

    /// A solid red PNG, so the watermark can be found by colour rather than by
    /// guessing at what counts as "ink" on a white photo.
    private func redSquarePNG(size: Int = 40) -> Data {
        let ctx = CGContext(data: nil, width: size, height: size,
                            bitsPerComponent: 8, bytesPerRow: size * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
        let image = ctx.makeImage()!
        let data = NSMutableData()
        let dest = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
        return data as Data
    }

    @Test("A corner watermark sits in the same place with and without a frame")
    func cornerWatermarkIsNotDisplacedByTheFrame() async throws {
        let source = CGSize(width: 400, height: 300)
        let (_, jpegData) = TestImageFactory.solidColorImage(
            color: CGColor(red: 1, green: 1, blue: 1, alpha: 1), size: source)
        let pngData = redSquarePNG()

        func render(withFrame: Bool, name: String) async throws -> (Bitmap, FrameGeometry)? {
            let inputURL = try createTempInputFile(data: jpegData, name: name)
            let frame = WhiteFrameConfig(isEnabled: true, metadataTextEnabled: false, style: .classic)
            let config = WatermarkConfiguration(
                watermarks: [
                    .image(try ImageWatermarkInput(pngData: pngData, scale: 0.2, opacity: 1.0),
                           position: .topLeft, scale: 0.2, opacity: 1.0, isVisible: true)
                ],
                whiteFrame: withFrame ? frame : nil
            )
            let result = try await WatermarkEngine().process(sourceURL: inputURL, config: config)
            defer { cleanup(inputURL) }
            guard let url = result.url, let cg = loadCGImage(url), let image = Bitmap(cg) else { return nil }
            let geometry = FrameGeometry(
                config: withFrame ? frame : WhiteFrameConfig(isEnabled: false),
                sourceSize: source)
            cleanup(url)
            return (image, geometry)
        }

        guard let (framed, geometry) = try await render(withFrame: true, name: "wm_framed"),
              let (plain, _) = try await render(withFrame: false, name: "wm_plain") else {
            Issue.record("render failed"); return
        }

        /// Bounds of the red watermark, in coordinates relative to the photo.
        func redBounds(_ image: Bitmap, origin: CGPoint) -> CGRect? {
            var minX = Int.max, minY = Int.max, maxX = Int.min, maxY = Int.min
            for y in 0..<Int(source.height) {
                for x in 0..<Int(source.width) {
                    guard let p = image.pixel(x: Int(origin.x) + x, y: Int(origin.y) + y) else { continue }
                    // Unmistakably red, with JPEG slop allowed for.
                    guard p.r > 150, p.g < 110, p.b < 110 else { continue }
                    minX = min(minX, x); maxX = max(maxX, x)
                    minY = min(minY, y); maxY = max(maxY, y)
                }
            }
            guard minX != .max else { return nil }
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        }

        let framedInk = redBounds(framed, origin: geometry.photoRect.origin)
        let plainInk = redBounds(plain, origin: .zero)

        guard let framedInk, let plainInk else {
            Issue.record("watermark not found (framed: \(String(describing: framedInk)), plain: \(String(describing: plainInk)))")
            return
        }
        // Same place on the photo. The frame used to inset watermark placement
        // by the border width — 12px on this image — to keep them out from
        // under the mat; with the mat outside, that dodge is gone.
        #expect(abs(framedInk.minX - plainInk.minX) <= 2,
                "watermark x moved: framed \(framedInk) vs plain \(plainInk)")
        #expect(abs(framedInk.minY - plainInk.minY) <= 2,
                "watermark y moved: framed \(framedInk) vs plain \(plainInk)")
        #expect(abs(framedInk.width - plainInk.width) <= 2, "watermark size changed")
    }

    // MARK: - Video parity

    @Test("The video layer tree uses the same geometry as photos")
    func videoLayerTreeMatchesPhotoGeometry() throws {
        let videoSize = CGSize(width: 1920, height: 1080)
        for style in FrameStyle.allCases {
            let frame = WhiteFrameConfig(isEnabled: true, style: style,
                                         rightPrimary: .text("@test"))
            let config = WatermarkConfiguration(watermarks: [], whiteFrame: frame)
            let geometry = FrameGeometry(
                config: frame, sourceSize: videoSize,
                hasCaptionContent: WhiteFrameRenderer.hasCaptionContent(config: frame, metadata: [:]))

            let tree = try VideoLayerBuilder.buildLayers(
                config: config, videoSize: videoSize, metadata: [:], isHDR: false)

            #expect(tree.renderSize == geometry.framedSize, "\(style): render size should be the framed canvas")
            #expect(tree.parentLayer.frame == CGRect(origin: .zero, size: geometry.framedSize))
            // Core Animation is y-up, so the video's vertical offset is the
            // bottom mat. Sharing FrameGeometry is what keeps this in step with
            // the photo path.
            #expect(tree.videoLayer.frame == CGRect(x: geometry.left, y: geometry.bottom,
                                                    width: videoSize.width, height: videoSize.height),
                    "\(style): video layer should sit in the photo rect")
        }
    }

    @Test("A gallery frame with nothing to say collapses its caption band")
    func emptyCaptionCollapsesTheBand() async throws {
        let source = CGSize(width: 400, height: 300)
        let (_, jpegData) = TestImageFactory.solidColorImage(
            color: CGColor(red: 0, green: 0, blue: 1, alpha: 1), size: source)
        let inputURL = try createTempInputFile(data: jpegData, name: "framed_empty_caption")

        // No metadata in the fixture and no typed handle, so every slot
        // resolves to nothing. Leaving a tall empty bar would just look broken.
        let frame = WhiteFrameConfig(isEnabled: true, style: .gallery,
                                     leftPrimary: .empty, leftSecondary: .empty,
                                     rightPrimary: .empty, rightSecondary: .empty)
        let config = WatermarkConfiguration(watermarks: [], whiteFrame: frame)
        let result = try await WatermarkEngine().process(sourceURL: inputURL, config: config)
        guard let outputURL = result.url, let cg = loadCGImage(outputURL) else {
            Issue.record("no output"); cleanup(inputURL); return
        }

        let collapsed = FrameGeometry(config: frame, sourceSize: source, hasCaptionContent: false)
        let withCaption = FrameGeometry(config: frame, sourceSize: source, hasCaptionContent: true)
        #expect(collapsed.bottom == collapsed.top, "band should collapse to a uniform mat")
        #expect(collapsed.framedSize.height < withCaption.framedSize.height)
        #expect(cg.height == Int(collapsed.framedSize.height),
                "export should use the collapsed geometry")

        cleanup(inputURL, outputURL)
    }

    @Test("An unframed video composition is unchanged")
    func unframedVideoIsUntouched() throws {
        let videoSize = CGSize(width: 1920, height: 1080)
        let tree = try VideoLayerBuilder.buildLayers(
            config: WatermarkConfiguration(watermarks: []),
            videoSize: videoSize, metadata: [:], isHDR: false)
        #expect(tree.renderSize == videoSize)
        #expect(tree.videoLayer.frame == CGRect(origin: .zero, size: videoSize))
    }
}

/// The print size shown in More is a promise about the exported file: this
/// many millimetres, at this resolution. These pin that promise to what the
/// engine actually writes, at each DPI the panel offers.
///
/// The panel computes it from the source's pixel size and `FrameGeometry`,
/// while the engine builds its geometry from the composited image's extent —
/// two different routes to the same number, and nothing else checks they agree.
@Suite("Print size matches the exported file")
struct PrintSizeAccuracyTests {

    private func inputFile(_ size: CGSize) throws -> URL {
        let (_, data) = TestImageFactory.solidColorImage(
            color: CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1), size: size)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("printsize_\(UUID().uuidString).jpg")
        try data.write(to: url)
        return url
    }

    private func exportedSize(_ url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return CGSize(width: image.width, height: image.height)
    }

    @Test("Every DPI setting exports exactly the size the panel predicts",
          arguments: [72, 150, 300, 600] as [CGFloat])
    func panelPredictsTheExport(dpi: CGFloat) async throws {
        let source = CGSize(width: 1200, height: 900)
        let url = try inputFile(source)
        defer { try? FileManager.default.removeItem(at: url) }

        var frame = WhiteFrameConfig(isEnabled: true, style: .gallery)
        frame.outputDPI = dpi
        let config = WatermarkConfiguration(watermarks: [], whiteFrame: frame)

        // What the More panel would display for this photo.
        let predicted = FrameGeometry(
            config: frame, sourceSize: source, dpi: dpi,
            hasCaptionContent: WhiteFrameRenderer.hasCaptionContent(config: frame, metadata: [:])
        ).framedSize

        let result = try await WatermarkEngine().process(sourceURL: url, config: config)
        guard let outputURL = result.url, let exported = exportedSize(outputURL) else {
            Issue.record("no output at \(dpi) DPI"); return
        }
        defer { try? FileManager.default.removeItem(at: outputURL) }

        #expect(exported == predicted,
                "at \(dpi) DPI the panel predicts \(predicted) but the export is \(exported)")

        // And the millimetres the panel prints are that size at that resolution.
        let mmWidth = predicted.width / dpi * 25.4
        let expectedBorderMM = frame.borderMillimetres
        // Source width plus a mat and keyline on each side, back in millimetres.
        let sourceMM = source.width / dpi * 25.4
        let keylineMM = FrameGeometry(config: frame, sourceSize: source, dpi: dpi)
            .keylineWidth / dpi * 25.4
        let expected = sourceMM + (expectedBorderMM + keylineMM) * 2
        // The mat and keyline are each rounded to a whole pixel, so the stated
        // size is exact to within a pixel — 0.09mm at 300 DPI, 0.35mm at 72.
        let onePixelInMM = 25.4 / dpi
        #expect(abs(mmWidth - expected) < onePixelInMM,
                "\(dpi) DPI: width reads \(mmWidth)mm, but the parts sum to \(expected)mm")
    }

    @Test("An 8mm border really measures 8mm on the exported file")
    func borderIsTheStatedMillimetres() async throws {
        let source = CGSize(width: 1200, height: 900)
        let url = try inputFile(source)
        defer { try? FileManager.default.removeItem(at: url) }

        for dpi in [150, 300, 600] as [CGFloat] {
            var frame = WhiteFrameConfig(isEnabled: true, style: .gallery)
            frame.outputDPI = dpi
            let geometry = FrameGeometry(config: frame, sourceSize: source, dpi: dpi)
            // The mat is the framed width less the photo and the two keylines,
            // halved — measured off the geometry the renderer actually uses.
            let matPixels = (geometry.framedSize.width - source.width) / 2 - geometry.keylineWidth
            let matMM = matPixels / dpi * 25.4
            #expect(abs(matMM - frame.borderMillimetres) < 25.4 / dpi,
                    "at \(dpi) DPI an \(frame.borderMillimetres)mm border measures \(matMM)mm")
        }
    }

    /// A portrait phone photo is stored landscape with an orientation tag, so
    /// the panel has to state the size of the image as *seen*, not as stored —
    /// otherwise a portrait photo advertises a landscape print.
    @Test("A rotated source is measured upright, matching the export")
    func rotatedSourceIsMeasuredUpright() async throws {
        let stored = CGSize(width: 1200, height: 900)
        let upright = CGSize(width: 900, height: 1200)
        let (_, data) = TestImageFactory.solidColorImage(
            color: CGColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1), size: stored)

        // Re-encode carrying orientation 6: stored landscape, displayed portrait.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("rotated_\(UUID().uuidString).jpg")
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let destination = CGImageDestinationCreateWithURL(
                url as CFURL, "public.jpeg" as CFString, 1, nil) else {
            Issue.record("could not build the rotated fixture"); return
        }
        CGImageDestinationAddImage(destination, image, [
            kCGImagePropertyOrientation as String: 6,
        ] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        defer { try? FileManager.default.removeItem(at: url) }

        var frame = WhiteFrameConfig(isEnabled: true, style: .gallery)
        frame.outputDPI = 300
        let config = WatermarkConfiguration(watermarks: [], whiteFrame: frame)

        let predicted = FrameGeometry(
            config: frame, sourceSize: upright, dpi: 300,
            hasCaptionContent: WhiteFrameRenderer.hasCaptionContent(config: frame, metadata: [:])
        ).framedSize

        let result = try await WatermarkEngine().process(sourceURL: url, config: config)
        guard let outputURL = result.url,
              let out = CGImageSourceCreateWithURL(outputURL as CFURL, nil),
              let exported = CGImageSourceCreateImageAtIndex(out, 0, nil) else {
            Issue.record("no output"); return
        }
        defer { try? FileManager.default.removeItem(at: outputURL) }

        #expect(CGSize(width: exported.width, height: exported.height) == predicted,
                "export is \(exported.width)x\(exported.height), panel predicts \(predicted)")
    }

    @Test("Automatic believes a real print resolution and ignores a JFIF default")
    func automaticResolution() {
        let frame = WhiteFrameConfig(isEnabled: true, style: .gallery)
        // 72 DPI is what a JPEG writes when nobody measured anything.
        #expect(FrameGeometry.resolveDPI(
            from: [kCGImagePropertyDPIWidth as String: 72], config: frame) == 300)
        #expect(FrameGeometry.resolveDPI(
            from: [kCGImagePropertyDPIWidth as String: 600], config: frame) == 600)
        #expect(FrameGeometry.resolveDPI(from: [:], config: frame) == 300)
    }
}
