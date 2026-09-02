import CoreGraphics
import Foundation
import Testing
@testable import WatermarkCore

/// The mat sits outside the photo, so geometry decides the exported size.
/// Both the photo and video paths derive from `FrameGeometry`, which makes
/// these tests the shared contract between them.
@Suite("Frame geometry")
struct FrameGeometryTests {

    static let portrait = CGSize(width: 3024, height: 4032)
    static let landscape = CGSize(width: 4032, height: 3024)

    static func config(style: FrameStyle = .classic, keyline: Bool = false) -> WhiteFrameConfig {
        WhiteFrameConfig(isEnabled: true, style: style, keylineEnabled: keyline)
    }

    // MARK: - Outside, not over

    @Test("The framed canvas is larger than the source in both dimensions")
    func framedCanvasGrows() {
        for style in FrameStyle.allCases {
            for size in [Self.portrait, Self.landscape] {
                let g = FrameGeometry(config: Self.config(style: style), sourceSize: size)
                #expect(g.framedSize.width > size.width, "\(style) \(size) did not grow in width")
                #expect(g.framedSize.height > size.height, "\(style) \(size) did not grow in height")
            }
        }
    }

    @Test("The photo keeps its full size inside the mat")
    func photoIsNeverCropped() {
        for style in FrameStyle.allCases {
            let g = FrameGeometry(config: Self.config(style: style), sourceSize: Self.portrait)
            #expect(g.photoRect.size == Self.portrait)
            // And it sits wholly inside the canvas.
            #expect(g.photoRect.minX >= 0)
            #expect(g.photoRect.minY >= 0)
            #expect(g.photoRect.maxX <= g.framedSize.width)
            #expect(g.photoRect.maxY <= g.framedSize.height)
        }
    }

    // MARK: - Style differences

    @Test("Classic mats are uniform on all four edges")
    func classicIsUniform() {
        let g = FrameGeometry(config: Self.config(style: .classic), sourceSize: Self.portrait)
        #expect(g.top == g.left)
        #expect(g.left == g.right)
        #expect(g.bottom == g.top)
    }

    @Test("Gallery's bottom band is taller than its other edges")
    func galleryBottomIsTaller() {
        for size in [Self.portrait, Self.landscape] {
            let g = FrameGeometry(config: Self.config(style: .gallery), sourceSize: size)
            #expect(g.bottom > g.top, "\(size): bottom \(g.bottom) should exceed top \(g.top)")
            #expect(g.left == g.right)
            #expect(g.top == g.left)
        }
    }

    @Test("Gallery's bottom band is tall enough for two lines of caption")
    func galleryBottomFitsTwoLines() {
        let g = FrameGeometry(config: Self.config(style: .gallery), sourceSize: Self.portrait)
        // Two lines at 1.25x plus the gap between them, with nothing left for
        // padding, is the absolute floor.
        let bareMinimum = g.captionFontSize * (1.25 * 2 + 0.25)
        #expect(g.captionBand.height > bareMinimum)
    }

    // MARK: - Resolution independence

    @Test("Proportions hold when the same photo is exported at two sizes")
    func proportionsHoldAcrossResolutions() {
        let small = CGSize(width: 1512, height: 2016)
        let large = CGSize(width: 6048, height: 8064)
        for style in FrameStyle.allCases {
            let a = FrameGeometry(config: Self.config(style: style), sourceSize: small)
            let b = FrameGeometry(config: Self.config(style: style), sourceSize: large)

            let matRatioA = a.left / min(small.width, small.height)
            let matRatioB = b.left / min(large.width, large.height)
            #expect(abs(matRatioA - matRatioB) < 0.001, "\(style): mat ratio drifted")

            let fontRatioA = a.captionFontSize / min(small.width, small.height)
            let fontRatioB = b.captionFontSize / min(large.width, large.height)
            #expect(abs(fontRatioA - fontRatioB) < 0.0001, "\(style): font ratio drifted")
        }
    }

    // MARK: - Even dimensions

    @Test("The framed canvas is always even, which video encoders require")
    func framedSizeIsEven() {
        // Odd sources, odd mats — the combinations most likely to produce an
        // odd canvas if the rounding were wrong.
        let awkward = [
            CGSize(width: 1001, height: 1333),
            CGSize(width: 999, height: 999),
            CGSize(width: 4001, height: 3001),
            CGSize(width: 100, height: 101),
        ]
        for style in FrameStyle.allCases {
            for size in awkward {
                let g = FrameGeometry(config: Self.config(style: style), sourceSize: size)
                #expect(Int(g.framedSize.width) % 2 == 0, "\(style) \(size): odd width \(g.framedSize.width)")
                #expect(Int(g.framedSize.height) % 2 == 0, "\(style) \(size): odd height \(g.framedSize.height)")
            }
        }
    }

    @Test("Rounding to even steals from the mat, never from the photo")
    func roundingNeverEatsThePhoto() {
        let g = FrameGeometry(config: Self.config(), sourceSize: CGSize(width: 1001, height: 1333))
        #expect(g.photoRect.width == 1001)
        #expect(g.photoRect.height == 1333)
    }

    // MARK: - Keyline

    @Test("The keyline has no thickness when disabled")
    func keylineOffIsZero() {
        #expect(FrameGeometry(config: Self.config(keyline: false), sourceSize: Self.portrait).keylineWidth == 0)
    }

    @Test("The keyline scales with the source and is at least a pixel")
    func keylineScales() {
        let big = FrameGeometry(config: Self.config(keyline: true), sourceSize: Self.portrait)
        let tiny = FrameGeometry(config: Self.config(keyline: true), sourceSize: CGSize(width: 80, height: 60))
        #expect(big.keylineWidth > tiny.keylineWidth)
        #expect(tiny.keylineWidth >= 1, "a keyline thinner than a pixel would vanish")
    }

    @Test("The keyline is stroked outside the photo, so it covers none of it")
    func keylineStaysOffThePhoto() {
        let g = FrameGeometry(config: Self.config(keyline: true), sourceSize: Self.portrait)
        // Stroking `keylineRect` with `keylineWidth` paints from its inner edge
        // outward; the inner edge is exactly the photo boundary.
        let innerEdge = g.keylineRect.insetBy(dx: g.keylineWidth / 2, dy: g.keylineWidth / 2)
        #expect(innerEdge == g.photoRect)
    }

    @Test("The keyline available in every style")
    func keylineAppliesToBothStyles() {
        for style in FrameStyle.allCases {
            let g = FrameGeometry(config: Self.config(style: style, keyline: true), sourceSize: Self.portrait)
            #expect(g.keylineWidth > 0, "\(style) lost its keyline")
        }
    }

    // MARK: - Caption band

    @Test("The caption band clears the photo and sits within the side mats")
    func captionBandIsClearOfThePhoto() {
        let g = FrameGeometry(config: Self.config(style: .gallery, keyline: true), sourceSize: Self.portrait)
        #expect(g.captionBand.minY >= g.photoRect.maxY, "caption band overlaps the photo")
        #expect(g.captionBand.minX == g.left)
        #expect(g.captionBand.maxX <= g.framedSize.width - g.right + 0.001)
        #expect(g.captionBand.height > 0)
    }
}
