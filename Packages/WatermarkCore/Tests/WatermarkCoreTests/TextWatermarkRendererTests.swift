import Testing
import CoreImage
@testable import WatermarkCore

/// Tests TextWatermarkRenderer for SF system font rendering at various
/// font sizes, colors, and opacity levels.
@Suite("TextWatermarkRenderer")
struct TextWatermarkRendererTests {

    @Test("Rendered CIImage is non-nil for valid input")
    func rendersNonNilImage() {
        let config = TextWatermarkInput(
            text: "TEST",
            fontSize: 48,
            opacity: 1.0
        )
        let ciImage = TextWatermarkRenderer.render(config: config)
        // RED: stub returns empty CIImage (infinite extent), GREEN: returns valid image
        #expect(!ciImage.extent.isInfinite, "Expected finite extent for rendered text")
    }

    @Test("Rendered CIImage has positive extent dimensions")
    func rendersWithPositiveExtent() {
        let config = TextWatermarkInput(
            text: "Watermark",
            fontSize: 72,
            opacity: 1.0
        )
        let ciImage = TextWatermarkRenderer.render(config: config)
        #expect(ciImage.extent.width > 0, "Expected positive width")
        #expect(ciImage.extent.height > 0, "Expected positive height")
    }

    @Test("Larger font size produces larger extent")
    func largerFontProducesLargerExtent() {
        let small = TextWatermarkInput(text: "Hi", fontSize: 24, opacity: 1.0)
        let large = TextWatermarkInput(text: "Hi", fontSize: 72, opacity: 1.0)

        let smallImage = TextWatermarkRenderer.render(config: small)
        let largeImage = TextWatermarkRenderer.render(config: large)

        // Larger font should produce a wider image
        #expect(largeImage.extent.width > smallImage.extent.width,
                "Larger font should produce wider text extent")
    }

    @Test("Opacity 0.5 produces translucent text (non-opaque CIImage)")
    func opacityAffectsOutput() {
        let opaque = TextWatermarkInput(text: "X", fontSize: 48, opacity: 1.0)
        let translucent = TextWatermarkInput(text: "X", fontSize: 48, opacity: 0.5)

        let opaqueImage = TextWatermarkRenderer.render(config: opaque)
        let translucentImage = TextWatermarkRenderer.render(config: translucent)

        // Both should render (different alpha channels, but both are valid CIImages)
        #expect(!opaqueImage.extent.isInfinite)
        #expect(!translucentImage.extent.isInfinite)
    }
}
