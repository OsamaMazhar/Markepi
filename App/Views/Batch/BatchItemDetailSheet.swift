import SwiftUI
import UIKit
import WatermarkCore

/// Per-item watermark override modal sheet.
///
/// Presents the watermark controls scoped to a single batch item: text, font,
/// color and opacity; placement (position + scale); and the white-frame /
/// caption controls. A header card shows the photo being edited and whether it
/// currently carries a custom watermark, and a footer button resets the item
/// back to the shared batch configuration.
///
/// The layout mirrors the main editor's `ToolPanelView` — the same leaf control
/// views grouped in `EditorCard`s — so per-item editing feels identical to the
/// primary editing surface rather than a separate, lower-fidelity screen.
///
/// Only text, placement, and white-frame sub-views are shown — not
/// LogoPickerView, SignatureCaptureView, or LayerListView. Per-item overrides
/// adjust text/position/scale/frame on individual items; logo/signature layers
/// are inherited from the shared config.
///
/// Per UI-SPEC Interaction Contract #2.
public struct BatchItemDetailSheet: View {
    /// 0-based index for display label ("Photo X").
    let itemIndex: Int

    /// Thumbnail of the photo being adjusted, shown in the header card.
    let thumbnail: UIImage?

    /// The per-item configuration (writes back on change).
    @Binding var perItemConfig: WatermarkConfiguration

    /// The shared batch configuration for "Reset to Batch Settings".
    let sharedConfig: WatermarkConfiguration

    /// Clears the per-item override so the item follows the shared config and
    /// loses its "custom" indicator. Distinct from simply assigning the shared
    /// config, which would leave an (identical) override in place.
    let onReset: () -> Void

    /// Dismiss callback.
    let onDismiss: () -> Void

    /// Internal proxy that conforms to WatermarkConfigurable for sub-view binding.
    @State private var proxy: BatchItemConfigProxy

    /// Whether the current per-item config differs from the shared config.
    @State private var isModified: Bool = false

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public init(
        itemIndex: Int,
        thumbnail: UIImage? = nil,
        perItemConfig: Binding<WatermarkConfiguration>,
        sharedConfig: WatermarkConfiguration,
        onReset: @escaping () -> Void = {},
        onDismiss: @escaping () -> Void
    ) {
        self.itemIndex = itemIndex
        self.thumbnail = thumbnail
        self._perItemConfig = perItemConfig
        self.sharedConfig = sharedConfig
        self.onReset = onReset
        self.onDismiss = onDismiss
        self._proxy = State(initialValue: BatchItemConfigProxy(config: perItemConfig.wrappedValue))
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    headerCard
                    textSection
                    placementSection
                    frameSection
                    resetSection
                }
                .padding(.vertical, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Adjust Photo \(itemIndex + 1)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onDismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear {
            // Sync proxy with current perItemConfig on appear
            proxy.config = perItemConfig
            isModified = false
            // Wire up config change callback using JSON comparison
            proxy.onConfigChanged = { newConfig in
                perItemConfig = newConfig
                // Compare JSON representations to detect if config differs from shared
                let newData = (try? JSONEncoder().encode(newConfig)) ?? Data()
                let sharedData = (try? JSONEncoder().encode(sharedConfig)) ?? Data()
                isModified = newData != sharedData
            }
        }
    }

    // MARK: - Header card

    /// Shows the photo being edited alongside its override status, giving the
    /// sheet a clear subject the way Adobe's per-asset adjustment panels do.
    private var headerCard: some View {
        HStack(spacing: 14) {
            thumbnailView
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: MarkepiRadius.lg, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: MarkepiRadius.lg, style: .continuous)
                        .strokeBorder(MarkepiColors.controlStroke, lineWidth: 0.5)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text("Photo \(itemIndex + 1)")
                    .font(.headline)
                Label {
                    Text(isModified ? "Custom watermark" : "Using batch settings")
                        .markepiTypography(.metadata)
                } icon: {
                    Image(systemName: isModified ? "checkmark.seal.fill" : "rectangle.on.rectangle")
                        .font(.caption)
                        .foregroundStyle(isModified ? Color.accentColor : Color.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .markepiGlass(
            shape: RoundedRectangle(cornerRadius: MarkepiRadius.xl, style: .continuous),
            isEnabled: !reduceTransparency
        )
        .clipShape(RoundedRectangle(cornerRadius: MarkepiRadius.xl, style: .continuous))
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if let thumbnail {
            Image(uiImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            RoundedRectangle(cornerRadius: MarkepiRadius.lg, style: .continuous)
                .fill(Color(.systemGray5))
                .overlay {
                    Image(systemName: "photo")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
        }
    }

    // MARK: - Text section

    private var textSection: some View {
        VStack(spacing: 0) {
            sectionHeader("Text")
            TextWatermarkInputView(viewModel: proxy, showsSectionHeader: false)
        }
    }

    // MARK: - Placement section

    private var placementSection: some View {
        VStack(spacing: 0) {
            sectionHeader("Placement")
            EditorCard {
                positionMenuRow
                Divider().padding(.leading, 16)
                ScaleStepperView(viewModel: proxy)
            }
        }
    }

    // MARK: - Frame section

    private var frameSection: some View {
        VStack(spacing: 0) {
            sectionHeader("Frame & Caption")
            EditorCard {
                WhiteFrameToggleView(viewModel: proxy)
            }
        }
    }

    // MARK: - Reset section

    private var resetSection: some View {
        VStack(spacing: 10) {
            Button {
                proxy.config = sharedConfig
                onReset()
                isModified = false
            } label: {
                Label("Reset to Batch Settings", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.markepiSecondary())
            .disabled(!isModified)

            Text(isModified
                 ? "This photo uses a custom watermark that overrides the batch settings."
                 : "This photo follows the shared batch watermark.")
                .markepiTypography(.metadata)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    // MARK: - Shared bits

    /// Left-aligned section title matching `TextWatermarkInputView`'s header.
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .markepiTypography(.sectionHeader)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
    }

    // MARK: - Position Menu (replaces PositionGridView)

    private var positionMenuRow: some View {
        let idx = proxy.activeLayerIndex
        let currentPos: WatermarkPosition = {
            guard idx >= 0, idx < proxy.config.watermarks.count else { return .center }
            return proxy.config.watermarks[idx].position
        }()
        return HStack {
            Text("Position")
                .markepiTypography(.controlLabel)
            Spacer()
            Menu {
                PositionMenuContent(
                    current: currentPos,
                    layerIndex: idx,
                    layout: proxy.previewLayout
                ) { position in
                    let safeIdx = max(0, min(idx, proxy.config.watermarks.count - 1))
                    proxy.updateLayerPosition(at: safeIdx, position: position)
                }
            } label: {
                HStack(spacing: 4) {
                    Text(currentPos.displayName)
                        .markepiTypography(.value)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityLabel("Watermark position, currently \(currentPos.displayName)")
            .accessibilityHint("Double tap to choose a different position")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
