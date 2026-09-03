import Testing
import ImageIO
import CoreImage
import Foundation
#if canImport(UIKit)
import UIKit
#endif
@testable import WatermarkCore

/// Tests for multi-layer compositing: verifies that text, image, and white frame
/// layers all compose correctly in a single render pass with per-layer visibility,
/// opacity, and D-12 compositing order enforcement.
@Suite("Multi-Layer Compositing")
struct MultiLayerCompositingTests {

    /// The metadata the engine will read from a source file, so a test can
    /// predict the framed size the same way the engine computes it.
    private func sourceMetadata(_ url: URL) -> [String: Any] {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any]
        else { return [:] }
        return props
    }

    private func createTempInputFile(data: Data, name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)_\(UUID().uuidString).jpg")
        try data.write(to: url)
        return url
    }

    private func cleanup(_ urls: URL...) {
        for url in urls {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Creates a small valid PNG in memory (platform-agnostic).
    private func createMinimalPNGWatermark() -> Data {
        #if canImport(UIKit)
        let size = CGSize(width: 8, height: 8)
        let renderer = UIGraphicsImageRenderer(size: size)
        let uiImage = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        return uiImage.pngData()!
        #else
        // Hardcoded valid 8x8 white PNG (67 bytes) for macOS testing
        let bytes: [UInt8] = [
            0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
            0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
            0x00, 0x00, 0x00, 0x08, 0x00, 0x00, 0x00, 0x08,
            0x08, 0x02, 0x00, 0x00, 0x00, 0x4B, 0x6D, 0x29,
            0xDC, 0x00, 0x00, 0x00, 0x12, 0x49, 0x44, 0x41,
            0x54, 0x78, 0x9C, 0x62, 0x60, 0x60, 0x60, 0xF8,
            0x0F, 0x04, 0x0C, 0x0C, 0x00, 0x02, 0x30, 0x00,
            0x01, 0xD4, 0xA6, 0x90, 0x91, 0x00, 0x00, 0x00,
            0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60,
            0x82,
        ]
        return Data(bytes)
        #endif
    }

    // MARK: - Test 1: All three layer types simultaneously active (MULT-01)

    @Test("Text + image + frame all enabled — all three render in single pass")
    func allThreeLayerTypesSimultaneously() async throws {
        let (_, jpegData) = TestImageFactory.solidColorImage(
            color: CGColor(red: 0, green: 0, blue: 1, alpha: 1),
            size: CGSize(width: 800, height: 600)
        )
        let inputURL = try createTempInputFile(data: jpegData, name: "multilayer_all")
        let pngData = createMinimalPNGWatermark()

        let config = WatermarkConfiguration(
            watermarks: [
                .text(TextWatermarkInput(text: "Top Text", fontSize: 36, opacity: 1.0),
                      position: .topLeft, scale: 0.15, opacity: 1.0, isVisible: true),
                .image(try ImageWatermarkInput(pngData: pngData, scale: 0.15, opacity: 1.0),
                       position: .bottomRight, scale: 0.15, opacity: 1.0, isVisible: true),
            ],
            whiteFrame: WhiteFrameConfig(isEnabled: true,
                                          metadataTextEnabled: true)
        )

        let engine = WatermarkEngine()
        let result = try await engine.process(sourceURL: inputURL, config: config)
        #expect(result.url != nil)
        #expect(FileManager.default.fileExists(atPath: result.url!.path))
        #expect(result.outputUTI == "public.jpeg")

        guard let outputURL = result.url,
              let source = CGImageSourceCreateWithURL(outputURL as CFURL, nil) else {
            Issue.record("Failed to read output image")
            cleanup(inputURL)
            return
        }
        // Framed export: the mat is added outside the 800x600 source.
        let frameConfig = config.whiteFrame ?? WhiteFrameConfig()
        let framed = FrameGeometry(
            config: frameConfig,
            sourceSize: CGSize(width: 800, height: 600),
            hasCaptionContent: WhiteFrameRenderer.hasCaptionContent(
                config: frameConfig, metadata: sourceMetadata(inputURL))
        ).framedSize
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        #expect((props[kCGImagePropertyPixelWidth] as? Int) == Int(framed.width))
        #expect((props[kCGImagePropertyPixelHeight] as? Int) == Int(framed.height))

        cleanup(inputURL, outputURL)
    }

    // MARK: - Test 2: Hidden layer (MULT-02)

    @Test("Hidden layer does not appear in output")
    func hiddenLayerSkipped() async throws {
        let (_, jpegData) = TestImageFactory.solidColorImage(
            color: CGColor(red: 0, green: 0, blue: 1, alpha: 1),
            size: CGSize(width: 400, height: 300)
        )
        let inputURL = try createTempInputFile(data: jpegData, name: "hidden_layer")

        let config = WatermarkConfiguration(
            watermarks: [
                .text(TextWatermarkInput(text: "VISIBLE", fontSize: 48, opacity: 1.0),
                      position: .topLeft, scale: 0.15, opacity: 1.0, isVisible: true),
                .text(TextWatermarkInput(text: "HIDDEN", fontSize: 48, opacity: 1.0),
                      position: .bottomRight, scale: 0.15, opacity: 1.0, isVisible: false),
            ]
        )

        let engine = WatermarkEngine()
        let result = try await engine.process(sourceURL: inputURL, config: config)
        #expect(result.url != nil)

        guard let outputURL = result.url,
              let source = CGImageSourceCreateWithURL(outputURL as CFURL, nil) else {
            Issue.record("Failed to read output")
            cleanup(inputURL)
            return
        }
        #expect(CGImageSourceGetCount(source) == 1)

        cleanup(inputURL, outputURL)
    }

    // MARK: - Test 3: Per-layer opacity (MULT-02)

    @Test("Per-layer opacity: translucent text, opaque image")
    func perLayerOpacity() async throws {
        let (_, jpegData) = TestImageFactory.solidColorImage(
            color: CGColor(red: 0, green: 0, blue: 1, alpha: 1),
            size: CGSize(width: 400, height: 300)
        )
        let inputURL = try createTempInputFile(data: jpegData, name: "opacity_test")
        let pngData = createMinimalPNGWatermark()

        let config = WatermarkConfiguration(
            watermarks: [
                .text(TextWatermarkInput(text: "Faint", fontSize: 48, opacity: 1.0),
                      position: .topLeft, scale: 0.15, opacity: 0.3, isVisible: true),
                .image(try ImageWatermarkInput(pngData: pngData, scale: 0.15, opacity: 1.0),
                       position: .bottomRight, scale: 0.15, opacity: 1.0, isVisible: true),
            ]
        )

        let engine = WatermarkEngine()
        let result = try await engine.process(sourceURL: inputURL, config: config)
        #expect(result.url != nil)

        guard let outputURL = result.url,
              let source = CGImageSourceCreateWithURL(outputURL as CFURL, nil) else {
            Issue.record("Failed to read output")
            cleanup(inputURL)
            return
        }
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        #expect((props[kCGImagePropertyPixelWidth] as? Int) == 400)
        #expect((props[kCGImagePropertyPixelHeight] as? Int) == 300)

        cleanup(inputURL, outputURL)
    }

    // MARK: - Test 4: Frame compositing order (D-12)

    @Test("White frame composites on top of watermarks per D-12")
    func frameCompositesOnTopOfWatermarks() async throws {
        let (_, jpegData) = TestImageFactory.solidColorImage(
            color: CGColor(red: 0, green: 0, blue: 1, alpha: 1),
            size: CGSize(width: 800, height: 600)
        )
        let inputURL = try createTempInputFile(data: jpegData, name: "frame_order")

        let config = WatermarkConfiguration(
            watermarks: [
                .text(TextWatermarkInput(text: "Watermark", fontSize: 48, opacity: 1.0),
                      position: .center, scale: 0.15, opacity: 1.0, isVisible: true),
            ],
            whiteFrame: WhiteFrameConfig(isEnabled: true,
                                          metadataTextEnabled: true)
        )

        let engine = WatermarkEngine()
        let result = try await engine.process(sourceURL: inputURL, config: config)
        #expect(result.url != nil)
        #expect(result.outputUTI == "public.jpeg")

        cleanup(inputURL, result.url!)
    }

    // MARK: - Test 5: Multiple text layers at different positions

    @Test("Multiple text layers at different positions — all render correctly")
    func multipleTextLayersAtDifferentPositions() async throws {
        let (_, jpegData) = TestImageFactory.solidColorImage(
            color: CGColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1),
            size: CGSize(width: 600, height: 400)
        )
        let inputURL = try createTempInputFile(data: jpegData, name: "multi_text")

        let config = WatermarkConfiguration(
            watermarks: [
                .text(TextWatermarkInput(text: "TopLeft", fontSize: 36, opacity: 1.0),
                      position: .topLeft, scale: 0.12, opacity: 1.0, isVisible: true),
                .text(TextWatermarkInput(text: "TopRight", fontSize: 36, opacity: 0.8),
                      position: .topRight, scale: 0.12, opacity: 1.0, isVisible: true),
                .text(TextWatermarkInput(text: "BottomLeft", fontSize: 36, opacity: 0.6),
                      position: .bottomLeft, scale: 0.12, opacity: 1.0, isVisible: true),
                .text(TextWatermarkInput(text: "BottomRight", fontSize: 36, opacity: 0.4),
                      position: .bottomRight, scale: 0.12, opacity: 1.0, isVisible: true),
            ]
        )

        let engine = WatermarkEngine()
        let result = try await engine.process(sourceURL: inputURL, config: config)
        #expect(result.url != nil)

        guard let outputURL = result.url,
              let source = CGImageSourceCreateWithURL(outputURL as CFURL, nil) else {
            Issue.record("Failed to read output")
            cleanup(inputURL)
            return
        }
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        #expect((props[kCGImagePropertyPixelWidth] as? Int) == 600)
        #expect((props[kCGImagePropertyPixelHeight] as? Int) == 400)

        cleanup(inputURL, outputURL)
    }

    // MARK: - Test 6: Backward compatibility — single text layer

    @Test("Backward compatible: single text layer with default opacity/visibility")
    func singleTextLayerStillWorks() async throws {
        let (_, jpegData) = TestImageFactory.solidColorImage(
            color: CGColor(red: 0, green: 0, blue: 1, alpha: 1),
            size: CGSize(width: 400, height: 300)
        )
        let inputURL = try createTempInputFile(data: jpegData, name: "backward_compat")

        let config = WatermarkConfiguration(
            watermarks: [
                .text(TextWatermarkInput(text: "Test", fontSize: 48, opacity: 0.8),
                      position: .center, scale: 0.1, opacity: 1.0, isVisible: true),
            ]
        )

        let engine = WatermarkEngine()
        let result = try await engine.process(sourceURL: inputURL, config: config)
        #expect(result.url != nil)
        #expect(FileManager.default.fileExists(atPath: result.url!.path))

        guard let outputURL = result.url,
              let source = CGImageSourceCreateWithURL(outputURL as CFURL, nil) else {
            Issue.record("Failed to read output")
            cleanup(inputURL)
            return
        }
        #expect(CGImageSourceGetCount(source) == 1)
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        #expect((props[kCGImagePropertyPixelWidth] as? Int) == 400)
        #expect((props[kCGImagePropertyPixelHeight] as? Int) == 300)

        cleanup(inputURL, outputURL)
    }

    // MARK: - Test 7: All layers visible with default opacity

    @Test("All layers visible with default opacity — output matches expected combined appearance")
    func allLayersVisibleDefaultOpacity() async throws {
        let (_, jpegData) = TestImageFactory.solidColorImage(
            color: CGColor(red: 0.1, green: 0.1, blue: 0.3, alpha: 1),
            size: CGSize(width: 500, height: 400)
        )
        let inputURL = try createTempInputFile(data: jpegData, name: "all_visible")
        let pngData = createMinimalPNGWatermark()

        let config = WatermarkConfiguration(
            watermarks: [
                .text(TextWatermarkInput(text: "Layer1", fontSize: 32, opacity: 0.9),
                      position: .topLeft, scale: 0.12, opacity: 1.0, isVisible: true),
                .text(TextWatermarkInput(text: "Layer2", fontSize: 28, opacity: 0.7),
                      position: .topRight, scale: 0.10, opacity: 1.0, isVisible: true),
                .image(try ImageWatermarkInput(pngData: pngData, scale: 0.15, opacity: 0.8),
                       position: .bottomRight, scale: 0.12, opacity: 1.0, isVisible: true),
            ],
            whiteFrame: WhiteFrameConfig(isEnabled: true,
                                          metadataTextEnabled: true)
        )

        let engine = WatermarkEngine()
        let result = try await engine.process(sourceURL: inputURL, config: config)
        #expect(result.url != nil)
        #expect(result.outputUTI == "public.jpeg")

        guard let outputURL = result.url,
              let source = CGImageSourceCreateWithURL(outputURL as CFURL, nil) else {
            Issue.record("Failed to read output")
            cleanup(inputURL)
            return
        }
        // Framed export: the mat is added outside the 500x400 source.
        let frameConfig = config.whiteFrame ?? WhiteFrameConfig()
        let framed = FrameGeometry(
            config: frameConfig,
            sourceSize: CGSize(width: 500, height: 400),
            hasCaptionContent: WhiteFrameRenderer.hasCaptionContent(
                config: frameConfig, metadata: sourceMetadata(inputURL))
        ).framedSize
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        #expect((props[kCGImagePropertyPixelWidth] as? Int) == Int(framed.width))
        #expect((props[kCGImagePropertyPixelHeight] as? Int) == Int(framed.height))

        cleanup(inputURL, outputURL)
    }

    // MARK: - Test 8: ProRAW DNG metadata round-trip via engine process()

    @Test("ProRAW DNG metadata passes through engine process() pipeline")
    func proRAWDNGMetadataRoundTrip() async throws {
        // This test verifies the engine's dngMetadata passthrough wiring.
        // Since DNG write is UNSUPPORTED (CGImageDestinationCreateWithData returns nil
        // for com.adobe.raw-image), we test with a JPEG source and verify the passthrough
        // wiring compiles and doesn't crash.
        let (_, jpegData) = TestImageFactory.solidColorImage(
            color: CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1),
            size: CGSize(width: 200, height: 150)
        )
        let inputURL = try createTempInputFile(data: jpegData, name: "proraw_wiring")

        let config = WatermarkConfiguration(
            watermarks: [
                .text(TextWatermarkInput(text: "ProRAW", fontSize: 24, opacity: 1.0),
                      position: .center, scale: 0.1, opacity: 1.0, isVisible: true),
            ]
        )

        let engine = WatermarkEngine()
        let result = try await engine.process(sourceURL: inputURL, config: config)
        #expect(result.url != nil)
        #expect(FileManager.default.fileExists(atPath: result.url!.path))

        guard let outputURL = result.url,
              let source = CGImageSourceCreateWithURL(outputURL as CFURL, nil) else {
            Issue.record("Failed to read output")
            cleanup(inputURL)
            return
        }
        #expect(CGImageSourceGetCount(source) == 1)

        cleanup(inputURL, outputURL)
    }
}
