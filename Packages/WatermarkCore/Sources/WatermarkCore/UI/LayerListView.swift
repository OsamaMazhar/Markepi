import SwiftUI
import WatermarkCore

/// Displays all watermark layers with selection and removal capability.
///
/// Generic over any `WatermarkConfigurable & Observable` ViewModel.
public struct LayerListView<ViewModel: WatermarkConfigurable & Observable>: View {
    @Bindable var viewModel: ViewModel
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public init(viewModel: ViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        if viewModel.config.watermarks.isEmpty { EmptyView() }
        else {
            VStack(spacing: 0) {
                // Section header
                Text("Layers")
                    .markepiTypography(.sectionHeader)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)

                // Row container with glass backing
                VStack(spacing: 0) {
                    ForEach(Array(viewModel.config.watermarks.enumerated()), id: \.offset) { index, layer in
                        layerRow(index: index, layer: layer)
                            .transition(.opacity.combined(with: .move(edge: .trailing)))

                        if index < viewModel.config.watermarks.count - 1 {
                            Divider()
                                .padding(.leading, 52)
                        }
                    }
                }
                .markepiGlass(
                    shape: RoundedRectangle(cornerRadius: 12, style: .continuous),
                    isEnabled: !reduceTransparency
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 16)
            }
        }
    }

    @ViewBuilder
    private func layerRow(index: Int, layer: WatermarkLayer) -> some View {
        Button {
            viewModel.activeLayerIndex = index
        } label: {
            HStack(spacing: 12) {
                Image(systemName: layerIcon(for: layer))
                    .foregroundStyle(viewModel.activeLayerIndex == index ? Color.accentColor : Color.secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(layerTypeName(for: layer))
                        .markepiTypography(.controlLabel)
                    Text(layerSubtitle(for: layer))
                        .markepiTypography(.metadata)
                        .lineLimit(1)
                }

                Spacer()

                Button {
                    withAnimation(.easeOut(duration: 0.25)) {
                        viewModel.removeLayer(at: index)
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.markepiDestructive())
                .frame(width: 44, height: 44)
                .accessibilityLabel("Remove layer: \(layerDescription(for: layer))")
                .accessibilityHint("Double tap to remove this watermark layer")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                viewModel.activeLayerIndex == index
                    ? Color.accentColor.opacity(0.08)
                    : Color.clear
            )
        }
        .buttonStyle(.plain)
    }

    private func layerIcon(for layer: WatermarkLayer) -> String {
        switch layer {
        case .text: return "textformat"
        case .image: return "photo"
        case .signature: return "signature"
        }
    }

    private func layerTypeName(for layer: WatermarkLayer) -> String {
        switch layer {
        case .text: return "Text"
        case .image: return "Logo"
        case .signature: return "Signature"
        }
    }

    private func layerSubtitle(for layer: WatermarkLayer) -> String {
        switch layer {
        case .text(let input, _, _, _, _):
            if input.text.isEmpty { return "Text watermark" }
            let truncated = String(input.text.prefix(30))
            return truncated.count < input.text.count ? truncated + "…" : truncated
        case .image:
            return "Image watermark"
        case .signature:
            return "Hand-drawn"
        }
    }

    private func layerDescription(for layer: WatermarkLayer) -> String {
        switch layer {
        case .text(let input, _, _, _, _):
            if input.text.isEmpty { return "Text" }
            return String(input.text.prefix(20))
        case .image:
            return "Logo"
        case .signature:
            return "Signature"
        }
    }
}
