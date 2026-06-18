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

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .onOpenURL { url in
                    viewModel.handleIncomingFile(url: url)
                }
                .onReceive(NotificationCenter.default.publisher(for: .didReceiveQuickAction)) { notif in
                    guard let type = notif.object as? String else { return }
                    viewModel.handleQuickAction(type)
                }
        }
    }
}
