import UIKit
import SwiftUI
import UniformTypeIdentifiers
import os.log
import WatermarkCore

#if DEBUG
private let shareLog = Logger(subsystem: "com.osamamazhar.markepi", category: "ShareExtension")
#endif

/// UIKit entry point for the share extension.
///
/// Markepi's share extension is a thin **handoff** bridge: it copies the shared
/// photo(s)/video(s) into the App Group `PendingShares` inbox, then opens the
/// main app via the `watermark://shared` URL scheme. The app drains the inbox
/// and loads everything into the full editor.
///
/// This gives the share flow exact feature + design parity with the app (it *is*
/// the app), and avoids the ~120MB extension memory ceiling that made the old
/// in-extension rendering fragile (it would stall on "Preparing photo…").
class ShareViewController: UIViewController {

    private let hostingController = UIHostingController(rootView: ShareHandoffView())

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        embedHandoffView()
        Task { await handoffAndOpenApp() }
    }

    // MARK: - UI

    private func embedHandoffView() {
        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        hostingController.didMove(toParent: self)
    }

    // MARK: - Handoff

    /// Copies every shared item into the App Group inbox, then opens the main app
    /// and closes the extension.
    private func handoffAndOpenApp() async {
        let providers = (extensionContext?.inputItems ?? [])
            .compactMap { $0 as? NSExtensionItem }
            .flatMap { $0.attachments ?? [] }

        #if DEBUG
        shareLog.info("Handoff start: \(providers.count, privacy: .public) provider(s)")
        #endif
        for provider in providers {
            await saveToInbox(provider)
        }
        #if DEBUG
        shareLog.info("Handoff done; opening main app")
        #endif

        openMainApp()
    }

    /// Writes a single provider's media into the shared inbox, preserving the
    /// original file (and thus its format, quality, and metadata).
    ///
    /// Uses `loadFileRepresentation` (not in-memory `Data`) so large videos and
    /// HEIC photos stay on disk — critical under the extension memory ceiling.
    private func saveToInbox(_ provider: NSItemProvider) async {
        // Check video first — some movie containers also conform to public.image.
        let typeID: String
        if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
            typeID = UTType.movie.identifier
        } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            typeID = UTType.image.identifier
        } else {
            #if DEBUG
            shareLog.error("Provider has no image/movie representation; registered types: \(provider.registeredTypeIdentifiers, privacy: .public)")
            #endif
            return
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            provider.loadFileRepresentation(forTypeIdentifier: typeID) { url, error in
                // The provided URL is ephemeral — copy into the App Group inbox now.
                if let url = url {
                    if SharedInboxStore.copy(from: url) == nil {
                        #if DEBUG
                        shareLog.error("loadFileRepresentation gave a URL but inbox copy failed")
                        #endif
                    }
                } else {
                    #if DEBUG
                    shareLog.error("loadFileRepresentation returned no URL: \(error?.localizedDescription ?? "nil", privacy: .public)")
                    #endif
                }
                continuation.resume()
            }
        }
    }

    /// Opens the main app via its custom URL scheme so it can drain the inbox,
    /// then completes the extension request once the open is dispatched.
    private func openMainApp() {
        guard let url = URL(string: "watermark://shared") else {
            extensionContext?.completeRequest(returningItems: nil)
            return
        }
        extensionContext?.open(url) { [weak self] success in
            if !success {
                self?.openViaResponderChain(url)
            }
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }

    /// Fallback when `NSExtensionContext.open` is unavailable: walk the responder
    /// chain to find `UIApplication` and ask it to open the URL.
    private func openViaResponderChain(_ url: URL) {
        var responder: UIResponder? = self
        while let current = responder {
            if let app = current as? UIApplication {
                app.open(url, options: [:], completionHandler: nil)
                return
            }
            responder = current.next
        }
    }
}

/// Minimal "Opening Markepi…" view shown briefly while the extension copies the
/// shared media and launches the app.
private struct ShareHandoffView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Opening Markepi…")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}
