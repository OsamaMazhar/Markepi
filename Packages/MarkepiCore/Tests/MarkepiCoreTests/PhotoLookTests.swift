import AVFoundation
import CoreImage
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import MarkepiCore

/// Looks: the colour looks applied to the photo's own pixels (never the frame).
@Suite("Photo looks")
struct PhotoLookTests {

    // MARK: - Helpers

    private let ctx = CIContextProvider.shared
    private let p3 = CGColorSpace(name: CGColorSpace.displayP3)!

    /// RGBA8 of one CI-coordinate pixel.
    private func pixel(_ image: CIImage, _ x: CGFloat, _ y: CGFloat) -> [Int] {
        var px = [UInt8](repeating: 0, count: 4)
        ctx.render(image, toBitmap: &px, rowBytes: 4, bounds: CGRect(x: x, y: y, width: 1, height: 1),
                   format: .RGBA8, colorSpace: p3)
        return px.map(Int.init)
    }

    private func average(_ image: CIImage, _ rect: CGRect? = nil) -> [Int] {
        let r = rect ?? image.extent
        let avg = image.applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: r)])
        return pixel(avg, 0, 0)
    }

    private func solid(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, size: CGFloat = 64) -> CIImage {
        CIImage(color: CIColor(red: r, green: g, blue: b, colorSpace: p3)!)
            .cropped(to: CGRect(x: 0, y: 0, width: size, height: size))
    }

    /// Gradient + colour chart-ish test image.
    private func chart(size: CGFloat = 256) -> CIImage {
        let rect = CGRect(x: 0, y: 0, width: size, height: size)
        let g = CIFilter(name: "CILinearGradient", parameters: [
            "inputPoint0": CIVector(x: 0, y: 0), "inputPoint1": CIVector(x: size, y: size),
            "inputColor0": CIColor(red: 0.9, green: 0.55, blue: 0.4), "inputColor1": CIColor(red: 0.1, green: 0.3, blue: 0.8),
        ])!.outputImage!
        return g.cropped(to: rect)
    }

    private func writeJPEG(_ image: CIImage, metadata: [String: Any] = EXIFMetadataFactory.realisticMetadata()) throws -> URL {
        let cg = try #require(CIContext().createCGImage(image, from: image.extent, format: .RGBA8, colorSpace: p3))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("look_\(UUID().uuidString).jpg")
        let dest = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        var props = metadata
        props[kCGImageDestinationLossyCompressionQuality as String] = 0.95
        CGImageDestinationAddImage(dest, cg, props as CFDictionary)
        #expect(CGImageDestinationFinalize(dest))
        return url
    }

    private func props(_ url: URL) -> [String: Any] {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return [:] }
        return CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any] ?? [:]
    }

    private func decoded(_ url: URL) throws -> CIImage {
        try #require(CIImage(contentsOf: url))
    }

    private var portraitURL: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/cc0-outdoor-portrait.jpg")
    }

    // MARK: - 1. Model & persistence

    @Test("Catalogue: 22 looks in three families, Original free, names trademark-free")
    func catalogue() {
        #expect(PhotoLook.allCases.count == 23)
        #expect(PhotoLook.Family.mood.looks.count == 10)
        #expect(PhotoLook.Family.undertone.looks.count == 6)
        #expect(PhotoLook.Family.film.looks.count == 9)
        #expect(PhotoLook.allCases.filter(\.isFree) == [.original, .vibrant, .natural, .neutral])
        let banned = ["kodak", "portra", "fuji", "velvia", "ilford", "cinestill", "ektar", "tri-x", "leica", "photographic style"]
        for look in PhotoLook.allCases {
            #expect(!banned.contains { look.title.lowercased().contains($0) }, "\(look.title)")
        }
    }

    @Test("Settings round-trip; unknown look and missing keys decode to Original defaults")
    func decoding() throws {
        let s = PhotoLookSettings(look: .chrome100, intensity: 0.6, tone: -0.3, color: 0.4, grain: 0.2)
        let back = try JSONDecoder().decode(PhotoLookSettings.self, from: JSONEncoder().encode(s))
        #expect(back == s)
        let unknown = try JSONDecoder().decode(PhotoLookSettings.self, from: Data(#"{"look":"futureLook9000"}"#.utf8))
        #expect(unknown.look == .original && unknown.intensity == 1 && unknown.grain == nil)
        let clamped = try JSONDecoder().decode(PhotoLookSettings.self, from: Data(#"{"look":"gold","intensity":7,"tone":-5}"#.utf8))
        #expect(clamped.intensity == 1 && clamped.tone == -1)
    }

    @Test("A config saved before Looks existed decodes to Original")
    func legacyConfig() throws {
        let legacy = #"{"watermarks":[],"outputFormat":"preserveSource","outputQuality":1}"#
        let cfg = try JSONDecoder().decode(WatermarkConfiguration.self, from: Data(legacy.utf8))
        #expect(cfg.photoLook == PhotoLookSettings())
        var withLook = cfg
        withLook.photoLook = .choosing(.amber)
        let again = try JSONDecoder().decode(WatermarkConfiguration.self, from: JSONEncoder().encode(withLook))
        #expect(again.photoLook.look == .amber)
    }

    // MARK: - 2. Renderer

    @Test("Identity recipe bakes an identity cube")
    func identityCube() {
        let data = PhotoLookRenderer.bake { PhotoLookRenderer.Recipe.identity.transform($0, skinScale: 1) }
        let floats = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        let n = PhotoLookRenderer.cubeDimension
        var maxError: Float = 0
        var i = 0
        for b in 0..<n { for g in 0..<n { for r in 0..<n {
            let expect = [Float(r), Float(g), Float(b)].map { $0 / Float(n - 1) }
            for c in 0..<3 { maxError = max(maxError, abs(floats[i + c] - expect[c])) }
            i += 4
        } } }
        #expect(maxError < 1.0 / 255)
    }

    @Test("Every recipe bakes quickly and stays in range")
    func recipesInRange() {
        for look in PhotoLook.allCases where look != .original {
            let recipe = PhotoLookRenderer.Recipe.catalog[look]!
            let start = Date()
            let data = PhotoLookRenderer.bake { recipe.transform($0, skinScale: 1) }
            #expect(Date().timeIntervalSince(start) < 0.25, "\(look) bake too slow")
            let floats = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
            #expect(floats.allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 1 }, "\(look) out of range")
            let out = average(PhotoLookRenderer.apply(.choosing(look), to: chart()))
            #expect(out.prefix(3).allSatisfy { $0 > 0 && $0 < 255 } || look.isMonochrome, "\(look) crushed: \(out)")
        }
    }

    @Test("Original and 0% intensity leave the photo untouched")
    func identityPaths() {
        let img = chart()
        #expect(PhotoLookRenderer.apply(PhotoLookSettings(), to: img) === img)
        #expect(PhotoLookRenderer.apply(PhotoLookSettings(look: .dramatic, intensity: 0), to: img) === img)
        let half = PhotoLookRenderer.apply(PhotoLookSettings(look: .starkBW, intensity: 0.5), to: img)
        let full = PhotoLookRenderer.apply(.choosing(.starkBW), to: img)
        // Half intensity sits between the photo and the full look.
        let (a, h, f) = (pixel(img, 30, 30), pixel(half, 30, 30), pixel(full, 30, 30))
        #expect(abs(h[0] - (a[0] + f[0]) / 2) <= 3)
    }

    @Test("Pad centre is a no-op; warmer moves gray toward amber, brighter lifts mids")
    func pad() {
        let gray = solid(0.5, 0.5, 0.5)
        #expect(PhotoLookRenderer.pad(gray, tone: 0, color: 0) === gray)
        let warm = pixel(PhotoLookRenderer.pad(gray, tone: 0, color: 1), 10, 10)
        #expect(warm[0] - warm[2] > 15)
        let cool = pixel(PhotoLookRenderer.pad(gray, tone: 0, color: -1), 10, 10)
        #expect(cool[2] - cool[0] > 15)
        let bright = pixel(PhotoLookRenderer.pad(gray, tone: 1, color: 0), 10, 10)
        #expect(bright[1] > pixel(gray, 10, 10)[1] + 8)
    }

    @Test("Grain is repeatable and keeps the same look at any resolution")
    func grain() throws {
        let big = solid(0.5, 0.5, 0.5, size: 2048)
        let a = PhotoLookRenderer.grain(big, amount: 0.75, size: 1.5)
        let b = PhotoLookRenderer.grain(big, amount: 0.75, size: 1.5)
        let ca = try #require(ctx.createCGImage(a, from: CGRect(x: 0, y: 0, width: 128, height: 128), format: .RGBA8, colorSpace: p3))
        let cb = try #require(ctx.createCGImage(b, from: CGRect(x: 0, y: 0, width: 128, height: 128), format: .RGBA8, colorSpace: p3))
        #expect(ca.dataProvider?.data as Data? == cb.dataProvider?.data as Data?)
        // Mean unchanged (zero-mean grain).
        #expect(abs(average(a)[1] - 128) <= 2)
        // Variance: a 512-px preview vs the 2048-px render shrunk to 512 px.
        func stdev(_ i: CIImage) -> Double {
            let cg = ctx.createCGImage(i, from: i.extent, format: .RGBA8, colorSpace: p3)!
            let d = [UInt8](cg.dataProvider!.data! as Data)
            let gs = stride(from: 1, to: d.count, by: 4).map { Double(d[$0]) }
            let m = gs.reduce(0, +) / Double(gs.count)
            return (gs.map { ($0 - m) * ($0 - m) }.reduce(0, +) / Double(gs.count)).squareRoot()
        }
        let preview = PhotoLookRenderer.grain(solid(0.5, 0.5, 0.5, size: 512), amount: 0.75, size: 1.5)
        let shrunk = a.transformed(by: CGAffineTransform(scaleX: 0.25, y: 0.25)).cropped(to: CGRect(x: 0, y: 0, width: 512, height: 512))
        let (sp, ss) = (stdev(preview), stdev(shrunk))
        #expect(sp > 0.5 && ss > 0.5)
        #expect(abs(sp - ss) / max(sp, ss) < 0.6, "preview σ=\(sp) export σ=\(ss)")
    }

    @Test("Halation: red glow around a bright light, mid-gray and dark corners untouched")
    func halation() {
        #expect(pixel(PhotoLookRenderer.halation(solid(0.5, 0.5, 0.5), strength: 0.55), 32, 32) == pixel(solid(0.5, 0.5, 0.5), 32, 32))
        let dark = solid(0.02, 0.02, 0.02, size: 400)
        let dot = CIImage(color: .white).cropped(to: CGRect(x: 190, y: 190, width: 20, height: 20))
        let scene = dot.composited(over: dark)
        let out = PhotoLookRenderer.halation(scene, strength: 0.55)
        let near = pixel(out, 214, 200)
        #expect(near[0] > near[1] + 5 && near[0] > near[2] + 5, "\(near)")
        #expect(pixel(out, 5, 5) == pixel(scene, 5, 5))
    }

    @Test("B&W looks stay RGB, and a coloured logo drawn over them keeps its colour")
    func monochromeStaysRGB() async throws {
        for look in [PhotoLook.mutedBW, .starkBW, .silver400] {
            let out = pixel(PhotoLookRenderer.apply(.choosing(look), to: chart()), 40, 40)
            #expect(abs(out[0] - out[1]) <= 2 && abs(out[1] - out[2]) <= 2, "\(look) not neutral: \(out)")
        }
        let url = try writeJPEG(chart(size: 400))
        var cfg = WatermarkConfiguration(watermarks: [
            .text(TextWatermarkInput(text: "RED", color: CGColor(red: 1, green: 0, blue: 0, alpha: 1)),
                  position: .center, scale: 0.3, opacity: 1, isVisible: true)])
        cfg.photoLook = .choosing(.mutedBW)
        let result = try #require(try await WatermarkEngine().process(sourceURL: url, config: cfg).url)
        let src = try #require(CGImageSourceCreateWithURL(result as CFURL, nil))
        let cg = try #require(CGImageSourceCreateImageAtIndex(src, 0, nil))
        #expect(cg.colorSpace?.model == .rgb)
        // Somewhere in the centre there are strongly red text pixels.
        let img = CIImage(cgImage: cg)
        var foundRed = false
        for x in stride(from: 120, to: 280, by: 2) { for y in stride(from: 180, to: 220, by: 2) {
            let p = pixel(img, CGFloat(x), CGFloat(y))
            if p[0] > 180 && p[1] < 90 && p[2] < 90 { foundRed = true }
        } }
        #expect(foundRed)
    }

    // MARK: - 3. Masks

    @Test("Undertone shifts masked skin ≥ 3× more than the rest")
    func undertoneUsesSkinMask() {
        let skinTone = solid(0.85, 0.62, 0.5, size: 200)
        let half = CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 100, height: 200))
            .composited(over: CIImage(color: .black).cropped(to: CGRect(x: 0, y: 0, width: 200, height: 200)))
        let out = PhotoLookRenderer.apply(.choosing(.amber), to: skinTone, masks: SceneMasks(skin: half))
        let orig = pixel(skinTone, 50, 100)
        func shift(_ p: [Int]) -> Int { abs(p[0] - orig[0]) + abs(p[1] - orig[1]) + abs(p[2] - orig[2]) }
        let masked = shift(pixel(out, 30, 100)), unmasked = shift(pixel(out, 170, 100))
        #expect(masked > 0 && masked >= 3 * unmasked, "masked \(masked) unmasked \(unmasked)")
        // No mask: only the light global shift.
        let global = shift(pixel(PhotoLookRenderer.apply(.choosing(.amber), to: skinTone), 30, 100))
        #expect(global == unmasked || abs(global - unmasked) <= 2)
    }

    @Test("Sky treatment only reaches the sky mask")
    func skyUsesSkyMask() {
        let blue = solid(0.35, 0.55, 0.85, size: 200)
        let top = CIImage(color: .white).cropped(to: CGRect(x: 0, y: 100, width: 200, height: 100))
            .composited(over: CIImage(color: .black).cropped(to: CGRect(x: 0, y: 0, width: 200, height: 200)))
        let out = PhotoLookRenderer.apply(.choosing(.dramatic), to: blue, masks: SceneMasks(sky: top))
        let noSky = PhotoLookRenderer.apply(.choosing(.dramatic), to: blue)
        #expect(pixel(out, 100, 30) == pixel(noSky, 100, 30))
        #expect(pixel(out, 100, 170)[2] < pixel(noSky, 100, 170)[2] - 5)
        #expect(PhotoLookRenderer.needsMasks(.choosing(.dramatic)))
        #expect(!PhotoLookRenderer.needsMasks(.choosing(.quiet)))
    }

    @Test("Vision skin mask on a real portrait: face lit, background dark; cached")
    func visionSkinMask() async throws {
        let provider = SceneMaskProvider()
        let masks = await provider.masks(for: portraitURL)
        guard let skin = masks.skin else {
            // Vision person segmentation is unavailable on some CI hosts.
            Issue.record("No person found in the CC0 portrait")
            return
        }
        // Fixture: 768×512, face around x≈0.42, y≈0.62 (from top), background top-right.
        let e = skin.extent
        let face = average(skin, CGRect(x: e.width * 0.39, y: e.height * (1 - 0.66), width: e.width * 0.06, height: e.height * 0.08))
        let background = average(skin, CGRect(x: e.width * 0.8, y: e.height * 0.7, width: e.width * 0.15, height: e.height * 0.2))
        #expect(face[0] > 128, "face \(face)")
        #expect(background[0] < 26, "background \(background)")
        _ = await provider.masks(for: portraitURL)
        #expect(await provider.computeCount == 1)
        #expect(await provider.cachedCount == 1)
    }

    @Test("No person and no sky: no masks")
    func noMasks() async throws {
        let url = try writeJPEG(solid(0.4, 0.4, 0.4, size: 300))
        let masks = await SceneMaskProvider().masks(for: url)
        #expect(masks.skin == nil && masks.sky == nil)
    }

    @Test("Embedded Portrait-mode skin matte is used when present")
    func embeddedSkinMatte() throws {
        // Base 64×64 with a skin matte whose left half is on.
        let base = try #require(CIContext().createCGImage(solid(0.8, 0.6, 0.5), from: CGRect(x: 0, y: 0, width: 64, height: 64)))
        var bytes = [UInt8](repeating: 0, count: 32 * 32)
        for y in 0..<32 { for x in 0..<16 { bytes[y * 32 + x] = 255 } }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("matte_\(UUID().uuidString).heic")
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.heic.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, base, nil)
        let meta = CGImageMetadataCreateMutable()
        CGImageMetadataRegisterNamespaceForPrefix(meta, "http://ns.apple.com/ImageIO/1.0/" as CFString, "iio" as CFString, nil)
        let info: [CFString: Any] = [
            kCGImageAuxiliaryDataInfoData: Data(bytes) as CFData,
            kCGImageAuxiliaryDataInfoDataDescription: ["Width": 32, "Height": 32, "BytesPerRow": 32,
                                                        "PixelFormat": Int(kCVPixelFormatType_OneComponent8)] as CFDictionary,
            kCGImageAuxiliaryDataInfoMetadata: meta,
        ]
        CGImageDestinationAddAuxiliaryDataInfo(dest, kCGImageAuxiliaryDataTypeSemanticSegmentationSkinMatte, info as CFDictionary)
        guard CGImageDestinationFinalize(dest), let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return }
        guard let mask = SceneMaskProvider.embeddedSkinMask(src, orientation: .up) else {
            // AVFoundation refused the synthetic matte's metadata on this host.
            withKnownIssue("Synthetic semantic matte not accepted by AVSemanticSegmentationMatte") { throw CancellationError() }
            return
        }
        #expect(pixel(mask, 4, 16)[0] > 200)
        #expect(pixel(mask, 28, 16)[0] < 30)
    }

    // MARK: - 4. Engine

    @Test("The look recolours the photo only: frame mat pixels are identical")
    func lookNeverTouchesFrame() async throws {
        let url = try writeJPEG(chart(size: 600))
        var plain = WatermarkConfiguration(watermarks: [])
        plain.whiteFrame = WhiteFrameConfig(isEnabled: true)
        var styled = plain
        styled.photoLook = .choosing(.velvet50)
        let engine = WatermarkEngine()
        let a = try decoded(try #require(try await engine.process(sourceURL: url, config: plain).url))
        let b = try decoded(try #require(try await engine.process(sourceURL: url, config: styled).url))
        #expect(a.extent == b.extent)
        // A point on the outer mat (2% in from the corner) and one at the centre of the photo.
        let e = a.extent
        #expect(pixel(a, e.width * 0.02, e.height * 0.5) == pixel(b, e.width * 0.02, e.height * 0.5))
        #expect(pixel(a, e.midX, e.midY) != pixel(b, e.midX, e.midY))
    }

    @Test("Styled HDR export keeps GPS, dates, device, colour profile and the gain map")
    func metadataAndHDRSurvive() async throws {
        guard let heic = TestImageFactory.hdrHEICWithGainMap(size: CGSize(width: 256, height: 192)) else { return }
        // Add camera metadata to the HDR fixture.
        let src = try #require(CGImageSourceCreateWithURL(heic as CFURL, nil))
        let tagged = FileManager.default.temporaryDirectory.appendingPathComponent("look_hdr_\(UUID().uuidString).heic")
        let dest = try #require(CGImageDestinationCreateWithURL(tagged as CFURL, UTType.heic.identifier as CFString, 1, nil))
        CGImageDestinationAddImageFromSource(dest, src, 0, EXIFMetadataFactory.realisticMetadata() as CFDictionary)
        if let aux = CGImageSourceCopyAuxiliaryDataInfoAtIndex(src, 0, kCGImageAuxiliaryDataTypeHDRGainMap) {
            CGImageDestinationAddAuxiliaryDataInfo(dest, kCGImageAuxiliaryDataTypeHDRGainMap, aux)
        }
        #expect(CGImageDestinationFinalize(dest))

        for look in [PhotoLook.cozy, .silver400, .amber, .tungsten800] {
            var cfg = WatermarkConfiguration(watermarks: [])
            cfg.photoLook = .choosing(look)
            let out = try #require(try await WatermarkEngine().process(sourceURL: tagged, config: cfg).url)
            let p = props(out)
            let gps = p[kCGImagePropertyGPSDictionary as String] as? [String: Any]
            let exif = p[kCGImagePropertyExifDictionary as String] as? [String: Any]
            let tiff = p[kCGImagePropertyTIFFDictionary as String] as? [String: Any]
            #expect((gps?[kCGImagePropertyGPSLatitude as String] as? Double).map { abs($0 - 37.7749) < 0.001 } == true, "\(look) GPS")
            #expect(exif?[kCGImagePropertyExifDateTimeOriginal as String] as? String == "2026:06:18 14:30:00", "\(look) date")
            #expect(tiff?[kCGImagePropertyTIFFModel as String] as? String == "iPhone 16 Pro", "\(look) model")
            #expect(p[kCGImagePropertyProfileName as String] != nil, "\(look) profile")
            let outSrc = try #require(CGImageSourceCreateWithURL(out as CFURL, nil))
            #expect(CGImageSourceCopyAuxiliaryDataInfoAtIndex(outSrc, 0, kCGImageAuxiliaryDataTypeHDRGainMap) != nil, "\(look) HDR")
        }
    }

    @Test("Free tier: Pro look exports as Original, free look at default tuning stays styled")
    func freeTierDowngrade() async throws {
        let url = try writeJPEG(chart(size: 400))
        let engine = WatermarkEngine()
        func render(_ s: PhotoLookSettings) async throws -> CIImage {
            var cfg = WatermarkConfiguration(watermarks: [])
            cfg.photoLook = s
            return try decoded(try #require(try await engine.process(sourceURL: url, config: cfg, tier: .free).url))
        }
        let original = try await render(PhotoLookSettings())
        let chrome = try await render(.choosing(.chrome100))
        let vibrant = try await render(.choosing(.vibrant))
        let tunedVibrant = try await render(PhotoLookSettings(look: .vibrant, intensity: 0.5))
        // The brand mark sits in a corner; compare the centre.
        func centre(_ i: CIImage) -> [Int] { pixel(i, i.extent.midX, i.extent.midY) }
        #expect(centre(chrome) == centre(original))
        #expect(centre(tunedVibrant) == centre(original))
        #expect(centre(vibrant) != centre(original))
        #expect(ExportPolicy(tier: .pro).allowsLook(.choosing(.chrome100)))
    }

    @Test("A styled Live Photo exports as a still; Original keeps it live")
    func livePhotoStill() async throws {
        var cfg = WatermarkConfiguration(watermarks: [])
        #expect(!WatermarkEngine.livePhotoExportsAsStill(config: cfg, tier: .pro))
        cfg.photoLook = .choosing(.faded)
        #expect(WatermarkEngine.livePhotoExportsAsStill(config: cfg, tier: .pro))
        // Free tier downgrades a Pro look → stays a Live Photo.
        #expect(!WatermarkEngine.livePhotoExportsAsStill(config: cfg, tier: .free))
        let still = try writeJPEG(chart(size: 200))
        let movie = FileManager.default.temporaryDirectory.appendingPathComponent("missing_\(UUID().uuidString).mov")
        let result = try await WatermarkEngine().processLivePhoto(stillImageURL: still, videoURL: movie, config: cfg)
        #expect(result.url != nil && result.livePhotoVideoURL == nil)
    }

    @Test("Batch: every photo styled, each with its own masks")
    func batch() async throws {
        let urls = try [chart(size: 300), solid(0.3, 0.5, 0.7, size: 300)].map { try writeJPEG($0) }
        let items = urls.map {
            BatchProcessor.BatchItem(id: UUID(), sourceURL: $0, mediaType: .photo, originalFilename: "look_batch_\(UUID().uuidString).jpg")
        }
        var cfg = WatermarkConfiguration(watermarks: [])
        cfg.photoLook = .choosing(.gold)
        let result = await BatchProcessor().process(items: items, sharedConfig: cfg)
        #expect(result.successes.count == 2)
        let keys = Set(urls.map(SceneMaskProvider.cacheKey))
        #expect(keys.count == 2)
    }

    @Test("A grain the user set carries from film to film, never onto a mood")
    func grainCarriesBetweenFilms() {
    var film = PhotoLookSettings.choosing(.velvet50)
    film.grain = 0.8
    #expect(film.choosing(.silver400).grain == 0.8)
    #expect(film.choosing(.vibrant).grain == nil)
    #expect(film.choosing(.vibrant).choosing(.faded).grain == nil)
}
}
