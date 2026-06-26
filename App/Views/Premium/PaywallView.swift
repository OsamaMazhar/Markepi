import SwiftUI
import WatermarkCore

/// Premium upgrade screen ("Watermark Pro").
///
/// The free tier lets people export/share **2 photos per day with every
/// feature unlocked**; Premium simply lifts that daily limit. Two plans are
/// offered: a $3.99 one-time unlock or a $0.99/month subscription.
///
/// The layout is intentionally compact and **never scrolls** — it reads the
/// available height via `GeometryReader` and tightens spacing/sizes on shorter
/// devices so everything fits on a single page.
///
/// StoreKit 2 wiring is a separate step: `selectedPlan` + `purchase()` are the
/// integration points. Until products exist, purchase/restore surface a clear
/// "coming soon" notice.
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss

    /// Currently highlighted plan. Defaults to the one-time unlock.
    @State private var selectedPlan: PremiumPlan = .lifetime

    /// Shown when a purchase/restore is attempted before StoreKit is wired.
    @State private var showComingSoon = false

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                // Tighten everything on shorter screens so it fits without scrolling.
                let compact = geo.size.height < 680
                let gap: CGFloat = compact ? 14 : 22

                VStack(spacing: 0) {
                    header(compact: compact)

                    Spacer(minLength: gap)

                    freeCard

                    Spacer(minLength: gap)

                    plansSection

                    Spacer(minLength: gap)

                    footer
                }
                .padding(.horizontal, 20)
                .padding(.top, compact ? 6 : 14)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Markepi Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary, Color.secondary.opacity(0.18))
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
        .alert("Coming Soon", isPresented: $showComingSoon) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("In-app purchases aren’t available just yet. Premium will unlock here as soon as it’s ready.")
        }
    }

    // MARK: - Header

    private func header(compact: Bool) -> some View {
        VStack(spacing: compact ? 10 : 14) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.16))
                    .frame(width: compact ? 64 : 84, height: compact ? 64 : 84)
                Image(systemName: "crown.fill")
                    .font(.system(size: compact ? 28 : 36, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .symbolRenderingMode(.hierarchical)
            }
            VStack(spacing: 5) {
                Text("Unlock Unlimited Exports")
                    .font(compact ? .title3.weight(.bold) : .title.weight(.bold))
                    .multilineTextAlignment(.center)
                Text("Keep every feature — just lift the daily limit.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Free tier card

    private var freeCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "gift.fill")
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text("Free every day")
                    .font(.body.weight(.semibold))
                Text("Share 2 photos a day with all features unlocked — fonts, frames, captions, and video.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        }
    }

    // MARK: - Plans

    private var plansSection: some View {
        VStack(spacing: 10) {
            Text("Go unlimited")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(PremiumPlan.allCases) { plan in
                planCard(plan)
            }
        }
    }

    private func planCard(_ plan: PremiumPlan) -> some View {
        let isSelected = plan == selectedPlan
        return Button {
            selectedPlan = plan
        } label: {
            HStack(spacing: 14) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(plan.title)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                        if let badge = plan.badge {
                            Text(badge)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Color.accentColor)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.16), in: Capsule())
                        }
                    }
                    Text(plan.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Text(plan.price)
                    .font(.headline)
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 10) {
            Button {
                purchase()
            } label: {
                Text(selectedPlan.callToAction)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.markepiPrimary())

            HStack(spacing: 18) {
                Button("Restore") { showComingSoon = true }
                Button("Terms") { showComingSoon = true }
                Button("Privacy") { showComingSoon = true }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Actions

    /// Integration point for StoreKit 2: resolve `selectedPlan` to its
    /// `Product`, call `product.purchase()`, verify, and grant entitlement.
    private func purchase() {
        showComingSoon = true
    }
}

// MARK: - Models

/// A purchasable premium plan. Both lift the free 2-photos/day limit.
enum PremiumPlan: String, CaseIterable, Identifiable {
    case lifetime
    case monthly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lifetime: return "One-Time Unlock"
        case .monthly: return "Monthly"
        }
    }

    var subtitle: String {
        switch self {
        case .lifetime: return "Pay once — yours forever"
        case .monthly: return "Billed every month, cancel anytime"
        }
    }

    var price: String {
        switch self {
        case .lifetime: return "$3.99"
        case .monthly: return "$0.99"
        }
    }

    var badge: String? {
        switch self {
        case .lifetime: return "Best value"
        case .monthly: return nil
        }
    }

    var callToAction: String {
        switch self {
        case .lifetime: return "Unlock Forever — $3.99"
        case .monthly: return "Subscribe — $0.99/month"
        }
    }
}

#Preview {
    PaywallView()
}
