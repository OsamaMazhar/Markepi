#if os(iOS)
import Testing
import SwiftUI
import UIKit
@testable import WatermarkCore

// MARK: - SnapshotTestViewModel Infrastructure Tests

@MainActor
@Suite("SnapshotTestViewModel")
struct SnapshotTestViewModelTests {

    @Test("SnapshotTestViewModel conforms to WatermarkConfigurable & Observable")
    func conformsToProtocol() {
        let vm = SnapshotTestViewModel()
        let configurable: any WatermarkConfigurable = vm
        #expect(Bool(true))
        _ = configurable
    }

    @Test("SnapshotTestViewModel has exactly 2 watermark layers pre-populated")
    func hasTwoWatermarkLayers() {
        let vm = SnapshotTestViewModel()
        #expect(vm.config.watermarks.count == 2)
    }

    @Test("SnapshotTestViewModel has text watermark at bottomRight with 'Sample Watermark'")
    func textWatermarkAtBottomRight() {
        let vm = SnapshotTestViewModel()
        guard vm.config.watermarks.count >= 1 else {
            #expect(Bool(false), "Expected at least 1 watermark layer, got \(vm.config.watermarks.count)")
            return
        }
        if case .text(let input, let position, let scale, let opacity, _) = vm.config.watermarks[0] {
            #expect(input.text == "Sample Watermark")
            #expect(position == .bottomRight)
            #expect(scale == 0.15)
            #expect(opacity == 1.0)
        } else {
            #expect(Bool(false), "First watermark should be text type")
        }
    }

    @Test("SnapshotTestViewModel has image watermark at bottomRight")
    func imageWatermarkAtBottomRight() {
        let vm = SnapshotTestViewModel()
        guard vm.config.watermarks.count >= 2 else {
            #expect(Bool(false), "Expected at least 2 watermark layers, got \(vm.config.watermarks.count)")
            return
        }
        if case .image(_, let position, let scale, let opacity, _) = vm.config.watermarks[1] {
            #expect(position == .bottomRight)
            #expect(scale == 0.15)
            #expect(opacity == 1.0)
        } else {
            #expect(Bool(false), "Second watermark should be image type")
        }
    }

    @Test("SnapshotTestViewModel has whiteFrame enabled")
    func whiteFrameEnabled() {
        let vm = SnapshotTestViewModel()
        #expect(vm.whiteFrameEnabled == true)
        #expect(vm.config.whiteFrame?.isEnabled == true)
    }

    @Test("SnapshotTestViewModel default renderingState is idle")
    func defaultRenderingStateIsIdle() {
        let vm = SnapshotTestViewModel()
        #expect(vm.renderingState == .idle)
    }

    @Test("SnapshotTestViewModel renderingState is settable to .done")
    func renderingStateSettableToDone() {
        let vm = SnapshotTestViewModel()
        vm.renderingState = .done
        #expect(vm.renderingState == .done)
    }
}

// MARK: - SnapshotRenderer Tests

@MainActor
@Suite("SnapshotRenderer")
struct SnapshotRendererTests {

    @Test("render() produces non-nil PNG Data for simple Text view")
    func rendersSimpleTextView() throws {
        let view = Text("hello")
        let data = try SnapshotRenderer.render(view, size: CGSize(width: 100, height: 50), scale: 1.0)
        #expect(data.count > 100, "PNG data should be larger than header size")
    }

    @Test("render() with inNavigationController produces valid PNG Data")
    func rendersInNavigationController() throws {
        let view = Text("hello")
        let data = try SnapshotRenderer.render(
            view,
            size: CGSize(width: 100, height: 50),
            scale: 1.0,
            inNavigationController: true
        )
        #expect(data.count > 100, "PNG data should be larger than header size")
    }

    @Test("SnapshotError.renderingFailed exists as an Error")
    func renderingFailedErrorExists() {
        let error = SnapshotRenderer.SnapshotError.renderingFailed
        #expect(error is Error)
    }
}

// MARK: - Pixel Comparator Tests

@MainActor
@Suite("SnapshotComparator")
struct SnapshotComparatorTests {

    @Test("compare returns true when comparing a PNG against itself")
    func identicalByteMatch() throws {
        let data = try SnapshotRenderer.render(
            Color.green, size: CGSize(width: 60, height: 60), scale: 2.0)
        // Ensure data is valid and loadable
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let _ = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            #expect(Bool(false), "CGImageSource should parse rendered PNG")
            return
        }
        let result = SnapshotRenderer.compare(actual: data, reference: data)
        #expect(result == true, "Identical PNG data must compare true")
    }

    @Test("compare returns false for different-sized images")
    func differentSizesReturnFalse() throws {
        let data1 = try SnapshotRenderer.render(Color.red, size: CGSize(width: 50, height: 50), scale: 1.0)
        let data2 = try SnapshotRenderer.render(Color.red, size: CGSize(width: 100, height: 100), scale: 1.0)
        // Different dimensions → guard fails → returns false
        let result = SnapshotRenderer.compare(actual: data1, reference: data2)
        #expect(result == false, "Different-sized images must not match")
    }

    @Test("compare returns false for views with clearly different content")
    func differentContentReturnsFalse() throws {
        // Use views that render markedly different content at large size
        let data1 = try SnapshotRenderer.render(
            Text("Hello").font(.system(size: 48)).foregroundStyle(.red),
            size: CGSize(width: 200, height: 100), scale: 2.0)
        let data2 = try SnapshotRenderer.render(
            Text("World").font(.system(size: 48)).foregroundStyle(.blue),
            size: CGSize(width: 200, height: 100), scale: 2.0)
        let result = SnapshotRenderer.compare(actual: data1, reference: data2, pixelTolerance: 0.30)
        #expect(result == false, "Large text with different words/colors should differ in >30% of pixels")
    }

    @Test("compare applies tolerance — same view renders pass at high tolerance")
    func toleranceApplied() throws {
        let data1 = try SnapshotRenderer.render(Color.blue, size: CGSize(width: 50, height: 50), scale: 2.0)
        let data2 = try SnapshotRenderer.render(Color.blue, size: CGSize(width: 50, height: 50), scale: 2.0)
        // At 100% tolerance, any pair of same-size images passes
        let result = SnapshotRenderer.compare(actual: data1, reference: data2, pixelTolerance: 1.0)
        #expect(result == true, "100% tolerance must accept any same-size pair")
    }
}
#endif
