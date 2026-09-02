// iOS-only UI. Guarded so WatermarkCore also builds for macOS, where the
// `markepi` CLI target links the engine without the SwiftUI layer.
#if canImport(UIKit)
import SwiftUI

public struct ProvenanceControlsView<ViewModel: WatermarkConfigurable & Observable>: View {
    @Bindable var viewModel: ViewModel
    @State private var showSigningInfo = false
    @State private var signingIdentityType: C2PASigningIdentity.IdentityType?

    /// The rights text field that currently holds keyboard focus, if any.
    /// Driving focus through a single optional enum lets the keyboard toolbar
    /// dismiss editing by setting it to `nil` — no UIKit responder calls.
    private enum RightsField: Hashable { case name, copyright, credit }
    @FocusState private var focusedField: RightsField?

    public init(viewModel: ViewModel) { self.viewModel = viewModel }

    private var report: SourceProvenanceReport? { viewModel.sourceProvenanceReport }
    private var creatorName: String {
        viewModel.config.rightsMetadata.creator.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var signingKeyIsUsable: Bool {
        signingIdentityType?.isUsableForSigning == true
    }
    private var sourceAllowsRightsProtection: Bool {
        report?.allowsRightsProtection == true
    }
    private var batchCanSignImages: Bool {
        !viewModel.hasMultiplePhotos || viewModel.batchSignableImageCount > 0
    }
    private var batchHasVideos: Bool {
        viewModel.hasMultiplePhotos && viewModel.batchVideoCount > 0
    }
    private var batchSigningDisclosure: BatchC2PASigningDisclosure {
        BatchC2PASigningDisclosure(
            signableImageCount: viewModel.batchSignableImageCount,
            videoCount: viewModel.batchVideoCount
        )
    }
    private var canSign: Bool {
        !creatorName.isEmpty && sourceAllowsRightsProtection && signingKeyIsUsable && batchCanSignImages
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            masterToggle

            if viewModel.config.provenanceEnabled {
                Divider()

                sectionTitle("Source provenance")
                sourceStatusSection
                Divider()

                sectionTitle("Rights")
                rightsSection
                Divider()

                // "How it was made" and "Keep metadata" are sealed into the
                // Content Credentials at signing time, so they must be decided
                // *before* the Sign button below.
                sectionTitle("Source & privacy")
                metadataControlsSection
                Divider()

                sectionTitle("Content Credentials")
                contentCredentialsSection
            }
        }
        .padding(16)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button {
                    focusedField = nil
                } label: {
                    Label("Done", systemImage: "keyboard.chevron.compact.down")
                }
            }
        }
        .task {
            refreshSigningIdentity()
            seedRightsDefaultsIfNeeded()
        }
        .sheet(isPresented: $showSigningInfo) {
            C2PASigningInfoSheet(
                creatorName: creatorName,
                identityType: signingIdentityType,
                batchSignableImageCount: viewModel.batchSignableImageCount,
                batchVideoCount: viewModel.batchVideoCount
            ) {
                viewModel.config.includeC2PAManifest = true
                if batchHasVideos {
                    viewModel.acknowledgeBatchC2PAImageOnlyNotice()
                }
                showSigningInfo = false
                // Resign the creator-name TextField before signing/export begins.
                // Leaving it first responder tears the remote text-input session
                // down mid-flight, which spams `RTIInputSystemClient … requires a
                // valid sessionID` and can trip an XPC misuse abort.
                focusedField = nil
                Task { await viewModel.renderAndPrepareShare() }
            } onCancel: {
                showSigningInfo = false
            }
        }
    }

    private var masterToggle: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $viewModel.config.provenanceEnabled.animation(.easeInOut(duration: 0.2))) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Content Credentials & rights")
                        .markepiTypography(.controlLabel)
                    Text("Sign, add rights, and declare source")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !viewModel.config.provenanceEnabled {
                Text("Off: photos are shared directly with no added provenance. Turn on to seal in Content Credentials (C2PA), rights metadata, and a source declaration, and to see an export summary before sharing.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }

    private var sourceStatusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
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

            if report?.allowsVerifiedCameraClaim == true {
                Label("Verified camera capture", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            }
        }
    }

    private var rightsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            labeledField("Name",
                         prompt: "Your name",
                         text: $viewModel.config.rightsMetadata.creator,
                         focus: .name)
            Divider()
            labeledField("Copyright",
                         prompt: "Optional",
                         text: $viewModel.config.rightsMetadata.copyrightNotice,
                         focus: .copyright)
            Divider()
            labeledField("Credit",
                         prompt: "Optional",
                         text: $viewModel.config.rightsMetadata.creditLine,
                         focus: .credit)
        }
        .onChange(of: viewModel.config.rightsMetadata.creator) { oldName, newName in
            autofillRights(oldName: oldName, newName: newName)
        }
    }

    /// A label on the left, a free-text field on the right. The prompt is shown
    /// in the system's muted placeholder color when the field is empty.
    private func labeledField(_ label: String, prompt: String, text: Binding<String>, focus: RightsField) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .markepiTypography(.controlLabel)
                .foregroundStyle(.secondary)
                .frame(width: 88, alignment: .leading)
            TextField(prompt, text: text)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.leading)
                .focused($focusedField, equals: focus)
                .submitLabel(focus == .credit ? .done : .next)
                .onSubmit { advanceFocus(from: focus) }
        }
    }

    /// Moves focus to the next rights field on Return, dismissing after the last.
    private func advanceFocus(from field: RightsField) {
        switch field {
        case .name:      focusedField = .copyright
        case .copyright: focusedField = .credit
        case .credit:    focusedField = nil
        }
    }

    /// Seeds Copyright and Credit from an already-present name when the panel
    /// appears. `onChange` only fires for live edits, so a name restored from
    /// saved settings would otherwise never populate these defaults. Only blank
    /// fields are filled, so a customized or intentionally-cleared value is kept.
    private func seedRightsDefaultsIfNeeded() {
        let name = creatorName
        guard !name.isEmpty else { return }
        if viewModel.config.rightsMetadata.copyrightNotice.isEmpty {
            viewModel.config.rightsMetadata.copyrightNotice = autoCopyright(for: name)
        }
        if viewModel.config.rightsMetadata.creditLine.isEmpty {
            viewModel.config.rightsMetadata.creditLine = autoCredit(for: name)
        }
    }

    /// Default copyright notice derived from the creator name.
    private func autoCopyright(for name: String) -> String {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? "" : "© \(n). All rights reserved."
    }

    /// Default credit line derived from the creator name.
    private func autoCredit(for name: String) -> String {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? "" : "Photo by \(n)"
    }

    /// Keeps Copyright and Credit in sync with the name *as long as the user
    /// hasn't customized them*. A field is refreshed only when it's empty or
    /// still holds the value auto-derived from the previous name — so a manual
    /// edit (or a deliberate deletion, which leaves the field empty showing the
    /// "Optional" placeholder) is preserved.
    private func autofillRights(oldName: String, newName: String) {
        // Matching the previous auto-value also covers the first fill (both the
        // field and the old name are empty), while a deletion leaves the field
        // empty but not equal to the old non-empty auto-value, so it stays empty.
        if viewModel.config.rightsMetadata.copyrightNotice == autoCopyright(for: oldName) {
            viewModel.config.rightsMetadata.copyrightNotice = autoCopyright(for: newName)
        }
        if viewModel.config.rightsMetadata.creditLine == autoCredit(for: oldName) {
            viewModel.config.rightsMetadata.creditLine = autoCredit(for: newName)
        }
    }

    private var contentCredentialsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Content Credentials (C2PA)", systemImage: "checkmark.seal")
                Spacer()
                Text(viewModel.config.includeC2PAManifest ? "On" : "Off")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(viewModel.config.includeC2PAManifest ? .green : .secondary)
            }

            signingKeyStatusRow

            Text("No key setup is required. Markepi creates a local device signing key for you automatically and stores it on this device. Secure Enclave is used when available; otherwise Markepi falls back to a local Keychain software key.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Text("This is a local/device signature, not a verified legal identity. The C2PA manifest is still tamper detectable: if the image or sealed details change later, verifiers can detect that.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if batchHasVideos {
                batchSigningNotice
            }

            signingControls
        }
    }

    private var signingKeyStatusRow: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: signingKeyIcon)
                .foregroundStyle(signingKeyColor)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(signingKeyTitle)
                    .font(.footnote.weight(.semibold))
                Text(signingKeyHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if signingIdentityType == .unsupported {
                Button("Check again") {
                    refreshSigningIdentity()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var batchSigningNotice: some View {
        Label {
            Text(batchSigningNoticeText)
                .font(.footnote)
        } icon: {
            Image(systemName: "square.stack.3d.up")
        }
        .foregroundStyle(.secondary)
        .padding(10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var signingControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            if viewModel.config.includeC2PAManifest {
                Button(role: .destructive) {
                    viewModel.config.includeC2PAManifest = false
                } label: {
                    Label("Remove Content Credentials", systemImage: "xmark.seal")
                }
                .buttonStyle(.bordered)
            } else {
                Button {
                    refreshSigningIdentity()
                    showSigningInfo = true
                } label: {
                    Label("Sign with Content Credentials", systemImage: "checkmark.seal")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSign)
            }

            if !batchCanSignImages {
                Text("This batch only contains videos. Content Credentials signing is image-only in this version, so videos can still be watermarked and exported without C2PA signatures.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if creatorName.isEmpty {
                Text("Add a creator name above to sign. Your name is sealed into the Content Credentials and cannot be changed afterward.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if !sourceAllowsRightsProtection {
                Text(report == nil
                     ? "Wait for source provenance analysis to finish before signing."
                     : "This source provenance does not allow rights protection signing.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if !signingKeyIsUsable {
                Text("A local signing key is required. Markepi normally creates it automatically; if it stays unavailable, try signing from Markepi on your iPhone.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var metadataControlsSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                labeledMenuPicker("How it was made",
                                  selection: $viewModel.config.sourceDeclaration) {
                    Text("Don\u{2019}t declare").tag(UserSourceDeclaration.none)
                    Text("Camera").tag(UserSourceDeclaration.camera)
                    Text("AI-generated").tag(UserSourceDeclaration.ai)
                    Text("AI-edited").tag(UserSourceDeclaration.aiEdited)
                }
                Text("Optionally state how this image was created. It\u{2019}s sealed into the Content Credentials when you sign.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                labeledMenuPicker("Keep metadata",
                                  selection: $viewModel.config.metadataPrivacyProfile) {
                    Text("Keep all").tag(MetadataPrivacyProfile.preserveAll)
                    Text("Remove GPS & device").tag(MetadataPrivacyProfile.stripSensitive)
                    Text("Minimal").tag(MetadataPrivacyProfile.minimalPublic)
                }
                Text("Choose how much of the photo\u{2019}s original metadata (location, device, EXIF) stays in the exported file.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// A leading label on the left with a compact menu picker on the right, so
    /// it\u{2019}s always clear what the selected value controls.
    private func labeledMenuPicker<Selection: Hashable, Content: View>(
        _ label: String,
        selection: Binding<Selection>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .markepiTypography(.controlLabel)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
            Spacer(minLength: 8)
            Picker(label, selection: selection, content: content)
                .labelsHidden()
                .pickerStyle(.menu)
                .lineLimit(1)
        }
    }

    private var signingKeyIcon: String {
        switch signingIdentityType {
        case .secureEnclave, .localSoftware:
            return "key.fill"
        case .unsupported:
            return "exclamationmark.triangle.fill"
        case .none:
            return "hourglass"
        }
    }

    private var signingKeyColor: Color {
        switch signingIdentityType {
        case .secureEnclave, .localSoftware:
            return .green
        case .unsupported:
            return .orange
        case .none:
            return .secondary
        }
    }

    private var signingKeyTitle: String {
        switch signingIdentityType {
        case .secureEnclave:
            return "Signing key ready"
        case .localSoftware:
            return "Signing key ready"
        case .unsupported:
            return "Signing key unavailable"
        case .none:
            return "Checking signing key..."
        }
    }

    private var signingKeyHelp: String {
        switch signingIdentityType {
        case .secureEnclave:
            return "Secure Enclave key on this device. No account, upload, or certificate file needed."
        case .localSoftware:
            return "Local Keychain fallback on this device. No account, upload, or certificate file needed."
        case .unsupported:
            return "This device could not create or load a local key. Try again on your iPhone in Markepi."
        case .none:
            return "Markepi will create or load the local key automatically."
        }
    }

    private var batchSigningNoticeText: String {
        batchSigningDisclosure.moreSectionText
    }

    private func refreshSigningIdentity() {
        signingIdentityType = C2PASigningIdentityStore().currentIdentity().type
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
#endif
