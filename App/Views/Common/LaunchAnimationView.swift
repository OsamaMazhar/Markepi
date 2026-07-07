import SwiftUI
import WatermarkCore

/// Animated launch splash shown once per cold launch.
///
/// This is a *pure overlay*: the real UI (`ContentView` / `OnboardingView`) is
/// built underneath it on the very first frame, so nothing about app init waits
/// on this view — the two run concurrently. The auto-dismiss timeline is driven
/// entirely by `async` `Task.sleep` (never a blocking `Thread.sleep`), so the
/// main thread is free to lay out the app behind the splash the whole time. If
/// the view goes away early, `.task` cancels and the `try?`-swallowed sleeps
/// simply return — it can never hang the launch.
///
/// Reuses the onboarding welcome hero (app logo + "Markepi" wordmark) so the
/// brand mark is identical to the first onboarding page.
struct LaunchAnimationView: View {
    /// Called once the entrance + hold has elapsed. The parent animates the
    /// overlay away (a `.transition(.opacity)` fade), so this view intentionally
    /// owns only the *entrance*, not the dismissal.
    let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Drives the entrance. Starts hidden/small; springs to visible/full-size.
    @State private var revealed = false

    // Adaptive glyph sizing mirrors the onboarding welcome hero.
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    @ScaledMetric private var wordmarkSize: CGFloat = UIDevice.current.userInterfaceIdiom == .pad ? 46 : 33
    @ScaledMetric private var glyphCircleSize: CGFloat = UIDevice.current.userInterfaceIdiom == .pad ? 140 : 120

    var body: some View {
        ZStack {
            MarkepiColors.canvasBackground
                .ignoresSafeArea()

            VStack(spacing: MarkepiSpacing.xxl) {
                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: glyphCircleSize, height: glyphCircleSize)
                    .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
                    .accessibilityLabel("Markepi")

                Text("Markepi")
                    .font(.system(size: wordmarkSize, weight: .bold))
                    .foregroundStyle(.primary)
            }
            // Entrance: fade + gentle scale-up. Reduce Motion collapses this to a
            // straight fade (no scale) so it stays calm for motion-sensitive users.
            .scaleEffect(reduceMotion ? 1 : (revealed ? 1 : 0.82))
            .opacity(revealed ? 1 : 0)
        }
        .task {
            // Entrance.
            if reduceMotion {
                withAnimation(.easeOut(duration: 0.25)) { revealed = true }
            } else {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.72)) { revealed = true }
            }

            // Hold so the mark is legible, then hand back to the parent to fade
            // out. Reduce Motion shortens the dwell. `try?` swallows the
            // cancellation error if the overlay is torn down early.
            let holdNanos: UInt64 = reduceMotion ? 500_000_000 : 1_150_000_000
            try? await Task.sleep(nanoseconds: holdNanos)

            onFinished()
        }
    }
}
