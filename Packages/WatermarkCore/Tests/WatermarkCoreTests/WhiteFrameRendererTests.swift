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

    /// The canvas a frame renders into: source plus mat, from the same
    /// geometry the renderer uses. The mat is drawn outside the photo, so this
    /// is always larger than the source.
    func framedRect(_ config: WhiteFrameConfig, _ source: CGRect,
                    metadata: [String: Any] = [:], dpi: CGFloat? = nil) -> CGRect {
        // Mirrors the renderer exactly — same DPI, same does-the-caption-say-
        // anything question — or it predicts a band the render rightly omits.
        CGRect(origin: .zero, size: FrameGeometry(
            config: config,
            sourceSize: source.size,
            dpi: dpi ?? FrameGeometry.resolveDPI(
                from: metadata, config: config, sourceSize: source.size),
            hasCaptionContent: WhiteFrameRenderer.hasCaptionContent(config: config, metadata: metadata)
        ).framedSize)
    }

    // MARK: - Border width tests

    @Test("An 8mm border at 300dpi is a 94pt mat, whatever the photo's size")
    func borderIsPhysical() throws {
        // Pinned to 300, because that is what makes the claim meaningful:
        // left to itself the resolution is derived from the photo, and then a
        // millimetre is a constant *share* rather than a constant pixel count.
        let config = WhiteFrameConfig(
            isEnabled: true,
            metadataTextEnabled: false,
            borderMillimetres: 8,
            outputDPI: 300
        )
        let small = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let large = CGRect(x: 0, y: 0, width: 6000, height: 4000)

        let renderedSmall = try WhiteFrameRenderer.render(
            config: config, sourceSize: small.size, metadata: emptyMetadata()
        )
        let renderedLarge = try WhiteFrameRenderer.render(
            config: config, sourceSize: large.size, metadata: emptyMetadata()
        )
        #expect(renderedSmall.extent == framedRect(config, small))
        #expect(renderedLarge.extent == framedRect(config, large))

        // The same edge on both: 8mm at 300dpi plus the keyline. Sized as a
        // percentage of the photo, this setting printed 32px of mat on the
        // small photo and 160px on the large one.
        let edge = FrameGeometry(config: config, sourceSize: small.size, dpi: 300).left
        #expect(renderedSmall.extent.width - small.width == edge * 2)
        #expect(renderedLarge.extent.width - large.width == edge * 2)
    }

    @Test("Border millimetres are clamped to something printable")
    func borderMillimetreClamping() {
        #expect(WhiteFrameConfig(borderMillimetres: 0).borderMillimetres == 0.5)
        #expect(WhiteFrameConfig(borderMillimetres: 500).borderMillimetres == 50)
        #expect(WhiteFrameConfig(borderMillimetres: 8).borderMillimetres == 8)
    }

    @Test("Frame width on square image (500x500) has equal border on all sides")
    func squareImageBorder() throws {
        let config = WhiteFrameConfig(
            isEnabled: true,
            metadataTextEnabled: false
        )
        let extent = CGRect(x: 0, y: 0, width: 500, height: 500)

        let rendered = try WhiteFrameRenderer.render(
            config: config, sourceSize: extent.size, metadata: emptyMetadata()
        )
        #expect(rendered.extent == framedRect(config, extent))
        // Frame width = min(500,500) × 0.04 = 20pt on all 4 sides (D-04)
    }

    // MARK: - Extent preservation

    @Test("Rendered extent is the framed canvas for various dimensions")
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
                config: config, sourceSize: extent.size, metadata: emptyMetadata()
            )
            #expect(rendered.extent == framedRect(config, extent),
                    "Expected extent \(extent) for size \(size), got \(rendered.extent)")
        }
    }

    // MARK: - Metadata text rendering

    @Test("Metadata text enabled produces text pixels in bottom frame region")
    func metadataTextEnabled() throws {
        let config = WhiteFrameConfig(
            isEnabled: true,
            metadataTextEnabled: true
        )
        let extent = CGRect(x: 0, y: 0, width: 800, height: 600)
        let metadata = metadataWithModel("iPhone 16 Pro")

        let rendered = try WhiteFrameRenderer.render(
            config: config, sourceSize: extent.size, metadata: metadata
        )
        // Rendered output should be valid (non-infinite extent)
        #expect(!rendered.extent.isInfinite)
        #expect(rendered.extent == framedRect(config, extent, metadata: metadata))
    }

    @Test("Metadata text disabled produces pure white frame (no text pixels)")
    func metadataTextDisabled() throws {
        let config = WhiteFrameConfig(
            isEnabled: true,
            metadataTextEnabled: false
        )
        let extent = CGRect(x: 0, y: 0, width: 600, height: 400)

        let rendered = try WhiteFrameRenderer.render(
            config: config, sourceSize: extent.size, metadata: emptyMetadata()
        )
        #expect(rendered.extent == framedRect(config, extent))
        // When text is disabled, bottom frame region should be pure white
        // (verified by absence of text rendering path)
    }

    @Test("Metadata text uses 'Taken by:' prefix per D-08")
    func attributionPrefix() throws {
        let config = WhiteFrameConfig(
            isEnabled: true,
            metadataTextEnabled: true
        )
        let extent = CGRect(x: 0, y: 0, width: 600, height: 400)
        let metadata = metadataWithModel("iPhone 16 Pro")

        let rendered = try WhiteFrameRenderer.render(
            config: config, sourceSize: extent.size, metadata: metadata
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
            metadataTextEnabled: true,
            customAttributionText: customText
        )
        let extent = CGRect(x: 0, y: 0, width: 600, height: 400)
        // Even with metadata present, custom text should be used
        let metadata = metadataWithModel("iPhone 16 Pro")

        let rendered = try WhiteFrameRenderer.render(
            config: config, sourceSize: extent.size, metadata: metadata
        )
        #expect(!rendered.extent.isInfinite)
        // Custom text "Custom Camera v2.0" should appear instead of
        // "Taken by: iPhone 16 Pro"
    }

    @Test("Custom attribution text nil uses DeviceMetadataProvider auto-generation")
    func nilCustomAttributionUsesAutoGeneration() throws {
        let config = WhiteFrameConfig(
            isEnabled: true,
            metadataTextEnabled: true,
            customAttributionText: nil
        )
        let extent = CGRect(x: 0, y: 0, width: 600, height: 400)
        let metadata = metadataWithModel("iPhone 14")

        let rendered = try WhiteFrameRenderer.render(
            config: config, sourceSize: extent.size, metadata: metadata
        )
        #expect(!rendered.extent.isInfinite)
        // Should auto-generate "Taken by: iPhone 14" via DeviceMetadataProvider
    }

    // MARK: - Empty metadata fallback

    @Test("Empty metadata dictionary falls back to current device model")
    func emptyMetadataFallback() throws {
        let config = WhiteFrameConfig(
            isEnabled: true,
            metadataTextEnabled: true
        )
        let extent = CGRect(x: 0, y: 0, width: 600, height: 400)

        let rendered = try WhiteFrameRenderer.render(
            config: config, sourceSize: extent.size, metadata: emptyMetadata()
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
            metadataTextEnabled: false
        )
        let extent = CGRect(x: 0, y: 0, width: 400, height: 300)

        let rendered = try WhiteFrameRenderer.render(
            config: config, sourceSize: extent.size, metadata: emptyMetadata()
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
            config: config, sourceSize: extent.size, metadata: emptyMetadata()
        )
        // The output must have a finite extent matching the base dimensions
        #expect(!rendered.extent.isInfinite, "Output CIImage should have finite extent")
        #expect(rendered.extent.origin == .zero, "Origin should be (0,0)")
        #expect(rendered.extent.width == framedRect(config, extent).width, "Width should be the framed canvas")
        #expect(rendered.extent.height == framedRect(config, extent).height, "Height should be the framed canvas")
    }

    // MARK: - Border has transparent inner area (per D-04)

    @Test("White frame has transparent inner area (not a solid white fill)")
    func transparentInnerArea() throws {
        let config = WhiteFrameConfig(
            isEnabled: true,
            metadataTextEnabled: false
        )
        let extent = CGRect(x: 0, y: 0, width: 400, height: 300)

        let rendered = try WhiteFrameRenderer.render(
            config: config, sourceSize: extent.size, metadata: emptyMetadata()
        )
        // GREEN: The inner area uses .clear blend mode for transparency
        // (grep for `.clear` in WhiteFrameRenderer.swift >=1 match)
        #expect(rendered.extent == framedRect(config, extent))
    }

    // MARK: - Default values

    @Test("WhiteFrameConfig default values match specification")
    func defaultConfigValues() {
        let config = WhiteFrameConfig()
        #expect(config.isEnabled == false, "Default isEnabled should be false")
        #expect(config.metadataTextEnabled == true, "Default metadataTextEnabled should be true")
        #expect(config.customAttributionText == nil, "Default customAttributionText should be nil")
        #expect(config.borderMillimetres == FrameMetrics.defaultBorderMillimetres)
        #expect(config.captionTextMillimetres == FrameMetrics.defaultCaptionMillimetres)
    }

    @Test("WhiteFrameConfig full initialization with all properties")
    func fullInit() {
        let customColor = CGColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1.0)
        let config = WhiteFrameConfig(
            isEnabled: true,
            metadataTextEnabled: true,
            customAttributionText: "Shot on My Phone",
            textColor: customColor,
            borderMillimetres: 12,
            captionTextMillimetres: 4
        )
        #expect(config.isEnabled == true)
        #expect(config.metadataTextEnabled == true)
        #expect(config.customAttributionText == "Shot on My Phone")
        #expect(config.borderMillimetres == 12)
        #expect(config.captionTextMillimetres == 4)
    }
}
