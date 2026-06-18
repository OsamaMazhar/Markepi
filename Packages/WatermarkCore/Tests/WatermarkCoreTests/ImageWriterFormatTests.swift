import Testing
import ImageIO
import CoreImage
import Foundation
@testable import WatermarkCore

/// Tests ImageWriter with destination UTI and quality parameters,
/// and WatermarkEngine format resolution from config.
@Suite("ImageWriterFormat")
struct ImageWriterFormatTests {

    // MARK: - ImageWriter: destinationUTI parameter

    @Test("ImageWriter.write(data) uses destinationUTI to produce correct format")
    func dataOverloadRespectsDestinationUTI() throws {
        let (cgImage, _) = TestImageFactory.solidColorImage(
            color: CGColor(red: 1, green: 0, blue: 0, alpha: 1),
            size: CGSize(width: 100, height: 100)
        )
        // Write as PNG with destinationUTI, even though source was JPEG
        let outputData = try ImageWriter.write(
            cgImage: cgImage,
            metadata: [:],
            gainMapAuxData: nil,
            dngMetadata: nil,
            destinationUTI: "public.png",
            quality: 1.0
        )
        #expect(!outputData.isEmpty)

        // Verify output is actually PNG
        guard let source = CGImageSourceCreateWithData(outputData as CFData, nil) else {
            Issue.record("Failed to create CGImageSource from output")
            return
        }
        let uti = CGImageSourceGetType(source) as String?
        #expect(uti == "public.png", "Expected PNG output, got \(uti ?? "nil")")
    }

    @Test("ImageWriter.write(file) uses destinationUTI to produce correct format")
    func fileOverloadRespectsDestinationUTI() throws {
        let (cgImage, _) = TestImageFactory.solidColorImage(
            color: CGColor(red: 0, green: 1, blue: 0, alpha: 1),
            size: CGSize(width: 100, height: 100)
        )
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_dest_\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try ImageWriter.write(
            cgImage: cgImage,
            metadata: [:],
            gainMapAuxData: nil,
            dngMetadata: nil,
            destinationUTI: "public.png",
            quality: 1.0,
            to: tempURL
        )
        #expect(FileManager.default.fileExists(atPath: tempURL.path))

        // Verify output is PNG by reading back
        guard let source = CGImageSourceCreateWithURL(tempURL as CFURL, nil) else {
            Issue.record("Failed to create CGImageSource from file")
            return
        }
        let uti = CGImageSourceGetType(source) as String?
        #expect(uti == "public.png", "Expected PNG output, got \(uti ?? "nil")")
    }

    // MARK: - ImageWriter: quality parameter

    @Test("ImageWriter with quality 0.85 writes JPEG successfully")
    func qualityAppliedToJPEG() throws {
        let (cgImage, _) = TestImageFactory.solidColorImage(
            color: CGColor(red: 0, green: 0, blue: 1, alpha: 1),
            size: CGSize(width: 100, height: 100)
        )
        let outputData = try ImageWriter.write(
            cgImage: cgImage,
            metadata: [:],
            gainMapAuxData: nil,
            dngMetadata: nil,
            destinationUTI: "public.jpeg",
            quality: 0.85
        )
        #expect(!outputData.isEmpty)
        #expect(outputData.count > 0)
    }

    @Test("ImageWriter with PNG destinationUTI and low quality still produces valid output")
    func pngWithQualityStillWorks() throws {
        let (cgImage, _) = TestImageFactory.solidColorImage(
            color: CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1),
            size: CGSize(width: 100, height: 100)
        )
        // PNG is lossless — quality value is ignored by encoder, but write should succeed
        let outputData = try ImageWriter.write(
            cgImage: cgImage,
            metadata: [:],
            gainMapAuxData: nil,
            dngMetadata: nil,
            destinationUTI: "public.png",
            quality: 0.5
        )
        #expect(!outputData.isEmpty, "PNG output with quality should still write successfully")

        // Verify output is PNG
        guard let source = CGImageSourceCreateWithData(outputData as CFData, nil) else {
            Issue.record("Failed to read back PNG output")
            return
        }
        let uti = CGImageSourceGetType(source) as String?
        #expect(uti == "public.png")
    }

    @Test("ImageWriter with TIFF destinationUTI produces valid TIFF output")
    func tiffDestinationUTIProducesTIFF() throws {
        let (cgImage, _) = TestImageFactory.solidColorImage(
            color: CGColor(red: 0, green: 1, blue: 0, alpha: 1),
            size: CGSize(width: 100, height: 100)
        )
        let outputData = try ImageWriter.write(
            cgImage: cgImage,
            metadata: [:],
            gainMapAuxData: nil,
            dngMetadata: nil,
            destinationUTI: "public.tiff",
            quality: 1.0
        )
        #expect(!outputData.isEmpty)

        // Verify output is TIFF
        guard let source = CGImageSourceCreateWithData(outputData as CFData, nil) else {
            Issue.record("Failed to read back TIFF output")
            return
        }
        let uti = CGImageSourceGetType(source) as String?
        #expect(uti == "public.tiff", "Expected TIFF output, got \(uti ?? "nil")")
    }

    // MARK: - Engine: format resolution from config

    @Test("Engine with .preserveSource keeps source UTI as output UTI")
    func enginePreserveSourceKeepsSourceUTI() async throws {
        let (_, jpegData) = TestImageFactory.solidColorImage(
            color: CGColor(red: 0, green: 0, blue: 1, alpha: 1),
            size: CGSize(width: 200, height: 200)
        )
        let inputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_preserve_\(UUID().uuidString).jpg")
        try jpegData.write(to: inputURL)
        defer { try? FileManager.default.removeItem(at: inputURL) }

        let config = WatermarkConfiguration(outputFormat: .preserveSource)
        let engine = WatermarkEngine()

        let result = try await engine.process(sourceURL: inputURL, config: config)
        #expect(result.url != nil)
        #expect(result.outputUTI == "public.jpeg", "Expected source UTI preserved, got \(result.outputUTI)")
        if let url = result.url {
            #expect(url.pathExtension == "jpg", "Expected .jpg extension, got .\(url.pathExtension)")
            try? FileManager.default.removeItem(at: url)
        }
    }

    @Test("Engine with .jpeg format override produces JPEG output regardless of source")
    func engineJpegOverrideProducesJPEG() async throws {
        let (_, jpegData) = TestImageFactory.solidColorImage(
            color: CGColor(red: 1, green: 0, blue: 0, alpha: 1),
            size: CGSize(width: 200, height: 200)
        )
        let inputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_jpeg_override_\(UUID().uuidString).jpg")
        try jpegData.write(to: inputURL)
        defer { try? FileManager.default.removeItem(at: inputURL) }

        let config = WatermarkConfiguration(outputFormat: .jpeg)
        let engine = WatermarkEngine()

        let result = try await engine.process(sourceURL: inputURL, config: config)
        #expect(result.url != nil)
        #expect(result.outputUTI == "public.jpeg", "Expected JPEG output UTI, got \(result.outputUTI)")
        if let url = result.url {
            #expect(url.pathExtension == "jpg", "Expected .jpg extension, got .\(url.pathExtension)")
            try? FileManager.default.removeItem(at: url)
        }
    }

    @Test("Engine with .tiff format override produces TIFF output")
    func engineTiffOverrideProducesTIFF() async throws {
        let (_, jpegData) = TestImageFactory.solidColorImage(
            color: CGColor(red: 0, green: 1, blue: 0, alpha: 1),
            size: CGSize(width: 200, height: 200)
        )
        let inputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_tiff_override_\(UUID().uuidString).jpg")
        try jpegData.write(to: inputURL)
        defer { try? FileManager.default.removeItem(at: inputURL) }

        let config = WatermarkConfiguration(outputFormat: .tiff)
        let engine = WatermarkEngine()

        let result = try await engine.process(sourceURL: inputURL, config: config)
        #expect(result.url != nil)
        #expect(result.outputUTI == "public.tiff", "Expected TIFF output UTI, got \(result.outputUTI)")
        if let url = result.url {
            #expect(url.pathExtension == "tiff", "Expected .tiff extension, got .\(url.pathExtension)")
            try? FileManager.default.removeItem(at: url)
        }
    }

    @Test("ProcessingResult.outputUTI reflects config format override, not source format")
    func processingResultReflectsOverride() async throws {
        let (_, jpegData) = TestImageFactory.solidColorImage(
            color: CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1),
            size: CGSize(width: 200, height: 200)
        )
        let inputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_output_uti_\(UUID().uuidString).jpg")
        try jpegData.write(to: inputURL)
        defer { try? FileManager.default.removeItem(at: inputURL) }

        // Source is JPEG, but config says PNG
        let config = WatermarkConfiguration(outputFormat: .png)
        let engine = WatermarkEngine()

        let result = try await engine.process(sourceURL: inputURL, config: config)
        #expect(result.outputUTI == "public.png",
                "ProcessingResult.outputUTI should be public.png, got \(result.outputUTI)")
        if let url = result.url {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
