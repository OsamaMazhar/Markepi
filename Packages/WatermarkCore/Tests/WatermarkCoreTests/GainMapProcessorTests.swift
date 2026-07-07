import Testing
import CoreVideo
import ImageIO
import Foundation
@testable import WatermarkCore

/// Unit tests for `GainMapProcessor` — the HDR gain-map re-alignment that keeps
/// the gain map in lockstep with the orientation-normalized, optionally
/// white-framed base image on export.
@Suite("GainMapProcessor")
struct GainMapProcessorTests {

    // MARK: - Fixtures

    /// Builds a gain-map aux dictionary shaped exactly as `ImageLoader` stores it:
    /// String keys, a `Data` blob, and a `[String: Any]` description.
    private func makeAux(
        pixels: [UInt8],
        width: Int,
        height: Int,
        bytesPerRow: Int? = nil,
        pixelFormat: Int = Int(kCVPixelFormatType_OneComponent8)
    ) -> [String: Any] {
        let stride = bytesPerRow ?? width
        let description: [String: Any] = [
            "Width": width,
            "Height": height,
            "BytesPerRow": stride,
            "PixelFormat": pixelFormat,
        ]
        return [
            kCGImageAuxiliaryDataInfoData as String: Data(pixels),
            kCGImageAuxiliaryDataInfoDataDescription as String: description,
        ]
    }

    private func pixels(of aux: [String: Any]) -> [UInt8]? {
        (aux[kCGImageAuxiliaryDataInfoData as String] as? Data).map { [UInt8]($0) }
    }

    private func description(of aux: [String: Any]) -> [String: Any]? {
        aux[kCGImageAuxiliaryDataInfoDataDescription as String] as? [String: Any]
    }

    // MARK: - Fast path

    @Test("Upright source with no frame returns the gain map unchanged")
    func fastPathReturnsVerbatim() throws {
        let aux = makeAux(pixels: [1, 2, 3, 4], width: 2, height: 2)
        let out = try #require(GainMapProcessor.aligned(
            auxData: aux,
            type: .appleHDR,
            sourceOrientation: .up,
            frameEnabled: false,
            frameWidthRatio: 0
        ))
        #expect(pixels(of: out) == [1, 2, 3, 4])
        let desc = try #require(description(of: out))
        #expect(desc["Width"] as? Int == 2)
        #expect(desc["Height"] as? Int == 2)
    }

    @Test("Nil aux data returns nil")
    func nilInputReturnsNil() {
        #expect(GainMapProcessor.aligned(
            auxData: nil,
            type: .appleHDR,
            sourceOrientation: .right,
            frameEnabled: true,
            frameWidthRatio: 0.04
        ) == nil)
    }

    // MARK: - Rotation

    @Test("Orientation .right rotates the gain map 90° CW and swaps dimensions")
    func rotatesRight() throws {
        // Source 4×2 (landscape), distinct value per pixel, top-left origin:
        //   row0: 10 11 12 13
        //   row1: 20 21 22 23
        let source: [UInt8] = [10, 11, 12, 13,
                               20, 21, 22, 23]
        let aux = makeAux(pixels: source, width: 4, height: 2)

        let out = try #require(GainMapProcessor.aligned(
            auxData: aux,
            type: .appleHDR,
            sourceOrientation: .right,
            frameEnabled: false,
            frameWidthRatio: 0
        ))

        // 90° CW → 2 wide, 4 tall. The original left column (10,20) becomes the
        // top row, bottom-left (20) lands top-left.
        let desc = try #require(description(of: out))
        #expect(desc["Width"] as? Int == 2)
        #expect(desc["Height"] as? Int == 4)
        #expect(desc["BytesPerRow"] as? Int == 2)
        #expect(pixels(of: out) == [20, 10,
                                    21, 11,
                                    22, 12,
                                    23, 13])
    }

    @Test("Orientation .down rotates 180° in place")
    func rotatesDown() throws {
        let source: [UInt8] = [1, 2, 3,
                               4, 5, 6]
        let aux = makeAux(pixels: source, width: 3, height: 2)
        let out = try #require(GainMapProcessor.aligned(
            auxData: aux,
            type: .appleHDR,
            sourceOrientation: .down,
            frameEnabled: false,
            frameWidthRatio: 0
        ))
        let desc = try #require(description(of: out))
        #expect(desc["Width"] as? Int == 3)
        #expect(desc["Height"] as? Int == 2)
        #expect(pixels(of: out) == [6, 5, 4,
                                    3, 2, 1])
    }

    @Test("Row padding in the source is dropped, honoring the source stride")
    func honorsPaddedStride() throws {
        // 2×2 map stored with a 4-byte stride (2 bytes padding per row). The 99s
        // are padding and must never be read as gain values.
        let padded: [UInt8] = [1, 2, 99, 99,
                               3, 4, 99, 99]
        let aux = makeAux(pixels: padded, width: 2, height: 2, bytesPerRow: 4)
        // 180° rotation forces the processing path and repacks tightly.
        let out = try #require(GainMapProcessor.aligned(
            auxData: aux,
            type: .appleHDR,
            sourceOrientation: .down,
            frameEnabled: false,
            frameWidthRatio: 0
        ))
        // Reading through the 4-byte stride, the logical pixels are (1,2 / 3,4);
        // 180° → (4,3 / 2,1). No padding byte (99) survives.
        let outPixels = try #require(pixels(of: out))
        #expect(outPixels == [4, 3, 2, 1])
        let desc = try #require(description(of: out))
        #expect(desc["BytesPerRow"] as? Int == 2)
    }

    // MARK: - Frame band neutralization

    @Test("White frame zeroes the border band and preserves the interior")
    func neutralizesFrameBand() throws {
        // 8×8 map, all boosted (200). ratio 0.25 → inset = round(8*0.25) = 2.
        let source = [UInt8](repeating: 200, count: 64)
        let aux = makeAux(pixels: source, width: 8, height: 8)

        let out = try #require(GainMapProcessor.aligned(
            auxData: aux,
            type: .appleHDR,
            sourceOrientation: .up,
            frameEnabled: true,
            frameWidthRatio: 0.25
        ))
        let px = try #require(pixels(of: out))
        func sample(_ x: Int, _ y: Int) -> UInt8 { px[y * 8 + x] }

        // Corners and edges inside the 2px band are neutralized to 0.
        #expect(sample(0, 0) == 0)
        #expect(sample(7, 0) == 0)
        #expect(sample(0, 7) == 0)
        #expect(sample(1, 4) == 0)   // left band, middle row
        #expect(sample(6, 4) == 0)   // right band, middle row
        // Interior (rows/cols 2...5) keeps the original boost.
        #expect(sample(2, 2) == 200)
        #expect(sample(5, 5) == 200)
        #expect(sample(4, 4) == 200)
    }

    // MARK: - Safe fallback

    @Test("Unsupported pixel format with a required transform drops the map")
    func unsupportedFormatDropped() {
        // 4 bytes/pixel format we don't decode → can't rotate safely.
        let bogusFormat = Int(kCVPixelFormatType_32BGRA)
        let aux = makeAux(
            pixels: [UInt8](repeating: 128, count: 16),
            width: 2, height: 2, bytesPerRow: 8, pixelFormat: bogusFormat
        )
        #expect(GainMapProcessor.aligned(
            auxData: aux,
            type: .appleHDR,
            sourceOrientation: .right,
            frameEnabled: false,
            frameWidthRatio: 0
        ) == nil)
    }

    @Test("ISO gain map with a white frame is dropped rather than mis-neutralized")
    func isoWithFrameDropped() {
        let aux = makeAux(pixels: [UInt8](repeating: 100, count: 16), width: 4, height: 4)
        #expect(GainMapProcessor.aligned(
            auxData: aux,
            type: .iso,
            sourceOrientation: .up,
            frameEnabled: true,
            frameWidthRatio: 0.25
        ) == nil)
    }

    @Test("ISO gain map is still rotated when no frame is applied")
    func isoRotatedWithoutFrame() throws {
        let source: [UInt8] = [10, 11, 12, 13,
                               20, 21, 22, 23]
        let aux = makeAux(pixels: source, width: 4, height: 2)
        let out = try #require(GainMapProcessor.aligned(
            auxData: aux,
            type: .iso,
            sourceOrientation: .right,
            frameEnabled: false,
            frameWidthRatio: 0
        ))
        let desc = try #require(description(of: out))
        #expect(desc["Width"] as? Int == 2)
        #expect(desc["Height"] as? Int == 4)
    }
}
