import SwiftUI
import WatermarkCore

/// Displays all watermark layers with selection and removal capability.
///
/// Generic over any `WatermarkConfigurable & Observable` ViewModel.
public struct LayerListView<ViewModel: WatermarkConfigurable & Observable>: View {
    @Bindable var viewModel: ViewModel

    public init(viewModel: ViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        if viewModel.config.watermarks.isEmpty { EmptyView() }
        else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Watermark Layers")
                    .font(.title3.weight(.semibold))

                VStack(spacing: 0) {
                    ForEach(Array(viewModel.config.watermarks.enumerated()), id: \.offset) { index, layer in
                        layerRow(index: index, layer: layer)
                            .transition(.opacity.combined(with: .move(edge: .trailing)))

                        if index < viewModel.config.watermarks.count - 1 {
                            Divider()
                        }
                    }
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                .clipShape(RoundedRectangle(cornerRadius: 10))
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
                    .foregroundStyle(.secondary)
                    .frame(width: 24)

                Text(layerDescription(for: layer))
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer()

                Button {
                    withAnimation(.easeOut(duration: 0.25)) {
                        viewModel.removeLayer(at: index)
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                        .font(.title3)
                }
                .frame(width: 44, height: 44)
                .accessibilityLabel("Remove layer: \(layerDescription(for: layer))")
                .accessibilityHint("Double tap to remove this watermark layer")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }

    private func layerIcon(for layer: WatermarkLayer) -> String {
        switch layer {
        case .text: return "textformat"
        case .image: return "photo"
        }
    }

    private func layerDescription(for layer: WatermarkLayer) -> String {
        switch layer {
        case .text(let input, _, _):
            if input.text.isEmpty { return "Text" }
            return String(input.text.prefix(20))
        case .image:
            return "Logo"
        }
    }
}
