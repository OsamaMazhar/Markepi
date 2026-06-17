import Testing
import ImageIO
import CoreImage
import Foundation
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
}
