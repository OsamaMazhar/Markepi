import SwiftUI

public struct C2PASigningInfoSheet: View {
    public let creatorName: String
    public let onConfirm: () -> Void
    public let onCancel: () -> Void

    public init(creatorName: String, onConfirm: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.creatorName = creatorName; self.onConfirm = onConfirm; self.onCancel = onCancel
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
                            Text("\u{2022} Creator: \(creatorName)")
                            Text("\u{2022} Copyright, credit and license you entered")
                            Text("\u{2022} That Markepi made this export, and the source\u{2019}s provenance")
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }

                    GroupBox("Important \u{2014} what this is NOT") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("This is signed by a **Markepi device signing identity**. "
                                 + "It proves the file hasn\u{2019}t been tampered with and that your "
                                 + "name was sealed in by you \u{2014} it does **not** verify your real-world "
                                 + "legal identity.")
                            Text("Identity-verified signing (a certificate issued to you by an "
                                 + "authority, or a third-party identity check) is **not available "
                                 + "in the app**.")
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
                    Button("Sign now", action: onConfirm).disabled(creatorName.isEmpty)
                }
            }
        }
    }
}
