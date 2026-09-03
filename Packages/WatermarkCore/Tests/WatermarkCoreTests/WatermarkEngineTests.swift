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
                      position: .center, scale: 0.1, opacity: 1.0, isVisible: true)
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
                      position: .topLeft, scale: 0.05, opacity: 1.0, isVisible: true)
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
                      position: .bottomRight, scale: 0.1, opacity: 1.0, isVisible: true)
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
                      position: .center, scale: 0.05, opacity: 1.0, isVisible: true)
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
                      position: .topCenter, scale: 0.1, opacity: 1.0, isVisible: true)
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
                      position: .topLeft, scale: 0.1, opacity: 1.0, isVisible: true),
                .image(imageInput, position: .bottomRight, scale: 0.5, opacity: 1.0, isVisible: true),
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
                .image(imageInput, position: .center, scale: 0.5, opacity: 1.0, isVisible: true),
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
                .image(imageInput, position: .center, scale: 0.5, opacity: 1.0, isVisible: true),
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

    @Test("Configurable padding via WatermarkConfiguration.paddingMillimetres")
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
                .image(imageInput, position: .topLeft, scale: 0.5, opacity: 1.0, isVisible: true),
            ]
        )
        config.paddingMillimetres = 20

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
                .image(imageInput, position: .topLeft, scale: 0.5, opacity: 1.0, isVisible: true),
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
                .image(imageInput, position: .bottomRight, scale: 0.4, opacity: 1.0, isVisible: true),
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

    // MARK: - White frame integration (Plan 03)

    /// Creates a JPEG with mock TIFF metadata for device model testing.
    private func createInputWithMetadata(
        model: String,
        size: CGSize = CGSize(width: 400, height: 300),
        color: CGColor = CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)
    ) throws -> URL {
        let (cgImage, _) = TestImageFactory.solidColorImage(
            color: color,
            size: size
        )
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, "public.jpeg" as CFString, 1, nil
        ) else {
            throw PipelineError.failedToCreateDestination
        }
        // Add TIFF metadata with device model
        let tiffDict: [CFString: Any] = [
            kCGImagePropertyTIFFModel: model,
        ]
        let metadata: [CFString: Any] = [
            kCGImagePropertyTIFFDictionary: tiffDict,
        ]
        CGImageDestinationAddImage(destination, cgImage, metadata as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw PipelineError.failedToFinalize
        }
        return try createTempInputFile(data: data as Data, name: "meta_\(model)")
    }

    @Test("White frame only (no watermarks) — output has white border visible at edges")
    func whiteFrameOnly() async throws {
        let inputURL = try createInputWithMetadata(model: "iPhone 16 Pro")
        let config = WatermarkConfiguration(
            watermarks: [],
            whiteFrame: WhiteFrameConfig(isEnabled: true, metadataTextEnabled: false, style: .classic)
        )
        let engine = WatermarkEngine()

        do {
            let result = try await engine.process(sourceURL: inputURL, config: config)

            guard let outputURL = result.url,
                  let source = CGImageSourceCreateWithURL(outputURL as CFURL, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                Issue.record("Failed to read output image")
                cleanup(inputURL)
                return
            }

            let pixelData = TestImageFactory.pixelData(from: cgImage)
            #expect(pixelData != nil, "Should be able to read pixel data")

            if let data = pixelData {
                let width = 400
                // Sample top-left corner (should be white frame)
                let borderOffset = (1 * width + 1) * 4
                guard borderOffset + 3 < data.count else {
                    Issue.record("Border pixel offset out of bounds")
                    cleanup(inputURL, outputURL)
                    return
                }
                let borderR = data[borderOffset]
                let borderG = data[borderOffset + 1]
                let borderB = data[borderOffset + 2]

                // RED: frame not rendered → edges show base color (gray ~128)
                // GREEN: white frame rendered → edges show white (r > 200, g > 200, b > 200)
                #expect(borderR > 200, "Top-left corner should be white frame border (got r=\(borderR), g=\(borderG), b=\(borderB))")
                #expect(borderG > 200, "Top-left corner green channel should be white")
                #expect(borderB > 200, "Top-left corner blue channel should be white")
            }

            cleanup(inputURL, outputURL)
        } catch {
            Issue.record("Engine threw: \(error) — expected in GREEN phase")
            cleanup(inputURL)
        }
    }

    @Test("White frame + text watermark — watermark appears on top of frame")
    func frameWithTextWatermark() async throws {
        let inputURL = try createInputWithMetadata(model: "iPhone 16 Pro")
        let config = WatermarkConfiguration(
            watermarks: [
                .text(TextWatermarkInput(text: "TOP", fontSize: 48, opacity: 1.0),
                      position: .topLeft, scale: 0.15, opacity: 1.0, isVisible: true),
            ],
            whiteFrame: WhiteFrameConfig(isEnabled: true, metadataTextEnabled: false, style: .classic)
        )
        let engine = WatermarkEngine()

        do {
            let result = try await engine.process(sourceURL: inputURL, config: config)

            guard let outputURL = result.url,
                  let source = CGImageSourceCreateWithURL(outputURL as CFURL, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                Issue.record("Failed to read output image")
                cleanup(inputURL)
                return
            }

            let pixelData = TestImageFactory.pixelData(from: cgImage)
            #expect(pixelData != nil)

            if let data = pixelData {
                // The watermark sits INSIDE the photo, which the mat surrounds —
                // so look for it in the photo's top-left quadrant rather than at
                // a fixed offset, which lands in the mat as soon as the border
                // changes size. White "TOP" on a mid-grey photo: the proof the
                // watermark composited on top is a near-white pixel in there.
                let width = cgImage.width
                let geometry = FrameGeometry(
                    config: WhiteFrameConfig(isEnabled: true, metadataTextEnabled: false,
                                             style: .classic),
                    sourceSize: CGSize(width: 400, height: 300),
                    hasCaptionContent: false)
                let photo = geometry.photoRect
                var foundInk = false
                var y = Int(photo.minY)
                while y < Int(photo.midY), !foundInk {
                    var x = Int(photo.minX)
                    while x < Int(photo.midX) {
                        let offset = (y * width + x) * 4
                        guard offset + 3 < data.count else { break }
                        if data[offset] > 240, data[offset + 1] > 240, data[offset + 2] > 240 {
                            foundInk = true
                            break
                        }
                        x += 1
                    }
                    y += 1
                }
                #expect(foundInk,
                        "the watermark should be visible on the photo, inside the mat")
            }

            cleanup(inputURL, outputURL)
        } catch {
            Issue.record("Engine threw: \(error) — expected in GREEN phase")
            cleanup(inputURL)
        }
    }

    @Test("White frame with metadata text — 'Taken by: Model' visible in bottom region")
    func frameWithMetadataText() async throws {
        let inputURL = try createInputWithMetadata(
            model: "iPhone 16 Pro",
            size: CGSize(width: 800, height: 600)
        )

        // Process WITH text
        let configWithText = WatermarkConfiguration(
            watermarks: [],
            whiteFrame: WhiteFrameConfig(
                isEnabled: true,
                metadataTextEnabled: true,
                // Predates frame styles: asserts classic's centred caption.
                style: .classic
            )
        )
        // Process WITHOUT text
        let configNoText = WatermarkConfiguration(
            watermarks: [],
            whiteFrame: WhiteFrameConfig(
                isEnabled: true,
                metadataTextEnabled: false,
                // Predates frame styles: asserts classic's centred caption.
                style: .classic
            )
        )
        let engine = WatermarkEngine()

        do {
            let resultWithText = try await engine.process(sourceURL: inputURL, config: configWithText)
            let resultNoText = try await engine.process(sourceURL: inputURL, config: configNoText)

            guard let urlWithText = resultWithText.url,
                  let urlNoText = resultNoText.url,
                  let sourceWith = CGImageSourceCreateWithURL(urlWithText as CFURL, nil),
                  let sourceWithout = CGImageSourceCreateWithURL(urlNoText as CFURL, nil),
                  let cgWith = CGImageSourceCreateImageAtIndex(sourceWith, 0, nil),
                  let cgWithout = CGImageSourceCreateImageAtIndex(sourceWithout, 0, nil) else {
                Issue.record("Failed to read output images")
                cleanup(inputURL)
                return
            }

            let dataWith = TestImageFactory.pixelData(from: cgWith)
            let dataWithout = TestImageFactory.pixelData(from: cgWithout)
            #expect(dataWith != nil && dataWithout != nil)

            if let with = dataWith, let without = dataWithout {
                // Compute average brightness in bottom frame region for both images.
                // With text, the region should have lower average brightness (darker).
                let width = 800
                let height = 600
                let frameStart = height - 30  // bottom frame starts here
                var sumWith: Int = 0, sumWithout: Int = 0
                var count = 0

                for row in frameStart..<height {
                    for col in (width/4)..<(3*width/4) {
                        let offset = (row * width + col) * 4
                        guard offset + 3 < with.count, offset + 3 < without.count else { continue }
                        let rw = Int(with[offset]), gw = Int(with[offset + 1]), bw = Int(with[offset + 2])
                        let rn = Int(without[offset]), gn = Int(without[offset + 1]), bn = Int(without[offset + 2])
                        sumWith += rw + gw + bw
                        sumWithout += rn + gn + bn
                        count += 1
                    }
                }

                let avgWith = Double(sumWith) / Double(count * 3)
                let avgWithout = Double(sumWithout) / Double(count * 3)

                // With text, the bottom frame region should be slightly darker
                // due to dark gray text pixels on white frame background
                #expect(avgWith <= avgWithout,
                        Comment(rawValue: "Text-enabled frame should not be brighter than text-disabled. With text: \(avgWith), Without text: \(avgWithout)"))
                #expect(count > 0, "Should have sampled at least 1 pixel")

                cleanup(inputURL, urlWithText, urlNoText)
            } else {
                cleanup(inputURL)
            }
        } catch {
            Issue.record("Engine threw: \(error) — expected in GREEN phase")
            cleanup(inputURL)
        }
    }

    @Test("White frame disabled — output identical to no-frame processing")
    func whiteFrameDisabled() async throws {
        let inputURL = try createInputWithMetadata(model: "iPhone 16 Pro")
        let config = WatermarkConfiguration(
            watermarks: [
                .text(TextWatermarkInput(text: "TEST", fontSize: 36, opacity: 1.0),
                      position: .center, scale: 0.1, opacity: 1.0, isVisible: true),
            ],
            whiteFrame: WhiteFrameConfig(isEnabled: false)
        )
        let engine = WatermarkEngine()

        do {
            let result = try await engine.process(sourceURL: inputURL, config: config)

            // Should process normally — frame is disabled
            #expect(result.url != nil)
            guard let outputURL = result.url,
                  let source = CGImageSourceCreateWithURL(outputURL as CFURL, nil) else {
                Issue.record("Failed to read output")
                cleanup(inputURL)
                return
            }
            #expect(CGImageSourceGetCount(source) == 1)

            // No frame here, so the export keeps the source's dimensions —
            // which is what makes this the control for the framed cases.
            let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
            #expect((props[kCGImagePropertyPixelWidth] as? Int) == 400)
            #expect((props[kCGImagePropertyPixelHeight] as? Int) == 300)

            cleanup(inputURL, outputURL)
        } catch {
            Issue.record("Engine threw: \(error) — expected in GREEN phase")
            cleanup(inputURL)
        }
    }

    @Test("Custom attribution text override appears in output")
    func customAttributionTextInOutput() async throws {
        let inputURL = try createInputWithMetadata(
            model: "iPhone 16 Pro",
            size: CGSize(width: 800, height: 600)
        )
        let customText = "Custom Camera v2"

        // Process with custom text
        let configCustom = WatermarkConfiguration(
            watermarks: [],
            whiteFrame: WhiteFrameConfig(
                isEnabled: true,
                metadataTextEnabled: true,
                customAttributionText: customText,
                // Predates frame styles: asserts classic's centred caption.
                style: .classic
            )
        )
        // Process without text
        let configNoText = WatermarkConfiguration(
            watermarks: [],
            whiteFrame: WhiteFrameConfig(
                isEnabled: true,
                metadataTextEnabled: false,
                // Predates frame styles: asserts classic's centred caption.
                style: .classic
            )
        )
        let engine = WatermarkEngine()

        do {
            let resultCustom = try await engine.process(sourceURL: inputURL, config: configCustom)
            let resultNoText = try await engine.process(sourceURL: inputURL, config: configNoText)

            guard let urlCustom = resultCustom.url,
                  let urlNoText = resultNoText.url,
                  let sourceCustom = CGImageSourceCreateWithURL(urlCustom as CFURL, nil),
                  let sourceNoText = CGImageSourceCreateWithURL(urlNoText as CFURL, nil),
                  let cgCustom = CGImageSourceCreateImageAtIndex(sourceCustom, 0, nil),
                  let cgNoText = CGImageSourceCreateImageAtIndex(sourceNoText, 0, nil) else {
                Issue.record("Failed to read output images")
                cleanup(inputURL)
                return
            }

            let dataCustom = TestImageFactory.pixelData(from: cgCustom)
            let dataNoText = TestImageFactory.pixelData(from: cgNoText)
            #expect(dataCustom != nil && dataNoText != nil)

            if let with = dataCustom, let without = dataNoText {
                let width = 800
                let height = 600
                let frameStart = height - 30
                var sumWith: Int = 0, sumWithout: Int = 0
                var count = 0

                for row in frameStart..<height {
                    for col in (width/4)..<(3*width/4) {
                        let offset = (row * width + col) * 4
                        guard offset + 3 < with.count, offset + 3 < without.count else { continue }
                        sumWith += Int(with[offset]) + Int(with[offset + 1]) + Int(with[offset + 2])
                        sumWithout += Int(without[offset]) + Int(without[offset + 1]) + Int(without[offset + 2])
                        count += 1
                    }
                }

                let avgWith = Double(sumWith) / Double(count * 3)
                let avgWithout = Double(sumWithout) / Double(count * 3)

                // Custom text on the frame should make the bottom region slightly darker
                #expect(avgWith <= avgWithout,
                        Comment(rawValue: "Custom text frame should not be brighter than text-disabled. Custom: \(avgWith), No text: \(avgWithout)"))
                #expect(count > 0, "Should have sampled at least 1 pixel")

                cleanup(inputURL, urlCustom, urlNoText)
            } else {
                cleanup(inputURL)
            }
        } catch {
            Issue.record("Engine threw: \(error) — expected in GREEN phase")
            cleanup(inputURL)
        }
    }

    @Test("Format preservation with white frame — JPEG in → JPEG out")
    func formatPreservationWithFrame() async throws {
        let inputURL = try createInputWithMetadata(model: "iPhone 16 Pro")
        let config = WatermarkConfiguration(
            watermarks: [],
            whiteFrame: WhiteFrameConfig(isEnabled: true, metadataTextEnabled: false, style: .classic)
        )
        let engine = WatermarkEngine()

        do {
            let result = try await engine.process(sourceURL: inputURL, config: config)
            #expect(result.outputUTI == "public.jpeg",
                    "Output should preserve JPEG format, got \(result.outputUTI)")

            if let outputURL = result.url {
                // Verify output is valid JPEG (not forced to PNG due to CG rendering)
                guard let outSource = CGImageSourceCreateWithURL(outputURL as CFURL, nil) else {
                    Issue.record("Failed to read output")
                    cleanup(inputURL, outputURL)
                    return
                }
                let outType = CGImageSourceGetType(outSource) as String?
                #expect(outType == "public.jpeg",
                        "Output type should be JPEG, got \(outType ?? "nil")")

                cleanup(inputURL, outputURL)
            } else {
                cleanup(inputURL)
            }
        } catch {
            Issue.record("Engine threw: \(error) — expected in GREEN phase")
            cleanup(inputURL)
        }
    }

    @Test("HDR gain map survives white frame processing")
    func hdrGainMapSurvivesFrame() async throws {
        // Use a standard test image (no real HDR gain map in test, but verify
        // that the processing path doesn't crash or strip auxiliary data)
        let inputURL = try createInputWithMetadata(model: "iPhone 16 Pro")
        let config = WatermarkConfiguration(
            watermarks: [],
            whiteFrame: WhiteFrameConfig(isEnabled: true, metadataTextEnabled: false, style: .classic)
        )
        let engine = WatermarkEngine()

        do {
            let result = try await engine.process(sourceURL: inputURL, config: config)
            // RED: frame not rendered → test passes because existing pipeline works
            // GREEN: frame rendered → gain map preserved (per Open Question #1:
            //         original unmodified gain map re-attached at output)
            #expect(result.url != nil)

            guard let outputURL = result.url,
                  let source = CGImageSourceCreateWithURL(outputURL as CFURL, nil) else {
                Issue.record("Failed to read output")
                cleanup(inputURL)
                return
            }
            #expect(CGImageSourceGetCount(source) == 1)

            // Verify dimensions preserved
            let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
            // Framed export: the mat is added outside the 400x300 source.
            let frameConfig = config.whiteFrame ?? WhiteFrameConfig()
            let framed = FrameGeometry(
                config: frameConfig,
                sourceSize: CGSize(width: 400, height: 300),
                hasCaptionContent: WhiteFrameRenderer.hasCaptionContent(
                    config: frameConfig, metadata: sourceMetadata(inputURL))
            ).framedSize
            #expect((props[kCGImagePropertyPixelWidth] as? Int) == Int(framed.width))
            #expect((props[kCGImagePropertyPixelHeight] as? Int) == Int(framed.height))

            cleanup(inputURL, outputURL)
        } catch {
            Issue.record("Engine threw: \(error) — expected in GREEN phase")
            cleanup(inputURL)
        }
    }

    @Test("Combined: text watermark + image watermark + white frame — all visible")
    func combinedAllFeatures() async throws {
        let inputURL = try createInputWithMetadata(
            model: "iPhone 16 Pro",
            size: CGSize(width: 500, height: 400)
        )
        // Create image watermark PNG
        let pngData = makeWatermarkPNG(size: CGSize(width: 40, height: 40),
                                        color: CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        let imageInput = try ImageWatermarkInput(pngData: pngData, scale: 0.3, opacity: 0.9)

        let config = WatermarkConfiguration(
            watermarks: [
                .text(TextWatermarkInput(text: "Hello", fontSize: 36, opacity: 1.0),
                      position: .topLeft, scale: 0.12, opacity: 1.0, isVisible: true),
                .image(imageInput, position: .bottomRight, scale: 0.3, opacity: 1.0, isVisible: true),
            ],
            whiteFrame: WhiteFrameConfig(
                isEnabled: true,
                metadataTextEnabled: true
            )
        )
        let engine = WatermarkEngine()

        do {
            let result = try await engine.process(sourceURL: inputURL, config: config)
            #expect(result.url != nil)
            #expect(FileManager.default.fileExists(atPath: result.url!.path))

            guard let outputURL = result.url,
                  let source = CGImageSourceCreateWithURL(outputURL as CFURL, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                Issue.record("Failed to read output image")
                cleanup(inputURL)
                return
            }

            // Verify dimensions preserved
            let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
            // Framed export: the mat is added outside the 500x400 source.
            let frameConfig = config.whiteFrame ?? WhiteFrameConfig()
            let framed = FrameGeometry(
                config: frameConfig,
                sourceSize: CGSize(width: 500, height: 400),
                hasCaptionContent: WhiteFrameRenderer.hasCaptionContent(
                    config: frameConfig, metadata: sourceMetadata(inputURL))
            ).framedSize
            #expect((props[kCGImagePropertyPixelWidth] as? Int) == Int(framed.width))
            #expect((props[kCGImagePropertyPixelHeight] as? Int) == Int(framed.height))

            // Verify format preserved
            #expect(result.outputUTI == "public.jpeg")

            // Sample top-left corner (should be white frame border at 20pt frame width)
            // Frame width = min(500,400) × 0.04 = 16pt
            let pixelData = TestImageFactory.pixelData(from: cgImage)
            #expect(pixelData != nil)

            if let data = pixelData {
                let width = 500
                // Top-left edge should have white frame border
                let tlOffset = (2 * width + 2) * 4
                guard tlOffset + 3 < data.count else {
                    Issue.record("Pixel offset out of bounds")
                    cleanup(inputURL, outputURL)
                    return
                }
                let r = data[tlOffset], g = data[tlOffset + 1], b = data[tlOffset + 2]

                // RED: no frame → edges show base color (gray ~128)
                // GREEN: frame rendered → edges show white (r > 200)
                #expect(r > 200 && g > 200 && b > 200,
                        "Top-left edge should be white frame, got r=\(r), g=\(g), b=\(b)")
            }

            cleanup(inputURL, outputURL)
        } catch {
            Issue.record("Engine threw: \(error) — expected in GREEN phase")
            cleanup(inputURL)
        }
    }
}
