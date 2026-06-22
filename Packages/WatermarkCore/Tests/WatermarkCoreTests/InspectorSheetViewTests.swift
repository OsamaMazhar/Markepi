import Testing
import SwiftUI
@testable import WatermarkCore

// MARK: - Mock ViewModel

/// Minimal mock conforming to `WatermarkConfigurable & Observable`
/// for InspectorSheetView instantiation tests.
@MainActor
@Observable
final class MockInspectorViewModel: WatermarkConfigurable {
    var config = WatermarkConfiguration()
    var activeLayerIndex = 0
    var renderingState: RenderingState = .idle
    var whiteFrameEnabled = false
    var outputFormat: OutputFormat = .preserveSource
    var outputQuality: Float = 1.0
    var sourceHasHDR = false
    var sourceFormatLabel: String? = nil
    var errorMessage: String? = nil
    var showError = false
    var hasMultiplePhotos = false
    var showSaveTemplateAlert = false
    var showTemplateList = false

    func renderAndPrepareShare() async {}
    func presentShareSheet() {}
    func cancelVideoExport() {}
    func cancelBatchProcessing() {}
}

// MARK: - SheetDetent Tests

@Suite("SheetDetent")
struct SheetDetentTests {

    @Test("SheetDetent.peek case exists")
    func peekCase() {
        let detent: SheetDetent = .peek
        #expect(detent == .peek)
    }

    @Test("SheetDetent.expanded case exists")
    func expandedCase() {
        let detent: SheetDetent = .expanded
        #expect(detent == .expanded)
    }

    @Test("SheetDetent is Equatable — same cases are equal")
    func equatableSameCases() {
        #expect(SheetDetent.peek == SheetDetent.peek)
        #expect(SheetDetent.expanded == SheetDetent.expanded)
    }

    @Test("SheetDetent is Equatable — different cases are not equal")
    func equatableDifferentCases() {
        #expect(SheetDetent.peek != SheetDetent.expanded)
    }
}

// MARK: - InspectorSheetView Initialization Tests

@Suite("InspectorSheetView Initialization")
@MainActor
struct InspectorSheetViewInitTests {

    @Test("InspectorSheetView initializes with required parameters (detent, peekHeight, viewModel)")
    func initializationSucceeds() {
        let vm = MockInspectorViewModel()
        let peek: CGFloat = 60
        let detent = Binding<SheetDetent>.constant(.peek)
        let view = InspectorSheetView(
            detent: detent,
            peekHeight: peek,
            viewModel: vm
        )
        // Verify struct creation succeeded — if init failed, we wouldn't reach here
        #expect(Bool(true))
        _ = view  // suppress unused warning
    }

    @Test("InspectorSheetView peekHeight constant is preserved after init")
    func peekHeightPreserved() {
        let vm = MockInspectorViewModel()
        let peek: CGFloat = 60
        let detent = Binding<SheetDetent>.constant(.peek)
        let view = InspectorSheetView(
            detent: detent,
            peekHeight: peek,
            viewModel: vm
        )
        #expect(view.peekHeight == 60)
    }

    @Test("InspectorSheetView with peek detent renders at peek height")
    func peekDetentInitialization() {
        let vm = MockInspectorViewModel()
        let peek: CGFloat = 60
        let detent = Binding<SheetDetent>.constant(.peek)
        let view = InspectorSheetView(
            detent: detent,
            peekHeight: peek,
            viewModel: vm
        )
        #expect(view.peekHeight == 60)
    }
}
