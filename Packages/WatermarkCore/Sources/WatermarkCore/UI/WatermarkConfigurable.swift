// iOS-only UI. Guarded so WatermarkCore also builds for macOS, where the
// `markepi` CLI target links the engine without the SwiftUI layer.
#if canImport(UIKit)
import CoreImage
import Foundation
import SwiftUI

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
    /// Default implementation returns false — the Share Extension ViewModel
    /// processes single items by design.
    var hasMultiplePhotos: Bool { get }

    /// Number of currently loaded batch items that can receive C2PA signing in
    /// this build. Defaults to zero for single-item surfaces and extensions.
    var batchSignableImageCount: Int { get }

    /// Number of currently loaded batch videos. C2PA signing is image-only in
    /// this build, so videos export without a C2PA signature.
    var batchVideoCount: Int { get }

    // Template Management (Phase 12)
    var showSaveTemplateAlert: Bool { get set }
    var showTemplateList: Bool { get set }

    func addLogoLayer(pngData: Data)
    func addSignatureLayer(strokeData: Data, inkColor: CGColor, strokeWidth: CGFloat)
    func removeLayer(at index: Int)
    func updateLayerPosition(at index: Int, position: WatermarkPosition)
    func updateLayerScale(at index: Int, scale: CGFloat)
    func updateLayerRotation(at index: Int, degrees: CGFloat)
    func setLayerOpacity(at index: Int, opacity: CGFloat)
    func setLayerVisibility(at index: Int, isVisible: Bool)
    func beginInteractiveConfigChange()
    func endInteractiveConfigChange()
    func moveLayer(from source: Int, to destination: Int)
    func updateSignature(at index: Int, inkColor: CGColor?, strokeWidth: CGFloat?)
    func toggleWhiteFrame()

    /// Triggers full-resolution rendering.
    /// Both ViewModels implement this with the same signature.
    func renderAndPrepareShare() async

    /// Records that the user accepted image-only C2PA signing for a mixed
    /// batch. Default no-op for single-item surfaces and extensions.
    func acknowledgeBatchC2PAImageOnlyNotice()

    /// Presents the share sheet (sets internal showShareSheet flag).
    func presentShareSheet()

    /// Where the photo and each layer landed in the last rendered preview.
    /// Nil until a preview exists — position pickers fall back to nominal
    /// placement, and dragging is disabled. Runtime-only, never persisted.
    var previewLayout: RenderLayout? { get }

    /// The analyzer's verdict for the currently-loaded source.
    /// Runtime-only — NOT persisted in config. Default nil.
    var sourceProvenanceReport: SourceProvenanceReport? { get }

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
        config.watermarks.append(
            .image(input, position: config.nextFreePosition, scale: 0.15, opacity: 1.0, isVisible: true))
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

    /// Sets the clockwise rotation (in degrees) of the image/logo layer at
    /// `index`. No-op for non-image layers — only logos are rotatable. The
    /// degree value is normalized to [0, 360) by `ImageWatermarkInput`.
    public func updateLayerRotation(at index: Int, degrees: CGFloat) {
        guard config.watermarks.indices.contains(index),
              case let .image(input, position, scale, opacity, isVisible) = config.watermarks[index] else { return }
        let updated = input.withRotationDegrees(degrees)
        config.watermarks[index] = .image(updated, position: position, scale: scale, opacity: opacity, isVisible: isVisible)
    }

    /// Sets the per-layer compositing opacity (0–1) of the layer at `index`.
    public func setLayerOpacity(at index: Int, opacity: CGFloat) {
        guard config.watermarks.indices.contains(index) else { return }
        config.watermarks[index] = config.watermarks[index].withOpacity(opacity)
    }

    /// Shows or hides the layer at `index` without removing it.
    public func setLayerVisibility(at index: Int, isVisible: Bool) {
        guard config.watermarks.indices.contains(index) else { return }
        config.watermarks[index] = config.watermarks[index].withVisibility(isVisible)
    }

    /// Called by high-frequency controls such as sliders before/after a drag.
    /// View models can defer expensive persistence while still applying live
    /// model changes for preview. Default no-op keeps simple conformers cheap.
    public func beginInteractiveConfigChange() {}

    public func endInteractiveConfigChange() {}

    /// Reorders the layer stack, keeping `activeLayerIndex` pointed at the moved
    /// layer. Index 0 is the bottom of the stack; the last index is the top.
    public func moveLayer(from source: Int, to destination: Int) {
        guard config.watermarks.indices.contains(source) else { return }
        let clampedDest = min(max(destination, 0), config.watermarks.count - 1)
        guard source != clampedDest else { return }
        let layer = config.watermarks.remove(at: source)
        config.watermarks.insert(layer, at: clampedDest)
        activeLayerIndex = clampedDest
    }

    /// Updates the ink color and/or stroke width of the signature layer at
    /// `index`, leaving the captured stroke geometry untouched. Stroke width is
    /// applied as a live render-time multiplier by `SignatureRenderer`, so the
    /// preview reflects thick/thin changes immediately.
    public func updateSignature(at index: Int, inkColor: CGColor? = nil, strokeWidth: CGFloat? = nil) {
        guard config.watermarks.indices.contains(index),
              case let .signature(input, position, scale, opacity, isVisible) = config.watermarks[index] else { return }
        let updated = SignatureInput(
            strokeData: input.strokeData,
            inkColor: inkColor ?? input.inkColor,
            strokeWidth: strokeWidth.map { min(max($0, 1), 12) } ?? input.strokeWidth
        )
        config.watermarks[index] = .signature(updated, position: position, scale: scale, opacity: opacity, isVisible: isVisible)
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

    /// Default no-op — only the main app ViewModel tracks batch C2PA notices.
    public func acknowledgeBatchC2PAImageOnlyNotice() {}

    /// Default no-op — only the main app ViewModel (WatermarkViewModel)
    /// implements batch processing. The Share Extension ViewModel uses this
    /// default, which safely does nothing.
    public func cancelBatchProcessing() {}

    /// Default no-op — only the main app ViewModel (WatermarkViewModel)
    /// implements unified cancel. The Share Extension ViewModel uses this
    /// default, which safely does nothing.
    public func cancelProcessing() {}

    /// Default returns false — the Share Extension ViewModel processes single
    /// items by design.
    public var hasMultiplePhotos: Bool { false }

    /// Default returns zero — only the main app batch ViewModel exposes counts.
    public var batchSignableImageCount: Int { 0 }

    /// Default returns zero — only the main app batch ViewModel exposes counts.
    public var batchVideoCount: Int { 0 }

    /// Default returns nil — ViewModels override with stored properties.
    public var sourceProvenanceReport: SourceProvenanceReport? { nil }

    /// Default returns nil — only surfaces with a live preview provide it.
    public var previewLayout: RenderLayout? { nil }
}
#endif
