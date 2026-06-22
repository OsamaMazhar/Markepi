import SwiftUI
import WatermarkCore

/// Floating control panel for the currently-selected `EditorTool`.
///
/// Hosts the existing WatermarkCore leaf control views (text, logo, signature,
/// frame, layers) plus a few small rows reimplemented locally (position, format,
/// quality, save-as-template). Sits as a floating glass card above the tool dock
/// so the photo canvas stays visible behind it.
struct ToolPanelView: View {
    let tool: EditorTool
    @Bindable var viewModel: WatermarkViewModel
    var onClose: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    // Output-format state (mirrors the previous ControlsView behaviour).
    @State private var showHDRLossWarning = false

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 16) {
                    content
                }
                .padding(.vertical, 16)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
        }
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.regularMaterial)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.18), radius: 20, y: 8)
        .task(id: tool) { syncActiveLayer() }
    }

    /// Points `activeLayerIndex` at the layer this tool edits, so the shared
    /// position/scale controls act on the right layer when a tool is opened.
    private func syncActiveLayer() {
        let matches: (WatermarkLayer) -> Bool
        switch tool {
        case .text:      matches = { if case .text = $0 { return true }; return false }
        case .signature: matches = { if case .signature = $0 { return true }; return false }
        case .logo:      matches = { if case .image = $0 { return true }; return false }
        default: return
        }
        if let idx = viewModel.config.watermarks.firstIndex(where: matches) {
            viewModel.activeLayerIndex = idx
        }
    }

    /// True when any layer matches the predicate — used to show position/size
    /// controls only once the relevant layer (logo/signature) actually exists.
    private func hasLayer(matching predicate: (WatermarkLayer) -> Bool) -> Bool {
        viewModel.config.watermarks.contains(where: predicate)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text(tool.panelTitle)
                .font(.headline)
                .foregroundStyle(.primary)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary, Color.secondary.opacity(0.18))
            }
            .accessibilityLabel("Hide \(tool.panelTitle) controls")
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 4)
    }

    // MARK: - Per-tool content

    @ViewBuilder
    private var content: some View {
        switch tool {
        case .text:
            TextWatermarkInputView(viewModel: viewModel)
            EditorCard {
                positionRow
                Divider().padding(.leading, 16)
                ScaleStepperView(viewModel: viewModel)
            }
        case .logo:
            LogoPickerView(viewModel: viewModel)
            if hasLayer(matching: { if case .image = $0 { return true }; return false }) {
                EditorCard {
                    positionRow
                    Divider().padding(.leading, 16)
                    ScaleStepperView(viewModel: viewModel)
                }
            }
        case .signature:
            SignatureCaptureView(viewModel: viewModel)
            if hasLayer(matching: { if case .signature = $0 { return true }; return false }) {
                EditorCard {
                    positionRow
                    Divider().padding(.leading, 16)
                    ScaleStepperView(viewModel: viewModel)
                }
            }
        case .frame:
            EditorCard { WhiteFrameToggleView(viewModel: viewModel) }
        case .layers:
            layersContent
        case .output:
            EditorCard {
                exportFormatRow
                Divider().padding(.leading, 16)
                qualitySliderRow
            }
            saveTemplateButton
                .padding(.horizontal, 16)
        }
    }

    @ViewBuilder
    private var layersContent: some View {
        if viewModel.config.watermarks.isEmpty {
            emptyHint(
                icon: "square.stack.3d.up.slash",
                title: "No Layers Yet",
                message: "Add text, a logo, or a signature to build up your watermark."
            )
        } else {
            LayerListView(viewModel: viewModel)
        }
    }

    private func emptyHint(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 24)
    }

    // MARK: - Position row

    private var positionRow: some View {
        HStack {
            Text("Position")
                .markepiTypography(.controlLabel)
            Spacer()
            Menu {
                ForEach(WatermarkPosition.allCases, id: \.rawValue) { position in
                    Button(position.displayName) {
                        viewModel.updateLayerPosition(at: safeLayerIndex, position: position)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(currentPosition.displayName)
                        .markepiTypography(.value)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityLabel("Watermark position, currently \(currentPosition.displayName)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var safeLayerIndex: Int {
        max(0, viewModel.activeLayerIndex)
    }

    private var currentPosition: WatermarkPosition {
        let idx = safeLayerIndex
        guard idx < viewModel.config.watermarks.count else { return .center }
        return viewModel.config.watermarks[idx].position
    }

    // MARK: - Output format row

    private var exportFormatRow: some View {
        HStack {
            Text("Format")
                .markepiTypography(.controlLabel)
            Spacer()
            Menu {
                Button("HEIC") { viewModel.config.outputFormat = .heic }
                Button("JPEG") {
                    if viewModel.sourceHasHDR { showHDRLossWarning = true }
                    viewModel.config.outputFormat = .jpeg
                }
                Button("PNG") { viewModel.config.outputFormat = .png }
                Button("TIFF") { viewModel.config.outputFormat = .tiff }
                Button("Match Source\(viewModel.sourceFormatLabel.map { " (\($0))" } ?? "")") {
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
        .alert("HDR Will Be Lost", isPresented: $showHDRLossWarning) {
            Button("Convert to JPEG") {}
            Button("Cancel", role: .cancel) {
                viewModel.config.outputFormat = .preserveSource
            }
        } message: {
            Text("JPEG does not support HDR. The image will be converted to standard dynamic range.")
        }
    }

    private var currentFormatLabel: String {
        switch viewModel.config.outputFormat {
        case .heic: return "HEIC"
        case .jpeg: return "JPEG"
        case .png: return "PNG"
        case .tiff: return "TIFF"
        case .preserveSource:
            return "Match Source\(viewModel.sourceFormatLabel.map { " (\($0))" } ?? "")"
        }
    }

    // MARK: - Quality slider row

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

    // MARK: - Save as template

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

// MARK: - EditorCard

/// A glass-backed rounded card used to group rows in the tool panel.
/// Mirrors the styling used by the WatermarkCore leaf control views.
struct EditorCard<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .markepiGlass(
            shape: RoundedRectangle(cornerRadius: 12, style: .continuous),
            isEnabled: !reduceTransparency
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 16)
    }
}
