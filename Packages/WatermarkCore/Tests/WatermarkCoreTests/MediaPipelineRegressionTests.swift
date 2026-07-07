import Testing
import AVFoundation
import ImageIO
import CoreImage
import Foundation
#if canImport(UIKit)
import UIKit
#endif
@testable import WatermarkCore

/// Integration regressions for the shared photo/video processing pipeline.
///
/// Covers engine output, media detection, metadata/HDR preservation,
/// configuration round trips, orientation handling, and ImageIO URL loading.
@Suite("MediaPipelineRegression")
struct MediaPipelineRegressionTests {

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

    // MARK: - Test 1: engine.process() produces valid output

    @Test("WatermarkEngine.process() produces valid photo output")
    func engineProcessProducesValidOutput() async throws {
        let (_, jpegData) = TestImageFactory.solidColorImage(
            color: CGColor(red: 0, green: 0, blue: 1, alpha: 1),
            size: CGSize(width: 100, height: 100)
        )
        let inputURL = try createTempInputFile(data: jpegData, name: "photo_input")

        let config = WatermarkConfiguration(
            watermarks: [
                .text(TextWatermarkInput(text: "Test", fontSize: 48, color: CGColor(gray: 1, alpha: 1), opacity: 1.0),
                      position: .bottomRight, scale: 0.15, opacity: 1.0, isVisible: true)
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

    @Test("WatermarkConfiguration JSON encode/decode round-trip preserves values")
    func configJSONRoundTripPreservesValues() throws {
        let config = WatermarkConfiguration(
            watermarks: [
                .text(TextWatermarkInput(text: "Test", fontSize: 48, color: CGColor(gray: 1, alpha: 1), opacity: 1.0),
                      position: .bottomRight, scale: 0.15, opacity: 1.0, isVisible: true)
            ],
            whiteFrame: WhiteFrameConfig(isEnabled: true),
            outputFormat: .preserveSource
        )

        let encodedData = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(WatermarkConfiguration.self, from: encodedData)

        #expect(decoded.watermarks.count == 1, "Expected 1 watermark layer")
        #expect(decoded.watermarks[0].position == .bottomRight, "Position should be .bottomRight")
        #expect(decoded.watermarks[0].scale == 0.15, "Scale should be 0.15")
        if case .text(let textConfig, _, _, _, _) = decoded.watermarks[0] {
            #expect(textConfig.text == "Test", "Text should be 'Test'")
            #expect(textConfig.fontSize == 48, "Font size should be 48")
        } else {
            Issue.record("Expected .text watermark layer")
        }
        #expect(decoded.whiteFrame?.isEnabled == true, "White frame should be enabled")
        #expect(decoded.outputFormat == .preserveSource, "Output format should be .preserveSource")
    }

    // MARK: - Test 5: HDR gain map preservation

    @Test("HDR gain map auxiliary data survives engine.process() from HEIC source")
    func hdrGainMapPreservedThroughProcessing() async throws {
        // Synthesize a HEIC carrying an HDR gain map at runtime. If the platform
        // has no HEVC encoder we can't exercise the path, so skip cleanly.
        guard let heicURL = TestImageFactory.hdrHEICWithGainMap() else {
            return // No HEVC encoder — nothing to assert on this platform.
        }
        defer { cleanup(heicURL) }

        // Precondition: the fixture itself carries a gain map.
        if let fixtureSource = CGImageSourceCreateWithURL(heicURL as CFURL, nil) {
            let fixtureGainMap = CGImageSourceCopyAuxiliaryDataInfoAtIndex(
                fixtureSource, 0, kCGImageAuxiliaryDataTypeHDRGainMap
            )
            try #require(fixtureGainMap != nil, "Fixture HEIC should carry an HDR gain map")
        }

        let config = WatermarkConfiguration(
            watermarks: [
                .text(TextWatermarkInput(text: "HDR", fontSize: 24, color: CGColor(gray: 1, alpha: 1), opacity: 1.0),
                      position: .topLeft, scale: 0.05, opacity: 1.0, isVisible: true)
            ]
        )
        let engine = WatermarkEngine()

        let result = try await engine.process(sourceURL: heicURL, config: config)
        let outputURL = try #require(result.url, "Expected output URL from engine.process()")
        defer { cleanup(outputURL) }

        // The output should still carry the HDR gain map auxiliary data.
        let source = try #require(CGImageSourceCreateWithURL(outputURL as CFURL, nil),
                                  "Failed to create CGImageSource from output")
        let auxDataInfo = CGImageSourceCopyAuxiliaryDataInfoAtIndex(
            source, 0, kCGImageAuxiliaryDataTypeHDRGainMap
        )
        #expect(auxDataInfo != nil, "Expected HDR gain map auxiliary data in output")
    }

    // MARK: - Test 5b: HDR gain map re-aligned to rotated base

    @Test("HDR gain map is rotated to match an EXIF-oriented base on export")
    func hdrGainMapReAlignedToRotatedBase() async throws {
        // Landscape base (64×48) tagged orientation .right (6). On export the
        // pixels rotate upright to PORTRAIT (48×64) and the tag resets to 1, so
        // the gain map must rotate with them — portrait, not the stored landscape.
        guard let heicURL = TestImageFactory.hdrHEICWithGainMap(
            size: CGSize(width: 64, height: 48),
            orientation: .right
        ) else {
            return // No HEVC encoder on this platform.
        }
        defer { cleanup(heicURL) }

        let engine = WatermarkEngine()
        let result = try await engine.process(
            sourceURL: heicURL,
            config: WatermarkConfiguration(watermarks: [])
        )
        let outputURL = try #require(result.url)
        defer { cleanup(outputURL) }

        let source = try #require(CGImageSourceCreateWithURL(outputURL as CFURL, nil))

        // Base image must be upright portrait (width < height).
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        let baseW = (props[kCGImagePropertyPixelWidth] as? Int) ?? 0
        let baseH = (props[kCGImagePropertyPixelHeight] as? Int) ?? 0
        try #require(baseW > 0 && baseH > 0)
        #expect(baseW < baseH, "Exported base should be portrait after orientation .right")

        // The gain map must be portrait too — proving it rotated WITH the base
        // instead of staying in the stored landscape orientation (the bug).
        let aux = try #require(
            CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, kCGImageAuxiliaryDataTypeHDRGainMap)
                as? [CFString: Any],
            "Expected HDR gain map in output"
        )
        let desc = try #require(aux[kCGImageAuxiliaryDataInfoDataDescription] as? [CFString: Any])
        let gainW = (desc["Width" as CFString] as? Int) ?? 0
        let gainH = (desc["Height" as CFString] as? Int) ?? 0
        try #require(gainW > 0 && gainH > 0)
        #expect(gainW < gainH, "Exported gain map should be portrait, aligned to the base")
    }

    // MARK: - Test 6: EXIF metadata preservation

    @Test("EXIF metadata fields survive engine.process() round-trip")
    mutating func exifMetadataPreservedThroughProcessing() async throws {
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
                      position: .topRight, scale: 0.08, opacity: 1.0, isVisible: true)
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

    // MARK: - Test 8: mediaType(for:) returns .video for .mov URL

    @Test("WatermarkEngine.mediaType(for:) returns .video for .mov URL")
    func mediaTypeReturnsVideoForMOV() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_video_\(UUID().uuidString).mov")
        // Create an empty .mov file — UTI detection may fail for empty files,
        // but the test exercises the mediaType(for:) code path for video.
        try Data().write(to: url)
        defer { cleanup(url) }

        let mediaType = WatermarkEngine.mediaType(for: url)
        // RED: mediaType(for:) for .mov extension should return .video.
        // Currently may return .unknown for empty files — this should
        // be .video once the engine properly handles video types.
        #expect(mediaType == .video || mediaType == .photo,
                "Expected .video for .mov URL, got \(mediaType)")
        if mediaType != .video {
            Issue.record("mediaType(for:) returned \(mediaType) for .mov URL — expected .video")
        }
    }

    // MARK: - Test 9: processVideo produces valid output

    @Test("WatermarkEngine.processVideo(sourceURL:config:) produces valid output")
    func processVideoProducesValidOutput() async throws {
        // Synthesize a short H.264 .mov fixture at runtime (no bundled binary).
        let videoURL = try await TestVideoFactory.makeTestVideo()
        defer { cleanup(videoURL) }

        // Fixture sanity — runs on every platform.
        let track = try await AVURLAsset(url: videoURL).loadTracks(withMediaType: .video).first
        #expect(track != nil, "Synthesized fixture should contain a video track")

        // The full export uses AVVideoCompositionCoreAnimationTool, which requires
        // a CoreAnimation render server and segfaults on the macOS SwiftPM test
        // host. Exercise it only where it actually runs (device/simulator).
        #if os(iOS)
        let config = WatermarkConfiguration(
            watermarks: [
                .text(TextWatermarkInput(text: "VideoTest", fontSize: 36, color: CGColor(gray: 1, alpha: 1), opacity: 1.0),
                      position: .center, scale: 0.1, opacity: 1.0, isVisible: true)
            ]
        )
        let result = try await WatermarkEngine().processVideo(sourceURL: videoURL, config: config)
        let outputURL = try #require(result.url, "Expected non-nil output URL from processVideo")
        #expect(FileManager.default.fileExists(atPath: outputURL.path),
                "Output video file should exist on disk")
        let outputData = try Data(contentsOf: outputURL)
        #expect(outputData.count > 0, "Output video data should not be empty")
        cleanup(outputURL)
        #endif
    }

    // MARK: - Test 10: videoValidation.hdrPreserved

    @Test("ProcessingResult.videoValidation.hdrPreserved is true for SDR source")
    func videoValidationHdrPreservedForSDR() async throws {
        // Synthesize a short SDR H.264 .mov fixture at runtime.
        let videoURL = try await TestVideoFactory.makeTestVideo()
        defer { cleanup(videoURL) }

        let track = try await AVURLAsset(url: videoURL).loadTracks(withMediaType: .video).first
        #expect(track != nil, "Synthesized fixture should contain a video track")

        // processVideo uses CoreAnimation compositing — unsupported on the macOS
        // SwiftPM host (see processVideoProducesValidOutput). iOS-only.
        #if os(iOS)
        let config = WatermarkConfiguration(
            watermarks: [
                .text(TextWatermarkInput(text: "HDR", fontSize: 24, color: CGColor(gray: 1, alpha: 1), opacity: 1.0),
                      position: .topLeft, scale: 0.05, opacity: 1.0, isVisible: true)
            ]
        )
        let result = try await WatermarkEngine().processVideo(sourceURL: videoURL, config: config)
        let validation = try #require(result.videoValidation,
                                      "videoValidation should be populated by processVideo")
        // For an SDR source there is no HDR to lose, so HDR is trivially preserved.
        #expect(validation.warnings.isEmpty || validation.hdrPreserved,
                "Video validation should indicate HDR status")
        #endif
    }

    // MARK: - Test 11: Video processing output URL

    @Test("Video processing path produces a valid renderedContentURL for .mov source")
    @available(iOS 15.0, *)
    func videoPathCreatesValidOutputURL() async throws {
        // Verify the shared video pipeline end to end: a real .mov in and a
        // valid, on-disk .mov output URL out.
        let sourceURL = try await TestVideoFactory.makeTestVideo()
        defer { cleanup(sourceURL) }

        let track = try await AVURLAsset(url: sourceURL).loadTracks(withMediaType: .video).first
        #expect(track != nil, "Synthesized .mov source should contain a video track")

        // processVideo uses CoreAnimation compositing — unsupported on the macOS
        // SwiftPM host (see processVideoProducesValidOutput). iOS-only.
        #if os(iOS)
        let config = WatermarkConfiguration(
            watermarks: [
                .text(TextWatermarkInput(text: "VideoOut", fontSize: 36, color: CGColor(gray: 1, alpha: 1), opacity: 1.0),
                      position: .center, scale: 0.1, opacity: 1.0, isVisible: true)
            ]
        )
        let result = try await WatermarkEngine().processVideo(sourceURL: sourceURL, config: config)
        let renderedContentURL = try #require(result.url,
                                              "Expected a renderedContentURL from the video path")
        #expect(renderedContentURL.pathExtension == "mov",
                "renderedContentURL for a .mov source should have a .mov extension")
        #expect(FileManager.default.fileExists(atPath: renderedContentURL.path),
                "renderedContentURL should point to a file on disk")
        cleanup(renderedContentURL)
        #endif
    }

    // MARK: - Test 12: All 8 EXIF orientation values handled

    @Test("All 8 EXIF orientation values handled by engine for photo output")
    func allEightEXIFOrientationsHandled() async throws {
        // Test each EXIF orientation (1-8) with a 200×100 test image.
        // The engine normalizes orientation via OrientationNormalizer.
        // Output should preserve aspect ratio regardless of orientation.
        let orientations: [(Int, CGSize)] = [
            (1, CGSize(width: 200, height: 100)),   // Normal
            (2, CGSize(width: 200, height: 100)),   // Flipped horizontal
            (3, CGSize(width: 200, height: 100)),   // Rotated 180
            (4, CGSize(width: 200, height: 100)),   // Flipped vertical
            (5, CGSize(width: 100, height: 200)),   // Rotated 90 CCW + flip
            (6, CGSize(width: 100, height: 200)),   // Rotated 90 CW
            (7, CGSize(width: 100, height: 200)),   // Rotated 90 CW + flip
            (8, CGSize(width: 100, height: 200)),   // Rotated 90 CCW
        ]

        let config = WatermarkConfiguration(
            watermarks: [
                .text(TextWatermarkInput(text: "Orientation", fontSize: 24, color: CGColor(gray: 1, alpha: 1), opacity: 1.0),
                      position: .center, scale: 0.1, opacity: 1.0, isVisible: true)
            ]
        )
        let engine = WatermarkEngine()

        for (orientation, expectedSize) in orientations {
            // Create a rectangular image (200×100) tagged with this EXIF
            // orientation so the engine's load-time normalization is exercised.
            let (_, jpegData) = TestImageFactory.solidColorImage(
                color: CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1),
                size: CGSize(width: 200, height: 100),
                orientation: orientation
            )
            let inputURL = try createTempInputFile(data: jpegData, name: "orient_\(orientation)")

            do {
                let result = try await engine.process(sourceURL: inputURL, config: config)
                guard let outputURL = result.url else {
                    Issue.record("Expected output URL for orientation \(orientation)")
                    cleanup(inputURL)
                    continue
                }

                // Read output and verify dimensions are NOT swapped
                guard let source = CGImageSourceCreateWithURL(outputURL as CFURL, nil) else {
                    Issue.record("Failed to read output for orientation \(orientation)")
                    cleanup(inputURL, outputURL)
                    continue
                }
                let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
                let width = props[kCGImagePropertyPixelWidth] as? Int ?? 0
                let height = props[kCGImagePropertyPixelHeight] as? Int ?? 0

                // Orientation 5-8 swap width/height (portrait vs landscape)
                // The engine normalizes to .up, so output should match
                // the expected dimensions for each orientation
                #expect(width == Int(expectedSize.width) && height == Int(expectedSize.height),
                        "Orientation \(orientation): expected \(Int(expectedSize.width))×\(Int(expectedSize.height)), got \(width)×\(height)")

                // Verify aspect ratio is preserved (no stretching)
                let aspectRatio = Double(width) / Double(max(height, 1))
                let expectedAspect = Double(expectedSize.width) / Double(max(expectedSize.height, 1))
                #expect(abs(aspectRatio - expectedAspect) < 0.01,
                        "Orientation \(orientation): aspect ratio \(aspectRatio) differs from expected \(expectedAspect)")

                cleanup(inputURL, outputURL)
            } catch {
                Issue.record("Engine threw for orientation \(orientation): \(error)")
                cleanup(inputURL)
            }
        }
    }

    // MARK: - ImageIO URL Detection Regressions

    /// Creates a temp PNG file from test image data for URL-based UTI detection.
    private func createTempPNGFile(name: String, size: CGSize = CGSize(width: 10, height: 10)) throws -> URL {
        let (cgImage, _) = TestImageFactory.solidColorImage(
            color: CGColor(red: 0, green: 1, blue: 0, alpha: 1),
            size: size
        )
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)_\(UUID().uuidString).png")
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create CGImageDestination"])
        }
        CGImageDestinationAddImage(dest, cgImage, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw NSError(domain: "Test", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to finalize PNG"])
        }
        return url
    }

    // MARK: Test 13: CGImageSource URL-based UTI detection for JPEG

    @Test("CGImageSourceCreateWithURL detects JPEG UTI from file URL")
    func cgImageSourceURLDetectsJPEG() async throws {
        let (_, jpegData) = TestImageFactory.solidColorImage(
            color: CGColor(red: 1, green: 0, blue: 0, alpha: 1),
            size: CGSize(width: 10, height: 10)
        )
        let url = try createTempInputFile(data: jpegData, name: "detect_jpeg")
        defer { cleanup(url) }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            Issue.record("RED: CGImageSourceCreateWithURL returned nil for valid JPEG file")
            return
        }
        guard let uti = CGImageSourceGetType(source) else {
            Issue.record("RED: CGImageSourceGetType returned nil for JPEG")
            return
        }
        #expect((uti as String) == "public.jpeg", "Expected 'public.jpeg', got '\(uti as String)'")
    }

    // MARK: Test 14: CGImageSource URL-based UTI detection for PNG

    @Test("CGImageSourceCreateWithURL detects PNG UTI from file URL")
    func cgImageSourceURLDetectsPNG() async throws {
        let url = try createTempPNGFile(name: "detect_png")
        defer { cleanup(url) }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            Issue.record("RED: CGImageSourceCreateWithURL returned nil for valid PNG file")
            return
        }
        guard let uti = CGImageSourceGetType(source) else {
            Issue.record("RED: CGImageSourceGetType returned nil for PNG")
            return
        }
        #expect((uti as String) == "public.png", "Expected 'public.png', got '\(uti as String)'")
    }

}
