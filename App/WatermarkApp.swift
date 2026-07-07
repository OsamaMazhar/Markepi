import SwiftUI
import UIKit
import WatermarkCore

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
    /// Single StoreKit source of truth. Created once here, injected into the
    /// environment, and kept in sync with the App Group premium cache that the
    /// export gate and Share Extension read.
    @State private var storeManager = StoreManager()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appearancePreference") private var appearancePreference: String = AppearancePreference.system.rawValue
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    #if DEBUG
    /// Developer test flag (Settings → Developer). When on, onboarding replays on
    /// every launch. Compiled out of App Store builds entirely.
    @AppStorage("debugAlwaysShowOnboarding") private var debugAlwaysShowOnboarding = false
    #endif

    /// Cold-launch splash gate. `@State` re-initialises to `true` on every fresh
    /// app process, so the animation plays once per launch and never again for
    /// the life of that process. It is a *sibling overlay*, never a wrapper — the
    /// real UI is built underneath it from the first frame so app init runs
    /// concurrently with the animation and is never blocked by it.
    @State private var showLaunchAnimation = true

    private var appearance: AppearancePreference {
        AppearancePreference(rawValue: appearancePreference) ?? .system
    }

    var body: some Scene {
        WindowGroup {
            // The real UI is the ZStack's base layer — it is created and laid out
            // immediately, in parallel with the splash overlaid on top. The splash
            // is a peer view, not a gate, so launch work is never serialised behind
            // the animation.
            ZStack {
                Group {
                    if hasCompletedOnboarding {
                        ContentView(viewModel: viewModel)
                            .environment(storeManager)
                            .onOpenURL { url in
                                if url.scheme == "watermark" {
                                    viewModel.importPendingShares()
                                } else {
                                    viewModel.handleIncomingFile(url: url)
                                }
                            }
                            .onChange(of: scenePhase) { _, phase in
                                if phase == .active {
                                    viewModel.importPendingShares()
                                }
                            }
                            .onReceive(NotificationCenter.default.publisher(for: .didReceiveQuickAction)) { notif in
                                guard let type = notif.object as? String else { return }
                                viewModel.handleQuickAction(type)
                            }
                    } else {
                        OnboardingView()
                            .environment(storeManager)
                    }
                }

                if showLaunchAnimation {
                    LaunchAnimationView {
                        // The overlay hands control back here after its entrance +
                        // hold; the parent owns the fade-out via `.transition`.
                        withAnimation(.easeInOut(duration: 0.35)) {
                            showLaunchAnimation = false
                        }
                    }
                    .transition(.opacity)
                    .zIndex(1)
                }
            }
            .preferredColorScheme(appearance.colorScheme)
            .task {
                #if DEBUG
                // Developer test flag: replay onboarding on every launch. Reset
                // the completion flag once at launch (under the splash) so the
                // normal gate shows onboarding; skipping still drops into the app
                // — and Settings — so the flag can be turned back off.
                if debugAlwaysShowOnboarding { hasCompletedOnboarding = false }
                #endif
            }
        }
    }
}

// MARK: - Onboarding

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var currentPage = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// iPad gets larger base type so onboarding reads at a comfortable distance
    /// on the bigger display. Drives *content density* only — the editor layout
    /// still responds to the window container, not the device idiom.
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    // Adaptive point sizes. `@ScaledMetric` keeps Dynamic Type working while the
    // base bumps up on iPad for legibility at arm's length.
    @ScaledMetric private var heroTitleSize: CGFloat = UIDevice.current.userInterfaceIdiom == .pad ? 46 : 33
    @ScaledMetric private var sectionTitleSize: CGFloat = UIDevice.current.userInterfaceIdiom == .pad ? 32 : 25
    @ScaledMetric private var bodySize: CGFloat = UIDevice.current.userInterfaceIdiom == .pad ? 20 : 17
    @ScaledMetric private var featureTitleSize: CGFloat = UIDevice.current.userInterfaceIdiom == .pad ? 20 : 17
    @ScaledMetric private var featureBodySize: CGFloat = UIDevice.current.userInterfaceIdiom == .pad ? 17 : 15
    @ScaledMetric private var glyphCircleSize: CGFloat = UIDevice.current.userInterfaceIdiom == .pad ? 140 : 120

    private var contentMaxWidth: CGFloat { isPad ? 720 : 640 }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Colorful aurora backdrop shared by the welcome + features pages,
                // matching the paywall's palette (full-bleed here). The paywall
                // page (tag 2) paints its own opaque base on top, so it keeps its
                // own top-fade treatment.
                MarkepiColors.canvasBackground.ignoresSafeArea()
                AuroraBackground(reduceMotion: reduceMotion, fade: false)

                TabView(selection: $currentPage) {
                    welcomePage.tag(0)
                    featuresPage(height: geo.size.height).tag(1)
                    // Page 3 is the purchase view, with its own aurora + "Skip".
                    purchasePage.tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                // Pages are transparent so the shared aurora shows through 1 & 2.
                // Skip lives ONLY on the final purchase page (PaywallView's own
                // top-right "Skip"); the welcome/features pages have none.
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: currentPage)
    }

    // MARK: - Page 1: Welcome

    private var welcomePage: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: MarkepiSpacing.xxl) {
                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: glyphCircleSize, height: glyphCircleSize)
                    .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
                    .accessibilityLabel("Markepi")

                VStack(spacing: MarkepiSpacing.sm) {
                    Text("Markepi")
                        .font(.system(size: heroTitleSize, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Add your watermark. Share instantly.\nNo camera roll clutter.")
                        .font(.system(size: bodySize))
                        .foregroundStyle(.white.opacity(0.82))
                        .multilineTextAlignment(.center)
                }
                .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
            }

            Spacer()
        }
        .frame(maxWidth: contentMaxWidth)
        .padding(.horizontal, MarkepiSpacing.xxxl)
        .padding(.bottom, MarkepiSpacing.xxxl)
    }

    // MARK: - Page 2: Features

    private func featuresPage(height: CGFloat) -> some View {
        // A borderless, Apple-style feature list sitting directly on the aurora —
        // no enclosing card. The whole title + list block is vertically centered
        // by the Spacers; the outer `minHeight: height` fills the viewport so the
        // Spacers have room to work, and lets the list scroll only if it ever
        // overflows (very large Dynamic Type / short devices).
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                // Flexible spacers top and bottom keep the title + list as one
                // tight unit, centered vertically in the viewport.
                Spacer(minLength: MarkepiSpacing.xl)

                Text("Everything You Need")
                    .font(.system(size: sectionTitleSize, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, MarkepiSpacing.xxxl)

                VStack(alignment: .leading, spacing: isPad ? MarkepiSpacing.xxl : MarkepiSpacing.xl) {
                    featureRow(
                        icon: "signature",
                        title: "Signature Watermark",
                        description: "Add your text, logo, or signature to photos and videos."
                    )
                    featureRow(
                        icon: "checkmark.seal",
                        title: "Content Credentials (C2PA)",
                        description: "Sign your photos with tamper-evident C2PA Content Credentials that prove they haven't been changed."
                    )
                    featureRow(
                        icon: "square.dashed",
                        title: "White Frame",
                        description: "Add a clean frame with an optional device-metadata caption."
                    )
                    featureRow(
                        icon: "lock.shield",
                        title: "Rights & Privacy",
                        description: "Embed creator, copyright, and credit — or strip GPS before you share."
                    )
                    featureRow(
                        icon: "rectangle.3.group",
                        title: "Placement Control",
                        description: "Place your watermark anywhere — 8 anchors plus manual scale."
                    )
                    featureRow(
                        icon: "square.stack.3d.up",
                        title: "Batch & Templates",
                        description: "Watermark many at once and save reusable one-tap templates."
                    )
                }

                Spacer(minLength: MarkepiSpacing.xl)
            }
            .frame(maxWidth: contentMaxWidth)
            .frame(maxWidth: .infinity, minHeight: height)
            .padding(.horizontal, MarkepiSpacing.xxxl)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func featureRow(icon: String, title: String, description: String) -> some View {
        // Icon chip is top-aligned to the title so multi-line rows read as a clean
        // list. A frosted glass chip (rather than a flat tint) gives the glyph a
        // defined surface to sit on directly over the aurora.
        HStack(alignment: .top, spacing: MarkepiSpacing.lg) {
            featureIconBadge(icon)

            VStack(alignment: .leading, spacing: MarkepiSpacing.xs) {
                Text(title)
                    .font(.system(size: featureTitleSize, weight: .semibold))
                    .foregroundStyle(.white)
                Text(description)
                    .font(.system(size: featureBodySize))
                    .foregroundStyle(.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .shadow(color: .black.opacity(0.22), radius: 6, y: 1)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Frosted glass icon chip for a feature row — a defined surface for the
    /// neutral glyph so it stays legible directly over the aurora.
    private func featureIconBadge(_ icon: String) -> some View {
        let side: CGFloat = isPad ? 54 : 46
        return RoundedRectangle(cornerRadius: MarkepiRadius.lg, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: MarkepiRadius.lg, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
            }
            .overlay {
                Image(systemName: icon)
                    .font(.system(size: side * 0.44, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.22), radius: 3, y: 1)
            }
            .frame(width: side, height: side)
            .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
    }

    // MARK: - Page 3: Purchase

    /// The final onboarding page is the purchase view. Its own "Skip" toolbar
    /// button (top-right) exits to the main app, so this page renders the full
    /// paywall rather than a custom hero.
    private var purchasePage: some View {
        PaywallView(onSkip: { hasCompletedOnboarding = true })
    }
}
