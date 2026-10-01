import AVFoundation
import CoreImage
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import MarkepiCore

/// Free vs Pro export output: size, HDR, metadata, the Markepi mark and where it goes.
@Suite("Free tier exports")
struct FreeTierExportTests {

    // MARK: - Fixtures

    /// A camera-like photo (gradient + grain, so it compresses like a real one)
    /// with realistic EXIF/GPS, written as a high-quality JPEG.
    private func cameraPhoto(width: Int = 4032, height: Int = 3024) throws -> URL {
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        let gradient = CIFilter(name: "CILinearGradient", parameters: [
            "inputPoint0": CIVector(x: 0, y: 0), "inputPoint1": CIVector(x: CGFloat(width), y: CGFloat(height)),
            "inputColor0": CIColor(red: 0.15, green: 0.35, blue: 0.6), "inputColor1": CIColor(red: 0.9, green: 0.7, blue: 0.4),
        ])!.outputImage!.cropped(to: rect)
        let noise = CIFilter(name: "CIRandomGenerator")!.outputImage!.cropped(to: rect)
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0.12, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 0.12, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 0.12, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputBiasVector": CIVector(x: -0.06, y: -0.06, z: -0.06, w: 0)])
        let image = noise.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: gradient])
        let cg = try #require(CIContext().createCGImage(image, from: rect, format: .RGBA8,
                                                         colorSpace: CGColorSpace(name: CGColorSpace.sRGB)))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("free_\(UUID().uuidString).jpg")
        let dest = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        var props = EXIFMetadataFactory.realisticMetadata()
        props[kCGImageDestinationLossyCompressionQuality as String] = 0.95
        CGImageDestinationAddImage(dest, cg, props as CFDictionary)
        #expect(CGImageDestinationFinalize(dest))
        return url
    }

    private func flatPhoto(width: Int = 1200, height: Int = 900) throws -> URL {
        let (_, data) = TestImageFactory.solidColorImage(
            color: CGColor(red: 0.45, green: 0.45, blue: 0.45, alpha: 1),
            size: CGSize(width: width, height: height))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("flat_\(UUID().uuidString).jpg")
        try data.write(to: url)
        return url
    }

    private func props(_ url: URL) -> [String: Any] {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return [:] }
        return CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any] ?? [:]
    }

    private func fileSize(_ url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }

    private func pixels(_ url: URL) throws -> (CGImage, [UInt8]) {
        let src = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let img = try #require(CGImageSourceCreateImageAtIndex(src, 0, nil))
        var buf = [UInt8](repeating: 0, count: img.width * img.height * 4)
        let ctx = try #require(CGContext(data: &buf, width: img.width, height: img.height, bitsPerComponent: 8,
                                         bytesPerRow: img.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
        return (img, buf)
    }

    /// Bounding box (top-left origin, pixels) of pixels that differ by more
    /// than `threshold` between two same-size images; nil if none do.
    private func diffBox(_ a: URL, _ b: URL, threshold: Int = 40) throws -> CGRect? {
        let (ia, pa) = try pixels(a), (_, pb) = try pixels(b)
        var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
        for y in 0..<ia.height {
            for x in 0..<ia.width {
                let i = (y * ia.width + x) * 4
                let d = abs(Int(pa[i]) - Int(pb[i])) + abs(Int(pa[i + 1]) - Int(pb[i + 1])) + abs(Int(pa[i + 2]) - Int(pb[i + 2]))
                if d > threshold { minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y) }
            }
        }
        return maxX < 0 ? nil : CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    private func text(_ s: String, at p: WatermarkPosition) -> WatermarkLayer {
        .text(TextWatermarkInput(text: s, fontSize: 48, opacity: 1), position: p, scale: 0.06, opacity: 1, isVisible: true)
    }

    // MARK: - Photo output (export-tiers)

    @Test("Free photo: 2048 px long side, ≤ 30% of Pro, metadata kept")
    func freePhotoIsSmaller() async throws {
        let src = try cameraPhoto()
        let engine = WatermarkEngine()
        let pro = try #require(try await engine.process(sourceURL: src, config: WatermarkConfiguration(watermarks: [])).url)
        let free = try #require(try await engine.process(sourceURL: src, config: WatermarkConfiguration(watermarks: []), tier: .free).url)

        let p = props(free)
        #expect(p[kCGImagePropertyPixelWidth as String] as? Int == 2048)
        #expect(p[kCGImagePropertyPixelHeight as String] as? Int == 1536)
        #expect(Double(fileSize(free)) <= 0.30 * Double(fileSize(pro)), "free \(fileSize(free)) vs pro \(fileSize(pro))")

        let exif = p[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
        #expect(exif[kCGImagePropertyExifLensModel as String] as? String == "iPhone 16 Pro back triple camera 6.86mm f/1.78")
        #expect(exif[kCGImagePropertyExifDateTimeOriginal as String] as? String == "2026:06:18 14:30:00")
        #expect(exif[kCGImagePropertyExifPixelXDimension as String] as? Int == 2048)
        #expect(exif[kCGImagePropertyExifPixelYDimension as String] as? Int == 1536)
        let tiff = p[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:]
        #expect(tiff[kCGImagePropertyTIFFModel as String] as? String == "iPhone 16 Pro")
        let gps = p[kCGImagePropertyGPSDictionary as String] as? [String: Any] ?? [:]
        #expect(gps[kCGImagePropertyGPSLatitude as String] != nil)
    }

    @Test("Free photo smaller than the cap keeps its size")
    func smallPhotoKeepsSize() async throws {
        let src = try flatPhoto(width: 1600, height: 1200)
        let out = try #require(try await WatermarkEngine().process(
            sourceURL: src, config: WatermarkConfiguration(watermarks: []), tier: .free).url)
        #expect(props(out)[kCGImagePropertyPixelWidth as String] as? Int == 1600)
    }

    @Test("Free tier writes lossless formats as JPEG")
    func freePNGBecomesJPEG() async throws {
        let src = try flatPhoto()
        let out = try #require(try await WatermarkEngine().process(
            sourceURL: src, config: WatermarkConfiguration(watermarks: [], outputFormat: .png), tier: .free))
        #expect(out.outputUTI == "public.jpeg")
    }

    @Test("Free photo drops the HDR gain map, Pro keeps it")
    func gainMapFollowsTier() async throws {
        guard let heic = TestImageFactory.hdrHEICWithGainMap() else { return }  // no HEVC encoder here
        let engine = WatermarkEngine()
        let pro = try #require(try await engine.process(sourceURL: heic, config: WatermarkConfiguration(watermarks: [])).url)
        let free = try #require(try await engine.process(sourceURL: heic, config: WatermarkConfiguration(watermarks: []), tier: .free).url)
        func gainMap(_ u: URL) -> Bool {
            guard let s = CGImageSourceCreateWithURL(u as CFURL, nil) else { return false }
            return CGImageSourceCopyAuxiliaryDataInfoAtIndex(s, 0, kCGImageAuxiliaryDataTypeHDRGainMap) != nil
        }
        #expect(gainMap(pro))
        #expect(!gainMap(free))
    }

    @Test("A downscaled Pro render keeps HDR (the comparison's Pro card); Free never does")
    func downscaledProKeepsGainMap() async throws {
        guard let heic = TestImageFactory.hdrHEICWithGainMap() else { return }
        let engine = WatermarkEngine()
        let cfg = WatermarkConfiguration(watermarks: [])
        let pro = try #require(try await engine.process(sourceURL: heic, config: cfg, maxPixelDimension: 32).url)
        let free = try #require(try await engine.process(sourceURL: heic, config: cfg, maxPixelDimension: 32, tier: .free).url)
        func gainMap(_ u: URL) -> Bool {
            guard let s = CGImageSourceCreateWithURL(u as CFURL, nil) else { return false }
            return CGImageSourceCopyAuxiliaryDataInfoAtIndex(s, 0, kCGImageAuxiliaryDataTypeHDRGainMap) != nil
        }
        #expect(props(pro)[kCGImagePropertyPixelWidth as String] as? Int == 32)
        #expect(gainMap(pro))
        #expect(!gainMap(free))
    }

    @Test("Batch items all follow the tier")
    func batchHonoursTier() async throws {
        // Unique names: renamed outputs share a folder with other tests running in parallel.
        let items = try (0..<2).map { _ in
            BatchProcessor.BatchItem(id: UUID(), sourceURL: try cameraPhoto(width: 3000, height: 2000), mediaType: .photo,
                                     originalFilename: "free_batch_\(UUID().uuidString).jpg")
        }
        let result = await BatchProcessor().process(items: items, sharedConfig: WatermarkConfiguration(watermarks: []), tier: .free)
        #expect(result.successes.count == 2)
        for url in result.successes {
            #expect(props(url)[kCGImagePropertyPixelWidth as String] as? Int == 2048)
        }
    }

    // MARK: - The mark (free-tier-watermark)

    @Test("Free export carries the mark bottom-right; Pro does not")
    func markOnlyOnFree() async throws {
        let src = try flatPhoto()
        let engine = WatermarkEngine()
        let config = WatermarkConfiguration(watermarks: [])
        let pro = try #require(try await engine.process(sourceURL: src, config: config).url)
        let free = try #require(try await engine.process(sourceURL: src, config: config, tier: .free).url)
        let box = try #require(try diffBox(pro, free), "free export shows no mark")
        #expect(box.minX > 600 && box.minY > 450, "mark expected bottom-right, got \(box)")
    }

    @Test("Mark moves to bottom-left when the user's text is bottom-right")
    func markAvoidsUserText() async throws {
        let src = try flatPhoto()
        let engine = WatermarkEngine()
        let config = WatermarkConfiguration(watermarks: [text("Northlight", at: .bottomRight)])
        let pro = try #require(try await engine.process(sourceURL: src, config: config).url)
        let free = try #require(try await engine.process(sourceURL: src, config: config, tier: .free).url)
        let box = try #require(try diffBox(pro, free))
        #expect(box.maxX < 600 && box.minY > 450, "mark expected bottom-left, got \(box)")
    }

    @Test("A blank text layer bottom-right doesn't push the mark away")
    func markIgnoresBlankText() async throws {
        let src = try flatPhoto()
        let engine = WatermarkEngine()
        // The editor's default text layer before anything is typed.
        let config = WatermarkConfiguration(watermarks: [text("", at: .bottomRight), text("  ", at: .bottomRight)])
        let pro = try #require(try await engine.process(sourceURL: src, config: config).url)
        let free = try #require(try await engine.process(sourceURL: src, config: config, tier: .free).url)
        let box = try #require(try diffBox(pro, free))
        #expect(box.minX > 600 && box.minY > 450, "mark expected bottom-right, got \(box)")
    }

    @Test("Mark sits on the photo, never on a frame's mat")
    func markStaysOnPhoto() async throws {
        let src = try flatPhoto()
        let engine = WatermarkEngine()
        var config = WatermarkConfiguration(watermarks: [])
        config.whiteFrame = WhiteFrameConfig(isEnabled: true, style: .noir, outputDPI: 300)
        let pro = try #require(try await engine.process(sourceURL: src, config: config))
        let free = try #require(try await engine.process(sourceURL: src, config: config, tier: .free))
        let proURL = try #require(pro.url), freeURL = try #require(free.url)
        let box = try #require(try diffBox(proURL, freeURL))
        let (img, _) = try pixels(freeURL)
        let photo = free.previewLayout?.photoRect ?? .zero   // normalized, y-down
        let photoPx = CGRect(x: photo.minX * CGFloat(img.width), y: photo.minY * CGFloat(img.height),
                             width: photo.width * CGFloat(img.width), height: photo.height * CGFloat(img.height))
        #expect(photoPx.insetBy(dx: -1, dy: -1).contains(box), "mark \(box) outside photo \(photoPx)")
    }

    @Test("Live preview never shows the mark")
    func previewHasNoMark() async throws {
        let src = try flatPhoto()
        let render = try await WatermarkEngine().renderPreview(
            sourceURL: src, config: WatermarkConfiguration(watermarks: []), maxPixelDimension: 1200)
        let w = render.image.width, h = render.image.height
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = try #require(CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                         space: CGColorSpaceCreateDeviceRGB(),
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.draw(render.image, in: CGRect(x: 0, y: 0, width: w, height: h))
        #expect(stride(from: 0, to: buf.count, by: 4).allSatisfy { buf[$0] < 150 }, "bright mark pixels in the preview")
    }

    // MARK: - Slot rule

    private let photo = CGRect(x: 0, y: 0, width: 1000, height: 800)
    private let mark = CGSize(width: 200, height: 50)

    /// Rect a slot's mark would occupy (padding 20), for marking it occupied.
    private func rect(_ p: WatermarkPosition) -> CGRect {
        let o = PositionCalculator.position(for: p, watermarkExtent: CGRect(origin: .zero, size: mark),
                                            baseExtent: photo, padding: 20)
        return CGRect(origin: o, size: mark)
    }

    private func slot(_ taken: [WatermarkPosition], extra: [CGRect] = []) -> WatermarkPosition {
        BrandMark.slot(mark: mark, base: photo, padding: 20, occupied: taken.map(rect) + extra).position
    }

    @Test("Slot order: corners, centre, bottom-middle, top-middle")
    func slotOrder() {
        #expect(slot([]) == .bottomRight)
        #expect(slot([.bottomRight]) == .bottomLeft)
        #expect(slot([.bottomRight, .bottomLeft, .topRight, .topLeft]) == .center)
        #expect(slot([.bottomRight, .bottomLeft, .topRight, .topLeft, .center]) == .bottomCenter)
        #expect(slot([.bottomRight, .bottomLeft, .topRight, .topLeft, .center, .bottomCenter]) == .topCenter)
    }

    @Test("Everything taken: least overlap, never a side middle")
    func slotFallback() {
        let all: [WatermarkPosition] = [.bottomRight, .bottomLeft, .topRight, .topLeft, .center, .bottomCenter, .topCenter]
        // A second element half over bottom-left makes it the most crowded; BR wins on order.
        let s = slot(all, extra: [rect(.bottomLeft).offsetBy(dx: 50, dy: 0)])
        #expect(s == .bottomRight)
        #expect(!BrandMark.slotOrder.contains(.middleLeft))
        #expect(!BrandMark.slotOrder.contains(.middleRight))
    }

    @Test("A dragged element over the bottom-right corner blocks it")
    func draggedElementBlocks() {
        let dragged = CGRect(x: 850, y: 10, width: 120, height: 60)
        #expect(slot([], extra: [dragged]) == .bottomLeft)
    }

    // MARK: - Video policy

    @Test("Video: free tone-maps to SDR and starts at 1080p; Pro keeps HDR")
    func videoPolicy() {
        let free = ExportPolicy(tier: .free), pro = ExportPolicy(tier: .pro)
        #expect(!VideoProcessor.outputIsHDR(sourceIsHDR: true, policy: free))
        #expect(VideoProcessor.outputIsHDR(sourceIsHDR: true, policy: pro))
        #expect(!VideoProcessor.outputIsHDR(sourceIsHDR: false, policy: pro))
        #expect(VideoProcessor.presetCandidates(outputIsHDR: false, policy: free).first == AVAssetExportPreset1920x1080)
        #expect(VideoProcessor.presetCandidates(outputIsHDR: true, policy: pro).first == AVAssetExportPresetHEVCHighestQuality)
        #expect(VideoProcessor.presetCandidates(outputIsHDR: false, policy: pro).first == AVAssetExportPresetHighestQuality)
    }

    // MARK: - Content Credentials

    final class CapturingClient: C2PAProvenanceClient, @unchecked Sendable {
        var manifest: C2PAManifestRequest?
        func readSourceSummary(from url: URL) async -> SourceProvenanceAnalyzer.C2PASummary? { nil }
        func signExport(outputURL: URL, source: URL, manifest: C2PAManifestRequest,
                        identity: C2PASigningIdentity) async throws -> C2PASigningResult {
            self.manifest = manifest
            return C2PASigningResult(status: .notSigned, identityType: identity.type, displayName: identity.displayName)
        }
        func verifyExport(at url: URL) async -> C2PAVerificationResult? { nil }
    }

    @Test("Free users can sign; the manifest records the visible mark")
    func freeSigningRecordsMark() async throws {
        let src = try flatPhoto()
        let client = CapturingClient()
        var rights = RightsMetadata()
        rights.creator = "Northlight Studio"
        let prov = ProvenanceExportOptions(rights: rights, privacyProfile: .preserveAll, includeC2PA: true,
                                           userDeclaration: .none, appVersion: "test", c2paClient: client)
        _ = try await WatermarkEngine().process(sourceURL: src, config: WatermarkConfiguration(watermarks: []),
                                                provenance: prov, tier: .free)
        let m = try #require(client.manifest, "free export was not offered for signing")
        #expect(m.visibleWatermarkApplied)
    }

    @Test("Mark paints nothing outside its own bounds")
    func markHasNoStrayPixels() throws {
        let mark = BrandMark.image(for: CGSize(width: 3000, height: 2000))
        // Black canvas reaching far above and below the mark.
        let canvas = CGRect(x: 0, y: -300, width: mark.extent.width, height: mark.extent.height + 600)
        let img = mark.composited(over: CIImage(color: .black).cropped(to: canvas))
        let cg = try #require(CIContext().createCGImage(img, from: canvas))
        let w = cg.width, h = cg.height
        let ctx = try #require(CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                         space: CGColorSpaceCreateDeviceRGB(),
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        let px = try #require(ctx.data).assumingMemoryBound(to: UInt8.self)
        // Rows 0 and h-1 are 300 px beyond the mark: they must stay black.
        for row in [0, h - 1] {
            let lit = (0..<w).filter { px[(row * w + $0) * 4] > 3 }
            #expect(lit.isEmpty, "stray mark pixels at row \(row): \(lit.prefix(5))")
        }
    }
}
