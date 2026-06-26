import SwiftUI

public struct ProvenanceControlsView<ViewModel: WatermarkConfigurable & Observable>: View {
    @Bindable var viewModel: ViewModel
    @State private var showSigningInfo = false

    public init(viewModel: ViewModel) { self.viewModel = viewModel }

    private var report: SourceProvenanceReport? { viewModel.sourceProvenanceReport }
    private var creatorName: String {
        viewModel.config.rightsMetadata.creator.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var canSign: Bool { !creatorName.isEmpty && report?.allowsRightsProtection == true }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: badgeIcon)
                Text(report?.state.displayLabel ?? "Analyzing source\u{2026}")
                    .markepiTypography(.controlLabel)
            }

            if let evidence = report?.evidence, !evidence.isEmpty {
                ForEach(evidence) { e in
                    Text("\(e.source): \(e.summary)")
                        .markepiTypography(.value)
                        .foregroundStyle(.secondary)
                }
            }

            if let warnings = report?.warnings, !warnings.isEmpty {
                ForEach(warnings, id: \.self) { warning in
                    Text(warning)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }

            Divider()

            TextField("Creator", text: $viewModel.config.rightsMetadata.creator)
            TextField("Copyright", text: $viewModel.config.rightsMetadata.copyrightNotice)
            TextField("Credit", text: $viewModel.config.rightsMetadata.creditLine)

            Divider()

            Picker("Metadata privacy", selection: $viewModel.config.metadataPrivacyProfile) {
                Text("Keep all").tag(MetadataPrivacyProfile.preserveAll)
                Text("Remove location & device IDs").tag(MetadataPrivacyProfile.stripSensitive)
                Text("Minimal").tag(MetadataPrivacyProfile.minimalPublic)
            }

            Toggle("Add Content Credentials (C2PA)", isOn: $viewModel.config.includeC2PAManifest)

            if !viewModel.config.includeC2PAManifest, viewModel.config.sourceDeclaration == .none,
               viewModel.config.rightsMetadata.creator.isEmpty {
                Text("Enable Content Credentials to sign your export. "
                     + "A signed export cryptographically seals your stated authorship "
                     + "and copyright so tampering is detectable.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Picker("Declare source", selection: $viewModel.config.sourceDeclaration) {
                Text("Don\u{2019}t declare").tag(UserSourceDeclaration.none)
                Text("I declare: Camera").tag(UserSourceDeclaration.camera)
                Text("I declare: AI").tag(UserSourceDeclaration.ai)
                Text("I declare: AI-edited").tag(UserSourceDeclaration.aiEdited)
            }

            if report?.allowsVerifiedCameraClaim == true {
                Label("Verified camera capture", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            }

            VStack(alignment: .leading, spacing: 6) {
                Button {
                    showSigningInfo = true
                } label: {
                    Label("Sign with Content Credentials", systemImage: "checkmark.seal")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSign)

                if !canSign {
                    Text("Add a creator name above to sign. Your name is sealed "
                         + "into the Content Credentials and cannot be changed afterward.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Toggle("Invisible creator protection (coming soon)",
                   isOn: $viewModel.config.invisibleProtectionEnabled)
                .disabled(true)
        }
        .padding(16)
        .sheet(isPresented: $showSigningInfo) {
            C2PASigningInfoSheet(creatorName: creatorName) {
                viewModel.config.includeC2PAManifest = true
                showSigningInfo = false
                Task { await viewModel.renderAndPrepareShare() }
            } onCancel: {
                showSigningInfo = false
            }
        }
    }

    private var badgeIcon: String {
        switch report?.state {
        case .verifiedCameraCapture: return "checkmark.seal"
        case .markedAI:              return "sparkles"
        case .userDeclared:          return "person.crop.circle.badge.questionmark"
        case .suspectedAI:           return "questionmark.diamond"
        case .unknown, .none:        return "questionmark.circle"
        }
    }
}
