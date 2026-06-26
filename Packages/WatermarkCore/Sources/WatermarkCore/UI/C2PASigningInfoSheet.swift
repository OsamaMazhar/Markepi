import SwiftUI

public struct C2PASigningInfoSheet: View {
    public let creatorName: String
    public let identityType: C2PASigningIdentity.IdentityType?
    public let batchSignableImageCount: Int
    public let batchVideoCount: Int
    public let onConfirm: () -> Void
    public let onCancel: () -> Void

    public init(
        creatorName: String,
        identityType: C2PASigningIdentity.IdentityType? = nil,
        batchSignableImageCount: Int = 0,
        batchVideoCount: Int = 0,
        onConfirm: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.creatorName = creatorName
        self.identityType = identityType
        self.batchSignableImageCount = batchSignableImageCount
        self.batchVideoCount = batchVideoCount
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    private var trimmedCreatorName: String {
        creatorName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var batchDisclosure: BatchC2PASigningDisclosure {
        BatchC2PASigningDisclosure(
            signableImageCount: batchSignableImageCount,
            videoCount: batchVideoCount
        )
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Label("Content Credentials (C2PA)", systemImage: "checkmark.seal")
                        .font(.title3.weight(.semibold))

                    Text("Signing seals this photo together with your stated authorship. "
                         + "If anyone changes the image or the details afterward, the seal "
                         + "breaks and verifiers can tell it was modified.")

                    GroupBox("What gets sealed") {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\u{2022} Creator: \(trimmedCreatorName)")
                            Text("\u{2022} Copyright, credit and license you entered")
                            Text("\u{2022} That Markepi made this export, and the source\u{2019}s provenance")
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }

                    GroupBox("Signing key") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(signingKeyText)
                            Text("No account, upload, or certificate file is needed.")
                                .foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if batchVideoCount > 0 {
                        GroupBox("Batch signing") {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(batchSigningText)
                                Text("Videos will continue exporting without C2PA signatures and will not be treated as signing errors.")
                                    .foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    GroupBox("Important \u{2014} what this is NOT") {
                        VStack(alignment: .leading, spacing: 6) {
                            (Text("This is a ")
                             + Text("local/device signature").bold()
                             + Text(", not a verified legal identity. It does ")
                             + Text("not").bold()
                             + Text(" verify your real-world legal identity."))
                            Text("The C2PA manifest is still tamper detectable: if the image or sealed details change later, verifiers can detect that.")
                            (Text("Identity-verified signing (a certificate issued to you by an authority, or a third-party identity check) is ")
                             + Text("not available in the app").bold()
                             + Text("."))
                                .foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Text("Works fully offline. No network is used.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationTitle("Sign export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onCancel) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(confirmButtonTitle, action: onConfirm).disabled(trimmedCreatorName.isEmpty)
                }
            }
        }
    }

    private var signingKeyText: String {
        switch identityType {
        case .secureEnclave:
            return "Markepi will use a Secure Enclave key created and stored on this device."
        case .localSoftware:
            return "Markepi will use a local Keychain software key created and stored on this device."
        case .unsupported:
            return "No local signing key is available on this device right now."
        case .none:
            return "Markepi creates or loads a local signing key automatically on this device."
        }
    }

    private var batchSigningText: String {
        batchDisclosure.sheetText
    }

    private var confirmButtonTitle: String {
        batchDisclosure.confirmationButtonTitle
    }
}
