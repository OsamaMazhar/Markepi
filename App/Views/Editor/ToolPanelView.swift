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

    /// Tallest the panel grows before its contents scroll. Lets short panels
    /// (e.g. logo/signature before a layer exists) size to their content
    /// instead of stretching to fill the dock or side rail.
    var maxHeight: CGFloat = 420

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    // Output-format state (mirrors the previous ControlsView behaviour).
    @State private var showHDRLossWarning = false

    /// Measured height of the scroll content, used to shrink the panel to fit
    /// its content (capped by `maxHeight`). Zero until the first layout pass.
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(spacing: 16) {
                    content
                }
                .padding(.vertical, 16)
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(key: PanelContentHeightKey.self, value: proxy.size.height)
                    }
                }
            }
            // Size to the content so a short panel (logo/signature with no
            // layer yet) stays compact; only grow up to `maxHeight`, beyond
            // which the scroll view takes over. ScrollView is otherwise greedy
            // and would stretch every panel to fill the dock or side rail.
            .frame(maxHeight: contentHeight == 0 ? maxHeight : min(contentHeight, maxHeight))
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
        }
        .background {
            RoundedRectangle(cornerRadius: MarkepiRadius.xxxxl, style: .continuous)
                .fill(.regularMaterial)
        }
        .clipShape(RoundedRectangle(cornerRadius: MarkepiRadius.xxxxl, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: MarkepiRadius.xxxxl, style: .continuous)
                .strokeBorder(MarkepiColors.panelStroke, lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.18), radius: 20, y: 8)
        .task(id: tool) { syncActiveLayer() }
        .onPreferenceChange(PanelContentHeightKey.self) { contentHeight = $0 }
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
        let wms = viewModel.config.watermarks
        let active = viewModel.activeLayerIndex
        // Keep the current selection if it's already the right kind of layer, so
        // a specific instance chosen in the Layers tool (or just added) stays the
        // one being edited instead of snapping back to the first.
        if active >= 0, active < wms.count, matches(wms[active]) { return }
        if let idx = wms.firstIndex(where: matches) {
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
            TextWatermarkInputView(viewModel: viewModel, showsSectionHeader: false)
            EditorCard {
                positionRow
                Divider().padding(.leading, 16)
                ScaleStepperView(viewModel: viewModel)
            }
        case .logo:
            LogoPickerView(viewModel: viewModel, showsSectionHeader: false)
            if hasLayer(matching: { if case .image = $0 { return true }; return false }) {
                EditorCard {
                    positionRow
                    Divider().padding(.leading, 16)
                    ScaleStepperView(viewModel: viewModel)
                    Divider().padding(.leading, 16)
                    RotationControlView(viewModel: viewModel)
                }
            }
        case .signature:
            SignatureCaptureView(viewModel: viewModel, showsSectionHeader: false)
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
            // Provenance & Content Credentials (C2PA) signing. Surfaced first so
            // the "Sign with Content Credentials" action is immediately visible
            // when the More panel opens (design decision D-25: signing lives in More).
            ProvenanceControlsView(viewModel: viewModel)
            EditorCard { DateStampToggleView(viewModel: viewModel) }
            EditorCard {
                resolutionRow
                Divider().padding(.leading, 16)
                printSizeRow
            }
            EditorCard {
                exportFormatRow
                Divider().padding(.leading, 16)
                qualitySliderRow
            }
            VStack(spacing: 8) {
                saveTemplateButton
                loadTemplateButton
            }
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
            LayerListView(viewModel: viewModel, showsSectionHeader: false)
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

    // MARK: - Resolution & print size

    /// DPI presets the millimetre frame sizes convert against. "Automatic"
    /// keeps the previous behaviour: believe the photo's own resolution when it
    /// is a real print measurement, else 300.
    private static let dpiPresets: [CGFloat] = [72, 150, 300, 600]

    private var selectedDPI: CGFloat? { viewModel.config.whiteFrame?.outputDPI }

    /// The DPI the render will actually use, so the print size below never
    /// disagrees with the frame above.
    private var effectiveDPI: CGFloat {
        selectedDPI ?? FrameGeometry.resolveDPI(from: viewModel.sourceMetadata)
    }

    private func setDPI(_ dpi: CGFloat?) {
        // The setting lives on the frame config because the frame is what
        // measures in millimetres; a frame is created (left disabled) if the
        // user sets a resolution before turning the frame on.
        var frame = viewModel.config.whiteFrame ?? WhiteFrameConfig(isEnabled: false)
        frame.outputDPI = dpi
        viewModel.config.whiteFrame = frame
    }

    private var resolutionRow: some View {
        HStack {
            Text("Resolution")
                .markepiTypography(.controlLabel)
            Spacer()
            Menu {
                Button("Automatic") { setDPI(nil) }
                ForEach(Self.dpiPresets, id: \.self) { dpi in
                    Button("\(Int(dpi)) DPI") { setDPI(dpi) }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(selectedDPI.map { "\(Int($0)) DPI" } ?? "Automatic")
                        .markepiTypography(.value)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("more.resolution")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var printSizeRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Print size")
                .markepiTypography(.controlLabel)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(printSizeText)
                    .markepiTypography(.value)
                if let pixels = viewModel.sourcePixelSize {
                    Text("\(Int(pixels.width)) × \(Int(pixels.height)) px at \(Int(effectiveDPI)) DPI")
                        .markepiTypography(.metadata)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("more.printSize")
    }

    /// Physical size of the *exported* image — the frame enlarges the canvas,
    /// so the number has to describe what comes out, not what went in.
    private var printSizeText: String {
        guard let pixels = viewModel.sourcePixelSize else { return "—" }
        let framed: CGSize
        if let frame = viewModel.config.whiteFrame, frame.isEnabled {
            framed = FrameGeometry(
                config: frame,
                sourceSize: pixels,
                dpi: effectiveDPI,
                hasCaptionContent: WhiteFrameRenderer.hasCaptionContent(
                    config: frame, metadata: viewModel.sourceMetadata)
            ).framedSize
        } else {
            framed = pixels
        }
        let mmWidth = framed.width / effectiveDPI * 25.4
        let mmHeight = framed.height / effectiveDPI * 25.4
        // Millimetres below a postcard, centimetres above — nobody reads a
        // poster as "1189 mm".
        if max(mmWidth, mmHeight) >= 200 {
            return String(format: "%.1f × %.1f cm", mmWidth / 10, mmHeight / 10)
        }
        return String(format: "%.0f × %.0f mm", mmWidth, mmHeight)
    }

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

    private var loadTemplateButton: some View {
        Button {
            viewModel.showTemplateList = true
        } label: {
            Label("Load Template", systemImage: "square.and.arrow.up.on.square")
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
            shape: RoundedRectangle(cornerRadius: MarkepiRadius.lg, style: .continuous),
            isEnabled: !reduceTransparency
        )
        .clipShape(RoundedRectangle(cornerRadius: MarkepiRadius.lg, style: .continuous))
        .padding(.horizontal, 16)
    }
}

// MARK: - Panel content-height measurement

/// Reports the natural height of the tool panel's scroll content so the panel
/// can fit its content (short for a single button, tall for a full controls
/// list) instead of always stretching to its `maxHeight`.
private struct PanelContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
