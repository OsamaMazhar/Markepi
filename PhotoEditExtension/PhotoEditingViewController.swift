import UIKit
import SwiftUI
import PhotosUI
import WatermarkCore

/// UIKit entry point for the Photo Editing extension.
///
/// Implements `PHContentEditingController` to integrate with the iOS Photos app
/// edit flow. Hosts SwiftUI `PhotosExtensionRootView` via `UIHostingController`,
/// following the same pattern as `ShareViewController` (D-01).
///
/// Lifecycle:
///   1. `canHandle(_:)` — Determines if this extension can edit a given
///      `PHAdjustmentData` (D-09)
///   2. `startContentEditing(with:placeholderImage:)` — Receives the source
///      media and presents the full watermarking UI (D-02)
///   3. `finishContentEditing(completionHandler:)` — Renders full-res output
///      and commits edit to Photos with `PHAdjustmentData` (D-02)
///   4. `cancelContentEditing()` — Cancels editing and resets state
class PhotoEditingViewController: UIViewController, PHContentEditingController {

    // MARK: - Properties

    /// ViewModel managing watermark configuration, preview generation,
    /// and the render-and-commit pipeline.
    private let viewModel = PhotosExtensionViewModel()

    /// Hosting controller for the SwiftUI watermarking UI.
    private var hostingController: UIHostingController<PhotosExtensionRootView<PhotosExtensionViewModel>>?

    // MARK: - PHContentEditingController

    /// Returns whether this extension can handle the given adjustment data.
    ///
    /// Delegates to the ViewModel which validates the `formatIdentifier`
    /// and `formatVersion` against our known constants (D-09).
    func canHandle(_ adjustmentData: PHAdjustmentData) -> Bool {
        return viewModel.canHandle(adjustmentData)
    }

    /// Presents the watermarking UI and loads the source media.
    ///
    /// Receives the `PHContentEditingInput` containing the source media URL
    /// and the `placeholderImage` for initial display. Delegates loading
    /// to the ViewModel, then sets up the SwiftUI hosting controller (D-02).
    func startContentEditing(with contentEditingInput: PHContentEditingInput,
                             placeholderImage: UIImage) {
        viewModel.startEditing(with: contentEditingInput, placeholderImage: placeholderImage)
        setupHostingController()
    }

    /// Renders the watermarked output and commits the edit to Photos.
    ///
    /// The ViewModel renders at full resolution via `WatermarkEngine.process()`,
    /// creates a `PHContentEditingOutput` with `PHAdjustmentData`, and calls
    /// the completion handler with the output (D-02).
    func finishContentEditing(completionHandler: @escaping (PHContentEditingOutput?) -> Void) {
        viewModel.finishEditing(completionHandler: completionHandler)
    }

    /// Cancels the current editing session.
    ///
    /// Delegates to the ViewModel to reset state. The Photos framework dismisses
    /// the extension after this returns.
    func cancelContentEditing() {
        viewModel.cancelEditing()
    }

    /// Whether to show a "Discard Changes?" confirmation before canceling.
    ///
    /// Returns `true` when the user has made configuration changes, preventing
    /// accidental dismissal (Pitfall 5).
    var shouldShowCancelConfirmation: Bool {
        return viewModel.hasUnsavedChanges
    }

    // MARK: - Hosting Controller Setup

    /// Creates and constrains the SwiftUI hosting controller to fill the view.
    ///
    /// Follows the exact pattern from `ShareViewController.setupHostingController()`
    /// (lines 32-45): add child → add subview → disable autoresizing mask →
    /// activate 4-edge constraints.
    private func setupHostingController() {
        let rootView = PhotosExtensionRootView(viewModel: viewModel)
        let host = UIHostingController(rootView: rootView)
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        hostingController = host
    }
}
