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
                // CGContext is y-up; flip so row 0 is the TOP.
                ctx.translateBy(x: 0, y: CGFloat(h))
                ctx.scaleBy(x: 1, y: -1)
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

        let geometry = FrameGeometry(config: frame, sourceSize: source)
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

        let frame = WhiteFrameConfig(isEnabled: true, metadataTextEnabled: false, style: .gallery)
        let config = WatermarkConfiguration(watermarks: [], whiteFrame: frame)
        let result = try await WatermarkEngine().process(sourceURL: inputURL, config: config)
        guard let outputURL = result.url, let cg = loadCGImage(outputURL), let output = Bitmap(cg) else {
            Issue.record("no output"); cleanup(inputURL); return
        }

        let g = FrameGeometry(config: frame, sourceSize: source)
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
            let frame = WhiteFrameConfig(isEnabled: true, metadataTextEnabled: false, style: style)
            let config = WatermarkConfiguration(watermarks: [], whiteFrame: frame)
            let geometry = FrameGeometry(config: frame, sourceSize: videoSize)

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
