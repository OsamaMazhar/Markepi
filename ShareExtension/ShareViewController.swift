import UIKit
import SwiftUI
import WatermarkCore

/// UIKit entry point for the share extension.
///
/// Hosts the SwiftUI `ShareExtensionRootView` via `UIHostingController`,
/// following the standard iOS pattern for custom share extension UIs
/// (RESEARCH.md Pattern 4).
///
/// On `viewDidLoad`, sets up the hosting controller and begins loading
/// the shared media from the first `NSItemProvider` in the extension context.
/// After the share sheet dismisses, calls `completeRequest` to close the
/// extension (D-07 one-shot workflow).
class ShareViewController: UIViewController {

    // MARK: - Properties

    private let viewModel = ShareExtensionViewModel()
    private var hostingController: UIHostingController<ShareExtensionRootView>?

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupHostingController()
        setupDismissHandler()
        Task { await loadSharedMedia() }
    }

    // MARK: - Hosting Controller Setup

    private func setupHostingController() {
        let rootView = ShareExtensionRootView(viewModel: viewModel)
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

    // MARK: - Dismiss Handler

    /// Sets the `completeRequest` closure on the ViewModel so it can close
    /// the extension after the share sheet dismisses (D-07 one-shot).
    /// Also sets `openURL` for URL scheme fallback (D-16).
    private func setupDismissHandler() {
        viewModel.completeRequest = { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
        viewModel.openURL = { [weak self] url in
            self?.extensionContext?.open(url, completionHandler: nil)
        }
    }

    // MARK: - Media Loading

    /// Collects ALL `NSItemProvider`s from the extension context's input items,
    /// sets them on the ViewModel for sequential processing, and loads the first item.
    private func loadSharedMedia() async {
        guard let extensionContext = extensionContext else { return }

        // Collect ALL providers from all input items (D-14: multi-item sequential)
        let allProviders = extensionContext.inputItems
            .compactMap { $0 as? NSExtensionItem }
            .flatMap { $0.attachments ?? [] }

        guard !allProviders.isEmpty else {
            viewModel.isLoadingMedia = false
            return
        }

        viewModel.sharedItems = allProviders
        viewModel.currentItemIndex = 0

        // Load the first item
        await viewModel.loadSharedMedia(from: allProviders[0])
    }
}