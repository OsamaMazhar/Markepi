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
            // Padding larger than base image should not crash — caller handles clamping
            let t = WatermarkPosition.bottomRight.translation(watermarkExtent: watermarkExtent, baseExtent: baseExtent, padding: 2000)
            #expect(t.tx < 0)    // pushed offscreen — expected, caller clamps
            #expect(t.ty < 0)
        }
    }

    // MARK: - All 9 cases present

    @Test("WatermarkPosition has exactly 9 cases")
    func allNineCasesPresent() {
        #expect(WatermarkPosition.allCases.count == 9)
    }
}
