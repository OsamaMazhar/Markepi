#if os(iOS)
import Foundation
import UIKit

/// Protocol capturing the rendering surface required by `ShareExtensionRootView`.
///
/// Extends `WatermarkConfigurable` with the view-model properties and methods
/// that the share extension root view accesses directly. Conforming types
/// include `ShareExtensionViewModel` (production) and `SnapshotTestViewModel`
/// (test-only, for XCTest snapshot tests).
///
/// All conforming types must be `@Observable` classes (required for `@State`
/// observation in the root view).
@MainActor
public protocol ShareExtensionRendering: WatermarkConfigurable {
    /// Watermarked preview image displayed in the preview area.
    var previewImage: UIImage? { get set }

    /// Whether the source media is a video.
    var isVideo: Bool { get set }

    /// True while media is loading (shows loading spinner).
    var isLoadingMedia: Bool { get set }

    /// Whether this is a multi-item share (>1 item).
    var isMultiItem: Bool { get set }

    /// Index of the current item being processed (0-based).
    var currentItemIndex: Int { get set }

    /// Total number of items to process.
    var totalItemCount: Int { get set }

    /// Human-readable multi-item progress label (e.g., "Item 3 of 5").
    var multiItemProgress: String { get set }

    /// Whether to show the HDR warning banner.
    var showHDRWarning: Bool { get set }

    /// Detailed HDR warning text.
    var hdrWarningMessage: String? { get set }

    /// Whether to show the audio mismatch warning banner.
    var showAudioWarning: Bool { get set }

    /// File URL of the source media (from NSItemProvider or PHContentEditingInput).
    var sourceURL: URL? { get set }

    /// Identifier for triggering preview generation via `.task(id:)`.
    var previewIdentifier: String { get set }

    /// When true, presents the UIActivityViewController share sheet.
    var showShareSheet: Bool { get set }

    /// Result of the full-resolution render (contains output file URL).
    var fullResResult: ProcessingResult? { get set }

    /// When true, presents the unsupported file type alert.
    var unsupportedType: Bool { get set }

    /// Closure set by ShareViewController to complete the extension request.
    var completeRequest: (() -> Void)? { get set }

    /// Dismisses the share sheet and completes the extension request.
    func handleShareDismiss()

    /// Generates a watermarked preview image.
    func generatePreview() async

    /// Processes the next item in a multi-item batch.
    func processNextItem() async

    /// Opens the main Watermark app from the extension.
    func openInMainApp()
}

/// Protocol capturing the rendering surface required by `PhotosExtensionRootView`.
///
/// Extends `WatermarkConfigurable` with the view-model properties and methods
/// that the Photos extension root view accesses directly. Uses an associated
/// type for the `finishEditing` callback to avoid importing `Photos` framework
/// into WatermarkCore (production VM uses `PHContentEditingOutput`, test VM
/// uses `Any`).
///
/// All conforming types must be `@Observable` classes.
@MainActor
public protocol PhotosExtensionRendering: WatermarkConfigurable {
    /// The type of the completion handler parameter for `finishEditing`.
    /// `PhotosExtensionViewModel` uses `PHContentEditingOutput?`.
    /// `SnapshotTestViewModel` uses `Any?` (test stub).
    associatedtype FinishOutput

    /// Watermarked preview image displayed in the preview area.
    var previewImage: UIImage? { get set }

    /// Whether the source media is a video.
    var isVideo: Bool { get set }

    /// True while media is loading (shows loading spinner).
    var isLoadingMedia: Bool { get set }

    /// Whether to show the HDR warning banner.
    var showHDRWarning: Bool { get set }

    /// Detailed HDR warning text.
    var hdrWarningMessage: String? { get set }

    /// File URL of the source media (from PHContentEditingInput).
    var sourceURL: URL? { get set }

    /// Identifier for triggering preview generation via `.task(id:)`.
    var previewIdentifier: String { get set }

    /// Completes editing in the Photos extension. Called by the "Done"
    /// toolbar button in PhotosExtensionRootView.
    ///
    /// - Parameter completionHandler: Called with the editing output when done.
    ///   The root view passes `{ _ in }` (parameter ignored).
    func finishEditing(completionHandler: @escaping (FinishOutput?) -> Void)

    /// Generates a watermarked preview image.
    func generatePreview() async
}
#endif
