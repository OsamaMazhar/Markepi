import SwiftUI
import WatermarkCore

/// Compact, single Export action for the editor's top bar.
///
/// Replaces the old duplicated "Share" buttons (the floating pinned bar *and*
/// the one inside the Output section). Terminal states render as a prominent
/// tinted button; long-running states render a small spinner and defer the
/// detailed progress + cancel affordance to `RenderProgressBanner`.
struct ExportToolbarButton: View {
    @Bindable var viewModel: WatermarkViewModel

    var body: some View {
        switch viewModel.renderingState {
        case .idle:
            Button {
                Task { await viewModel.renderAndPrepareShare() }
            } label: {
                Label(viewModel.hasMultiplePhotos ? "Export All" : "Export",
                      systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.borderedProminent)
            .tint(.accentColor)

        case .rendering, .renderingVideo, .batchProcessing:
            ProgressView()
                .controlSize(.small)

        case .done:
            Button {
                // Render is complete (button stays green). Re-open the export
                // receipt so the user always confirms from there, rather than
                // jumping straight into the share sheet. Only fall back to the
                // share sheet when there's no receipt to show (e.g. formats that
                // don't produce a provenance receipt).
                if viewModel.lastExportReceipt != nil {
                    viewModel.showExportReceipt = true
                } else {
                    viewModel.presentShareSheet()
                }
            } label: {
                Label(viewModel.hasMultiplePhotos ? "Share All" : "Share",
                      systemImage: "checkmark.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)

        case .error:
            Button {
                Task { await viewModel.renderAndPrepareShare() }
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .tint(.orange)
        }
    }
}

/// Floating progress banner shown above the tool dock during single-item
/// rendering and video export. Batch progress keeps its own full overlay.
struct RenderProgressBanner: View {
    @Bindable var viewModel: WatermarkViewModel
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        switch viewModel.renderingState {
        case .rendering:
            banner {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Rendering…")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                }
            }
        case .renderingVideo(let progress, let eta):
            banner {
                VStack(spacing: 10) {
                    HStack(spacing: 12) {
                        ProgressView(value: progress, total: 1.0)
                            .progressViewStyle(.linear)
                            .tint(.accentColor)
                        Text("\(Int(progress * 100))%")
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                    HStack {
                        // Near 100% the export is finalizing/writing the file —
                        // say so instead of a static "100%" that looks hung.
                        Text(progress >= 0.99
                             ? "Finalizing…"
                             : (eta.map { "About \(Int($0))s remaining" } ?? "Exporting video…"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Cancel", role: .destructive) {
                            viewModel.cancelProcessing()
                        }
                        .font(.subheadline.weight(.medium))
                    }
                }
            }
        default:
            EmptyView()
        }
    }

    private func banner<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.regularMaterial)
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 18, y: 6)
            .padding(.horizontal, 12)
    }
}
