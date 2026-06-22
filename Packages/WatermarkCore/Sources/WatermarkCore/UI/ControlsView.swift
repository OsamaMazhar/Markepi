import SwiftUI
import WatermarkCore

/// Composite view combining all watermarking controls: text input, position
/// picker, scale stepper, logo picker, white frame toggle, and layer list.
///
/// Generic over any `WatermarkConfigurable & Observable` ViewModel so both
/// the main app and share extension can reuse it with their own ViewModels.
///
/// Includes the Share/Render button which adapts to the ViewModel's
/// `renderingState` (idle/rendering/done/error).
public struct ControlsView<ViewModel: WatermarkConfigurable & Observable>: View {
    @State var viewModel: ViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    // Section switching state
    @State private var section: ControlsSection = .watermark

    // Export Options state
    @State private var showHDRLossWarning = false
    @State private var pendingFormatSelection: OutputFormat = .preserveSource

    /// Computed property for source format label shown when .preserveSource is selected.
    /// Defaults to nil — the ViewModel provides the label after media loading.
    private var sourceFormatLabel: String? {
        viewModel.sourceFormatLabel
    }

    /// True when the ViewModel has multiple photos loaded — gates batch-mode UI.
    private var isBatchMode: Bool { viewModel.hasMultiplePhotos }

    public init(viewModel: ViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            switch section {
            case .watermark:
                watermarkSectionContent
            case .style:
                styleSectionContent
            case .output:
                outputSectionContent
            }
        }
        .markepiScrollEdgeProtection {
            MarkepiPillBar(selection: $section)
        }
    }

    // MARK: - Section 1: Watermark

    private var watermarkSectionContent: some View {
        VStack(spacing: 16) {
            ControlSection(label: "Text and position controls") {
                TextWatermarkInputView(viewModel: viewModel)
            }
            ControlSection(label: "Text and position controls") {
                positionMenuRow
                Divider()
                    .padding(.leading, 52)
                ScaleStepperView(viewModel: viewModel)
            }
        }
        .padding(.top, 16)
    }

    private var positionMenuRow: some View {
        let currentPos = currentPosition
        return HStack {
            Text("Position")
                .markepiTypography(.controlLabel)
            Spacer()
            Menu {
                ForEach(WatermarkPosition.allCases, id: \.rawValue) { position in
                    Button(position.displayName) {
                        let idx = safeLayerIndex
                        viewModel.updateLayerPosition(at: idx, position: position)
                    }
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

    private var currentPosition: WatermarkPosition {
        let idx = safeLayerIndex
        guard idx < viewModel.config.watermarks.count else { return .center }
        return viewModel.config.watermarks[idx].position
    }

    private var safeLayerIndex: Int {
        let idx = viewModel.activeLayerIndex
        guard idx >= 0 else { return 0 }
        return idx
    }

    // MARK: - Section 2: Style

    private var styleSectionContent: some View {
        VStack(spacing: 16) {
            LogoPickerView(viewModel: viewModel)
                .padding(.bottom, 16)
            SignatureCaptureView(viewModel: viewModel)
                .padding(.bottom, 16)
            WhiteFrameToggleView(viewModel: viewModel)
                .padding(.bottom, 16)
            LayerListView(viewModel: viewModel)
        }
        .padding(.top, 16)
    }

    // MARK: - Section 3: Output

    private var outputSectionContent: some View {
        VStack(spacing: 16) {
            ControlSection(label: "Export options") {
                exportFormatRow
                Divider()
                    .padding(.leading, 52)
                qualitySliderRow
            }
            .alert("HDR Will Be Lost", isPresented: $showHDRLossWarning) {
                Button("Convert to JPEG") {
                    // Keep JPEG selection — config already changed
                    pendingFormatSelection = .preserveSource
                }
                Button("Cancel", role: .cancel) {
                    viewModel.config.outputFormat = .preserveSource
                }
            } message: {
                Text("JPEG does not support HDR. The image will be converted to standard dynamic range.")
            }

            ControlSection(label: "Template controls") {
                saveTemplateButton
            }

            ShareActionButton(viewModel: viewModel)
                .padding(.horizontal, 16)
        }
        .padding(.top, 16)
    }

    // MARK: - Export Format Row

    private var exportFormatRow: some View {
        HStack {
            Text("Format")
                .markepiTypography(.controlLabel)
            Spacer()
            Menu {
                Button("HEIC") {
                    viewModel.config.outputFormat = .heic
                }
                Button("JPEG") {
                    if viewModel.sourceHasHDR {
                        pendingFormatSelection = .jpeg
                        showHDRLossWarning = true
                    }
                    viewModel.config.outputFormat = .jpeg
                }
                Button("PNG") {
                    viewModel.config.outputFormat = .png
                }
                Button("TIFF") {
                    viewModel.config.outputFormat = .tiff
                }
                Button("Match Source\(sourceFormatLabel.map { " (\($0))" } ?? "")") {
                    viewModel.config.outputFormat = .preserveSource
                }
            } label: {
                HStack(spacing: 4) {
                    Text(currentFormatLabel)
                        .markepiTypography(.value)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var currentFormatLabel: String {
        switch viewModel.config.outputFormat {
        case .heic: return "HEIC"
        case .jpeg: return "JPEG"
        case .png: return "PNG"
        case .tiff: return "TIFF"
        case .preserveSource: return "Match Source\(sourceFormatLabel.map { " (\($0))" } ?? "")"
        }
    }

    // MARK: - Quality Slider Row

    private var qualitySliderRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Quality")
                    .markepiTypography(.controlLabel)
                Spacer()
                Text("\(Int(viewModel.config.outputQuality * 100))%")
                    .markepiTypography(.value)
            }
            Slider(value: Binding(
                get: { viewModel.config.outputQuality },
                set: { newValue in
                    // Snap to 1.0 when >= 0.98
                    if newValue >= 0.98 && newValue < 1.0 {
                        viewModel.config.outputQuality = 1.0
                    } else {
                        viewModel.config.outputQuality = newValue
                    }
                }
            ), in: 0.6...1.0, step: 0.01)
            .disabled(viewModel.config.outputFormat.isLossless)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Save-as-Template Button

    private var saveTemplateButton: some View {
        Button {
            viewModel.showSaveTemplateAlert = true
        } label: {
            Label("Save as Template", systemImage: "square.and.arrow.down.on.square")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.markepiSecondary())
    }
}

// MARK: - ControlSection

private struct ControlSection<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let label: String
    @ViewBuilder let content: () -> Content

    init(label: String, @ViewBuilder content: @escaping () -> Content) {
        self.label = label
        self.content = content
    }

    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
        .markepiGlass(
            shape: RoundedRectangle(cornerRadius: 12, style: .continuous),
            isEnabled: !reduceTransparency
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 16)
    }
}
