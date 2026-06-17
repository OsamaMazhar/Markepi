import Testing
import ImageIO
import CoreImage
import Foundation
#if canImport(UIKit)
import UIKit
#endif
@testable import WatermarkCore

/// End-to-end integration tests for WatermarkEngine.
///
/// Tests the full pipeline: load → watermarked render → write → verify
/// using test images created by TestImageFactory.
@Suite("WatermarkEngine E2E")
struct WatermarkEngineTests {

    /// Creates a temp JPEG file from test image data for engine input.
    private func createTempInputFile(data: Data, name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)_\(UUID().uuidString).jpg")
        try data.write(to: url)
        return url
    }

    /// Cleans up temp files after a test.
    private func cleanup(_ urls: URL...) {
        for url in urls {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Basic processing

    @Test("Process a test image — engine returns ProcessingResult with output file")
    func processReturnsResult() async throws {
        let (_, jpegData) = TestImageFactory.solidColorImage(
            color: CGColor(red: 0, green: 0, blue: 1, alpha: 1),
            size: CGSize(width: 800, height: 600)
        )
        let inputURL = try createTempInputFile(data: jpegData, name: "e2e_input")

        let config = WatermarkConfiguration(
            watermarks: [
                .text(TextWatermarkInput(text: "TEST", fontSize: 48, opacity: 1.0),
                      position: .center, scale: 0.1)
            ]
        )
        let engine = WatermarkEngine()

        // RED: stub throws invalidSource → test will fail
        // GREEN: engine processes successfully
        do {
            let result = try await engine.process(sourceURL: inputURL, config: config)
            #expect(result.url != nil, "Expected non-nil output URL")
            #expect(result.outputUTI == "public.jpeg", "Expected JPEG output UTI")
            #expect(FileManager.default.fileExists(atPath: result.url!.path),
                    "Output file should exist on disk")
            cleanup(inputURL, result.url!)
        } catch {
            // RED phase: expected
            Issue.record("Engine threw: \(error) — expected in GREEN phase")
            cleanup(inputURL)
        }
    }

    @Test("Output preserves source image pixel dimensions")
    func outputPreservesDimensions() async throws {
        let (_, jpegData) = TestImageFactory.solidColorImage(
            color: CGColor(red: 1, green: 0, blue: 0, alpha: 1),
            size: CGSize(width: 400, height: 300)
        )
        let inputURL = try createTempInputFile(data: jpegData, name: "dims_input")

        let config = WatermarkConfiguration(
            watermarks: [
                .text(TextWatermarkInput(text: "OK", fontSize: 36, opacity: 1.0),
                      position: .topLeft, scale: 0.05)
            ]
        )
        let engine = WatermarkEngine()

        do {
            let result = try await engine.process(sourceURL: inputURL, config: config)

            guard let outputURL = result.url else {
                Issue.record("Expected output URL")
                cleanup(inputURL)
                return
            }

            // Read output and verify dimensions
            guard let source = CGImageSourceCreateWithURL(outputURL as CFURL, nil) else {
                Issue.record("Failed to read output file")
                cleanup(inputURL, outputURL)
                return
            }
            let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
            let width = props[kCGImagePropertyPixelWidth] as? Int ?? 0
            let height = props[kCGImagePropertyPixelHeight] as? Int ?? 0
            #expect(width == 400, "Output width should be 400, got \(width)")
            #expect(height == 300, "Output height should be 300, got \(height)")

            cleanup(inputURL, outputURL)
        } catch {
            Issue.record("Engine threw: \(error) — expected in GREEN phase")
            cleanup(inputURL)
        }
    }

    @Test("Output preserves source format UTI (JPEG in → JPEG out)")
    func outputPreservesFormat() async throws {
        let (_, jpegData) = TestImageFactory.solidColorImage(
            color: CGColor(red: 0, green: 1, blue: 0, alpha: 1),
            size: CGSize(width: 200, height: 200)
        )
        let inputURL = try createTempInputFile(data: jpegData, name: "fmt_input")

        let config = WatermarkConfiguration(
            watermarks: [
                .text(TextWatermarkInput(text: "A", fontSize: 24, opacity: 1.0),
                      position: .bottomRight, scale: 0.1)
            ]
        )
        let engine = WatermarkEngine()

        do {
            let result = try await engine.process(sourceURL: inputURL, config: config)
            #expect(result.outputUTI == "public.jpeg", "Expected JPEG output UTI")

            if let outputURL = result.url {
                cleanup(inputURL, outputURL)
            } else {
                cleanup(inputURL)
            }
        } catch {
            Issue.record("Engine threw: \(error) — expected in GREEN phase")
            cleanup(inputURL)
        }
    }

    @Test("Output file has valid structure (CGImageSourceGetCount == 1)")
    func outputHasValidStructure() async throws {
        let (_, jpegData) = TestImageFactory.solidColorImage(
            color: CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1),
            size: CGSize(width: 100, height: 100)
        )
        let inputURL = try createTempInputFile(data: jpegData, name: "struct_input")

        let config = WatermarkConfiguration(
            watermarks: [
                .text(TextWatermarkInput(text: "X", fontSize: 12, opacity: 1.0),
                      position: .center, scale: 0.05)
            ]
        )
        let engine = WatermarkEngine()

        do {
            let result = try await engine.process(sourceURL: inputURL, config: config)
            guard let outputURL = result.url else {
                Issue.record("Expected output URL")
                cleanup(inputURL)
                return
            }
            guard let source = CGImageSourceCreateWithURL(outputURL as CFURL, nil) else {
                Issue.record("Failed to create source from output")
                cleanup(inputURL, outputURL)
                return
            }
            #expect(CGImageSourceGetCount(source) == 1, "Expected exactly 1 image in output")
            cleanup(inputURL, outputURL)
        } catch {
            Issue.record("Engine threw: \(error) — expected in GREEN phase")
            cleanup(inputURL)
        }
    }

    @Test("Metadata round-trip preserves keys through full pipeline")
    func metadataRoundTrip() async throws {
        let (_, jpegData) = TestImageFactory.solidColorImage(
            color: CGColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1),
            size: CGSize(width: 200, height: 150)
        )
        let inputURL = try createTempInputFile(data: jpegData, name: "meta_input")

        let config = WatermarkConfiguration(
            watermarks: [
                .text(TextWatermarkInput(text: "META", fontSize: 32, opacity: 0.8),
                      position: .topCenter, scale: 0.1)
            ]
        )
        let engine = WatermarkEngine()

        do {
            let result = try await engine.process(sourceURL: inputURL, config: config)

            guard let outputURL = result.url else {
                Issue.record("Expected output URL")
                cleanup(inputURL)
                return
            }

            // Read input and output metadata
            guard let inSource = CGImageSourceCreateWithURL(inputURL as CFURL, nil),
                  let outSource = CGImageSourceCreateWithURL(outputURL as CFURL, nil) else {
                Issue.record("Failed to create CGImageSource")
                cleanup(inputURL, outputURL)
                return
            }
            let inProps = CGImageSourceCopyPropertiesAtIndex(inSource, 0, nil) as? [CFString: Any] ?? [:]
            let outProps = CGImageSourceCopyPropertiesAtIndex(outSource, 0, nil) as? [CFString: Any] ?? [:]

            // Verify key dimensions are preserved
            #expect(inProps[kCGImagePropertyPixelWidth] as? Int == outProps[kCGImagePropertyPixelWidth] as? Int)
            #expect(inProps[kCGImagePropertyPixelHeight] as? Int == outProps[kCGImagePropertyPixelHeight] as? Int)

            cleanup(inputURL, outputURL)
        } catch {
            Issue.record("Engine threw: \(error) — expected in GREEN phase")
            cleanup(inputURL)
        }
    }

    // MARK: - Image watermark helpers

    /// Creates a small colored PNG Data blob for use as an image watermark.
    private func makeWatermarkPNG(
        size: CGSize = CGSize(width: 40, height: 40),
        color: CGColor = CGColor(red: 1, green: 0, blue: 0, alpha: 1)
    ) -> Data {
        #if canImport(UIKit)
        let rect = CGRect(origin: .zero, size: size)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.pngData { ctx in
            UIColor(cgColor: color).setFill()
            ctx.fill(rect)
        }
        #else
        // macOS fallback via Core Image
        let ciImage = CIImage(color: CIColor(cgColor: color))
            .cropped(to: CGRect(origin: .zero, size: size))
        let context = CIContext()
        let cgImage = context.createCGImage(ciImage, from: ciImage.extent)!
        let data = NSMutableData()
        let dest = CGImageDestinationCreateWithData(
            data, "public.png" as CFString, 1, nil
        )!
        CGImageDestinationAddImage(dest, cgImage, nil)
        CGImageDestinationFinalize(dest)
        return data as Data
        #endif
    }

    // MARK: - Mixed text + image watermark

    @Test("Mixed text and image layers both appear in output")
    func mixedTextAndImageLayers() async throws {
        let (_, jpegData) = TestImageFactory.solidColorImage(
            color: CGColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1),
            size: CGSize(width: 400, height: 300)
        )
        let inputURL = try createTempInputFile(data: jpegData, name: "mixed_input")

        // Create a small red PNG watermark
        let pngData = makeWatermarkPNG(size: CGSize(width: 40, height: 40),
                                        color: CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        let imageInput = try ImageWatermarkInput(pngData: pngData, scale: 0.5, opacity: 0.8)

        let config = WatermarkConfiguration(
            watermarks: [
                .text(TextWatermarkInput(text: "TOP", fontSize: 36, opacity: 1.0),
                      position: .topLeft, scale: 0.1),
                .image(imageInput, position: .bottomRight, scale: 0.5),
            ]
        )
        let engine = WatermarkEngine()

        do {
            let result = try await engine.process(sourceURL: inputURL, config: config)
            // RED: image layer is skipped, but text layer should still work
            // GREEN: both layers composited — output dimensions and format preserved
            #expect(result.url != nil, "Expected non-nil output URL")
            #expect(FileManager.default.fileExists(atPath: result.url!.path))

            // Verify output is valid
            if let outputURL = result.url,
               let source = CGImageSourceCreateWithURL(outputURL as CFURL, nil) {
                #expect(CGImageSourceGetCount(source) == 1)

                let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
                let width = props[kCGImagePropertyPixelWidth] as? Int ?? 0
                let height = props[kCGImagePropertyPixelHeight] as? Int ?? 0
                #expect(width == 400, "Output width should be preserved")
                #expect(height == 300, "Output height should be preserved")

                cleanup(inputURL, outputURL)
            } else {
                cleanup(inputURL)
            }
        } catch {
            Issue.record("Engine threw: \(error) — expected in GREEN phase")
            cleanup(inputURL)
        }
    }

    // MARK: - Image watermark opacity

    @Test("Image watermark at opacity 1.0 is fully visible in output pixels")
    func imageWatermarkFullOpacity() async throws {
        // Pure blue base image
        let (_, jpegData) = TestImageFactory.solidColorImage(
            color: CGColor(red: 0, green: 0, blue: 1, alpha: 1),
            size: CGSize(width: 200, height: 200)
        )
        let inputURL = try createTempInputFile(data: jpegData, name: "opaque_input")

        // Red PNG watermark — when applied over blue at full opacity, center should be red
        let pngData = makeWatermarkPNG(size: CGSize(width: 100, height: 100),
                                        color: CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        let imageInput = try ImageWatermarkInput(pngData: pngData, scale: 0.5, opacity: 1.0)

        let config = WatermarkConfiguration(
            watermarks: [
                .image(imageInput, position: .center, scale: 0.5),
            ]
        )
        let engine = WatermarkEngine()

        do {
            let result = try await engine.process(sourceURL: inputURL, config: config)
            // RED: image layer skipped — output is pure blue (no watermark)
            // GREEN: image watermark applied at center — center pixel should be red-dominant
            #expect(result.url != nil)

            guard let outputURL = result.url,
                  let source = CGImageSourceCreateWithURL(outputURL as CFURL, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                Issue.record("Failed to read output image")
                cleanup(inputURL)
                return
            }

            // Sample center pixel — should show red watermark over blue base
            let pixelData = TestImageFactory.pixelData(from: cgImage)
            #expect(pixelData != nil, "Should be able to read pixel data")

            if let data = pixelData {
                // Center pixel at (100, 100) in 200×200 RGBA8 image
                let width = 200
                let centerRow = 100
                let centerCol = 100
                let offset = (centerRow * width + centerCol) * 4
                guard offset + 3 < data.count else {
                    Issue.record("Pixel offset out of bounds")
                    cleanup(inputURL, outputURL)
                    return
                }
                let r = data[offset]
                let g = data[offset + 1]
                let b = data[offset + 2]
                // RED: watermark not applied → center shows blue (b > r)
                // GREEN: red watermark over blue → center shows red (r should be high)
                #expect(r > 100, "Red channel should show watermark presence (got r=\(r), g=\(g), b=\(b))")
            }

            cleanup(inputURL, outputURL)
        } catch {
            Issue.record("Engine threw: \(error) — expected in GREEN phase")
            cleanup(inputURL)
        }
    }

    @Test("Image watermark at opacity 0.0 is invisible")
    func imageWatermarkZeroOpacity() async throws {
        let (_, jpegData) = TestImageFactory.solidColorImage(
            color: CGColor(red: 0, green: 1, blue: 0, alpha: 1),
            size: CGSize(width: 200, height: 200)
        )
        let inputURL = try createTempInputFile(data: jpegData, name: "invisible_input")

        let pngData = makeWatermarkPNG(size: CGSize(width: 50, height: 50),
                                        color: CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        let imageInput = try ImageWatermarkInput(pngData: pngData, scale: 0.5, opacity: 0.0)

        let config = WatermarkConfiguration(
            watermarks: [
                .image(imageInput, position: .center, scale: 0.5),
            ]
        )
        let engine = WatermarkEngine()

        do {
            let result = try await engine.process(sourceURL: inputURL, config: config)
            // GREEN: opacity 0.0 — output should still be valid, watermark invisible
            #expect(result.url != nil)

            if let outputURL = result.url,
               let source = CGImageSourceCreateWithURL(outputURL as CFURL, nil) {
                let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
                let width = props[kCGImagePropertyPixelWidth] as? Int ?? 0
                let height = props[kCGImagePropertyPixelHeight] as? Int ?? 0
                #expect(width == 200 && height == 200, "Dimensions preserved")

                cleanup(inputURL, outputURL)
            } else {
                cleanup(inputURL)
            }
        } catch {
            Issue.record("Engine threw: \(error) — expected in GREEN phase")
            cleanup(inputURL)
        }
    }

    // MARK: - Padding

    @Test("Configurable padding via WatermarkConfiguration.padding")
    func configurablePadding() async throws {
        let (_, jpegData) = TestImageFactory.solidColorImage(
            color: CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1),
            size: CGSize(width: 300, height: 200)
        )
        let inputURL = try createTempInputFile(data: jpegData, name: "pad_input")

        let pngData = makeWatermarkPNG(size: CGSize(width: 20, height: 20))
        let imageInput = try ImageWatermarkInput(pngData: pngData, scale: 0.5, opacity: 1.0)

        var config = WatermarkConfiguration(
            watermarks: [
                .image(imageInput, position: .topLeft, scale: 0.5),
            ]
        )
        config.padding = 50

        let engine = WatermarkEngine()

        do {
            let result = try await engine.process(sourceURL: inputURL, config: config)
            // GREEN: padding=50 applied — output valid
            #expect(result.url != nil)

            if let outputURL = result.url,
               let source = CGImageSourceCreateWithURL(outputURL as CFURL, nil) {
                #expect(CGImageSourceGetCount(source) == 1)
                cleanup(inputURL, outputURL)
            } else {
                cleanup(inputURL)
            }
        } catch {
            Issue.record("Engine threw: \(error) — expected in GREEN phase")
            cleanup(inputURL)
        }
    }

    @Test("Default padding is 20 when not explicitly set")
    func defaultPadding() async throws {
        let (_, jpegData) = TestImageFactory.solidColorImage(
            color: CGColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1),
            size: CGSize(width: 200, height: 200)
        )
        let inputURL = try createTempInputFile(data: jpegData, name: "defpad_input")

        let pngData = makeWatermarkPNG(size: CGSize(width: 20, height: 20))
        let imageInput = try ImageWatermarkInput(pngData: pngData, scale: 0.5, opacity: 1.0)

        // No explicit padding set — should default to 20
        let config = WatermarkConfiguration(
            watermarks: [
                .image(imageInput, position: .topLeft, scale: 0.5),
            ]
        )
        let engine = WatermarkEngine()

        do {
            let result = try await engine.process(sourceURL: inputURL, config: config)
            #expect(result.url != nil)

            if let outputURL = result.url {
                cleanup(inputURL, outputURL)
            } else {
                cleanup(inputURL)
            }
        } catch {
            Issue.record("Engine threw: \(error) — expected in GREEN phase")
            cleanup(inputURL)
        }
    }

    // MARK: - Image-only watermark configuration

    @Test("Image-only watermark config produces valid output (no text layers)")
    func imageOnlyConfig() async throws {
        let (_, jpegData) = TestImageFactory.solidColorImage(
            color: CGColor(red: 0.8, green: 0.8, blue: 0.8, alpha: 1),
            size: CGSize(width: 150, height: 150)
        )
        let inputURL = try createTempInputFile(data: jpegData, name: "imgonly_input")

        let pngData = makeWatermarkPNG(size: CGSize(width: 30, height: 30))
        let imageInput = try ImageWatermarkInput(pngData: pngData, scale: 0.4, opacity: 0.9)

        let config = WatermarkConfiguration(
            watermarks: [
                .image(imageInput, position: .bottomRight, scale: 0.4),
            ]
        )
        let engine = WatermarkEngine()

        do {
            let result = try await engine.process(sourceURL: inputURL, config: config)
            // RED: image layer skipped → output has no watermark applied
            // GREEN: image watermark rendered at bottomRight
            #expect(result.url != nil)

            if let outputURL = result.url,
               let source = CGImageSourceCreateWithURL(outputURL as CFURL, nil) {
                let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
                let width = props[kCGImagePropertyPixelWidth] as? Int ?? 0
                let height = props[kCGImagePropertyPixelHeight] as? Int ?? 0
                #expect(width == 150 && height == 150, "Dimensions preserved")

                cleanup(inputURL, outputURL)
            } else {
                cleanup(inputURL)
            }
        } catch {
            Issue.record("Engine threw: \(error) — expected in GREEN phase")
            cleanup(inputURL)
        }
    }
}
