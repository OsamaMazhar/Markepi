import SwiftUI

/// Plain-language explainer for Content Credentials (C2PA), reached from
/// Settings. Sets honest expectations about what Markepi's signature proves and,
/// crucially, when the credentials survive sharing versus when they're stripped —
/// so users aren't surprised that a WhatsApp photo or a screenshot loses them.
///
/// Copy stays Tier-1 honest (D-24/D-27): the signature is described as a local
/// device signature, never a verified legal identity or "proof of authorship".
public struct ContentCredentialsInfoView: View {
    public init() {}

    public var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: "checkmark.seal")
                        .font(.system(size: 40))
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                    Text("Content Credentials are a tamper‑evident record attached to your exported image. When they're present, anyone can check who signed it, what edits it lists, and whether the pixels have changed since — using a free verifier such as contentcredentials.org.")
                        .font(.subheadline)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            } header: {
                Text("What they are")
            }

            Section {
                Text("Markepi signs with a key created automatically on this device. This is a **device signature, not a verified legal identity**, so verifiers will show it as “untrusted” — that's expected and normal.")
                    .font(.subheadline)
                Text("What it does prove is **integrity**: if the image or the sealed details change after signing, a verifier can detect it. It's a self‑asserted, tamper‑evident record made at the moment you export — not a guarantee of authorship.")
                    .font(.subheadline)
            } header: {
                Text("What Markepi's signature means")
            } footer: {
                Text("Content Credentials are available for photos. Videos are watermarked but not signed in this version.")
            }

            Section {
                infoRow(
                    icon: "eye",
                    title: "Visible watermark",
                    detail: "Survives everything — screenshots, recompression, reposting. It can be cropped, but it's always visible. This is Markepi's core protection."
                )
                infoRow(
                    icon: "checkmark.seal",
                    title: "Content Credentials (C2PA)",
                    detail: "Cryptographic and detailed, but only survives when the file itself isn't changed. Strong where the channel cooperates; removed where it doesn't."
                )
                infoRow(
                    icon: "wand.and.stars",
                    title: "Invisible watermark",
                    detail: "Coming in a future update. An imperceptible mark in the pixels that can survive recompression and light edits, so provenance can be recovered even after the credential is stripped."
                )
            } header: {
                Text("Three layers of protection")
            } footer: {
                Text("Each layer covers a different weakness of the others.")
            }

            Section {
                Text("Content Credentials stay intact only when the file's original bytes are preserved. They survive:")
                    .font(.subheadline)
                bullet("AirDrop, Files, and email attachments")
                bullet("Messaging apps **when you send the image as a file or document** (for example, WhatsApp's Document option)")
                bullet("Markepi's **Save to Photos** — it stores the original file, so the credentials are kept")
            } header: {
                Text("When credentials are kept")
            }

            Section {
                Text("Anything that re‑encodes the image removes the Content Credentials:")
                    .font(.subheadline)
                bullet("Posting to WhatsApp, Instagram, Facebook, or X as a normal photo (these apps recompress every image)")
                bullet("Taking a screenshot")
                bullet("The system “Save Image” in a share sheet, which re‑encodes the picture")
                bullet("Editing in an app that isn't C2PA‑aware, including most built‑in phone photo editors")
            } header: {
                Text("When credentials are removed")
            } footer: {
                Text("This is a limitation of the C2PA standard, not a Markepi bug. A removed credential can't be recovered — but your visible watermark always remains.")
            }

            Section {
                Text("Editing changes the pixels, which breaks the signature by design. A **C2PA‑aware editor** (such as Photoshop or Lightroom) adds itself to the history and re‑signs, so the chain continues: “Markepi signed this, then this editor changed it.” Most other editors — including typical built‑in gallery editors — simply drop the credentials on save.")
                    .font(.subheadline)
            } header: {
                Text("What happens when someone edits it")
            }

            Section {
                Link(destination: Self.verifyURL) {
                    Label("Verify at contentcredentials.org", systemImage: "arrow.up.forward.app")
                }
            } header: {
                Text("Check an image")
            } footer: {
                Text("Tip: upload the file from Files (or AirDrop it first) rather than the photo picker — some photo pickers re‑process the image and can strip the credentials before the verifier ever sees them.")
            }
        }
        .navigationTitle("Content Credentials")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func infoRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(.tint)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func bullet(_ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("•").font(.subheadline).foregroundStyle(.secondary)
            Text(text).font(.subheadline)
        }
    }

    private static let verifyURL = URL(string: "https://contentcredentials.org/verify")!
}
