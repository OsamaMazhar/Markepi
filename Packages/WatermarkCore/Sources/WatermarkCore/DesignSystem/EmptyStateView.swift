// iOS-only UI. Guarded so WatermarkCore also builds for macOS, where the
// `markepi` CLI target links the engine without the SwiftUI layer.
#if canImport(UIKit)
import SwiftUI

/// A shared empty state component used across the main app and Share Extension
/// when no media is loaded.
///
/// It presents the app's brand mark as a glowing hero over a calm accent
/// spotlight, a short value proposition, and the primary/secondary entry points.
/// The goal is a finished, branded launch surface — eye-catching but quiet — that
/// never reads as a blank placeholder.
///
/// Per D-08 the same component is used in both targets: the main app passes the
/// action closures (rendering the CTAs); the Share Extension passes `nil` (media
/// is already selected), so only the hero + copy show.
///
/// The brand mark lives in the package's `Media.xcassets` as a **template**
/// image, so it adopts the app accent via `foregroundStyle` and stays consistent
/// in light and dark. Reduce Transparency drops the soft glow; Reduce Motion
/// drops the slow breathing animation.
public struct EmptyStateView: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Optional closure triggered by the primary "Choose Photo" CTA button.
    /// When `nil`, the CTA button is not rendered (extension contexts).
    let onChoosePhoto: (() -> Void)?

    /// Optional closure for the secondary "Import from Files" CTA. When `nil`
    /// the button is omitted (extensions, or hosts without a Files importer).
    let onImportFiles: (() -> Void)?

    /// Drives the hero's slow "breathing" glow (disabled under Reduce Motion).
    @State private var glow = false

    /// Creates an empty state view.
    ///
    /// - Parameters:
    ///   - onChoosePhoto: Closure invoked by the primary CTA. Pass `nil` in
    ///     extension contexts where no photo-picker action is needed.
    ///   - onImportFiles: Closure invoked by the secondary "Import from Files"
    ///     CTA. Pass `nil` to omit it.
    public init(
        onChoosePhoto: (() -> Void)?,
        onImportFiles: (() -> Void)? = nil
    ) {
        self.onChoosePhoto = onChoosePhoto
        self.onImportFiles = onImportFiles
    }

    public var body: some View {
        ZStack {
            ambientBackground

            VStack(spacing: 0) {
                Spacer(minLength: 24)

                hero
                    .padding(.bottom, 30)

                copyBlock

                if onChoosePhoto != nil || onImportFiles != nil {
                    actions
                        .padding(.top, 36)
                }

                Spacer(minLength: 24)
            }
            .padding(.horizontal, 32)
        }
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .contain)       // Group as one logical region
    }

    /// A soft accent spotlight, brightest just behind the hero and fading to the
    /// canvas. It gives the screen depth and keeps the surrounding space feeling
    /// intentional rather than empty. Kept low-contrast so it never competes with
    /// the content.
    private var ambientBackground: some View {
        GeometryReader { geo in
            let reach = min(geo.size.width, geo.size.height)
            RadialGradient(
                colors: [
                    Color.accentColor.opacity(reduceTransparency ? 0.09 : 0.15),
                    .clear
                ],
                center: UnitPoint(x: 0.5, y: 0.42),
                startRadius: 0,
                endRadius: reach * 0.72
            )
            .ignoresSafeArea()
        }
        .allowsHitTesting(false)
    }

    /// The brand mark tinted to the app accent, lifted off the canvas by a soft
    /// halo that breathes slowly for a subtle sense of life.
    private var hero: some View {
        ZStack {
            if !reduceTransparency {
                Circle()
                    .fill(Color.accentColor.opacity(0.22))
                    .frame(width: 188, height: 188)
                    .blur(radius: 58)
                    .scaleEffect(glow ? 1.06 : 0.92)
            }

            Image("BrandMark", bundle: .module)
                .resizable()
                .scaledToFit()
                .frame(width: 178)
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.accentColor, Color.accentColor.opacity(0.78)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .shadow(color: Color.accentColor.opacity(0.30), radius: 16, y: 6)
        }
        .frame(height: 150)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 3.4).repeatForever(autoreverses: true)) {
                glow = true
            }
        }
        .accessibilityHidden(true)
    }

    private var copyBlock: some View {
        VStack(spacing: 10) {
            Text("Add a Photo or Video")
                .font(.title2.weight(.bold))
                .foregroundStyle(.primary)
            Text("Add your signature watermark, frame, and caption — then export in full quality.")
                .markepiTypography(.controlLabel)
                .foregroundStyle(.secondary)
        }
    }

    private var actions: some View {
        VStack(spacing: 12) {
            if let onChoosePhoto {
                Button(action: onChoosePhoto) {
                    Label("Choose Photo or Video", systemImage: "photo.on.rectangle.angled")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(FilledAccentButtonStyle())
            }
            if let onImportFiles {
                Button(action: onImportFiles) {
                    Label("Import from Files", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(FilledAccentButtonStyle())
            }
        }
        .frame(maxWidth: 360)
    }
}

/// The prominent, filled call-to-action for the empty state: white label on an
/// accent-gradient capsule with a soft accent shadow. Unlike `markepiPrimary`
/// (a glass pill with tinted text) this reads unmistakably as *the* primary
/// action, which is what the launch screen needs.
private struct FilledAccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.vertical, 16)
            .padding(.horizontal, 20)
            .background(
                LinearGradient(
                    colors: [Color.accentColor, Color.accentColor.opacity(0.85)],
                    startPoint: .top, endPoint: .bottom
                ),
                in: Capsule()
            )
            .shadow(color: Color.accentColor.opacity(0.35), radius: 12, y: 5)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
#endif
