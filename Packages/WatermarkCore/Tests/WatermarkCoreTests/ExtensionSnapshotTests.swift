import Testing
import SwiftUI
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

    @Test("compare returns true for identical images")
    func identicalImagesReturnTrue() throws {
        let view = Text("test")
        let data1 = try SnapshotRenderer.render(view, size: CGSize(width: 50, height: 50), scale: 1.0)
        let data2 = try SnapshotRenderer.render(view, size: CGSize(width: 50, height: 50), scale: 1.0)
        let result = SnapshotRenderer.compare(actual: data1, reference: data2)
        #expect(result == true, "Identical view renders should match within default 2% tolerance")
    }

    @Test("compare returns true when difference below 2% tolerance threshold")
    func similarImagesWithinTolerance() throws {
        let view = Text("tolerance test")
        let data1 = try SnapshotRenderer.render(view, size: CGSize(width: 100, height: 40), scale: 1.0)
        let data2 = try SnapshotRenderer.render(view, size: CGSize(width: 100, height: 40), scale: 1.0)
        let result = SnapshotRenderer.compare(actual: data1, reference: data2, pixelTolerance: 0.02)
        #expect(result == true, "Two renders of same view should be within 2% tolerance")
    }

    @Test("compare returns false when images differ significantly")
    func differentImagesReturnFalse() throws {
        let view1 = Text("AAAAA").font(.title).foregroundStyle(.blue)
        let view2 = Text("BBBBB").font(.title).foregroundStyle(.red)
        let data1 = try SnapshotRenderer.render(view1, size: CGSize(width: 100, height: 50), scale: 1.0)
        let data2 = try SnapshotRenderer.render(view2, size: CGSize(width: 100, height: 50), scale: 1.0)
        let result = SnapshotRenderer.compare(actual: data1, reference: data2, pixelTolerance: 0.02)
        #expect(result == false, "Views with different text and color should differ more than 2%")
    }
}
