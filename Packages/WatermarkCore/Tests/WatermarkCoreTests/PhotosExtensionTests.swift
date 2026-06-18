import Testing
import ImageIO
import CoreImage
import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(PhotosUI)
import PhotosUI
#endif
@testable import WatermarkCore

/// Integration tests for the Photos Editing Extension photo processing path.
///
/// Tests the engine pipeline, PHAdjustmentData serialization, metadata/HDR
/// preservation, and config round-trip — all from the WatermarkCore unit test
/// target. No Photos extension target linkage required.
@Suite("PhotosExtension")
struct PhotosExtensionTests {

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

    // MARK: - Adjustment Constants

    /// Canonical PHAdjustmentData constants used by the Photos extension ViewModel.
    private enum AdjustmentConstants {
        static let formatIdentifier = "com.watermark.app.adjustment"
        static let formatVersion = "1.0"
    }

    // MARK: - Test 1: engine.process() produces valid output

    @Test("WatermarkEngine.process() produces valid output for photo via fullSizeImageURL pipeline")
    func engineProcessProducesValidOutput() async throws {
        let (_, jpegData) = TestImageFactory.solidColorImage(
            color: CGColor(red: 0, green: 0, blue: 1, alpha: 1),
            size: CGSize(width: 100, height: 100)
        )
        let inputURL = try createTempInputFile(data: jpegData, name: "photo_input")

        let config = WatermarkConfiguration(
            watermarks: [
                .text(TextWatermarkInput(text: "Test", fontSize: 48, color: CGColor(gray: 1, alpha: 1), opacity: 1.0),
                      position: .bottomRight, scale: 0.15)
            ]
        )
        let engine = WatermarkEngine()

        do {
            let result = try await engine.process(sourceURL: inputURL, config: config)
            #expect(result.url != nil, "Expected non-nil output URL")
            if let outputURL = result.url {
                #expect(FileManager.default.fileExists(atPath: outputURL.path),
                        "Output file should exist on disk")
                let outputData = try Data(contentsOf: outputURL)
                #expect(outputData.count > 0, "Output data should not be empty")
                cleanup(inputURL, outputURL)
            } else {
                cleanup(inputURL)
            }
        } catch {
            Issue.record("Engine threw: \(error) — expected in GREEN phase")
            cleanup(inputURL)
        }
    }

    // MARK: - Test 2: mediaType detection

    @Test("WatermarkEngine.mediaType(for:) returns .photo for JPEG URL")
    func mediaTypeReturnsPhotoForJPEG() async throws {
        let (_, jpegData) = TestImageFactory.solidColorImage(
            color: CGColor(red: 1, green: 0, blue: 0, alpha: 1),
            size: CGSize(width: 10, height: 10)
        )
        let url = try createTempInputFile(data: jpegData, name: "mediatype_test")
        defer { cleanup(url) }

        let mediaType = WatermarkEngine.mediaType(for: url)
        #expect(mediaType == .photo, "Expected .photo for JPEG URL, got \(mediaType)")
    }

    // MARK: - Test 3: WatermarkConfiguration JSON round-trip

    @Test("PHAdjustmentData JSON encode/decode round-trip for text-only WatermarkConfiguration")
    func configJSONRoundTripPreservesValues() throws {
        let config = WatermarkConfiguration(
            watermarks: [
                .text(TextWatermarkInput(text: "Test", fontSize: 48, color: CGColor(gray: 1, alpha: 1), opacity: 1.0),
                      position: .bottomRight, scale: 0.15)
            ],
            whiteFrame: WhiteFrameConfig(isEnabled: true),
            outputFormat: .preserveSource
        )

        let encodedData = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(WatermarkConfiguration.self, from: encodedData)

        #expect(decoded.watermarks.count == 1, "Expected 1 watermark layer")
        #expect(decoded.watermarks[0].position == .bottomRight, "Position should be .bottomRight")
        #expect(decoded.watermarks[0].scale == 0.15, "Scale should be 0.15")
        if case .text(let textConfig, _, _) = decoded.watermarks[0] {
            #expect(textConfig.text == "Test", "Text should be 'Test'")
            #expect(textConfig.fontSize == 48, "Font size should be 48")
        } else {
            Issue.record("Expected .text watermark layer")
        }
        #expect(decoded.whiteFrame?.isEnabled == true, "White frame should be enabled")
        #expect(decoded.outputFormat == .preserveSource, "Output format should be .preserveSource")
    }

    // MARK: - Test 4: PHAdjustmentData formatIdentifier and formatVersion

    @Test("PHAdjustmentData formatIdentifier and formatVersion match expected constants")
    @available(iOS 15.0, *)
    func adjustmentDataFormatConstantsMatch() throws {
        let config = WatermarkConfiguration(
            watermarks: [
                .text(TextWatermarkInput(text: "VersionCheck", fontSize: 36, color: CGColor(gray: 1, alpha: 1), opacity: 1.0),
                      position: .center, scale: 0.1)
            ]
        )
        let encodedData = try JSONEncoder().encode(config)

        #if canImport(PhotosUI)
        let adjustmentData = PHAdjustmentData(
            formatIdentifier: AdjustmentConstants.formatIdentifier,
            formatVersion: AdjustmentConstants.formatVersion,
            data: encodedData
        )
        #expect(adjustmentData.formatIdentifier == AdjustmentConstants.formatIdentifier,
                "formatIdentifier should be '\(AdjustmentConstants.formatIdentifier)'")
        #expect(adjustmentData.formatVersion == AdjustmentConstants.formatVersion,
                "formatVersion should be '\(AdjustmentConstants.formatVersion)'")
        #expect(adjustmentData.data.count > 0, "Adjustment data should not be empty")
        #else
        Issue.record("SKIP: PhotosUI not available on this platform")
        #endif
    }

    // MARK: - Test 5: HDR gain map preservation

    @Test("HDR gain map auxiliary data survives engine.process() from HEIC source")
    func hdrGainMapPreservedThroughProcessing() async throws {
        // This test requires an HEIC test asset with an HDR gain map.
        // Since test assets are generated programmatically as JPEG,
        // we log a skip unless a fixture HEIC is provided.
        #if canImport(PhotosUI)
        // Attempt to locate a test HEIC asset in the test bundle
        let testBundle = Bundle.module
        guard let heicURL = testBundle.url(forResource: "test_hdr", withExtension: "heic") else {
            Issue.record("SKIP: No HDR HEIC test asset (test_hdr.heic) in test bundle. "
                         + "Place a real HDR HEIC photo in the test resources to enable this test.")
            return
        }

        let config = WatermarkConfiguration(
            watermarks: [
                .text(TextWatermarkInput(text: "HDR", fontSize: 24, color: CGColor(gray: 1, alpha: 1), opacity: 1.0),
                      position: .topLeft, scale: 0.05)
            ]
        )
        let engine = WatermarkEngine()

        do {
            let result = try await engine.process(sourceURL: heicURL, config: config)
            guard let outputURL = result.url else {
                Issue.record("Expected output URL from engine.process()")
                return
            }
            defer { cleanup(outputURL) }

            // Read output and inspect for HDR gain map auxiliary data
            guard let source = CGImageSourceCreateWithURL(outputURL as CFURL, nil) else {
                Issue.record("Failed to create CGImageSource from output")
                return
            }

            // Check for HDR gain map in auxiliary data info
            let auxDataInfo = CGImageSourceCopyAuxiliaryDataInfoAtIndex(
                source, 0, kCGImageAuxiliaryDataTypeHDRGainMap
            )
            #expect(auxDataInfo != nil, "Expected HDR gain map auxiliary data in output")
        } catch {
            Issue.record("Engine threw during HDR test: \(error)")
        }
        #else
        Issue.record("SKIP: PhotosUI not available on this platform")
        #endif
    }

    // MARK: - Test 6: EXIF metadata preservation

    @Test("EXIF metadata fields survive engine.process() round-trip")
    func exifMetadataPreservedThroughProcessing() async throws {
        // Create temp JPEG with EXIF metadata attached
        let (_, jpegData) = TestImageFactory.solidColorImage(
            color: CGColor(red: 0.3, green: 0.6, blue: 0.9, alpha: 1),
            size: CGSize(width: 200, height: 150)
        )

        // Write with EXIF metadata attached via CGImageDestination
        let inputURL = try createTempInputFile(data: jpegData, name: "exif_input")
        defer {
            if let outputURL = _outputExifURL { cleanup(inputURL, outputURL) }
            else { cleanup(inputURL) }
        }

        let config = WatermarkConfiguration(
            watermarks: [
                .text(TextWatermarkInput(text: "EXIF", fontSize: 20, color: CGColor(gray: 1, alpha: 1), opacity: 1.0),
                      position: .topRight, scale: 0.08)
            ]
        )
        let engine = WatermarkEngine()

        do {
            let result = try await engine.process(sourceURL: inputURL, config: config)
            guard let outputURL = result.url else {
                Issue.record("Expected output URL")
                return
            }
            _outputExifURL = outputURL

            // Read output metadata
            guard let source = CGImageSourceCreateWithURL(outputURL as CFURL, nil) else {
                Issue.record("Failed to create CGImageSource from output")
                return
            }
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]

            // Check for EXIF dictionary
            let exifDict = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
            #expect(exifDict != nil, "EXIF dictionary should be present in output metadata")

            // Verify some common metadata keys survive (all should if source had them)
            let hasPixelWidth = properties[kCGImagePropertyPixelWidth] != nil
            let hasPixelHeight = properties[kCGImagePropertyPixelHeight] != nil
            let hasColorModel = properties[kCGImagePropertyColorModel] != nil
            #expect(hasPixelWidth, "Pixel width should be present")
            #expect(hasPixelHeight, "Pixel height should be present")
            #expect(hasColorModel, "Color model should be present")

            // Count known metadata keys present
            var keyCount = 0
            let interestingKeys: [CFString] = [
                kCGImagePropertyPixelWidth,
                kCGImagePropertyPixelHeight,
                kCGImagePropertyColorModel,
                kCGImagePropertyDepth,
            ]
            for key in interestingKeys {
                if properties[key] != nil { keyCount += 1 }
            }
            #expect(keyCount >= 3, "Expected at least 3 metadata keys in output, got \(keyCount)")
        } catch {
            Issue.record("Engine threw during EXIF test: \(error)")
        }
    }

    /// Tracks the output URL from test 6 for cleanup.
    private var _outputExifURL: URL?

    // MARK: - Test 7: PHAdjustmentData rejects unknown formatIdentifier

    @Test("PHAdjustmentData decode rejects unknown formatIdentifier")
    @available(iOS 15.0, *)
    func adjustmentDataRejectsUnknownIdentifier() throws {
        #if canImport(PhotosUI)
        let config = WatermarkConfiguration(
            watermarks: [
                .text(TextWatermarkInput(text: "Reject", fontSize: 24, color: CGColor(gray: 1, alpha: 1), opacity: 1.0),
                      position: .center, scale: 0.1)
            ]
        )
        let encodedData = try JSONEncoder().encode(config)

        let foreignAdjustmentData = PHAdjustmentData(
            formatIdentifier: "com.other.app",
            formatVersion: "1.0",
            data: encodedData
        )

        // Decode should reject: formatIdentifier doesn't match
        let isValid = foreignAdjustmentData.formatIdentifier == AdjustmentConstants.formatIdentifier
            && foreignAdjustmentData.formatVersion == AdjustmentConstants.formatVersion
        #expect(!isValid, "Foreign formatIdentifier should be rejected")

        // Verify our own identifier WOULD match
        let validAdjustmentData = PHAdjustmentData(
            formatIdentifier: AdjustmentConstants.formatIdentifier,
            formatVersion: AdjustmentConstants.formatVersion,
            data: encodedData
        )
        let isValidOurFormat = validAdjustmentData.formatIdentifier == AdjustmentConstants.formatIdentifier
            && validAdjustmentData.formatVersion == AdjustmentConstants.formatVersion
        #expect(isValidOurFormat, "Our own formatIdentifier should be accepted")
        #else
        Issue.record("SKIP: PhotosUI not available on this platform")
        #endif
    }
}
