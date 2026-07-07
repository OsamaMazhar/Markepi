import SwiftUI

/// Layer manager: lists every watermark layer with selection, visibility,
/// reordering, opacity, and removal — the parametric stack editor.
///
/// The stack is bottom-to-top (index 0 composites first / lowest). Tapping a
/// row makes it the active layer; the type-specific panels (Text, Signature…)
/// then edit that layer's parameters.
///
/// Generic over any `WatermarkConfigurable & Observable` ViewModel.
public struct LayerListView<ViewModel: WatermarkConfigurable & Observable>: View {
    @Bindable var viewModel: ViewModel
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// Whether to render the built-in section header. Hidden when the host
    /// already provides a single title (editor tool panel); shown when the view
    /// stands alone as a labeled section (extensions' ControlsView).
    private let showsSectionHeader: Bool

    public init(viewModel: ViewModel, showsSectionHeader: Bool = true) {
        self.viewModel = viewModel
        self.showsSectionHeader = showsSectionHeader
    }

    public var body: some View {
        if viewModel.config.watermarks.isEmpty { EmptyView() }
        else {
            VStack(spacing: 0) {
                if showsSectionHeader {
                    Text("Layers")
                        .markepiTypography(.sectionHeader)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }

                VStack(spacing: 0) {
                    ForEach(Array(viewModel.config.watermarks.enumerated()), id: \.offset) { index, layer in
                        layerRow(index: index, layer: layer)
                            .transition(.opacity.combined(with: .move(edge: .trailing)))

                        if index < viewModel.config.watermarks.count - 1 {
                            Divider().padding(.leading, 52)
                        }
                    }
                }
                .markepiGlass(
                    shape: RoundedRectangle(cornerRadius: 12, style: .continuous),
                    isEnabled: !reduceTransparency
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 16)

                Text("Top layer sits in front. Tap a layer to edit it.")
                    .markepiTypography(.metadata)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
            }
        }
    }

    @ViewBuilder
    private func layerRow(index: Int, layer: WatermarkLayer) -> some View {
        let isActive = viewModel.activeLayerIndex == index
        let count = viewModel.config.watermarks.count

        VStack(spacing: 0) {
            Button {
                viewModel.activeLayerIndex = index
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: layerIcon(for: layer))
                        .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(layerTypeName(for: layer))
                            .markepiTypography(.controlLabel)
                        Text(layerSubtitle(for: layer))
                            .markepiTypography(.metadata)
                            .lineLimit(1)
                    }

                    Spacer()

                    // Visibility toggle — hide a layer without deleting it.
                    Button {
                        viewModel.setLayerVisibility(at: index, isVisible: !layer.isVisible)
                    } label: {
                        Image(systemName: layer.isVisible ? "eye" : "eye.slash")
                            .foregroundStyle(layer.isVisible ? Color.secondary : Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 40, height: 40)
                    .accessibilityLabel(layer.isVisible ? "Hide layer" : "Show layer")

                    // Reorder.
                    VStack(spacing: 0) {
                        Button {
                            viewModel.moveLayer(from: index, to: index + 1)
                        } label: {
                            Image(systemName: "chevron.up").font(.caption.weight(.bold))
                        }
                        .buttonStyle(.plain)
                        .disabled(index >= count - 1)
                        .accessibilityLabel("Move layer up")

                        Button {
                            viewModel.moveLayer(from: index, to: index - 1)
                        } label: {
                            Image(systemName: "chevron.down").font(.caption.weight(.bold))
                        }
                        .buttonStyle(.plain)
                        .disabled(index <= 0)
                        .accessibilityLabel("Move layer down")
                    }
                    .foregroundStyle(.secondary)
                    .frame(width: 32)

                    Button {
                        withAnimation(.easeOut(duration: 0.25)) {
                            viewModel.removeLayer(at: index)
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill").font(.title3)
                    }
                    .buttonStyle(.markepiDestructive())
                    .frame(width: 40, height: 40)
                    .accessibilityLabel("Remove layer: \(layerDescription(for: layer))")
                    .accessibilityHint("Double tap to remove this watermark layer")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(isActive ? Color.accentColor.opacity(0.08) : Color.clear)
            }
            .buttonStyle(.plain)

            // Universal parametric controls for the active layer — position,
            // size, and opacity — available on every layer type (text, logo,
            // signature). This is where layers are placed in different spots.
            if isActive {
                VStack(alignment: .leading, spacing: 12) {
                    // Position (9-preset grid)
                    HStack {
                        Text("Position")
                            .markepiTypography(.controlLabel)
                        Spacer()
                        Menu {
                            ForEach(WatermarkPosition.allCases, id: \.rawValue) { position in
                                Button {
                                    viewModel.updateLayerPosition(at: index, position: position)
                                } label: {
                                    if layer.position == position {
                                        Label(position.displayName, systemImage: "checkmark")
                                    } else {
                                        Text(position.displayName)
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(layer.position.displayName)
                                    .markepiTypography(.value)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityLabel("Layer position, currently \(layer.position.displayName)")
                    }

                    // Size
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Size")
                                .markepiTypography(.controlLabel)
                            Spacer()
                            Text("\(Int((scaleBinding(index).wrappedValue * 100).rounded()))%")
                                .markepiTypography(.value)
                                .monospacedDigit()
                        }
                        Slider(value: scaleBinding(index), in: 0.02...0.90)
                            .accessibilityLabel("Layer size")
                    }

                    // Opacity
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Opacity")
                                .markepiTypography(.controlLabel)
                            Spacer()
                            Text("\(Int((opacityBinding(index).wrappedValue * 100).rounded()))%")
                                .markepiTypography(.value)
                                .monospacedDigit()
                        }
                        Slider(value: opacityBinding(index), in: 0...1, step: 0.01) { isEditing in
                            if isEditing {
                                viewModel.beginInteractiveConfigChange()
                            } else {
                                viewModel.endInteractiveConfigChange()
                            }
                        }
                            .accessibilityLabel("Layer opacity")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.accentColor.opacity(0.08))
            }
        }
    }

    private func opacityBinding(_ index: Int) -> Binding<Double> {
        Binding(
            get: {
                guard viewModel.config.watermarks.indices.contains(index) else { return 1 }
                return Double(viewModel.config.watermarks[index].opacity)
            },
            set: { viewModel.setLayerOpacity(at: index, opacity: CGFloat($0)) }
        )
    }

    private func scaleBinding(_ index: Int) -> Binding<Double> {
        Binding(
            get: {
                guard viewModel.config.watermarks.indices.contains(index) else { return 0.15 }
                return Double(viewModel.config.watermarks[index].scale)
            },
            set: { viewModel.updateLayerScale(at: index, scale: CGFloat($0)) }
        )
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
