import Testing
import CoreImage
@testable import WatermarkCore

/// Tests WatermarkPosition.translation() for all 9 positions across
/// landscape, portrait, and square aspect ratios using CIImage
/// bottom-left origin coordinate math.
///
/// Assertions verify the x and y translation components of the
/// returned CGAffineTransform within ±1 point tolerance.
@Suite("WatermarkPosition Translation")
struct PositionCalculatorTests {

    // MARK: - Landscape (4032×3024)

    @Suite("Landscape 4032×3024 — watermark 200×50, padding 20")
    struct Landscape {
        let baseExtent = CGRect(x: 0, y: 0, width: 4032, height: 3024)
        let watermarkExtent = CGRect(x: 0, y: 0, width: 200, height: 50)
        let padding: CGFloat = 20

        @Test("topLeft")
        func topLeft() {
            let t = WatermarkPosition.topLeft.translation(watermarkExtent: watermarkExtent, baseExtent: baseExtent, padding: padding)
            #expect(abs(t.tx - 20) <= 1)
            #expect(abs(t.ty - 2954) <= 1)
        }
        @Test("topCenter")
        func topCenter() {
            let t = WatermarkPosition.topCenter.translation(watermarkExtent: watermarkExtent, baseExtent: baseExtent, padding: padding)
            #expect(abs(t.tx - 1916) <= 1)
            #expect(abs(t.ty - 2954) <= 1)
        }
        @Test("topRight")
        func topRight() {
            let t = WatermarkPosition.topRight.translation(watermarkExtent: watermarkExtent, baseExtent: baseExtent, padding: padding)
            #expect(abs(t.tx - 3812) <= 1)
            #expect(abs(t.ty - 2954) <= 1)
        }
        @Test("middleLeft")
        func middleLeft() {
            let t = WatermarkPosition.middleLeft.translation(watermarkExtent: watermarkExtent, baseExtent: baseExtent, padding: padding)
            #expect(abs(t.tx - 20) <= 1)
            #expect(abs(t.ty - 1487) <= 1)
        }
        @Test("center")
        func center() {
            let t = WatermarkPosition.center.translation(watermarkExtent: watermarkExtent, baseExtent: baseExtent, padding: padding)
            #expect(abs(t.tx - 1916) <= 1)
            #expect(abs(t.ty - 1487) <= 1)
        }
        @Test("middleRight")
        func middleRight() {
            let t = WatermarkPosition.middleRight.translation(watermarkExtent: watermarkExtent, baseExtent: baseExtent, padding: padding)
            #expect(abs(t.tx - 3812) <= 1)
            #expect(abs(t.ty - 1487) <= 1)
        }
        @Test("bottomLeft")
        func bottomLeft() {
            let t = WatermarkPosition.bottomLeft.translation(watermarkExtent: watermarkExtent, baseExtent: baseExtent, padding: padding)
            #expect(abs(t.tx - 20) <= 1)
            #expect(abs(t.ty - 20) <= 1)
        }
        @Test("bottomCenter")
        func bottomCenter() {
            let t = WatermarkPosition.bottomCenter.translation(watermarkExtent: watermarkExtent, baseExtent: baseExtent, padding: padding)
            #expect(abs(t.tx - 1916) <= 1)
            #expect(abs(t.ty - 20) <= 1)
        }
        @Test("bottomRight")
        func bottomRight() {
            let t = WatermarkPosition.bottomRight.translation(watermarkExtent: watermarkExtent, baseExtent: baseExtent, padding: padding)
            #expect(abs(t.tx - 3812) <= 1)
            #expect(abs(t.ty - 20) <= 1)
        }
    }

    // MARK: - Portrait (3024×4032)

    @Suite("Portrait 3024×4032 — watermark 200×50, padding 20")
    struct Portrait {
        let baseExtent = CGRect(x: 0, y: 0, width: 3024, height: 4032)
        let watermarkExtent = CGRect(x: 0, y: 0, width: 200, height: 50)
        let padding: CGFloat = 20

        @Test("topLeft")
        func topLeft() {
            let t = WatermarkPosition.topLeft.translation(watermarkExtent: watermarkExtent, baseExtent: baseExtent, padding: padding)
            #expect(abs(t.tx - 20) <= 1)
            #expect(abs(t.ty - 3962) <= 1)
        }
        @Test("topCenter")
        func topCenter() {
            let t = WatermarkPosition.topCenter.translation(watermarkExtent: watermarkExtent, baseExtent: baseExtent, padding: padding)
            #expect(abs(t.tx - 1412) <= 1)
            #expect(abs(t.ty - 3962) <= 1)
        }
        @Test("topRight")
        func topRight() {
            let t = WatermarkPosition.topRight.translation(watermarkExtent: watermarkExtent, baseExtent: baseExtent, padding: padding)
            #expect(abs(t.tx - 2804) <= 1)
            #expect(abs(t.ty - 3962) <= 1)
        }
        @Test("middleLeft")
        func middleLeft() {
            let t = WatermarkPosition.middleLeft.translation(watermarkExtent: watermarkExtent, baseExtent: baseExtent, padding: padding)
            #expect(abs(t.tx - 20) <= 1)
            #expect(abs(t.ty - 1991) <= 1)
        }
        @Test("center")
        func center() {
            let t = WatermarkPosition.center.translation(watermarkExtent: watermarkExtent, baseExtent: baseExtent, padding: padding)
            #expect(abs(t.tx - 1412) <= 1)
            #expect(abs(t.ty - 1991) <= 1)
        }
        @Test("middleRight")
        func middleRight() {
            let t = WatermarkPosition.middleRight.translation(watermarkExtent: watermarkExtent, baseExtent: baseExtent, padding: padding)
            #expect(abs(t.tx - 2804) <= 1)
            #expect(abs(t.ty - 1991) <= 1)
        }
        @Test("bottomLeft")
        func bottomLeft() {
            let t = WatermarkPosition.bottomLeft.translation(watermarkExtent: watermarkExtent, baseExtent: baseExtent, padding: padding)
            #expect(abs(t.tx - 20) <= 1)
            #expect(abs(t.ty - 20) <= 1)
        }
        @Test("bottomCenter")
        func bottomCenter() {
            let t = WatermarkPosition.bottomCenter.translation(watermarkExtent: watermarkExtent, baseExtent: baseExtent, padding: padding)
            #expect(abs(t.tx - 1412) <= 1)
            #expect(abs(t.ty - 20) <= 1)
        }
        @Test("bottomRight")
        func bottomRight() {
            let t = WatermarkPosition.bottomRight.translation(watermarkExtent: watermarkExtent, baseExtent: baseExtent, padding: padding)
            #expect(abs(t.tx - 2804) <= 1)
            #expect(abs(t.ty - 20) <= 1)
        }
    }

    // MARK: - Square (1000×1000)

    @Suite("Square 1000×1000 — watermark 200×50, padding 20")
    struct Square {
        let baseExtent = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        let watermarkExtent = CGRect(x: 0, y: 0, width: 200, height: 50)
        let padding: CGFloat = 20

        @Test("topLeft")
        func topLeft() {
            let t = WatermarkPosition.topLeft.translation(watermarkExtent: watermarkExtent, baseExtent: baseExtent, padding: padding)
            #expect(abs(t.tx - 20) <= 1)
            #expect(abs(t.ty - 930) <= 1)
        }
        @Test("topCenter")
        func topCenter() {
            let t = WatermarkPosition.topCenter.translation(watermarkExtent: watermarkExtent, baseExtent: baseExtent, padding: padding)
            #expect(abs(t.tx - 400) <= 1)
            #expect(abs(t.ty - 930) <= 1)
        }
        @Test("topRight")
        func topRight() {
            let t = WatermarkPosition.topRight.translation(watermarkExtent: watermarkExtent, baseExtent: baseExtent, padding: padding)
            #expect(abs(t.tx - 780) <= 1)
            #expect(abs(t.ty - 930) <= 1)
        }
        @Test("middleLeft")
        func middleLeft() {
            let t = WatermarkPosition.middleLeft.translation(watermarkExtent: watermarkExtent, baseExtent: baseExtent, padding: padding)
            #expect(abs(t.tx - 20) <= 1)
            #expect(abs(t.ty - 475) <= 1)
        }
        @Test("center")
        func center() {
            let t = WatermarkPosition.center.translation(watermarkExtent: watermarkExtent, baseExtent: baseExtent, padding: padding)
            #expect(abs(t.tx - 400) <= 1)
            #expect(abs(t.ty - 475) <= 1)
        }
        @Test("middleRight")
        func middleRight() {
            let t = WatermarkPosition.middleRight.translation(watermarkExtent: watermarkExtent, baseExtent: baseExtent, padding: padding)
            #expect(abs(t.tx - 780) <= 1)
            #expect(abs(t.ty - 475) <= 1)
        }
        @Test("bottomLeft")
        func bottomLeft() {
            let t = WatermarkPosition.bottomLeft.translation(watermarkExtent: watermarkExtent, baseExtent: baseExtent, padding: padding)
            #expect(abs(t.tx - 20) <= 1)
            #expect(abs(t.ty - 20) <= 1)
        }
        @Test("bottomCenter")
        func bottomCenter() {
            let t = WatermarkPosition.bottomCenter.translation(watermarkExtent: watermarkExtent, baseExtent: baseExtent, padding: padding)
            #expect(abs(t.tx - 400) <= 1)
            #expect(abs(t.ty - 20) <= 1)
        }
        @Test("bottomRight")
        func bottomRight() {
            let t = WatermarkPosition.bottomRight.translation(watermarkExtent: watermarkExtent, baseExtent: baseExtent, padding: padding)
            #expect(abs(t.tx - 780) <= 1)
            #expect(abs(t.ty - 20) <= 1)
        }
    }

    // MARK: - Edge cases: padding

    @Suite("Padding edge cases")
    struct PaddingEdgeCases {
        let baseExtent = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        let watermarkExtent = CGRect(x: 0, y: 0, width: 200, height: 50)

        @Test("padding = 0")
        func paddingZero() {
            let t = WatermarkPosition.bottomLeft.translation(watermarkExtent: watermarkExtent, baseExtent: baseExtent, padding: 0)
            #expect(t.tx == 0)
            #expect(t.ty == 0)
        }

        @Test("padding = 0 at topLeft")
        func paddingZeroTopLeft() {
            let t = WatermarkPosition.topLeft.translation(watermarkExtent: watermarkExtent, baseExtent: baseExtent, padding: 0)
            #expect(t.tx == 0)
            #expect(abs(t.ty - 950) <= 1)  // height - watermarkHeight
        }

        @Test("large padding should still compute valid translation")
        func largePadding() {
            // Padding larger than base image should not crash — caller handles clamping.
            // For bottomRight: x = width - w - padding → negative (offscreen left)
            //                  y = padding → exceeds height (offscreen above)
            let t = WatermarkPosition.bottomRight.translation(watermarkExtent: watermarkExtent, baseExtent: baseExtent, padding: 2000)
            #expect(t.tx < 0)                         // offscreen left
            #expect(t.ty > baseExtent.height)          // offscreen above (CIImage bottom-left: +Y = up)
        }
    }

    // MARK: - All 9 cases present

    @Test("WatermarkPosition has exactly 9 preset cases")
    func allNineCasesPresent() {
        #expect(WatermarkPosition.allCases.count == 9)
    }

    // MARK: - Custom (dragged) placement

    @Suite("Custom placement 1000×800 — watermark 200×100")
    struct Custom {
        let baseExtent = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let watermarkExtent = CGRect(x: 0, y: 0, width: 200, height: 100)

        private func translation(_ x: CGFloat, _ y: CGFloat) -> CGAffineTransform {
            WatermarkPosition.custom(x: x, y: y).translation(
                watermarkExtent: watermarkExtent, baseExtent: baseExtent, padding: 20)
        }

        @Test("(0,0) sits flush against the top-left corner")
        func topLeftCorner() {
            let t = translation(0, 0)
            #expect(t.tx == 0)
            #expect(t.ty == 700)   // CIImage y-up: base height - watermark height
        }

        @Test("(1,1) sits flush against the bottom-right corner")
        func bottomRightCorner() {
            let t = translation(1, 1)
            #expect(t.tx == 800)
            #expect(t.ty == 0)
        }

        @Test("(0.5,0.5) matches the centre preset")
        func centre() {
            let t = translation(0.5, 0.5)
            let preset = WatermarkPosition.center.translation(
                watermarkExtent: watermarkExtent, baseExtent: baseExtent, padding: 20)
            #expect(abs(t.tx - preset.tx) <= 0.001)
            #expect(abs(t.ty - preset.ty) <= 0.001)
        }

        @Test("out-of-range fractions keep the element inside the image")
        func staysInBounds() {
            for (fx, fy) in [(-5.0, -5.0), (7.0, 7.0), (2.0, -1.0)] {
                let t = translation(CGFloat(fx), CGFloat(fy))
                #expect(t.tx >= 0)
                #expect(t.ty >= 0)
                #expect(t.tx + watermarkExtent.width <= baseExtent.width)
                #expect(t.ty + watermarkExtent.height <= baseExtent.height)
            }
        }

        @Test("an element larger than the image is pinned, not pushed off")
        func oversizedElement() {
            let t = WatermarkPosition.custom(x: 1, y: 0).translation(
                watermarkExtent: CGRect(x: 0, y: 0, width: 2000, height: 1600),
                baseExtent: baseExtent,
                padding: 20
            )
            #expect(t.tx == 0)
            #expect(t.ty == 0)
        }

        @Test("round-trips through its raw value, presets keep their old keys")
        func rawValueRoundTrip() {
            #expect(WatermarkPosition.bottomRight.rawValue == "bottomRight")
            #expect(WatermarkPosition(rawValue: "topLeft") == .topLeft)
            #expect(WatermarkPosition(rawValue: "nonsense") == nil)

            let custom = WatermarkPosition.custom(x: 0.25, y: 0.75)
            let decoded = WatermarkPosition(rawValue: custom.rawValue)
            #expect(decoded == custom)
        }

        /// Saved configs and templates hold the old string form, so the JSON
        /// shape must not change for presets.
        @Test("encodes as a plain string, as the String-backed enum did")
        func codableCompatibility() throws {
            let positions: [WatermarkPosition] = [.bottomLeft, .custom(x: 0.25, y: 0.75)]
            let json = try JSONEncoder().encode(positions)
            #expect(String(data: json, encoding: .utf8) == "[\"bottomLeft\",\"custom:0.2500,0.7500\"]")
            #expect(try JSONDecoder().decode([WatermarkPosition].self, from: json) == positions)
        }
    }

    // MARK: - Reading placement back out of a render

    @Suite("RenderLayout")
    struct Layout {
        @Test("a layer flush in the photo's top-left reads as (0,0)")
        func topLeftFraction() {
            // Photo matted into the middle 80% of the output (white frame).
            let layout = RenderLayout(
                photoRect: CGRect(x: 0, y: 0.1, width: 1, height: 0.8),
                layerFrames: [0: CGRect(x: 0, y: 0.1, width: 0.2, height: 0.1)]
            )
            #expect(layout.travelFraction(ofLayer: 0) == CGPoint(x: 0, y: 0))
        }

        @Test("a layer flush bottom-right reads as (1,1)")
        func bottomRightFraction() {
            let layout = RenderLayout(
                photoRect: CGRect(x: 0, y: 0, width: 1, height: 1),
                layerFrames: [0: CGRect(x: 0.8, y: 0.9, width: 0.2, height: 0.1)]
            )
            #expect(layout.travelFraction(ofLayer: 0) == CGPoint(x: 1, y: 1))
        }

        @Test("a layer that wasn't rendered has no fraction")
        func missingLayer() {
            let layout = RenderLayout(photoRect: .zero, layerFrames: [:])
            #expect(layout.travelFraction(ofLayer: 0) == nil)
        }

        @Test("switching to Custom doesn't move the element")
        func asCustomKeepsPlacement() {
            let layout = RenderLayout(
                photoRect: CGRect(x: 0, y: 0.1, width: 1, height: 0.8),
                layerFrames: [0: CGRect(x: 0, y: 0.1, width: 0.2, height: 0.1)]
            )
            #expect(WatermarkPosition.topLeft.asCustom(in: layout, layerIndex: 0) == .custom(x: 0, y: 0))
            // No render yet — fall back to the preset's nominal corner.
            #expect(WatermarkPosition.bottomRight.asCustom(in: nil, layerIndex: 0) == .custom(x: 1, y: 1))
            // Already custom: left exactly as it is.
            let dragged = WatermarkPosition.custom(x: 0.3, y: 0.6)
            #expect(dragged.asCustom(in: layout, layerIndex: 0) == dragged)
        }
    }

    // MARK: - Auto-placement of new elements

    @Suite("nextFreePosition")
    struct NextFreePosition {
        private func text(_ body: String, at position: WatermarkPosition) -> WatermarkLayer {
            .text(
                TextWatermarkInput(text: body, fontSize: 48, color: CGColor(gray: 1, alpha: 1)),
                position: position, scale: 0.05, opacity: 1.0, isVisible: true
            )
        }

        @Test("first element lands bottom-right")
        func firstElement() {
            #expect(WatermarkConfiguration().nextFreePosition == .bottomRight)
        }

        @Test("a second element avoids the first")
        func avoidsOccupied() {
            let config = WatermarkConfiguration(watermarks: [text("©", at: .bottomRight)])
            #expect(config.nextFreePosition == .bottomLeft)
        }

        /// Regression: new text layers start empty, so skipping them piled the
        /// 3rd and 4th element onto the same corner as the 2nd.
        @Test("a text layer with nothing typed in it yet still holds its spot")
        func emptyPlaceholderHoldsItsSpot() {
            var config = WatermarkConfiguration(watermarks: [text("", at: .bottomRight)])
            for expected in [WatermarkPosition.bottomLeft, .topRight, .topLeft] {
                #expect(config.nextFreePosition == expected)
                config.watermarks.append(text("", at: expected))
            }
        }

        @Test("hidden layers reserve nothing")
        func ignoresHiddenLayers() {
            let hidden = WatermarkLayer.text(
                TextWatermarkInput(text: "hi", fontSize: 48, color: CGColor(gray: 1, alpha: 1)),
                position: .bottomRight, scale: 0.05, opacity: 1.0, isVisible: false
            )
            #expect(WatermarkConfiguration(watermarks: [hidden]).nextFreePosition == .bottomRight)
        }

        @Test("past nine elements it keeps cycling instead of stacking")
        func cyclesWhenFull() {
            let all = WatermarkPosition.allCases.map { text("x", at: $0) }
            let config = WatermarkConfiguration(watermarks: all)
            #expect(config.nextFreePosition == .bottomRight)
            var plusOne = config
            plusOne.watermarks.append(text("x", at: .bottomRight))
            #expect(plusOne.nextFreePosition == .bottomLeft)
        }

        @Test("dragged elements block no preset")
        func customBlocksNothing() {
            let config = WatermarkConfiguration(
                watermarks: [text("©", at: .custom(x: 0.9, y: 0.9))])
            #expect(config.nextFreePosition == .bottomRight)
        }
    }
}
