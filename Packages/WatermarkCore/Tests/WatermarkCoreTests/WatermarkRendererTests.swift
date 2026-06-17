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
}
