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
}
