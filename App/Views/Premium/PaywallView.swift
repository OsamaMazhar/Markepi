import StoreKit
import SwiftUI
import UIKit
import MarkepiCore

/// Premium upgrade screen ("Markepi Pro").
///
/// Everyone exports as much as they like with every feature. The free tier's
/// files are capped at 2048 px, SDR, with a small Markepi mark; Premium exports
/// in full resolution with HDR and no mark. Three plans
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

    /// StoreKit source of truth, injected from `MarkepiApp`.
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

    /// Presents Apple's native offer-code redemption sheet, where the user types
    /// an alphanumeric code distributed through App Store Connect. A successful
    /// redemption lands as a transaction on `Transaction.updates`, which
    /// `StoreManager` already observes — so entitlement is granted with no extra
    /// wiring here, and the paywall flips to the "Pro" state on its own.
    @State private var showRedeemCode = false

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
            GeometryReader { proxy in
                let compact = verticalSizeClass == .compact || dynamicTypeSize >= .xxLarge
                let gap: CGFloat = compact ? 14 : 22

                ZStack {
                    // Full-bleed aurora — the same colorful backdrop the onboarding
                    // pages use — so the paywall reads as one cohesive premium
                    // surface instead of a colorful top fading to a flat black half.
                    // Frosted glass cards (below) keep the content legible over it.
                    MarkepiColors.canvasBackground.ignoresSafeArea()
                    AuroraBackground(reduceMotion: reduceMotion, fade: false)

                    // Scrolls only when it has to. App Review rejected 1.3 (2)
                    // under Guideline 4 because the subscribe button "was not
                    // visible": the layout assumed its content always fit, and
                    // an iPad `.sheet` is a ~620pt form sheet while the iPad
                    // branch simultaneously bumps every type size. Whatever
                    // overflowed fell off the bottom — the footer, and the CTA
                    // with it. `minHeight` keeps the roomy look wherever the
                    // content does fit, so the Spacers still distribute exactly
                    // as before; past that it scrolls rather than truncating.
                    ScrollView {
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
                        .frame(maxWidth: isPad ? 720 : 640, alignment: .top)
                        // GeometryReader parks content at the top-leading corner, so on
                        // the wide iPad canvas the 720pt column would hug the left edge.
                        // Expand an outer frame to full width (default .center) to seat
                        // the column in the middle of the display.
                        .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .top)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 14)
                        }
                    .scrollBounceBehavior(.basedOnSize)
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
                            // A bare glyph: the toolbar's glass button is the
                            // circle (a filled circle icon nested a second one).
                            Image(systemName: "xmark")
                                .font(.body.weight(.bold))
                                .foregroundStyle(.white)
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
        .offerCodeRedemption(isPresented: $showRedeemCode)
    }

    // MARK: - Header

    private func header(compact: Bool) -> some View {
        let scale: CGFloat = isPad ? 1.15 : 1
        let badge = (compact ? 60 : 80) * scale
        // Copy flips once the user is entitled: the hero becomes a celebratory
        // confirmation rather than a sales pitch.
        let title = store.isPremium ? "You're Markepi Pro" : "Export in Full Quality"
        let subtitle = store.isPremium
            ? "Thanks for your support — every export is full quality."
            : "Full resolution, HDR, and no Markepi watermark."
        return VStack(spacing: compact ? 10 : 14) {
            CrownBadge(size: badge, reduceMotion: reduceMotion,
                       glyphSize: (compact ? 26 : 34) * scale,
                       verified: store.isPremium)
            VStack(spacing: 5) {
                Text(title)
                    .font(.system(size: titleSize * (compact ? 0.86 : 1.05), weight: .heavy))
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

    /// What staying free means, in one line — the plans are the focus.
    private var freeCard: some View {
        (Text(Image(systemName: "gift.fill")) + Text("  Free: unlimited, up to 2048 px, with a Markepi mark"))
            .font(.system(size: subSize, weight: .medium))
            .foregroundStyle(.white.opacity(0.8))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
    }

    // MARK: - Plans

    private var plansSection: some View {
        VStack(spacing: 10) {
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
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: bodySize * 1.25, weight: isSelected ? .bold : .regular))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.6))

                PlanRowContent(title: plan.title, subtitle: plan.subtitle, badge: plan.badge,
                               price: displayPrice(for: plan),
                               bodySize: bodySize, subSize: subSize)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
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
                                  lineWidth: isSelected ? 3 : 1)
            }
            .shadow(color: isSelected ? Color.accentColor.opacity(0.3) : .black.opacity(0.12),
                    radius: 10, y: 4)
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
            proPerk(icon: "photo.on.rectangle.angled",
                    title: "Full resolution",
                    detail: "Photos at their original size and videos up to 4K, with all metadata kept intact.")
            perkDivider
            proPerk(icon: "sun.max.fill",
                    title: "HDR photos & videos",
                    detail: "The HDR brightness from your camera is kept in every export.")
            perkDivider
            proPerk(icon: "eye.slash",
                    title: "No Markepi watermark",
                    detail: "Only your own text, logo and signature appear on your work.")
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
                Button("Redeem Code") { showRedeemCode = true }
                    .accessibilityLabel("Redeem an offer code")
                    .accessibilityHint("Enter a code to unlock Markepi Pro")
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
        .font(.title3.weight(.bold))
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 17)
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

// MARK: - Plan row

/// One plan's text: title (+ badge) and subtitle on the left, the price on
/// the right, vertically centred — the same for every plan, so prices line
/// up. On sale the normal price sits struck directly under the sale price and
/// the badge reads SALE in gold.
///
/// Two layouts, the first that fits the real width wins: price column on the
/// right; or prices under the text (long currencies like "₫129.000", large
/// Dynamic Type). Prices are fixed-size — they move, never truncate or shrink —
/// and the subtitle reports no ideal width, so it wraps instead of forcing the
/// price down. No device checks: iPad and landscape fall out of the width.
struct PlanRowContent: View {
    let title: String
    let subtitle: String
    let badge: String?
    let price: String
    let bodySize: CGFloat
    let subSize: CGFloat

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                info
                Spacer(minLength: 8)
                current
            }
            VStack(alignment: .leading, spacing: 6) {
                info
                current
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title)\(badge.map { ", \($0)" } ?? ""), \(price). \(subtitle)")
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 3) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { titleText; badgeView }
                VStack(alignment: .leading, spacing: 4) { titleText; badgeView }
            }
            Text(subtitle)
                .font(.system(size: subSize, weight: .medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                // Wrap rather than claim a full line in the fit test.
                .frame(minWidth: 0, idealWidth: 0, maxWidth: .infinity, alignment: .leading)
        }
    }

    private var titleText: some View {
        Text(title)
            .font(.system(size: bodySize * 1.05, weight: .bold))
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var badgeView: some View {
        if let badge {
            Text(badge)
                .font(.system(size: subSize * 0.78, weight: .heavy))
                .tracking(0.5)
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.accentColor.opacity(0.16), in: Capsule())
                .lineLimit(1)
                .fixedSize()
        }
    }

    private var current: some View {
        Text(price)
            .font(.system(size: bodySize * 1.3, weight: .heavy))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .fixedSize()
    }

}

#Preview("Plan rows") {
    let prices = ["$4.99", "Rp 79.000", "₫129.000", "CHF 5.00"]
    ScrollView {
        VStack(alignment: .leading, spacing: 14) {
            ForEach([250.0, 300.0, 560.0], id: \.self) { width in
                Text("width \(Int(width))").font(.caption).foregroundStyle(.secondary)
                ForEach(prices, id: \.self) { price in
                    PlanRowContent(title: "One-Time Unlock", subtitle: "Pay once — yours forever",
                                   badge: "Best value", price: price, bodySize: 16, subSize: 14)
                        .frame(width: width).padding(12)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
                PlanRowContent(title: "Annual", subtitle: "Billed yearly, cancel anytime", badge: "Save 75%",
                               price: "$2.99", bodySize: 16, subSize: 14)
                    .frame(width: width).padding(12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .padding()
    }
}

// MARK: - Models

/// A purchasable premium plan. All three unlock full-quality exports and
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

// MARK: - Export comparison (free users, every export)

/// Free vs Pro, shown to a free user on EVERY export before anything renders.
/// Two cards built from the user's own edit — Pro as Pro exports it, Free with
/// the Markepi mark where the export will put it — each with what its file
/// contains. There is deliberately no "Don't show again".
///
/// The buttons only record the choice and dismiss; `ContentView` acts on it in
/// the sheet's `onDismiss`, once this sheet is fully gone.
struct ExportComparisonSheet: View {
    let viewModel: WatermarkViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var comparison: WatermarkViewModel.ExportComparison?

    private static let gold = Color(red: 0.96, green: 0.76, blue: 0.29)

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 12) {
                header
                if sideBySide(in: geo.size) {
                    HStack(spacing: 12) { proCard; freeCard }
                } else {
                    proCard
                    freeCard
                }
                buttons
            }
            .padding(.horizontal, 14)
            .padding(.top, 18)
            .padding(.bottom, max(geo.safeAreaInsets.bottom, 10))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(Color(.systemBackground))
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task { comparison = await viewModel.makeExportComparison() }
    }

    /// Cards side by side when that shows the photo larger than stacking
    /// (landscape screens, or portrait photos on a wide sheet).
    private func sideBySide(in size: CGSize) -> Bool {
        let img = comparison?.pro?.size ?? CGSize(width: 4, height: 3)
        guard img.width > 0, img.height > 0 else { return size.width > size.height }
        let aspect = img.width / img.height
        func fitted(_ w: CGFloat, _ h: CGFloat) -> CGFloat {
            min(w, h * aspect) * min(w / aspect, h)
        }
        let h = size.height * 0.75   // what the header and buttons leave
        return fitted(size.width / 2, h) > fitted(size.width, h / 2)
    }

    private var header: some View {
        Text(headerText)
            .markepiTypography(.sectionHeader)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }

    private var headerText: String {
        guard let c = comparison else { return "Choose your export" }
        if c.itemCount > 1 { return "Export \(c.itemCount) items" }
        return c.isVideo ? "Export video" : "Export photo"
    }

    private var proCard: some View {
        card(label: "Markepi Pro", image: comparison?.pro, specs: comparison?.proSpecs ?? [], isPro: true)
            .onTapGesture(perform: unlock)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Opens Markepi Pro")
    }

    private var freeCard: some View {
        card(label: "Free", image: comparison?.free, specs: comparison?.freeSpecs ?? [], isPro: false)
            .onTapGesture(perform: exportFree)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Exports with the free quality")
    }

    private func card(label: String, image: UIImage?, specs: [String], isPro: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    if isPro { Image(systemName: "star.fill").foregroundStyle(Self.gold) }
                    Text(label)
                }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(isPro ? .primary : .secondary)
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    ForEach(specs, id: \.self) { Text($0) }
                }
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(isPro ? .primary : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            ZStack {
                if let image {
                    Image(uiImage: image).resizable().scaledToFit()
                        // Pro shows the photo's HDR highlights; Free is the SDR file it exports.
                        .allowedDynamicRange(isPro ? .high : .standard)
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.tertiarySystemFill))
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(shape)
        .overlay(shape.stroke(isPro ? Self.gold : Color(.separator), lineWidth: isPro ? 2 : 0.5))
        .contentShape(shape)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(specs.joined(separator: ", "))")
    }

    private var buttons: some View {
        HStack(spacing: 10) {
            Button(action: unlock) {
                Label("Unlock full quality", systemImage: "star.fill")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(Self.gold)
            .foregroundStyle(.black)

            Button(action: exportFree) {
                Text("Export free")
                    .font(.body.weight(.semibold))
                    .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
            .fixedSize()
        }
        .controlSize(.large)
    }

    private func unlock() {
        viewModel.comparisonChoice = .unlock
        dismiss()
    }

    private func exportFree() {
        viewModel.comparisonChoice = .exportFree
        dismiss()
    }
}
