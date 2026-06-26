import SwiftUI
import UIKit

extension Notification.Name {
    static let didReceiveQuickAction = Notification.Name("didReceiveQuickAction")
}

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }
}

class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let shortcutItem = connectionOptions.shortcutItem {
            handleShortcut(shortcutItem)
        }
    }

    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        handleShortcut(shortcutItem)
        completionHandler(true)
    }

    private func handleShortcut(_ item: UIApplicationShortcutItem) {
        NotificationCenter.default.post(name: .didReceiveQuickAction, object: item.type)
    }
}

@main
struct WatermarkApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var viewModel = WatermarkViewModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                // This is a media-focused editor on a permanently dark canvas
                // (HIG: media apps may adopt a permanent dark appearance). Lock
                // the dark scheme so semantic colors (.primary/.secondary)
                // resolve light and stay legible on the black surfaces — without
                // this, `.primary` text renders black-on-black and vanishes.
                .preferredColorScheme(.dark)
                .onOpenURL { url in
                    // The Share Extension hands media off via `watermark://shared`,
                    // staging it in the App Group inbox. Everything else is a
                    // file/template open routed through the file importer.
                    if url.scheme == "watermark" {
                        viewModel.importPendingShares()
                    } else {
                        viewModel.handleIncomingFile(url: url)
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    // Fallback drain: if the URL open didn't fire (or the app was
                    // already foregrounded), pick up any shares on activation.
                    if phase == .active {
                        viewModel.importPendingShares()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .didReceiveQuickAction)) { notif in
                    guard let type = notif.object as? String else { return }
                    viewModel.handleQuickAction(type)
                }
        }
    }
}
