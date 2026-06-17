import UIKit
import SwiftUI

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
    private func setupDismissHandler() {
        viewModel.completeRequest = { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }

    // MARK: - Media Loading

    /// Extracts the first `NSItemProvider` from the extension context's
    /// input items and delegates loading to the ViewModel.
    private func loadSharedMedia() async {
        guard let extensionContext = extensionContext else { return }

        // Provide the extension context to the ViewModel for URL scheme fallback
        viewModel.extensionContext = extensionContext

        guard let inputItem = extensionContext.inputItems.first as? NSExtensionItem,
              let provider = inputItem.attachments?.first else {
            viewModel.isLoadingMedia = false
            return
        }

        await viewModel.loadSharedMedia(from: provider)
    }
}