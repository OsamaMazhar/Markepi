import CoreImage
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Logo/image watermark picker with Photos library and Files app support.
///
/// Generic over any `WatermarkConfigurable & Observable` ViewModel.
public struct LogoPickerView<ViewModel: WatermarkConfigurable & Observable>: View {
    @Bindable var viewModel: ViewModel
    @State private var showConfirmationDialog = false
    @State private var showPhotosPicker = false
    @State private var showFileImporter = false
    @State private var logoPickerItems: [PhotosPickerItem] = []
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
        VStack(spacing: 0) {
            // Section header
            if showsSectionHeader {
                Text("Logo")
                    .markepiTypography(.sectionHeader)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }

            if logoLayerIndices.isEmpty {
                // Empty state: a single capsule button, with no surrounding card
                // so its shape isn't nested inside a mismatched rounded rect.
                addLogoButton
                    .padding(.horizontal, 16)
            } else {
                // One selectable, removable row per logo instance.
                VStack(spacing: 0) {
                    ForEach(Array(logoLayerIndices.enumerated()), id: \.element) { ordinal, index in
                        logoRow(index: index, ordinal: ordinal + 1)
                        if index != logoLayerIndices.last {
                            Divider().padding(.leading, 16)
                        }
                    }
                }
                .markepiGlass(
                    shape: RoundedRectangle(cornerRadius: 12, style: .continuous),
                    isEnabled: !reduceTransparency
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 16)

                // "Add another logo" — capsule button below the card.
                addLogoButton
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
            }
        }
        .confirmationDialog("Add Logo Watermark", isPresented: $showConfirmationDialog) {
            Button("From Photos") {
                showPhotosPicker = true
            }
            Button("From Files") {
                showFileImporter = true
            }
            Button("Cancel", role: .cancel) {}
        }
        .photosPicker(
            isPresented: $showPhotosPicker,
            selection: $logoPickerItems,
            maxSelectionCount: 1,
            matching: .images
        )
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.png]
        ) { result in
            switch result {
            case .success(let url):
                guard let data = try? Data(contentsOf: url) else { return }
                viewModel.addLogoLayer(pngData: data)
            case .failure:
                break
            }
        }
        .onChange(of: logoPickerItems) { _, items in
            guard let item = items.first else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    viewModel.addLogoLayer(pngData: data)
                }
                logoPickerItems = []
            }
        }
    }

    /// Indices of every image (logo) layer, in stack order.
    private var logoLayerIndices: [Int] {
        viewModel.config.watermarks.indices.filter {
            if case .image = viewModel.config.watermarks[$0] { return true }
            return false
        }
    }

    private var addLogoButton: some View {
        Button {
            showConfirmationDialog = true
        } label: {
            Label(logoLayerIndices.isEmpty ? "Add Logo" : "Add Another Logo",
                  systemImage: "photo.badge.plus")
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.markepiPrimary())
        .accessibilityLabel("Add logo watermark")
        .accessibilityHint("Choose a logo image from your photo library or files")
    }

    /// A single logo instance: tap to select (so position/scale edit it),
    /// trash to remove. The active instance is highlighted.
    private func logoRow(index: Int, ordinal: Int) -> some View {
        let isActive = viewModel.activeLayerIndex == index
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "photo")
                    .foregroundStyle(isActive ? Color.accentColor : .secondary)
                    .frame(width: 24)

                Text("Logo \(ordinal)")
                    .markepiTypography(.controlLabel)

                if isActive {
                    Text("Editing")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.16), in: Capsule())
                }

                Spacer()

                Button(role: .destructive) {
                    withAnimation(.easeOut(duration: 0.25)) {
                        viewModel.removeLayer(at: index)
                    }
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove Logo \(ordinal)")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .onTapGesture { viewModel.activeLayerIndex = index }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(isActive ? [.isSelected, .isButton] : .isButton)
            .accessibilityHint("Double tap to select this logo for position and size edits")

            if isActive {
                Divider()
                    .padding(.leading, 52)
                logoOpacityControl(index: index)
            }
        }
    }

    private func logoOpacityControl(index: Int) -> some View {
        let binding = logoOpacityBinding(index)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Opacity")
                    .markepiTypography(.controlLabel)
                Spacer()
                Text("\(Int((binding.wrappedValue * 100).rounded()))%")
                    .markepiTypography(.value)
                    .monospacedDigit()
            }
            Slider(value: binding, in: 0...1, step: 0.01) { isEditing in
                if isEditing {
                    viewModel.beginInteractiveConfigChange()
                } else {
                    viewModel.endInteractiveConfigChange()
                }
            }
                .accessibilityLabel("Logo opacity")
                .accessibilityValue("\(Int((binding.wrappedValue * 100).rounded())) percent")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.accentColor.opacity(0.08))
    }

    private func logoOpacityBinding(_ index: Int) -> Binding<Double> {
        Binding(
            get: {
                guard let input = logoInput(at: index) else { return 0.8 }
                return Double(input.opacity)
            },
            set: { updateLogoOpacity(at: index, opacity: CGFloat($0)) }
        )
    }

    private func logoInput(at index: Int) -> ImageWatermarkInput? {
        guard viewModel.config.watermarks.indices.contains(index),
              case let .image(input, _, _, _, _) = viewModel.config.watermarks[index] else { return nil }
        return input
    }

    private func updateLogoOpacity(at index: Int, opacity: CGFloat) {
        guard viewModel.config.watermarks.indices.contains(index),
              case let .image(input, position, scale, layerOpacity, isVisible) = viewModel.config.watermarks[index]
        else { return }

        let clamped = max(0.0, min(1.0, opacity))
        guard abs(input.opacity - clamped) >= 0.0005 else { return }

        viewModel.config.watermarks[index] = .image(
            input.withOpacity(clamped),
            position: position,
            scale: scale,
            opacity: layerOpacity,
            isVisible: isVisible
        )
        if viewModel.activeLayerIndex != index {
            viewModel.activeLayerIndex = index
        }
    }
}
