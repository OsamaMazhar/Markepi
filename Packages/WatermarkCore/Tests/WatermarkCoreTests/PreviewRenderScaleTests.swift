import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import WatermarkCore

/// The editor renders previews at screen size instead of full resolution, which
/// is what lets it keep up with a finger. These pin the two things that could
/// silently make a preview lie about the export: different proportions, and a
/// millimetre-specified mat that doesn't scale with the photo.
@Suite("Preview render scale")
struct PreviewRenderScaleTests {

    private func sourceFile() throws -> URL {
        let (_, data) = TestImageFactory.solidColorImage(
            color: CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1),
            size: CGSize(width: 4000, height: 3000)
        )
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("preview_scale_\(UUID().uuidString).jpg")
        try data.write(to: url)
        return url
    }

    private func config() -> WatermarkConfiguration {
        var config = WatermarkConfiguration(watermarks: [
            .text(
                TextWatermarkInput(text: "MARKEPI", fontSize: 48, color: CGColor(gray: 1, alpha: 1)),
                position: .custom(x: 0.25, y: 0.75), scale: 0.06, opacity: 1.0, isVisible: true
            )
        ])
        config.whiteFrame = WhiteFrameConfig(isEnabled: true)
        return config
    }

    /// Everything the editor draws on top of the preview — the drag ghost, its
    /// bounds — comes from `RenderLayout`, so a preview must place the photo and
    /// the layers at the same *proportions* as the export.
    @Test("a preview places the photo and its layers exactly where the export does")
    func layoutMatchesFullResolution() async throws {
        let url = try sourceFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let engine = WatermarkEngine()

        let full = try await engine.process(sourceURL: url, config: config())
        let preview = try await engine.process(
            sourceURL: url, config: config(), maxPixelDimension: 1800)
        defer {
            for output in [full.url, preview.url] {
                if let output { try? FileManager.default.removeItem(at: output) }
            }
        }

        let fullLayout = try #require(full.previewLayout)
        let previewLayout = try #require(preview.previewLayout)

        // Normalized rects, so they should agree regardless of pixel size.
        // 0.5% covers the rounding of a millimetre mat onto a pixel grid.
        #expect(abs(previewLayout.photoRect.minX - fullLayout.photoRect.minX) < 0.005)
        #expect(abs(previewLayout.photoRect.minY - fullLayout.photoRect.minY) < 0.005)
        #expect(abs(previewLayout.photoRect.width - fullLayout.photoRect.width) < 0.005)
        #expect(abs(previewLayout.photoRect.height - fullLayout.photoRect.height) < 0.005)

        let fullText = try #require(fullLayout.layerFrames[0])
        let previewText = try #require(previewLayout.layerFrames[0])
        #expect(abs(previewText.minX - fullText.minX) < 0.01)
        #expect(abs(previewText.minY - fullText.minY) < 0.01)
        #expect(abs(previewText.width - fullText.width) < 0.01)
    }

    @Test("a preview really is rendered smaller, and the export is untouched")
    func previewIsSmallerButExportIsNot() async throws {
        let url = try sourceFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let engine = WatermarkEngine()

        let full = try await engine.process(sourceURL: url, config: config())
        let preview = try await engine.process(
            sourceURL: url, config: config(), maxPixelDimension: 1800)
        defer {
            for output in [full.url, preview.url] {
                if let output { try? FileManager.default.removeItem(at: output) }
            }
        }

        func longestSide(_ result: ProcessingResult) throws -> Int {
            let output = try #require(result.url)
            let source = try #require(CGImageSourceCreateWithURL(output as CFURL, nil))
            let properties = try #require(
                CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
            let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
            let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
            return max(width, height)
        }

        // The mat makes the framed output a little larger than the photo itself,
        // so this is "screen-sized, not source-sized", not an exact 1800.
        let previewSide = try longestSide(preview)
        let fullSide = try longestSide(full)
        #expect(previewSide <= 2200, "preview longest side was \(previewSide)")
        #expect(fullSide >= 4000, "export longest side was \(fullSide)")
        // Same shape, just smaller — the mat scaled with the photo.
        #expect(abs(Double(previewSide) / Double(fullSide) - 1800.0 / 4000.0) < 0.02)
    }
}

/// The editor's drag lifts a layer out of the composite and draws it on its own
/// while it follows the finger. That copy has to exist for every kind of layer,
/// not just text.
@Suite("Draggable layer previews")
struct LayerPreviewImageTests {

    @Test("a text layer renders a draggable copy, an empty one doesn't")
    func textLayers() {
        let filled = WatermarkLayer.text(
            TextWatermarkInput(text: "MARKEPI", fontSize: 48, color: CGColor(gray: 1, alpha: 1)),
            position: .bottomRight, scale: 0.05, opacity: 1, isVisible: true
        )
        let empty = WatermarkLayer.text(
            TextWatermarkInput(text: "", fontSize: 48, color: CGColor(gray: 1, alpha: 1)),
            position: .bottomRight, scale: 0.05, opacity: 1, isVisible: true
        )
        #expect(LayerPreviewImage.render(filled) != nil)
        #expect(LayerPreviewImage.render(empty) == nil)
    }

    @Test("a logo layer renders a draggable copy, rotation included")
    func logoLayers() throws {
        let (_, jpegData) = TestImageFactory.solidColorImage(
            color: CGColor(red: 1, green: 0, blue: 0, alpha: 1),
            size: CGSize(width: 200, height: 100)
        )
        let input = try ImageWatermarkInput(pngData: jpegData)
        let upright = WatermarkLayer.image(
            input, position: .bottomLeft, scale: 0.15, opacity: 1, isVisible: true)
        let turned = WatermarkLayer.image(
            input.withRotationDegrees(90), position: .bottomLeft, scale: 0.15,
            opacity: 1, isVisible: true)

        let uprightCopy = try #require(LayerPreviewImage.render(upright))
        let turnedCopy = try #require(LayerPreviewImage.render(turned))
        // Rotating swaps the copy's proportions, so the ghost matches what the
        // renderer will actually composite.
        #expect(uprightCopy.width > uprightCopy.height)
        #expect(turnedCopy.height > turnedCopy.width)
    }

    // A signature is PencilKit stroke data, which can only be built on iOS —
    // `SignatureRendererTests` covers that renderer there. `LayerPreviewImage`
    // routes signatures through it exactly as it routes text and logos.
}
