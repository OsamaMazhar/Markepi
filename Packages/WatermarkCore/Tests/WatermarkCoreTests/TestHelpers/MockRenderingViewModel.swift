// Exercises the iOS-only SwiftUI layer, which is behind `canImport(UIKit)`
// in the sources. Guarded to match so the test target still builds for
// macOS, where `swift test` and the `markepi` CLI run.
#if canImport(UIKit)
import Foundation
import SwiftUI
import WatermarkCore

/// Minimal mock ViewModel conforming to `WatermarkConfigurable & Observable`
/// for testing `ShareActionButton` rendering states.
///
/// Records method calls for verification in tests (spy pattern).
@MainActor
@Observable
final class MockRenderingViewModel: WatermarkConfigurable {
    var config: WatermarkConfiguration = WatermarkConfiguration()
    var activeLayerIndex: Int = 0
    var renderingState: RenderingState = .idle
    var errorMessage: String? = nil
    var showError: Bool = false
    var showSaveTemplateAlert: Bool = false
    var showTemplateList: Bool = false
    var hasMultiplePhotos: Bool = false
    var sourceHasHDR: Bool = false
    var sourceFormatLabel: String? = nil

    // Spy callbacks for verifying protocol method invocations
    var renderAndPrepareShareCallCount = 0
    var presentShareSheetCallCount = 0
    var cancelProcessingCallCount = 0
    var cancelVideoExportCallCount = 0
    var cancelBatchProcessingCallCount = 0

    func renderAndPrepareShare() async {
        renderAndPrepareShareCallCount += 1
    }

    func presentShareSheet() {
        presentShareSheetCallCount += 1
    }

    func cancelProcessing() {
        cancelProcessingCallCount += 1
    }

    func cancelVideoExport() {
        cancelVideoExportCallCount += 1
    }

    func cancelBatchProcessing() {
        cancelBatchProcessingCallCount += 1
    }
}
#endif
