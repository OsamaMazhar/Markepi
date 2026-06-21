import Foundation
import Observation
import SwiftUI
import WatermarkCore

/// Lightweight @Observable proxy that conforms to WatermarkConfigurable
/// and wraps a single WatermarkConfiguration for in-sheet editing by the
/// existing sub-views (TextWatermarkInputView, inline position Menu,
/// ScaleStepperView, WhiteFrameToggleView).
///
/// Used by BatchItemDetailSheet to scope watermark controls to a single
/// item's per-item configuration override, without affecting the shared
/// batch configuration.
@MainActor
@Observable
final class BatchItemConfigProxy: WatermarkConfigurable {
    var config: WatermarkConfiguration {
        didSet { onConfigChanged?(config) }
    }
    var activeLayerIndex: Int = 0
    var renderingState: RenderingState = .idle
    var showSaveTemplateAlert: Bool = false
    var showTemplateList: Bool = false
    var errorMessage: String? = nil
    var showError: Bool = false
    var sourceHasHDR: Bool = false
    var sourceFormatLabel: String? = nil

    /// Called whenever `config` is mutated via any sub-view binding.
    var onConfigChanged: ((WatermarkConfiguration) -> Void)?

    init(config: WatermarkConfiguration) {
        self.config = config
    }

    func renderAndPrepareShare() async {}
    func presentShareSheet() {}
    func cancelVideoExport() {}
    func cancelProcessing() {}

    func applyTemplate(_ template: Template) {
        config = template.config
    }
}
