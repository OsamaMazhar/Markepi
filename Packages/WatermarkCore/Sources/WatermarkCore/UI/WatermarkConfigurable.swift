import CoreImage
import Foundation
import SwiftUI
import WatermarkCore

/// Protocol abstracting the watermark configuration and layer management
/// interface shared by both `WatermarkViewModel` (main app) and
/// `ShareExtensionViewModel` (share extension).
///
/// Enables the `ControlsView` and its sub-views to work with any conforming
/// ViewModel, eliminating code duplication between app and extension.
///
/// Conforming types must be `@Observable` classes. Both ViewModels already
/// implement all protocol requirements — this is a pure protocol conformance
/// addition.
@MainActor
public protocol WatermarkConfigurable: AnyObject {
    var config: WatermarkConfiguration { get set }
    var activeLayerIndex: Int { get set }
    var renderingState: RenderingState { get }
    var whiteFrameEnabled: Bool { get }
    var outputFormat: OutputFormat { get set }
    var outputQuality: Float { get set }
    var sourceHasHDR: Bool { get }
    var sourceFormatLabel: String? { get }
    var errorMessage: String? { get set }
    var showError: Bool { get set }

    /// Returns true when the ViewModel has more than one photo loaded.
    /// Used by ControlsView to gate batch-mode UI (Watermark All, batch progress).
    /// Default implementation returns false — share/Photos extension ViewModels
    /// process single items by design.
    var hasMultiplePhotos: Bool { get }

    // Template Management (Phase 12)
    var showSaveTemplateAlert: Bool { get set }
    var showTemplateList: Bool { get set }

    func addLogoLayer(pngData: Data)
    func addSignatureLayer(strokeData: Data, inkColor: CGColor, strokeWidth: CGFloat)
    func removeLayer(at index: Int)
    func updateLayerPosition(at index: Int, position: WatermarkPosition)
    func updateLayerScale(at index: Int, scale: CGFloat)
    func toggleWhiteFrame()

    /// Triggers full-resolution rendering.
    /// Both ViewModels implement this with the same signature.
    func renderAndPrepareShare() async

    /// Presents the share sheet (sets internal showShareSheet flag).
    func presentShareSheet()

    /// Cancels an in-progress video export.
    /// Called by ControlsView's Cancel button during .renderingVideo state.
    /// The ViewModel cancels the export task and cleans up the incomplete temp file.
    func cancelVideoExport()

    /// Cancels an in-progress batch processing operation.
    /// Called by ControlsView's Cancel button during .batchProcessing state.
    /// The ViewModel cancels the batch task and cleans up incomplete temp files.
    func cancelBatchProcessing()

    /// Cancels the active processing operation (video export or batch processing).
    /// Unified cancel entry point for ControlsView buttons. Default implementation
    /// is empty — WatermarkViewModel overrides with type-aware routing.
    func cancelProcessing()

    /// Applies a template's configuration to the current state.
    /// Called from TemplateListView when a row is tapped.
    func applyTemplate(_ template: Template)
}

// MARK: - Default Implementations

extension WatermarkConfigurable {

    // MARK: Layer Management

    public func addLogoLayer(pngData: Data) {
        guard let _ = CIImage(data: pngData) else {
            errorMessage = "The selected image is not a valid PNG file."
            showError = true
            return
        }
        guard let input = try? ImageWatermarkInput(pngData: pngData) else {
            errorMessage = "The selected image is not a valid PNG file."
            showError = true
            return
        }
        config.watermarks.append(.image(input, position: .bottomRight, scale: 0.15, opacity: 1.0, isVisible: true))
        activeLayerIndex = config.watermarks.count - 1
    }

    public func addSignatureLayer(strokeData: Data, inkColor: CGColor, strokeWidth: CGFloat) {
        // Default: no-op. Overridden by WatermarkViewModel with PencilKit implementation.
    }

    public func removeLayer(at index: Int) {
        guard index >= 0, index < config.watermarks.count else { return }
        config.watermarks.remove(at: index)
        if activeLayerIndex >= config.watermarks.count {
            activeLayerIndex = max(0, config.watermarks.count - 1)
        }
    }

    public func updateLayerPosition(at index: Int, position: WatermarkPosition) {
        guard index >= 0, index < config.watermarks.count else { return }
        let scale = config.watermarks[index].scale
        switch config.watermarks[index] {
        case .text(let input, _, _, let opacity, let isVisible):
            config.watermarks[index] = .text(input, position: position, scale: scale, opacity: opacity, isVisible: isVisible)
        case .image(let input, _, _, let opacity, let isVisible):
            config.watermarks[index] = .image(input, position: position, scale: scale, opacity: opacity, isVisible: isVisible)
        case .signature(let input, _, _, let opacity, let isVisible):
            config.watermarks[index] = .signature(input, position: position, scale: scale, opacity: opacity, isVisible: isVisible)
        }
    }

    public func updateLayerScale(at index: Int, scale scaleInput: CGFloat) {
        guard index >= 0, index < config.watermarks.count else { return }
        let clamped = min(max(scaleInput, 0.01), 0.90)
        let position = config.watermarks[index].position
        switch config.watermarks[index] {
        case .text(let input, _, _, let opacity, let isVisible):
            config.watermarks[index] = .text(input, position: position, scale: clamped, opacity: opacity, isVisible: isVisible)
        case .image(let input, _, _, let opacity, let isVisible):
            config.watermarks[index] = .image(input, position: position, scale: clamped, opacity: opacity, isVisible: isVisible)
        case .signature(let input, _, _, let opacity, let isVisible):
            config.watermarks[index] = .signature(input, position: position, scale: clamped, opacity: opacity, isVisible: isVisible)
        }
    }

    // MARK: White Frame

    public func toggleWhiteFrame() {
        setWhiteFrameEnabled(!whiteFrameEnabled)
    }

    /// Sets the white frame to an explicit on/off state.
    ///
    /// Prefer this over `toggleWhiteFrame()` when driving a `Toggle`: it is
    /// idempotent, so a stray or duplicated `set` call from SwiftUI cannot leave
    /// the frame stuck on (the bug where the frame could be enabled but not
    /// disabled). Enabling preserves any existing frame configuration.
    public func setWhiteFrameEnabled(_ enabled: Bool) {
        if enabled {
            if config.whiteFrame == nil {
                config.whiteFrame = WhiteFrameConfig(isEnabled: true)
            } else {
                config.whiteFrame?.isEnabled = true
            }
        } else {
            config.whiteFrame = nil
        }
    }

    public var whiteFrameEnabled: Bool {
        config.whiteFrame?.isEnabled ?? false
    }

    // MARK: Export Settings

    public var outputFormat: OutputFormat {
        get { config.outputFormat }
        set { config.outputFormat = newValue }
    }

    public var outputQuality: Float {
        get { config.outputQuality }
        set { config.outputQuality = newValue }
    }

    // MARK: - Template Management (Phase 12)

    public func applyTemplate(_ template: Template) {
        config = template.config
    }

    // MARK: - Batch Processing (Phase 13)

    /// Default no-op — only the main app ViewModel (WatermarkViewModel)
    /// implements batch processing. Share and Photos extension ViewModels
    /// use this default which safely does nothing.
    public func cancelBatchProcessing() {}

    /// Default no-op — only the main app ViewModel (WatermarkViewModel)
    /// implements unified cancel. Share and Photos extension ViewModels
    /// use this default which safely does nothing.
    public func cancelProcessing() {}

    /// Default returns false — share and Photos extension ViewModels
    /// process single items by design.
    public var hasMultiplePhotos: Bool { false }
}
