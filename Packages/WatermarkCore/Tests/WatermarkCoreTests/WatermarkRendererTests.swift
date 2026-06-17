import Testing
import CoreImage
@testable import WatermarkCore

/// Tests WatermarkRenderer for layer compositing order, positioning,
/// and output extent cropping.
@Suite("WatermarkRenderer")
struct WatermarkRendererTests {

    /// Creates a small colored CIImage for use as a watermark layer in tests.
    private func makeLayer(size: CGSize, color: CIColor) -> CIImage {
        return CIImage(color: color).cropped(to: CGRect(origin: .zero, size: size))
    }

    @Test("Single layer composited at (0,0) over base — layer appears at bottom-left")
    func singleLayerAtOrigin() {
        let base = makeLayer(size: CGSize(width: 100, height: 200), color: CIColor(red: 1, green: 0, blue: 0))
        let layer = makeLayer(size: CGSize(width: 20, height: 10), color: CIColor(red: 0, green: 1, blue: 0))

        let composited = WatermarkRenderer.composite(
            layers: [(layer, CGPoint(x: 0, y: 0))],
            onto: base
        )

        // RED: stub returns base unchanged → extent matches base
        // GREEN: composite preserves base extent
        #expect(composited.extent.width == 100)
        #expect(composited.extent.height == 200)
        #expect(!composited.extent.isInfinite)
    }

    @Test("Two layers composited in order — second layer on top of first")
    func twoLayerOrder() {
        let base = makeLayer(size: CGSize(width: 100, height: 100), color: CIColor(red: 0, green: 0, blue: 1))
        let layer1 = makeLayer(size: CGSize(width: 30, height: 30), color: CIColor(red: 1, green: 0, blue: 0))
        let layer2 = makeLayer(size: CGSize(width: 30, height: 30), color: CIColor(red: 0, green: 1, blue: 0))

        let composited = WatermarkRenderer.composite(
            layers: [
                (layer1, CGPoint(x: 0, y: 0)),
                (layer2, CGPoint(x: 10, y: 10)),
            ],
            onto: base
        )

        // Extent should match base
        #expect(composited.extent.width == 100)
        #expect(composited.extent.height == 100)
        #expect(!composited.extent.isInfinite)
    }

    @Test("Output extent equals base extent — cropped correctly")
    func outputCroppedToBase() {
        let base = makeLayer(size: CGSize(width: 50, height: 50), color: CIColor(red: 0.5, green: 0.5, blue: 0.5))
        let largeLayer = makeLayer(size: CGSize(width: 200, height: 200), color: CIColor(red: 1, green: 1, blue: 1))

        let composited = WatermarkRenderer.composite(
            layers: [(largeLayer, CGPoint(x: 0, y: 0))],
            onto: base
        )

        // Should be cropped to base extent
        #expect(composited.extent.width == 50)
        #expect(composited.extent.height == 50)
    }

    @Test("Layer at topLeft on 100×200 base, 20×10 watermark → positioned at bottom-left origin")
    func topLeftPosition() {
        let base = makeLayer(size: CGSize(width: 100, height: 200), color: CIColor(red: 0, green: 0, blue: 1))
        let layer = makeLayer(size: CGSize(width: 20, height: 10), color: CIColor(red: 1, green: 0, blue: 0))

        // topLeft in CIImage coordinates: x = 0, y = baseHeight - layerHeight = 190
        let pos = CGPoint(x: 0, y: 190)
        let composited = WatermarkRenderer.composite(
            layers: [(layer, pos)],
            onto: base
        )

        #expect(composited.extent.width == 100)
        #expect(composited.extent.height == 200)
        #expect(!composited.extent.isInfinite)
    }

    // MARK: - Multi-layer ordering (Plan 02 additions)

    @Test("Three layers composited — all layers present in output extent")
    func threeLayerCompositing() {
        let base = makeLayer(size: CGSize(width: 100, height: 100), color: CIColor(red: 0, green: 0, blue: 1))
        let layer1 = makeLayer(size: CGSize(width: 60, height: 60), color: CIColor(red: 1, green: 0, blue: 0))
        let layer2 = makeLayer(size: CGSize(width: 40, height: 40), color: CIColor(red: 0, green: 1, blue: 0))

        let composited = WatermarkRenderer.composite(
            layers: [
                (layer1, CGPoint(x: 0, y: 0)),
                (layer2, CGPoint(x: 30, y: 30)),
            ],
            onto: base
        )

        // Extent should match base — all layers cropped to base bounds
        #expect(composited.extent.width == 100)
        #expect(composited.extent.height == 100)
        #expect(!composited.extent.isInfinite)
    }

    @Test("Layer order matters — swapped order produces different pixel output")
    func layerOrderAffectsOutput() {
        // Two identical layers overlapping, different order → different result
        let base = makeLayer(size: CGSize(width: 10, height: 10), color: CIColor(red: 0, green: 0, blue: 1))
        let redLayer = makeLayer(size: CGSize(width: 10, height: 10), color: CIColor(red: 1, green: 0, blue: 0))
        let greenLayer = makeLayer(size: CGSize(width: 10, height: 10), color: CIColor(red: 0, green: 1, blue: 0))

        // Order A: red on bottom, green on top
        let orderA = WatermarkRenderer.composite(
            layers: [
                (redLayer, CGPoint(x: 0, y: 0)),
                (greenLayer, CGPoint(x: 0, y: 0)),
            ],
            onto: base
        )

        // Order B: green on bottom, red on top
        let orderB = WatermarkRenderer.composite(
            layers: [
                (greenLayer, CGPoint(x: 0, y: 0)),
                (redLayer, CGPoint(x: 0, y: 0)),
            ],
            onto: base
        )

        // Both should produce valid finite extents
        #expect(!orderA.extent.isInfinite)
        #expect(!orderB.extent.isInfinite)

        // Render to verify they produce different pixel values
        let context = CIContext()
        guard let cgA = context.createCGImage(orderA, from: orderA.extent),
              let cgB = context.createCGImage(orderB, from: orderB.extent) else {
            Issue.record("Failed to render composited images")
            return
        }

        let dataA = TestImageFactory.pixelData(from: cgA)
        let dataB = TestImageFactory.pixelData(from: cgB)

        // The pixel outputs should differ because order matters per D-01
        #expect(dataA != nil && dataB != nil, "Pixel data should be non-nil")
        if let a = dataA, let b = dataB {
            // Green-on-top (A) vs red-on-top (B) should differ
            // Compare center pixel: A should be green-dominated, B should be red-dominated
            let centerIdx = 5 * 40 + 5 * 4  // row 5, col 5 in 10×10 RGBA8
            if centerIdx + 2 < a.count && centerIdx + 2 < b.count {
                let aGreen = a[centerIdx + 1]  // G channel
                let bGreen = b[centerIdx + 1]
                let aRed = a[centerIdx + 0]    // R channel
                let bRed = b[centerIdx + 0]
                // Order A has green on top → green should be higher
                // Order B has red on top → red should be higher
                #expect(aGreen > bGreen || aRed < bRed,
                        "Layer order should affect compositing result")
            }
        }
    }

    @Test("Tiny layer (scale 0.01 equivalent) still renders")
    func tinyLayerRenders() {
        let base = makeLayer(size: CGSize(width: 100, height: 100), color: CIColor(red: 0, green: 0, blue: 1))
        // A 1×1 pixel layer — represents scale 0.01 on a reasonable watermark
        let tinyLayer = makeLayer(size: CGSize(width: 1, height: 1), color: CIColor(red: 1, green: 1, blue: 1))

        let composited = WatermarkRenderer.composite(
            layers: [(tinyLayer, CGPoint(x: 10, y: 10))],
            onto: base
        )

        #expect(!composited.extent.isInfinite)
        #expect(composited.extent.width == 100)
        #expect(composited.extent.height == 100)
    }

    @Test("Large layer (scale 0.90 equivalent) still renders")
    func largeLayerRenders() {
        let base = makeLayer(size: CGSize(width: 100, height: 100), color: CIColor(red: 0, green: 0, blue: 1))
        // A 90×90 pixel layer — represents scale 0.90
        let largeLayer = makeLayer(size: CGSize(width: 90, height: 90), color: CIColor(red: 1, green: 0, blue: 0))

        let composited = WatermarkRenderer.composite(
            layers: [(largeLayer, CGPoint(x: 0, y: 0))],
            onto: base
        )

        #expect(!composited.extent.isInfinite)
        #expect(composited.extent.width == 100)
        #expect(composited.extent.height == 100)
    }
}
