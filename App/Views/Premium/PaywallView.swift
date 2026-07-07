import SwiftUI
import UIKit
import WatermarkCore

/// Premium upgrade screen ("Markepi Pro").
///
/// The free tier lets people export/share **3 photos or 1 video per day with
/// every feature unlocked**; Premium simply lifts that daily limit. Three plans
/// are offered: a $4.99 one-time unlock, a $2.99/year subscription, or a
/// $0.99/month subscription — all granting the same entitlement.
///
/// **Visual treatment.** An immersive, slowly-drifting `MeshGradient` "aurora"
/// (iOS 18+) sits behind a glowing crown hero, fading into the neutral grouped
/// background so the plan cards and legal copy stay legible in both light and
/// dark appearances. All motion (aurora drift, crown glow, CTA sheen) is frozen
/// when **Reduce Motion** is on. The layout is intentionally compact and **never
/// scrolls** — it reads the available height via `GeometryReader` and tightens
/// spacing/sizes on shorter devices so everything fits on a single page.
///
/// Two presentation modes share this view:
/// - **Sheet** (default, `onSkip == nil`): shown from the editor's crown
///   button; a "✕" closes by dismissing the sheet.
/// - **Onboarding** (`onSkip` set): embedded as the final onboarding page; the
///   close affordance becomes a "Skip" text button that calls `onSkip` to exit
///   to the main app, and extra bottom inset clears the TabView page dots.
///
/// Purchases are driven through `StoreManager` (injected via the environment):
/// `selectedPlan.premiumProduct` resolves to the StoreKit `Product`, and
/// `purchase()` / `restore()` grant the entitlement. Prices come from StoreKit
/// live (`displayPrice`), falling back to `PremiumPlan.price` offline.
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL

    /// StoreKit source of truth, injected from `WatermarkApp`.
    @Environment(StoreManager.self) private var store

    /// Currently highlighted plan. Defaults to the one-time unlock.
    @State private var selectedPlan: PremiumPlan = .lifetime

    /// True while a purchase or restore is in flight (disables the CTA).
    @State private var isWorking = false

    /// Populated to surface a purchase/restore failure or "nothing to restore".
    @State private var infoMessage: String?
    @State private var showInfo = false

    /// Drives the one-shot entrance animation (content fades/rises in).
    @State private var appeared = false

    /// When set, the paywall acts as the final onboarding page: the close
    /// affordance becomes a "Skip" text button (top-right) that calls this
    /// instead of dismissing a sheet. Nil keeps the sheet "✕" + dismiss path.
    var onSkip: (() -> Void)? = nil

    /// iPad gets larger base type so the paywall reads at a comfortable
    /// distance on the bigger display. Drives content density only.
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    // `@ScaledMetric` preserves Dynamic Type while the base bumps up on iPad.
    @ScaledMetric private var titleSize: CGFloat = UIDevice.current.userInterfaceIdiom == .pad ? 32 : 26
    @ScaledMetric private var bodySize: CGFloat = UIDevice.current.userInterfaceIdiom == .pad ? 19 : 16
    @ScaledMetric private var subSize: CGFloat = UIDevice.current.userInterfaceIdiom == .pad ? 17 : 14

    var body: some View {
        NavigationStack {
            GeometryReader { _ in
                let compact = verticalSizeClass == .compact || dynamicTypeSize >= .xxLarge
                let gap: CGFloat = compact ? 14 : 22

                ZStack {
                    // Full-bleed aurora — the same colorful backdrop the onboarding
                    // pages use — so the paywall reads as one cohesive premium
                    // surface instead of a colorful top fading to a flat black half.
                    // Frosted glass cards (below) keep the content legible over it.
                    MarkepiColors.canvasBackground.ignoresSafeArea()
                    AuroraBackground(reduceMotion: reduceMotion, fade: false)

                    VStack(spacing: 0) {
                        header(compact: compact)

                        Spacer(minLength: gap)

                        if store.isPremium {
                            // Already entitled (a real purchase, a restore, or the
                            // DEBUG "Force Premium" override): show what's unlocked
                            // instead of the plans + buy CTA.
                            proBenefitsCard

                            Spacer(minLength: gap)

                            Button {
                                finishUnlocked()
                            } label: {
                                PurchaseCTALabel(title: "Continue",
                                                 isWorking: false,
                                                 reduceMotion: reduceMotion)
                            }
                            .buttonStyle(.plain)
                        } else {
                            freeCard

                            Spacer(minLength: gap)

                            plansSection

                            Spacer(minLength: gap)

                            footer
                        }
                    }
                    .padding(.horizontal, isPad ? 28 : 20)
                    .padding(.top, compact ? 6 : 14)
                    .padding(.bottom, onSkip != nil ? 40 : 12)
                    .frame(maxWidth: isPad ? 720 : 640, maxHeight: .infinity, alignment: .top)
                    // GeometryReader parks content at the top-leading corner, so on
                    // the wide iPad canvas the 720pt column would hug the left edge.
                    // Expand an outer frame to full width (default .center) to seat
                    // the column in the middle of the display.
                    .frame(maxWidth: .infinity)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 14)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            // Let the aurora bleed under the bar; the hero headline supplies context.
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if let onSkip {
                        Button("Skip", action: onSkip)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .accessibilityLabel("Skip and continue to the app")
                    } else {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.white.opacity(0.9), .white.opacity(0.22))
                        }
                        .accessibilityLabel("Close")
                    }
                }
            }
            .onAppear {
                withAnimation(.easeOut(duration: 0.55)) { appeared = true }
            }
        }
        .alert("Markepi Pro", isPresented: $showInfo) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(infoMessage ?? "")
        }
    }

    // MARK: - Header

    private func header(compact: Bool) -> some View {
        let scale: CGFloat = isPad ? 1.15 : 1
        let badge = (compact ? 60 : 80) * scale
        // Copy flips once the user is entitled: the hero becomes a celebratory
        // confirmation rather than a sales pitch.
        let title = store.isPremium ? "You're Markepi Pro" : "Unlock Unlimited Exports"
        let subtitle = store.isPremium
            ? "Thanks for your support — no more daily limits."
            : "Keep every feature — just lift the daily limit."
        return VStack(spacing: compact ? 10 : 14) {
            CrownBadge(size: badge, reduceMotion: reduceMotion,
                       glyphSize: (compact ? 26 : 34) * scale,
                       verified: store.isPremium)
            VStack(spacing: 5) {
                Text(title)
                    .font(.system(size: titleSize * (compact ? 0.82 : 1.0), weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text(subtitle)
                    .font(.system(size: subSize * (compact ? 0.95 : 1.05)))
                    .foregroundStyle(.white.opacity(0.82))
                    .multilineTextAlignment(.center)
            }
            .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, compact ? 2 : 6)
    }

    // MARK: - Free tier card

    private var freeCard: some View {
        HStack(spacing: 14) {
            FeatureIconChip(systemName: "gift.fill")
            VStack(alignment: .leading, spacing: 3) {
                Text("Free every day")
                    .font(.system(size: bodySize, weight: .semibold))
                Text("Share 3 photos or 1 video a day with all features unlocked — fonts, frames, captions, and video.")
                    .font(.system(size: subSize))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .markepiGlassCard()
    }

    // MARK: - Plans

    private var plansSection: some View {
        VStack(spacing: 10) {
            Text("Go unlimited")
                .font(.system(size: subSize * 0.95, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(PremiumPlan.allCases) { plan in
                planCard(plan)
            }
        }
    }

    private func planCard(_ plan: PremiumPlan) -> some View {
        let isSelected = plan == selectedPlan
        return Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
                selectedPlan = plan
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: bodySize * 1.05))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(plan.title)
                            .font(.system(size: bodySize, weight: .semibold))
                            .foregroundStyle(.primary)
                        if let badge = plan.badge {
                            Text(badge)
                                .font(.system(size: subSize * 0.8, weight: .bold))
                                .foregroundStyle(Color.accentColor)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.16), in: Capsule())
                        }
                    }
                    Text(plan.subtitle)
                        .font(.system(size: subSize))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Text(displayPrice(for: plan))
                    .font(.system(size: bodySize, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background {
                RoundedRectangle(cornerRadius: MarkepiRadius.xxl, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay {
                        // Accent wash on the selected plan so it reads as chosen
                        // even before you notice the ring.
                        RoundedRectangle(cornerRadius: MarkepiRadius.xxl, style: .continuous)
                            .fill(Color.accentColor.opacity(isSelected ? 0.14 : 0))
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: MarkepiRadius.xxl, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : Color.white.opacity(0.12),
                                  lineWidth: isSelected ? 2 : 1)
            }
            .shadow(color: isSelected ? Color.accentColor.opacity(0.32) : .black.opacity(0.18),
                    radius: isSelected ? 12 : 10, y: isSelected ? 5 : 6)
            .scaleEffect(isSelected ? 1.0 : 0.985)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    // MARK: - Unlocked state

    /// The "what you get" card shown when the user already holds the entitlement
    /// (a real purchase, a restore, or the DEBUG "Force Premium" toggle). Sits
    /// where the plans normally are, so the screen stays balanced instead of
    /// leaving a void, and reuses the neutral card styling of the rest of the
    /// paywall so it reads in both light and dark.
    private var proBenefitsCard: some View {
        VStack(spacing: 0) {
            proPerk(icon: "infinity",
                    title: "Unlimited exports",
                    detail: "Save and share as many photos and videos as you like — no daily limit.")
            perkDivider
            proPerk(icon: "checkmark.seal",
                    title: "Every feature, always free",
                    detail: "Fonts, frames, captions, signatures, and date stamps are included for everyone — Pro just lifts the export cap.")
            perkDivider
            proPerk(icon: "photo.on.rectangle.angled",
                    title: "Full quality preserved",
                    detail: "Full-resolution photos and videos with all metadata kept intact.")
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .markepiGlassCard()
    }

    private func proPerk(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 14) {
            FeatureIconChip(systemName: icon)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: bodySize, weight: .semibold))
                Text(detail)
                    .font(.system(size: subSize))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var perkDivider: some View {
        Divider()
            .overlay(Color.primary.opacity(0.08))
            .padding(.leading, 74)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 8) {
            Button {
                Task { await purchase() }
            } label: {
                PurchaseCTALabel(title: ctaTitle,
                                 isWorking: isWorking,
                                 reduceMotion: reduceMotion)
            }
            .buttonStyle(.plain)
            .disabled(isWorking)

            // App Review requires an auto-renew disclosure adjacent to the
            // subscription CTA.
            if selectedPlan.premiumProduct.isSubscription {
                Text("Auto-renews until cancelled. Manage or cancel anytime in Settings.")
                    .font(.system(size: subSize * 0.72))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 18) {
                Button("Restore") { Task { await restore() } }
                Button("Terms") { openURL(Self.termsURL) }
                Button("Privacy") { openURL(Self.privacyURL) }
            }
            .font(.caption)
            .foregroundStyle(.white.opacity(0.78))
            .disabled(isWorking)
        }
    }

    // MARK: - Legal

    private static let termsURL = URL(string: "https://www.orbitaar.com/markepi/terms-of-use.html")!
    private static let privacyURL = URL(string: "https://www.orbitaar.com/markepi/privacy-policy.html")!

    // MARK: - Derived UI

    /// Live price when StoreKit has loaded the product; otherwise the static
    /// fallback so the paywall still reads correctly offline / in previews.
    private func displayPrice(for plan: PremiumPlan) -> String {
        store.product(for: plan.premiumProduct)?.displayPrice ?? plan.price
    }

    private var ctaTitle: String {
        selectedPlan.callToAction(price: displayPrice(for: selectedPlan))
    }

    // MARK: - Actions

    /// Resolves the selected plan to its `Product` and drives the StoreKit
    /// purchase through `StoreManager`. On success, dismisses (or advances
    /// onboarding).
    private func purchase() async {
        guard !isWorking else { return }
        isWorking = true
        let outcome = await store.purchase(selectedPlan.premiumProduct)
        isWorking = false

        switch outcome {
        case .success:
            finishUnlocked()
        case .cancelled, .pending:
            break   // Nothing to show; pending is delivered later by the listener.
        case .failed(let message):
            present(message)
        }
    }

    /// Restores previous purchases. Dismisses if a valid entitlement is found,
    /// otherwise tells the user there was nothing to restore.
    private func restore() async {
        guard !isWorking else { return }
        isWorking = true
        await store.restore()
        isWorking = false

        if store.isPremium {
            finishUnlocked()
        } else {
            present("No previous purchases were found for this Apple ID.")
        }
    }

    /// Exits the paywall after a successful unlock — advancing onboarding when
    /// embedded there, or dismissing the sheet otherwise.
    private func finishUnlocked() {
        if let onSkip {
            onSkip()
        } else {
            dismiss()
        }
    }

    private func present(_ message: String) {
        infoMessage = message
        showInfo = true
    }
}

// MARK: - Aurora background

/// A slowly-drifting `MeshGradient` (iOS 18+) that tints the top of the paywall
/// and fades to clear so the neutral background carries the lower content.
///
/// The interior mesh control points orbit on gentle sinusoids driven by
/// `TimelineView(.animation)`; when **Reduce Motion** is on the timeline is
/// dropped and a static mesh is drawn instead. Colours are a fixed indigo /
/// violet / accent "aurora" chosen to be dark enough for white hero text in
/// either appearance.
struct AuroraBackground: View {
    let reduceMotion: Bool
    /// When true (paywall default), the aurora fades out over the top ~55% so
    /// plan cards / legal read on the neutral base. When false (onboarding
    /// welcome/features pages), it stays opaque edge-to-edge for a fully
    /// colorful backdrop.
    var fade: Bool = true

    var body: some View {
        Group {
            if reduceMotion {
                mesh(points: points(at: 0))
            } else {
                TimelineView(.animation) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    mesh(points: points(at: t))
                }
            }
        }
        // Fill the container and bleed into EVERY safe area — including the
        // navigation-bar strip in the paywall. `ignoresSafeArea()` must be the
        // outermost modifier: applying a fixed `.frame` after it re-clips the
        // mesh back to the safe-area box, which (inside the paywall's
        // NavigationStack) left the white `canvasBackground` showing through the
        // top bar in light mode. This mirrors how `canvasBackground` itself
        // fills, so the aurora always covers the same region.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .mask(maskGradient)
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }

    private var maskGradient: LinearGradient {
        if fade {
            return LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: 0.30),
                    .init(color: .clear, location: 0.58)
                ],
                startPoint: .top, endPoint: .bottom
            )
        }
        // Full-bleed: opaque edge-to-edge.
        return LinearGradient(colors: [.black, .black], startPoint: .top, endPoint: .bottom)
    }

    private func mesh(points: [SIMD2<Float>]) -> some View {
        MeshGradient(width: 3, height: 3, points: points, colors: colors)
    }

    private let colors: [Color] = [
        Color(red: 0.36, green: 0.20, blue: 0.62), Color.accentColor,               Color(red: 0.11, green: 0.30, blue: 0.66),
        Color(red: 0.52, green: 0.22, blue: 0.58), Color(red: 0.20, green: 0.16, blue: 0.44), Color(red: 0.16, green: 0.36, blue: 0.70),
        Color(red: 0.10, green: 0.12, blue: 0.32), Color(red: 0.30, green: 0.18, blue: 0.55), Color(red: 0.09, green: 0.20, blue: 0.46)
    ]

    /// Corners stay pinned; the four edge midpoints and the centre drift on
    /// slow, out-of-phase sinusoids for an organic aurora shimmer.
    private func points(at t: TimeInterval) -> [SIMD2<Float>] {
        func wob(_ speed: Double, _ amp: Double, _ phase: Double) -> Float {
            Float(sin(t * speed + phase) * amp)
        }
        return [
            [0.0, 0.0], [0.5 + wob(0.35, 0.14, 0.0), 0.0], [1.0, 0.0],
            [0.0, 0.5 + wob(0.45, 0.10, 1.3)],
            [0.5 + wob(0.55, 0.16, 2.1), 0.5 + wob(0.40, 0.14, 3.4)],
            [1.0, 0.5 + wob(0.50, 0.10, 4.2)],
            [0.0, 1.0], [0.5 + wob(0.38, 0.14, 5.0), 1.0], [1.0, 1.0]
        ]
    }
}

// MARK: - Crown badge

/// The hero crown: a frosted translucent disc with a soft, gently-pulsing glow
/// behind a white `crown.fill`. The pulse is disabled under Reduce Motion.
private struct CrownBadge: View {
    let size: CGFloat
    let reduceMotion: Bool
    let glyphSize: CGFloat
    /// When true, a small check-seal is tucked at the badge's corner to signal
    /// the user is already entitled.
    var verified: Bool = false

    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.16))
                .blur(radius: size * 0.28)
                .frame(width: size * 1.55, height: size * 1.55)
                .scaleEffect(pulse ? 1.08 : 0.94)

            Circle()
                .fill(.white.opacity(0.18))
                .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1))
                .frame(width: size, height: size)

            Image(systemName: "crown.fill")
                .font(.system(size: glyphSize, weight: .semibold))
                .foregroundStyle(.white)
                .symbolRenderingMode(.hierarchical)
                .shadow(color: .black.opacity(0.25), radius: 4, y: 1)
        }
        .frame(width: size, height: size)
        .overlay(alignment: .bottomTrailing) {
            if verified {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: size * 0.32, weight: .bold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.accentColor)
                    .background(Circle().fill(.white).padding(size * 0.05))
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                    .offset(x: size * 0.10, y: size * 0.10)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

// MARK: - Purchase CTA

/// The prominent gradient call-to-action. A soft accent shadow lifts it off the
/// page, and a diagonal highlight sweeps across on a loop (frozen under Reduce
/// Motion) for a premium, tappable feel.
private struct PurchaseCTALabel: View {
    let title: String
    let isWorking: Bool
    let reduceMotion: Bool

    @State private var sweep = false

    private var gradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.accentColor,
                Color.accentColor.opacity(0.88),
                Color(red: 0.42, green: 0.24, blue: 0.72)
            ],
            startPoint: .leading, endPoint: .trailing
        )
    }

    var body: some View {
        ZStack {
            Text(title).opacity(isWorking ? 0 : 1)
            if isWorking { ProgressView().tint(.white) }
        }
        .font(.headline)
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(gradient, in: Capsule())
        .overlay {
            GeometryReader { geo in
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.clear, .white.opacity(0.38), .clear],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .frame(width: geo.size.width * 0.45)
                    .offset(x: sweep ? geo.size.width * 1.1 : -geo.size.width * 0.55)
                    .allowsHitTesting(false)
            }
            .mask(Capsule())
        }
        .clipShape(Capsule())
        .shadow(color: Color.accentColor.opacity(0.42), radius: 14, y: 6)
        .opacity(isWorking ? 0.9 : 1)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 2.6).delay(0.6).repeatForever(autoreverses: false)) {
                sweep = true
            }
        }
    }
}

// MARK: - Models

/// A purchasable premium plan. All three lift the free daily export limit and
/// grant the identical entitlement — the choice is purely billing cadence.
enum PremiumPlan: String, CaseIterable, Identifiable {
    case lifetime
    case annual
    case monthly

    var id: String { rawValue }

    /// The StoreKit product this plan purchases.
    var premiumProduct: PremiumProduct {
        switch self {
        case .lifetime: return .lifetime
        case .annual: return .annual
        case .monthly: return .monthly
        }
    }

    var title: String {
        switch self {
        case .lifetime: return "One-Time Unlock"
        case .annual: return "Annual"
        case .monthly: return "Monthly"
        }
    }

    var subtitle: String {
        switch self {
        case .lifetime: return "Pay once — yours forever"
        case .annual: return "Billed yearly, cancel anytime"
        case .monthly: return "Billed monthly, cancel anytime"
        }
    }

    /// Static fallback price shown only until StoreKit loads live prices
    /// (offline, previews). Live `displayPrice` is preferred at runtime.
    var price: String {
        switch self {
        case .lifetime: return "$4.99"
        case .annual: return "$2.99"
        case .monthly: return "$0.99"
        }
    }

    var badge: String? {
        switch self {
        case .lifetime: return "Best value"
        case .annual: return "Save 75%"   // $2.99/yr vs $0.99/mo ≈ $11.88/yr
        case .monthly: return nil
        }
    }

    /// The primary button label for this plan, using the resolved `price`.
    func callToAction(price: String) -> String {
        switch self {
        case .lifetime: return "Unlock Forever — \(price)"
        case .annual: return "Subscribe — \(price)/year"
        case .monthly: return "Subscribe — \(price)/month"
        }
    }
}

// MARK: - Shared premium surface styling

/// Shared visual language for the premium surfaces — the paywall (`PaywallView`)
/// and the onboarding feature list (`OnboardingView`). Both sit on the same
/// full-bleed aurora, so their cards must read as one system: a frosted "glass
/// card" that floats legibly over the colorful backdrop in either appearance,
/// and an accent icon chip that gives every feature/benefit row the same glyph
/// treatment. Keeping these together is what prevents the two screens from
/// drifting into two different-looking designs.

/// A frosted card surface for content that floats over the aurora.
/// `.regularMaterial` keeps enclosed `.primary`/`.secondary` text legible in
/// both appearances, a hairline white stroke lifts the edge off the gradient,
/// and a soft shadow gives it depth.
struct MarkepiGlassCard: ViewModifier {
    var cornerRadius: CGFloat = MarkepiRadius.xxl

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.regularMaterial)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
    }
}

extension View {
    /// Wraps the view in the shared frosted glass card used across the premium
    /// surfaces. See ``MarkepiGlassCard``.
    func markepiGlassCard(cornerRadius: CGFloat = MarkepiRadius.xxl) -> some View {
        modifier(MarkepiGlassCard(cornerRadius: cornerRadius))
    }
}

/// The accent rounded-square chip that holds a feature/benefit row's SF Symbol.
/// A fixed square keeps every row's glyph in an identical box, which vertically
/// aligns the titles and descriptions down the list.
struct FeatureIconChip: View {
    let systemName: String
    var size: CGFloat = 44

    var body: some View {
        RoundedRectangle(cornerRadius: MarkepiRadius.md, style: .continuous)
            .fill(Color.accentColor.opacity(0.16))
            .overlay {
                Image(systemName: systemName)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: size, height: size)
    }
}

#Preview {
    PaywallView()
        .environment(StoreManager())
}
