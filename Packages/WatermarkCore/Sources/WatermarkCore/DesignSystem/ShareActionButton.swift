import SwiftUI

/// A standalone Share/Render button that drives off the ViewModel's
/// `renderingState`. Generic over any `WatermarkConfigurable & Observable`
/// ViewModel so all three targets can consume it.
///
/// Placement-agnostic — does not assume it's in ControlsView, a toolbar,
/// or a floating pill. The caller provides the container styling.
///
/// ## Rendering State Machine
///
/// Extracted verbatim from `ControlsView.swift` (the `shareButton` computed
/// property, lines 239–358). Preserves all 6 states, button copy, icons,
/// animations, and protocol method calls.
///
/// | State | Visual | Action |
/// |-------|--------|--------|
/// | `.idle` | "Share" / "Watermark All" (primary) | `renderAndPrepareShare()` |
/// | `.rendering` | Spinner + "Rendering..." (glass capsule, disabled) | — |
/// | `.renderingVideo(progress, eta)` | Progress bar + cancel button | Cancel → `cancelProcessing()` |
/// | `.batchProcessing(current, total, eta)` | Progress bar + stop button | Stop → `cancelProcessing()` |
/// | `.done` | "Ready to Share" / "Ready to Share All" (primary) | `presentShareSheet()` |
/// | `.error` | "Retry" (secondary) | `renderAndPrepareShare()` |
public struct ShareActionButton<ViewModel: WatermarkConfigurable & Observable>: View {
    @State var viewModel: ViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public init(viewModel: ViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        Group {
            switch viewModel.renderingState {
            case .idle:
                Button {
                    Task { await viewModel.renderAndPrepareShare() }
                } label: {
                    Label(
                        viewModel.hasMultiplePhotos ? "Watermark All" : "Share",
                        systemImage: viewModel.hasMultiplePhotos ? "square.and.arrow.up.on.square.fill" : "square.and.arrow.up"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.markepiPrimary())

            case .rendering:
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.regular)
                    Text("Rendering...")
                        .markepiTypography(.controlLabel)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .markepiGlass(shape: RoundedRectangle(cornerRadius: 12, style: .continuous),
                              isEnabled: !reduceTransparency)
                .disabled(true)
                .transition(.opacity.combined(with: .scale))

            case .renderingVideo(let progress, let eta):
                videoRenderingView(progress: progress, eta: eta)

            case .batchProcessing(let current, let total, let eta):
                batchProcessingView(current: current, total: total, eta: eta)

            case .done:
                Button {
                    if !reduceMotion {
                        withAnimation(.easeOut(duration: 0.3)) {}
                    }
                    viewModel.presentShareSheet()
                } label: {
                    Label(
                        viewModel.hasMultiplePhotos ? "Ready to Share All" : "Ready to Share",
                        systemImage: "checkmark.circle.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.markepiPrimary())

            case .error:
                Button {
                    Task { await viewModel.renderAndPrepareShare() }
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.markepiSecondary())
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: viewModel.renderingState)
    }

    // MARK: - Video Rendering State

    /// Renders the `.renderingVideo(progress:eta:)` state: progress bar,
    /// percentage, ETA, and a Cancel button.
    ///
    /// Extracted verbatim from `ControlsView.swift` lines 268–298.
    private func videoRenderingView(progress: Double, eta: TimeInterval?) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                ProgressView(value: progress, total: 1.0)
                    .progressViewStyle(.linear)
                    .tint(.blue)
                Text("\(Int(progress * 100))%")
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                    .frame(width: 36, alignment: .trailing)
            }
            if let eta = eta {
                Text("~\(Int(eta))s remaining")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("--")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Button {
                viewModel.cancelProcessing()
            } label: {
                Text("Cancel")
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
            }
            .buttonStyle(.markepiSecondary())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    // MARK: - Batch Processing State

    /// Renders the `.batchProcessing(current:total:eta:)` state: progress bar,
    /// count, ETA, and a Stop Processing button.
    ///
    /// Extracted verbatim from `ControlsView.swift` lines 300–330.
    private func batchProcessingView(current: Int, total: Int, eta: TimeInterval?) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                ProgressView(value: total > 0 ? Double(current) / Double(total) : 0, total: 1.0)
                    .progressViewStyle(.linear)
                    .tint(.blue)
                Text("\(current)/\(total)")
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                    .frame(width: 56, alignment: .trailing)
            }
            if let eta = eta, eta > 0 {
                Text("ETA: \(Int(eta / 60)) min")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("--")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Button {
                viewModel.cancelProcessing()
            } label: {
                Text("Stop Processing")
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
            }
            .buttonStyle(.markepiSecondary())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }
}
