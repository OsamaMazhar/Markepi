# Handoff: Contact and Follow Us links in Settings (SwiftUI)

**Goal:** Add two sections to the app's Settings `Form`.

- **Contact** lists email, X, Reddit and the website.
- **Follow Us** lists TikTok, Instagram and YouTube, each with a Follow or Subscribe button.

It needs no dependencies, no new files and no Info.plist changes. `Link` opens URLs, and iOS opens the TikTok, Instagram or YouTube app when it's installed, otherwise Safari.

Reference implementation: Markepi `App/Views/ContentView.swift`, `SettingsView`.

## 1. Sections (place them above "About")

```swift
Section("Contact") {
    linkRow("Email", "contact@orbitaar.com", "envelope", "mailto:contact@orbitaar.com")
    linkRow("X (Twitter)", "@Orbitaar", "at", "https://x.com/Orbitaar")
    linkRow("Reddit", "r/Markepi", "bubble.left.and.bubble.right", "https://www.reddit.com/r/Markepi/")
    linkRow("Website", "orbitaar.com", "globe", "https://www.orbitaar.com")
}

Section {
    followRow("TikTok", "@orbitaar", "music.note", "Follow", "https://www.tiktok.com/@orbitaar")
    followRow("Instagram", "@orbitaar__", "camera", "Follow", "https://www.instagram.com/orbitaar__/")
    // sub_confirmation=1 opens YouTube's subscribe prompt directly.
    followRow("YouTube", "@orbitaar", "play.rectangle", "Subscribe", "https://www.youtube.com/@orbitaar?sub_confirmation=1")
} header: {
    Text("Follow Us")
} footer: {
    Text("Enjoying <AppName>? Follow us on TikTok and Instagram and subscribe on YouTube for tips, new features and updates.")
}
```

## 2. Helpers (private funcs on the Settings view)

```swift
/// A tappable row: title + icon on the left, the address/handle on the right.
private func linkRow(_ title: String, _ value: String, _ icon: String, _ url: String) -> some View {
    Link(destination: URL(string: url)!) {
        LabeledContent {
            Text(value)
        } label: {
            Label(title, systemImage: icon)
        }
    }
}

/// A social row whose trailing pill names the action (Follow / Subscribe).
private func followRow(_ title: String, _ handle: String, _ icon: String, _ action: String, _ url: String) -> some View {
    Link(destination: URL(string: url)!) {
        HStack {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(handle).font(.caption).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: icon)
            }
            Spacer()
            Text(action)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.accentColor))
        }
    }
}
```

## Notes

- **The URLs are fixed strings**, so the force-unwrap `URL(string:)!` is safe. If you edit one, open it once to check it.
- **The icons are generic:** SF Symbols has no brand logos. Adding real logos would need image assets and their brand-usage rules, so they were left out.
- **The YouTube subscribe prompt:** adding `?sub_confirmation=1` to the channel URL makes YouTube ask "Subscribe?" as soon as the channel opens.
- **Shared handles:** every Orbitaar app uses the same accounts. Only the Reddit sub (`r/Markepi`) and the `<AppName>` in the footer are per-app. Swap or drop the Reddit row for another app.
- **Check every link before shipping.** TikTok, Instagram and YouTube were confirmed to be the Orbitaar accounts on 2026-10-09. X and Reddit block automated checks, so tap those on a device.
- **Use the app's design system:** if the app has its own typography system (Markepi uses `.markepiTypography(.metadata)` for the handle line), swap it in for the raw `.font`.
- **Mention the links in App Review notes** (for example "adds Contact and Follow Us links in Settings"), because reviewers check that external links work.
