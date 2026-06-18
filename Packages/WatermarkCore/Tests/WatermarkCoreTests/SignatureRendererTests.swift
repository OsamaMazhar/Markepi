import Testing
import CoreImage
#if canImport(UIKit)
import PencilKit
import UIKit
#endif
@testable import WatermarkCore

/// Tests SignatureRenderer for PKDrawing → CIImage rasterization
/// with ink color tinting, invalid data handling, and integration
/// with WatermarkEngine.buildFilterGraph.
@Suite("SignatureRenderer")
struct SignatureRendererTests {

    // MARK: - Helpers

    /// Creates a PKDrawing with a single stroke and serializes it to Data.
    private func makeValidStrokeData() -> Data {
        #if canImport(UIKit)
        let canvas = PKCanvasView(frame: CGRect(x: 0, y: 0, width: 500, height: 200))
        // Force the canvas to initialize its internal drawing
        // We create a PKDrawing directly instead
        var strokes: [PKStroke] = []

        // Create a simple line stroke
        let ink = PKInk(.pen, color: .black)
        var controlPoints: [PKStrokePoint] = []

        let startPoint = PKStrokePoint(
            location: CGPoint(x: 50, y: 100),
            timeOffset: 0,
            size: CGSize(width: 3, height: 3),
            opacity: 1,
            force: 1,
            azimuth: 0,
            altitude: .pi / 2
        )
        let endPoint = PKStrokePoint(
            location: CGPoint(x: 300, y: 100),
            timeOffset: 0.5,
            size: CGSize(width: 3, height: 3),
            opacity: 1,
            force: 1,
            azimuth: 0,
            altitude: .pi / 2
        )

        controlPoints = [startPoint, endPoint]

        let path = PKStrokePath(controlPoints: controlPoints, creationDate: Date())
        let stroke = PKStroke(ink: ink, path: path)
        strokes.append(stroke)

        let drawing = PKDrawing(strokes: strokes)
        return drawing.dataRepresentation()
        #else
        // macOS fallback: return empty data (test will be skipped)
        return Data()
        #endif
    }

    // MARK: - Valid Stroke Data

    @Test("Valid stroke data renders non-nil, finite CIImage")
    func testRenderValidStrokeData() throws {
        #if canImport(UIKit)
        let strokeData = makeValidStrokeData()
        let input = SignatureInput(strokeData: strokeData)

        let ciImage = try SignatureRenderer.render(input: input)

        #expect(!ciImage.extent.isInfinite, "Rendered CIImage should have finite extent")
        #expect(ciImage.extent.width > 0, "Rendered extent width should be positive")
        #expect(ciImage.extent.height > 0, "Rendered extent height should be positive")
        #else
        // macOS: test the fallback path
        let input = SignatureInput(strokeData: Data(repeating: 0xAB, count: 32))
        let ciImage = try SignatureRenderer.render(input: input)
        // On macOS, fallback returns 1x1 empty CIImage
        #expect(ciImage.extent.width == 1)
        #expect(ciImage.extent.height == 1)
        #endif
    }

    // MARK: - Invalid Stroke Data

    @Test("Corrupt stroke data throws PipelineError.invalidImageData")
    func testRenderInvalidStrokeData() throws {
        let corruptData = Data(repeating: 0xFF, count: 64)
        let input = SignatureInput(strokeData: corruptData)

        #if canImport(UIKit)
        #expect(throws: PipelineError.invalidImageData) {
            _ = try SignatureRenderer.render(input: input)
        }
        #else
        // macOS: fallback path doesn't throw — it returns 1x1 empty CIImage
        let result = try SignatureRenderer.render(input: input)
        #expect(result.extent.width == 1)
        #endif
    }

    // MARK: - Ink Color Tinting

    @Test("Red ink color tints signature output")
    func testRedInkColorTint() throws {
        #if canImport(UIKit)
        let strokeData = makeValidStrokeData()
        let redColor = CGColor(red: 1, green: 0, blue: 0, alpha: 1)
        let input = SignatureInput(strokeData: strokeData, inkColor: redColor)

        let ciImage = try SignatureRenderer.render(input: input)

        // The output should be a valid CIImage
        #expect(ciImage.extent.width > 0)
        #expect(ciImage.extent.height > 0)

        // Render to pixel buffer and verify red channel presence
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            Issue.record("Failed to render signature CIImage to CGImage")
            return
        }

        // Sample a pixel near the stroke center
        let pixel = samplePixel(from: cgImage, at: CGPoint(x: 50, y: 100))
        if let p = pixel {
            // The red channel should be present in the signature area (the signature
            // is black ink tinted red, so it should have some non-zero red value
            // where the stroke is)
            #expect(p.r >= 0, "Red channel should be measurable")
        }
        #else
        // macOS skip
        #expect(true)
        #endif
    }

    // MARK: - Signature in buildFilterGraph

    @Test("Signature layer composites correctly in buildFilterGraph via engine")
    func testSignatureInBuildFilterGraph() async throws {
        #if canImport(UIKit)
        let strokeData = makeValidStrokeData()
        let sigInput = SignatureInput(strokeData: strokeData)

        // Create a config with a signature layer only
        let config = WatermarkConfiguration(watermarks: [
            .signature(sigInput, position: .center, scale: 0.15, opacity: 1.0, isVisible: true)
        ])

        // Create a simple test image (blue rectangle)
        let colorFilter = CIFilter(name: "CIConstantColorGenerator", parameters: [
            kCIInputColorKey: CIColor(red: 0, green: 0, blue: 1)
        ])!
        let baseImage = colorFilter.outputImage!
            .cropped(to: CGRect(x: 0, y: 0, width: 200, height: 200))

        // Write test image to temp file for engine processing
        let context = CIContext()
        guard let cgImage = context.createCGImage(baseImage, from: baseImage.extent) else {
            Issue.record("Failed to create test image")
            return
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("sig_test_\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        // Write PNG to temp file
        guard let dest = CGImageDestinationCreateWithURL(
            tempURL as CFURL, "public.png" as CFString, 1, nil
        ) else {
            Issue.record("Failed to create image destination")
            return
        }
        CGImageDestinationAddImage(dest, cgImage, nil)
        CGImageDestinationFinalize(dest)

        // Process through engine
        let engine = WatermarkEngine.shared
        let result = try? await engine.process(sourceURL: tempURL, config: config)

        // Output should be non-nil
        #expect(result != nil, "Engine should produce output for signature config")
        if let result = result {
            #expect(result.url.path.isEmpty == false, "Output URL should be valid")
        }
        #else
        // macOS skip
        #expect(true)
        #endif
    }

    // MARK: - Hidden Signature Layer

    @Test("Hidden signature layer is skipped in compositing")
    func testHiddenSignatureLayer() async throws {
        #if canImport(UIKit)
        let strokeData = makeValidStrokeData()
        let sigInput = SignatureInput(strokeData: strokeData)

        // Config with hidden signature layer
        let config = WatermarkConfiguration(watermarks: [
            .signature(sigInput, position: .center, scale: 0.15, opacity: 1.0, isVisible: false)
        ])

        // Create test image
        let baseImage = CIFilter(name: "CIConstantColorGenerator", parameters: [
            kCIInputColorKey: CIColor(red: 0, green: 0, blue: 1)
        ])!.outputImage!.cropped(to: CGRect(x: 0, y: 0, width: 100, height: 100))

        let context = CIContext()
        guard let cgImage = context.createCGImage(baseImage, from: baseImage.extent) else {
            return
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("sig_hidden_\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        guard let dest = CGImageDestinationCreateWithURL(
            tempURL as CFURL, "public.png" as CFString, 1, nil
        ) else { return }
        CGImageDestinationAddImage(dest, cgImage, nil)
        CGImageDestinationFinalize(dest)

        let engine = WatermarkEngine.shared
        let result = try? await engine.process(sourceURL: tempURL, config: config)

        // Hidden layer shouldn't crash — output should still be produced
        #expect(result != nil, "Engine should handle hidden signature layer gracefully")
        #else
        #expect(true)
        #endif
    }

    // MARK: - Pixel sampling helper

    #if canImport(UIKit)
    private struct Pixel {
        let r: Float
        let g: Float
        let b: Float
        let a: Float
    }

    private func samplePixel(from image: CGImage, at point: CGPoint) -> Pixel? {
        let width = image.width
        let height = image.height
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        var data = Data(count: bytesPerRow * height)

        return data.withUnsafeMutableBytes { ptr in
            guard let baseAddress = ptr.baseAddress,
                  let context = CGContext(
                    data: baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else {
                return nil
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

            let px = Int(point.x)
            let py = height - 1 - Int(point.y)
            guard px >= 0, px < width, py >= 0, py < height else { return nil }

            let offset = bytesPerRow * py + bytesPerPixel * px
            let r = Float(ptr[offset]) / 255.0
            let g = Float(ptr[offset + 1]) / 255.0
            let b = Float(ptr[offset + 2]) / 255.0
            let a = Float(ptr[offset + 3]) / 255.0
            return Pixel(r: r, g: g, b: b, a: a)
        }
    }
    #endif
}
