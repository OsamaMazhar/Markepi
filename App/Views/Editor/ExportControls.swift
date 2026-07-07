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

    /// When true, renders the prominent states as a CIRCULAR Liquid Glass button
    /// (real `.glassProminent` on device, `.borderedProminent` on the simulator
    /// where the glass styles crash). Used by the landscape side rail so Share
    /// reads as a round glass button like the portrait toolbar's, instead of the
    /// flat bordered fill `borderedProminent` gives outside a toolbar. Toolbar
    /// usage keeps `glassCircle == false`: the nav bar themes the button itself.
    var glassCircle: Bool = false

    /// Square content box for the circular rail button. Sizing the *label* (not
    /// the whole control) keeps the glyph centered in the circle and gives the
    /// prominent glass button a predictable diameter once its own padding is
    /// added — matching the left rail's Back button without `controlSize(.large)`
    /// (which blew the button up too large).
    private static let railLabelSize: CGFloat = 30

    var body: some View {
        switch viewModel.renderingState {
        case .idle:
            Button {
                Task { await viewModel.renderAndPrepareShare() }
            } label: {
                exportLabel("Export", icon: "square.and.arrow.up")
            }
            .modifier(ProminentExportStyle(glassCircle: glassCircle, tint: .accentColor))

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
                exportLabel("Share", icon: "checkmark.circle.fill")
            }
            .modifier(ProminentExportStyle(glassCircle: glassCircle, tint: MarkepiColors.statusSuccess))

        case .error:
            Button {
                Task { await viewModel.renderAndPrepareShare() }
            } label: {
                exportLabel("Retry", icon: "arrow.clockwise")
            }
            .modifier(ProminentExportStyle(glassCircle: glassCircle, tint: MarkepiColors.statusWarning))
        }
    }

    /// The button label. In the toolbar it shows the title + icon. In the
    /// landscape rail it's icon-only and framed to a centered square so the
    /// prominent glass circle wraps it symmetrically (the bare `square.and.arrow.up`
    /// glyph otherwise sits high/off-centre in the circle).
    @ViewBuilder
    private func exportLabel(_ title: String, icon: String) -> some View {
        let resolvedTitle = (icon == "square.and.arrow.up" || icon == "checkmark.circle.fill")
            && viewModel.hasMultiplePhotos ? "\(title) All" : title
        if glassCircle {
            Label(resolvedTitle, systemImage: icon)
                .labelStyle(.iconOnly)
                .frame(width: Self.railLabelSize, height: Self.railLabelSize)
                // `square.and.arrow.up` is bottom-heavy (the tray + baseline
                // whitespace) so it reads slightly low/off-centre when boxed.
                // A 1pt upward nudge optically centres the arrow in the circle;
                // the other glyphs (checkmark/clockwise) are already balanced.
                .offset(y: icon == "square.and.arrow.up" ? -1 : 0)
        } else {
            Label(resolvedTitle, systemImage: icon)
        }
    }
}

/// Applies the export button's prominent styling. In the toolbar (`glassCircle
/// == false`) it's a standard prominent/tinted button the nav bar themes into
/// glass. In the landscape rail (`glassCircle == true`) it's a CIRCULAR button
/// using the real `.glassProminent` Liquid Glass style on a device, falling back
/// to `.borderedProminent` on the simulator — the glass button styles hit the
/// same `swift_getOpaqueTypeMetadata` crash as `glassEffect` on simulators that
/// don't match the SDK, so `#if targetEnvironment(simulator)` keeps that call
/// out of simulator builds. No `controlSize(.large)`: the circle's size comes
/// from the square label so it matches the left-rail buttons.
private struct ProminentExportStyle: ViewModifier {
    let glassCircle: Bool
    let tint: Color

    func body(content: Content) -> some View {
        if glassCircle {
            #if targetEnvironment(simulator)
            content
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
                .tint(tint)
            #else
            if #available(iOS 26, *) {
                content
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.circle)
                    .tint(tint)
            } else {
                content
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.circle)
                    .tint(tint)
            }
            #endif
        } else {
            content
                .buttonStyle(.borderedProminent)
                .tint(tint)
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
                RoundedRectangle(cornerRadius: MarkepiRadius.xxxl, style: .continuous)
                    .fill(.regularMaterial)
            }
            .clipShape(RoundedRectangle(cornerRadius: MarkepiRadius.xxxl, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 18, y: 6)
            .padding(.horizontal, 12)
    }
}
