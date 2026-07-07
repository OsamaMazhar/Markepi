import SwiftUI
import WatermarkCore

/// Full preview-area overlay shown during batch processing.
///
/// Displays a determinate progress bar, "X of Y" item count, ETA label,
/// and a red "Stop Processing" cancel button. Rendered with .ultraThinMaterial
/// background over the preview area in ContentView.
///
/// Per UI-SPEC Interaction Contract #4.
public struct BatchProgressOverlay: View {
    /// 1-based index of the currently processing item (0 when not started).
    let current: Int

    /// Total number of items in the batch.
    let total: Int

    /// Estimated time remaining in seconds, or nil when not yet available.
    let eta: TimeInterval?

    /// Cancel callback invoked when the user taps "Stop Processing".
    let onCancel: () -> Void

    /// Reduce Motion accessibility setting — declared here for Plan 18-03
    /// call site gating (.transition(reduceMotion ? .identity : .opacity)).
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        current: Int,
        total: Int,
        eta: TimeInterval?,
        onCancel: @escaping () -> Void
    ) {
        self.current = current
        self.total = total
        self.eta = eta
        self.onCancel = onCancel
    }

    public var body: some View {
        ZStack {
            Color.clear
                .background(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                // Count label — centered, semibold caption, monospaced digits
                Text("\(current) of \(total)")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)

                // Determinate progress bar — full width, blue tint
                ProgressView(
                    value: min(Double(current), Double(total)),
                    total: Double(total)
                )
                .progressViewStyle(.linear)
                .tint(.blue)
                .frame(maxWidth: 280)

                // ETA label — caption2, secondary color
                if let eta = eta, eta > 0 {
                    Text("ETA: \(Int(eta / 60)) min")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Estimating...")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer().frame(height: 8)

                // Cancel button — red-tinted bordered, 50pt height
                Button(role: .destructive, action: onCancel) {
                    Text("Stop Processing")
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .frame(width: MarkepiSizing.batchCancelButtonWidth)
                .accessibilityLabel("Cancel batch processing")
            }
            .padding(32)
            .accessibilityElement(children: .contain)
        }
        .accessibilityValue("\(current) of \(total)")
    }
}
