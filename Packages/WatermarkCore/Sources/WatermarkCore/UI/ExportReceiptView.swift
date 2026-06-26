import SwiftUI

public struct ExportReceiptView: View {
    public let receipt: ExportReceipt
    private let onShare: (() -> Void)?

    public init(receipt: ExportReceipt, onShare: (() -> Void)? = nil) {
        self.receipt = receipt
        self.onShare = onShare
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header
                cards
            }
            .padding(.horizontal, 20)
            .padding(.top, 28)
            .padding(.bottom, onShare == nil ? 28 : 120)
        }
        .scrollBounceBehavior(.basedOnSize)
        .presentationDragIndicator(.visible)
        .safeAreaInset(edge: .bottom) {
            if let onShare {
                shareBar(onShare)
            }
        }
    }

    // MARK: - Hero header

    private var header: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(heroTint.opacity(0.15))
                    .frame(width: 76, height: 76)
                Image(systemName: heroIcon)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(heroTint)
            }
            .accessibilityHidden(true)

            Text(heroTitle)
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)

            Text(heroSubtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Cards

    private var cards: some View {
        VStack(spacing: 18) {
            sourceCard
            recordsCard
            if let verification = receipt.signingResult?.verification, verification.hasWarnings {
                verificationCard(verification)
            }
            if !(receipt.signingResult?.warnings.isEmpty ?? true) {
                notesCard
            }
            privacyCard
        }
    }

    private var sourceCard: some View {
        ReceiptCard(title: "Source", systemImage: "photo.on.rectangle.angled") {
            ReceiptRow(icon: sourceStateIcon,
                       iconTint: sourceStateTint,
                       title: "State",
                       value: receipt.report.state.displayLabel)
            // Skip the user-declaration evidence here — it's shown once, clearly,
            // in the "Declared by you" row below, so we don't repeat it.
            ForEach(receipt.report.evidence.filter { $0.kind != .userDeclaration }) { e in
                ReceiptDivider()
                ReceiptRow(icon: "doc.text.magnifyingglass",
                           title: e.source,
                           value: e.summary)
            }
            if receipt.report.userDeclaration != .none {
                ReceiptDivider()
                ReceiptRow(icon: "person.crop.circle.badge.checkmark",
                           title: "Declared by you",
                           value: receipt.report.userDeclaration.displayLabel)
            }
        }
    }

    private var recordsCard: some View {
        ReceiptCard(title: "Records Added", systemImage: "checkmark.seal") {
            ReceiptRow(icon: signingIcon,
                       iconTint: signingTint,
                       title: "Content Credentials",
                       value: signingText)

            if receipt.signingResult?.status == .signed, let s = receipt.signingResult {
                ReceiptNote("Signed with \(s.displayName). This is a device signing identity, not a verified legal identity. The manifest is tamper-evident: if the image changes later, verifiers can detect it.")
            }

            if !receipt.rightsMetadata.creator.isEmpty {
                ReceiptDivider()
                ReceiptRow(icon: "person.fill", title: "Creator", value: receipt.rightsMetadata.creator)
            }
            if !receipt.rightsMetadata.copyrightNotice.isEmpty {
                ReceiptDivider()
                ReceiptRow(icon: "c.circle", title: "Copyright", value: receipt.rightsMetadata.copyrightNotice)
            }
            if !receipt.rightsMetadata.creditLine.isEmpty {
                ReceiptDivider()
                ReceiptRow(icon: "text.badge.star", title: "Credit", value: receipt.rightsMetadata.creditLine)
            }
            if !receipt.rightsMetadata.usageTerms.isEmpty {
                ReceiptDivider()
                ReceiptRow(icon: "doc.plaintext", title: "Usage terms", value: receipt.rightsMetadata.usageTerms)
            }
        }
    }

    private func verificationCard(_ verification: C2PAVerificationResult) -> some View {
        ReceiptCard(title: "Verification",
                    systemImage: verification.signatureIsIntact ? "checkmark.shield" : "exclamationmark.shield") {
            ReceiptRow(icon: verification.signatureIsIntact ? "checkmark.seal.fill" : "exclamationmark.seal.fill",
                       iconTint: verification.signatureIsIntact ? .green : .orange,
                       title: verification.signatureIsIntact ? "Signature intact" : "Could not verify",
                       value: verification.signatureIsIntact ? "Tamper detection active" : "")
            ForEach(verification.items) { item in
                ReceiptDivider()
                VStack(alignment: .leading, spacing: 4) {
                    Label {
                        Text(item.code).font(.caption.monospaced()).foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: isExpected(item) ? "info.circle" : "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                    }
                    Text(explanation(for: item)).font(.footnote)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
    }

    private var notesCard: some View {
        ReceiptCard(title: "Notes", systemImage: "info.circle") {
            ForEach(Array((receipt.signingResult?.warnings ?? []).enumerated()), id: \.offset) { idx, warning in
                if idx > 0 { ReceiptDivider() }
                ReceiptRow(icon: "exclamationmark.circle", iconTint: .orange, title: warning, value: "")
            }
        }
    }

    private var privacyCard: some View {
        ReceiptCard(title: "Privacy", systemImage: "lock.shield") {
            ReceiptRow(icon: privacyIcon, title: "Profile", value: privacyText)
            if receipt.privacyActions.isEmpty {
                ReceiptNote("No metadata was removed — all original details are preserved.")
            } else {
                ForEach(receipt.privacyActions, id: \.self) { action in
                    ReceiptDivider()
                    ReceiptRow(icon: "minus.circle", iconTint: .secondary, title: action, value: "")
                }
            }
        }
    }

    // MARK: - Share bar

    private func shareBar(_ onShare: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            Divider()
            Button(action: onShare) {
                Label("Continue to Share", systemImage: "square.and.arrow.up")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
        .background(.bar)
    }

    // MARK: - Derived display values

    /// True for verification codes that are expected for Markepi's local device
    /// signing key (shown with an info icon rather than a warning triangle).
    private func isExpected(_ item: C2PAVerificationItem) -> Bool {
        item.code.contains("untrusted")
    }

    /// A clear, honest explanation for known verification codes, falling back to
    /// the verifier's own wording for anything else.
    private func explanation(for item: C2PAVerificationItem) -> String {
        if item.code.contains("untrusted") {
            return "Markepi signs with a private key created on this device, not a "
                + "certificate from a public authority — so verifiers list the "
                + "signer as “untrusted”. The signature itself is valid and "
                + "tamper-evident; this only means your real-world identity isn’t "
                + "certified by a third party. Authority-issued (identity-verified) "
                + "signing isn’t available in the app."
        }
        return item.explanation
    }

    private var isSigned: Bool { receipt.signingResult?.status == .signed }

    private var heroIcon: String {
        isSigned ? "checkmark.seal.fill" : "checkmark.circle.fill"
    }

    private var heroTint: Color { isSigned ? .green : .accentColor }

    private var heroTitle: String {
        isSigned ? "Protected & Ready" : "Ready to Share"
    }

    private var heroSubtitle: String {
        if isSigned {
            return "Your photo is watermarked and sealed with Content Credentials. Here's a summary of what was added."
        }
        return "Your photo is watermarked and ready. Review the summary below, then continue to share."
    }

    private var sourceStateIcon: String {
        switch receipt.report.state {
        case .verifiedCameraCapture: return "checkmark.seal"
        case .markedAI:              return "sparkles"
        case .userDeclared:          return "person.crop.circle.badge.questionmark"
        case .suspectedAI:           return "questionmark.diamond"
        case .unknown:               return "questionmark.circle"
        }
    }

    private var sourceStateTint: Color {
        switch receipt.report.state {
        case .verifiedCameraCapture: return .green
        case .markedAI, .suspectedAI: return .orange
        default: return .secondary
        }
    }

    private var signingIcon: String { isSigned ? "checkmark.seal.fill" : "seal" }
    private var signingTint: Color { isSigned ? .green : .secondary }

    private var signingText: String {
        switch receipt.signingResult?.status {
        case .signed:       return "Signed"
        case .notSigned:    return "Not signed"
        case .notSupported: return "Not supported for this format"
        case .none:         return "Not signed"
        }
    }

    private var privacyIcon: String {
        switch receipt.privacyProfile {
        case .preserveAll:    return "tray.full"
        case .stripSensitive: return "location.slash"
        case .minimalPublic:  return "lock.doc"
        }
    }

    private var privacyText: String {
        switch receipt.privacyProfile {
        case .preserveAll: return "Keep all"
        case .stripSensitive: return "Remove location & device IDs"
        case .minimalPublic: return "Minimal"
        }
    }
}

// MARK: - Building blocks

/// A grouped card with a small section heading, mirroring the app's editor cards.
private struct ReceiptCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                content()
            }
            .background(Color.secondary.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

/// A single icon + title + trailing value row.
private struct ReceiptRow: View {
    let icon: String
    var iconTint: Color = .secondary
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(iconTint)
                .frame(width: 24)
            Text(title)
                .font(.subheadline)
            if !value.isEmpty {
                Spacer(minLength: 8)
                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Hairline separator inset to match the row content.
private struct ReceiptDivider: View {
    var body: some View {
        Divider().padding(.leading, 16)
    }
}

/// A secondary explanatory note inside a card.
private struct ReceiptNote: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
    }
}
