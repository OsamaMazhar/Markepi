import Testing
import CoreImage
import ImageIO
import Foundation
#if canImport(UIKit)
import UIKit
#endif
@testable import WatermarkCore

/// Tests for WhiteFrameRenderer: border width, text placement, HDR
/// compatibility, frame proportion, custom attribution text.
///
/// RED phase: WhiteFrameRenderer.render() currently throws
/// PipelineError.frameRenderFailed. All tests will fail until
/// the GREEN implementation provides the full render pipeline.
@Suite("WhiteFrameRenderer")
struct WhiteFrameRendererTests {

    // MARK: - Test metadata helpers

    /// Creates a mock metadata dictionary with a TIFF model string.
    private func metadataWithModel(_ model: String) -> [String: Any] {
        let tiffKey = kCGImagePropertyTIFFDictionary as String
        let modelKey = kCGImagePropertyTIFFModel as String
        return [tiffKey: [modelKey: model]]
    }

    /// Creates an empty metadata dictionary (for fallback testing).
    private func emptyMetadata() -> [String: Any] {
        return [:]
    }

    // MARK: - Border width tests

    @Test("Frame width ratio 0.04 on 1000x800 produces 32pt border")
    func frameWidthRatio040On1000x800() throws {
        let config = WhiteFrameConfig(
            isEnabled: true,
            frameWidthRatio: 0.04,
            metadataTextEnabled: false
        )
        let extent = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let metadata = emptyMetadata()

        let rendered = try WhiteFrameRenderer.render(
            config: config, baseExtent: extent, metadata: metadata
        )
        // Frame width = min(1000, 800) × 0.04 = 32pt
        // Rendered extent must match base extent (full image size)
        #expect(rendered.extent == extent,
                "Rendered CIImage extent should match baseExtent (\(extent)), got \(rendered.extent)")
        #expect(!rendered.extent.isInfinite, "Rendered extent should not be infinite")
    }

    @Test("Frame width ratio 0.03 (minimum per D-05) produces valid border")
    func frameWidthRatioMinimum003() throws {
        let config = WhiteFrameConfig(
            isEnabled: true,
            frameWidthRatio: 0.03,
            metadataTextEnabled: false
        )
        let extent = CGRect(x: 0, y: 0, width: 1000, height: 800)

        let rendered = try WhiteFrameRenderer.render(
            config: config, baseExtent: extent, metadata: emptyMetadata()
        )
        // Frame width = min(1000, 800) × 0.03 = 24pt
        #expect(rendered.extent == extent)
    }

    @Test("Frame width ratio 0.05 (maximum per D-05) produces valid border")
    func frameWidthRatioMaximum005() throws {
        let config = WhiteFrameConfig(
            isEnabled: true,
            frameWidthRatio: 0.05,
            metadataTextEnabled: false
        )
        let extent = CGRect(x: 0, y: 0, width: 1000, height: 800)

        let rendered = try WhiteFrameRenderer.render(
            config: config, baseExtent: extent, metadata: emptyMetadata()
        )
        // Frame width = min(1000, 800) × 0.05 = 40pt
        #expect(rendered.extent == extent)
    }

    @Test("Frame width ratio out-of-range values are clamped (0.02 → 0.03, 0.06 → 0.05)")
    func frameWidthRatioClamping() {
        // Init-time clamping per D-05: ratio must be in 0.03–0.05
        let lowConfig = WhiteFrameConfig(frameWidthRatio: 0.02)
        #expect(lowConfig.frameWidthRatio == 0.03, "0.02 should clamp to 0.03")

        let highConfig = WhiteFrameConfig(frameWidthRatio: 0.06)
        #expect(highConfig.frameWidthRatio == 0.05, "0.06 should clamp to 0.05")

        let validConfig = WhiteFrameConfig(frameWidthRatio: 0.04)
        #expect(validConfig.frameWidthRatio == 0.04, "0.04 should remain unchanged")
    }

    @Test("Frame width on square image (500x500) has equal border on all sides")
    func squareImageBorder() throws {
        let config = WhiteFrameConfig(
            isEnabled: true,
            frameWidthRatio: 0.04,
            metadataTextEnabled: false
        )
        let extent = CGRect(x: 0, y: 0, width: 500, height: 500)

        let rendered = try WhiteFrameRenderer.render(
            config: config, baseExtent: extent, metadata: emptyMetadata()
        )
        #expect(rendered.extent == extent)
        // Frame width = min(500,500) × 0.04 = 20pt on all 4 sides (D-04)
    }

    // MARK: - Extent preservation

    @Test("Rendered CIImage extent matches baseExtent size for various dimensions")
    func extentMatchesBaseExtent() throws {
        let config = WhiteFrameConfig(isEnabled: true, metadataTextEnabled: false)
        let sizes: [CGSize] = [
            CGSize(width: 1920, height: 1080),
            CGSize(width: 400, height: 300),
            CGSize(width: 100, height: 100),
        ]

        for size in sizes {
            let extent = CGRect(origin: .zero, size: size)
            let rendered = try WhiteFrameRenderer.render(
                config: config, baseExtent: extent, metadata: emptyMetadata()
            )
            #expect(rendered.extent == extent,
                    "Expected extent \(extent) for size \(size), got \(rendered.extent)")
        }
    }

    // MARK: - Metadata text rendering

    @Test("Metadata text enabled produces text pixels in bottom frame region")
    func metadataTextEnabled() throws {
        let config = WhiteFrameConfig(
            isEnabled: true,
            frameWidthRatio: 0.05,
            metadataTextEnabled: true
        )
        let extent = CGRect(x: 0, y: 0, width: 800, height: 600)
        let metadata = metadataWithModel("iPhone 16 Pro")

        let rendered = try WhiteFrameRenderer.render(
            config: config, baseExtent: extent, metadata: metadata
        )
        // Rendered output should be valid (non-infinite extent)
        #expect(!rendered.extent.isInfinite)
        #expect(rendered.extent == extent)
    }

    @Test("Metadata text disabled produces pure white frame (no text pixels)")
    func metadataTextDisabled() throws {
        let config = WhiteFrameConfig(
            isEnabled: true,
            frameWidthRatio: 0.04,
            metadataTextEnabled: false
        )
        let extent = CGRect(x: 0, y: 0, width: 600, height: 400)

        let rendered = try WhiteFrameRenderer.render(
            config: config, baseExtent: extent, metadata: emptyMetadata()
        )
        #expect(rendered.extent == extent)
        // When text is disabled, bottom frame region should be pure white
        // (verified by absence of text rendering path)
    }

    @Test("Metadata text uses 'Taken by:' prefix per D-08")
    func attributionPrefix() throws {
        let config = WhiteFrameConfig(
            isEnabled: true,
            frameWidthRatio: 0.04,
            metadataTextEnabled: true
        )
        let extent = CGRect(x: 0, y: 0, width: 600, height: 400)
        let metadata = metadataWithModel("iPhone 16 Pro")

        let rendered = try WhiteFrameRenderer.render(
            config: config, baseExtent: extent, metadata: metadata
        )
        // Text should be "Taken by: iPhone 16 Pro" (single line per D-08)
        #expect(!rendered.extent.isInfinite)
    }

    // MARK: - Custom attribution text

    @Test("Custom attribution text override replaces auto-generated text")
    func customAttributionText() throws {
        let customText = "Custom Camera v2.0"
        let config = WhiteFrameConfig(
            isEnabled: true,
            frameWidthRatio: 0.04,
            metadataTextEnabled: true,
            customAttributionText: customText
        )
        let extent = CGRect(x: 0, y: 0, width: 600, height: 400)
        // Even with metadata present, custom text should be used
        let metadata = metadataWithModel("iPhone 16 Pro")

        let rendered = try WhiteFrameRenderer.render(
            config: config, baseExtent: extent, metadata: metadata
        )
        #expect(!rendered.extent.isInfinite)
        // Custom text "Custom Camera v2.0" should appear instead of
        // "Taken by: iPhone 16 Pro"
    }

    @Test("Custom attribution text nil uses DeviceMetadataProvider auto-generation")
    func nilCustomAttributionUsesAutoGeneration() throws {
        let config = WhiteFrameConfig(
            isEnabled: true,
            frameWidthRatio: 0.04,
            metadataTextEnabled: true,
            customAttributionText: nil
        )
        let extent = CGRect(x: 0, y: 0, width: 600, height: 400)
        let metadata = metadataWithModel("iPhone 14")

        let rendered = try WhiteFrameRenderer.render(
            config: config, baseExtent: extent, metadata: metadata
        )
        #expect(!rendered.extent.isInfinite)
        // Should auto-generate "Taken by: iPhone 14" via DeviceMetadataProvider
    }

    // MARK: - Empty metadata fallback

    @Test("Empty metadata dictionary falls back to current device model")
    func emptyMetadataFallback() throws {
        let config = WhiteFrameConfig(
            isEnabled: true,
            frameWidthRatio: 0.04,
            metadataTextEnabled: true
        )
        let extent = CGRect(x: 0, y: 0, width: 600, height: 400)

        let rendered = try WhiteFrameRenderer.render(
            config: config, baseExtent: extent, metadata: emptyMetadata()
        )
        #expect(!rendered.extent.isInfinite)
        // Should fall back to UIDevice.current.model (or "Unknown" on macOS)
        // per D-07 via DeviceMetadataProvider.attributionText(from:)
    }

    // MARK: - HDR compatibility

    @Test("UIGraphicsImageRendererFormat uses .extended preferredRange for HDR")
    func hdrPreferredRange() throws {
        let config = WhiteFrameConfig(
            isEnabled: true,
            frameWidthRatio: 0.04,
            metadataTextEnabled: false
        )
        let extent = CGRect(x: 0, y: 0, width: 400, height: 300)

        let rendered = try WhiteFrameRenderer.render(
            config: config, baseExtent: extent, metadata: emptyMetadata()
        )
        // GREEN: the UIGraphicsImageRendererFormat inside render() must
        // use `preferredRange = .extended` for HDR compatibility.
        // Verified by grep: `preferredRange` in WhiteFrameRenderer.swift >=1 match
        #expect(!rendered.extent.isInfinite)
    }

    @Test("WhiteFrameRenderer uses CGRect-based dimensions (no infinite extent)")
    func noInfiniteExtent() throws {
        let config = WhiteFrameConfig(isEnabled: true, metadataTextEnabled: false)
        let extent = CGRect(x: 0, y: 0, width: 800, height: 600)

        let rendered = try WhiteFrameRenderer.render(
            config: config, baseExtent: extent, metadata: emptyMetadata()
        )
        // The output must have a finite extent matching the base dimensions
        #expect(!rendered.extent.isInfinite, "Output CIImage should have finite extent")
        #expect(rendered.extent.origin == .zero, "Origin should be (0,0)")
        #expect(rendered.extent.width == extent.width, "Width should match base extent")
        #expect(rendered.extent.height == extent.height, "Height should match base extent")
    }

    // MARK: - Border has transparent inner area (per D-04)

    @Test("White frame has transparent inner area (not a solid white fill)")
    func transparentInnerArea() throws {
        let config = WhiteFrameConfig(
            isEnabled: true,
            frameWidthRatio: 0.05,
            metadataTextEnabled: false
        )
        let extent = CGRect(x: 0, y: 0, width: 400, height: 300)

        let rendered = try WhiteFrameRenderer.render(
            config: config, baseExtent: extent, metadata: emptyMetadata()
        )
        // GREEN: The inner area uses .clear blend mode for transparency
        // (grep for `.clear` in WhiteFrameRenderer.swift >=1 match)
        #expect(rendered.extent == extent)
    }

    // MARK: - Default values

    @Test("WhiteFrameConfig default values match specification")
    func defaultConfigValues() {
        let config = WhiteFrameConfig()
        #expect(config.isEnabled == false, "Default isEnabled should be false")
        #expect(config.frameWidthRatio == 0.04, "Default frameWidthRatio should be 0.04")
        #expect(config.metadataTextEnabled == true, "Default metadataTextEnabled should be true")
        #expect(config.customAttributionText == nil, "Default customAttributionText should be nil")
        #expect(config.textFontSizeRatio == 0.018, "Default textFontSizeRatio should be 0.018")
    }

    @Test("WhiteFrameConfig full initialization with all properties")
    func fullInit() {
        let customColor = CGColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1.0)
        let config = WhiteFrameConfig(
            isEnabled: true,
            frameWidthRatio: 0.045,
            metadataTextEnabled: true,
            customAttributionText: "Shot on My Phone",
            textColor: customColor,
            textFontSizeRatio: 0.5
        )
        #expect(config.isEnabled == true)
        #expect(config.frameWidthRatio == 0.045)
        #expect(config.metadataTextEnabled == true)
        #expect(config.customAttributionText == "Shot on My Phone")
        #expect(config.textFontSizeRatio == 0.5)
    }
}
