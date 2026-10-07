import SwiftUI
import MarkepiCore

/// Floating control panel for the currently-selected `EditorTool`.
///
/// Hosts the existing MarkepiCore leaf control views (text, logo, signature,
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
        case .looks:
            if viewModel.looksAvailable {
                LooksPanel(viewModel: viewModel)
            } else {
                emptyHint(
                    icon: "camera.filters",
                    title: "Looks Are for Photos",
                    message: "Videos export with their original colour."
                )
            }
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
            WhiteFrameToggleView(viewModel: viewModel)
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
                PositionMenuContent(
                    current: currentPosition,
                    layerIndex: safeLayerIndex,
                    layout: viewModel.previewLayout
                ) { position in
                    viewModel.updateLayerPosition(at: safeLayerIndex, position: position)
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
        selectedDPI ?? FrameGeometry.resolveDPI(
            from: viewModel.sourceMetadata,
            sourceSize: viewModel.sourcePixelSize ?? .zero)
    }

    private func setDPI(_ dpi: CGFloat?) {
        // The setting lives on the frame config because the frame is what
        // measures in millimetres; a frame is created (left disabled) if the
        // user sets a resolution before turning the frame on.
        if viewModel.config.whiteFrame == nil {
            viewModel.config.whiteFrame = WhiteFrameConfig(isEnabled: false)
        }
        // Through `editFrame` like every other frame setting, so "apply to all
        // styles" carries the resolution across with the rest.
        viewModel.config.editFrame { $0.outputDPI = dpi }
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
/// Mirrors the styling used by the MarkepiCore leaf control views.
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

// MARK: - Looks

/// Colour looks for the photo itself — never the frame or the watermarks.
/// Called "Looks" so it can't be mistaken for Apple's Photographic Styles or
/// for the frame *styles*.
///
/// Built from the editor's own parts: the glass pill bar picks the family, the
/// strip uses the frame-style strip's photo-shaped cells and accent ring, and
/// the adjustments are the same title · value slider rows as the frame panel.
private struct LooksPanel: View {
    @Bindable var viewModel: WatermarkViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var settings: PhotoLookSettings { viewModel.config.photoLook }

    var body: some View {
        VStack(spacing: MarkepiSpacing.lg) {
            MarkepiPillBar(
                selection: $viewModel.lookFamily,
                options: PhotoLook.Family.allCases,
                groupLabel: "Look family",
                title: \.title,
                icon: { family in
                    switch family {
                    case .mood: return "sparkles"
                    case .undertone: return "face.smiling"
                    case .film: return "film"
                    }
                }
            )
            .padding(.horizontal, MarkepiSpacing.lg)

            LookStrip(
                looks: viewModel.lookFamily.looks,
                thumbnails: viewModel.lookThumbnails,
                selected: settings.look,
                fallbackAspect: viewModel.sourceAspectRatio,
                isLocked: { !$0.isFree && !viewModel.looksUnlocked },
                select: { look in
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { viewModel.selectLook(look) }
                }
            )
            .task(id: viewModel.lookThumbnailIdentifier) { await viewModel.generateLookThumbnails() }

            if settings.look != .original {
                EditorCard { adjustments }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            notes
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: settings.look == .original)
        .sensoryFeedback(.selection, trigger: settings.look)
        .onAppear {
            // Open on the family of the look already chosen.
            if let family = settings.look.family { viewModel.lookFamily = family }
        }
    }

    // MARK: Adjustments

    @ViewBuilder
    private var adjustments: some View {
        sliderRow("Intensity", value: binding(\.intensity), range: 0...1,
                  display: percent(settings.intensity))
        Divider().padding(.leading, MarkepiSpacing.lg)
        ToneWarmthPad(tone: binding(\.tone), warmth: binding(\.color), onEditingChanged: editing)
            .padding(.horizontal, MarkepiSpacing.lg)
            .padding(.vertical, MarkepiSpacing.md)
        if settings.look.isFilm {
            Divider().padding(.leading, MarkepiSpacing.lg)
            let grain = settings.grain ?? (PhotoLookRenderer.defaultGrain(for: settings.look) ?? 0)
            sliderRow("Grain", value: Binding(get: { grain }, set: { viewModel.config.photoLook.grain = $0 }),
                      range: 0...1, display: percent(grain))
        }
        if !settings.isDefaultTuning {
            Divider().padding(.leading, MarkepiSpacing.lg)
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                    viewModel.selectLook(settings.look)
                }
            } label: {
                Label("Reset Adjustments", systemImage: "arrow.counterclockwise")
                    .markepiTypography(.controlLabel)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, MarkepiSpacing.lg)
            .padding(.vertical, MarkepiSpacing.md)
        }
    }

    private func binding(_ key: WritableKeyPath<PhotoLookSettings, Double>) -> Binding<Double> {
        Binding(get: { viewModel.config.photoLook[keyPath: key] },
                set: { viewModel.config.photoLook[keyPath: key] = $0 })
    }

    private func percent(_ v: Double) -> String { "\(Int((v * 100).rounded()))%" }

    /// The frame panel's slider row: title and value on one line, slider under
    /// it, optional end-cap symbols saying which way is which.
    private func sliderRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>,
                           display: String, low: String? = nil, high: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: MarkepiSpacing.sm) {
            HStack {
                Text(title).markepiTypography(.controlLabel)
                Spacer()
                Text(display)
                    .markepiTypography(.value)
                    .contentTransition(.numericText())
            }
            Slider(value: value, in: range) {
                Text(title)
            } minimumValueLabel: {
                if let low { Image(systemName: low).foregroundStyle(.secondary) }
            } maximumValueLabel: {
                if let high { Image(systemName: high).foregroundStyle(.secondary) }
            } onEditingChanged: { editing($0) }
            .accessibilityValue(display)
        }
        .padding(.horizontal, MarkepiSpacing.lg)
        .padding(.vertical, MarkepiSpacing.md)
    }

    private func editing(_ active: Bool) {
        if active { viewModel.beginInteractiveConfigChange() } else { viewModel.endInteractiveConfigChange() }
    }

    // MARK: Notes

    @ViewBuilder
    private var notes: some View {
        let lockedLook = settings.isActive && !viewModel.looksUnlocked && !ExportPolicy(tier: .free).allowsLook(settings)
        if lockedLook || viewModel.lookMakesLivePhotoStill {
            VStack(alignment: .leading, spacing: MarkepiSpacing.sm) {
                if lockedLook {
                    HStack(spacing: MarkepiSpacing.sm) {
                        Image(systemName: "crown.fill").foregroundStyle(.yellow)
                        Text("Pro look — free exports use Original.")
                            .markepiTypography(.metadata)
                        Spacer(minLength: 0)
                        Button("Unlock") { viewModel.showPaywall = true }
                            .font(.footnote.weight(.semibold))
                            .buttonStyle(.borderedProminent)
                            .buttonBorderShape(.capsule)
                            .controlSize(.small)
                    }
                }
                if viewModel.lookMakesLivePhotoStill {
                    Label("With a look, this Live Photo is shared as a still photo.", systemImage: "livephoto.slash")
                        .markepiTypography(.metadata)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, MarkepiSpacing.lg + MarkepiSpacing.xs)
        }
    }
}

/// Two-axis Tone & Warmth pad: up is brighter, right is warmer.
///
/// A soft field that previews the direction (cool blue → warm amber, light
/// above, deep below) under a dot grid; the knob grows while held, snaps to
/// the centre with a tick, and a double-tap returns it there. VoiceOver gets
/// two ordinary sliders instead.
private struct ToneWarmthPad: View {
    @Binding var tone: Double
    @Binding var warmth: Double
    var onEditingChanged: (Bool) -> Void

    @State private var isDragging = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    /// Compact and square: a small target, so a swipe anywhere else in the
    /// panel still scrolls it, and it sits beside its readouts in the narrow
    /// landscape side panel too.
    private let side: CGFloat = 112
    private let snap = 0.06
    private var isCentred: Bool { tone == 0 && warmth == 0 }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: MarkepiRadius.lg, style: .continuous) }

    var body: some View {
        HStack(alignment: .center, spacing: MarkepiSpacing.lg) {
            pad
            VStack(alignment: .leading, spacing: MarkepiSpacing.sm) {
                Text("Tone & Warmth").markepiTypography(.controlLabel)
                readout("sun.max.fill", "Tone", tone)
                readout("thermometer.medium", "Warmth", warmth)
                Button("Reset", systemImage: "arrow.counterclockwise") { reset() }
                    .font(.caption.weight(.semibold))
                    .opacity(isCentred ? 0 : 1)
                    .disabled(isCentred)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: isCentred)
            }
            Spacer(minLength: 0)
        }
        .sensoryFeedback(trigger: isCentred) { _, centred in centred ? .impact(weight: .light) : nil }
        .accessibilityRepresentation {
            VStack {
                Slider(value: $tone, in: -1...1) { Text("Tone, darker to brighter") }
                Slider(value: $warmth, in: -1...1) { Text("Warmth, cooler to warmer") }
            }
        }
    }

    private var pad: some View {
        let size = CGSize(width: side, height: side)
        return ZStack {
            field
            dots(size)
            edgeIcons
            knob.position(x: (warmth + 1) / 2 * side, y: (1 - tone) / 2 * side)
        }
        .frame(width: side, height: side)
        .clipShape(shape)
        .overlay { shape.strokeBorder(MarkepiColors.controlStroke, lineWidth: 0.5) }
        .contentShape(shape)
        .gesture(drag(in: size))
        .onTapGesture(count: 2) { reset() }
    }

    // MARK: Parts

    private var field: some View {
        ZStack {
            shape.fill(Color(.secondarySystemBackground))
            shape.fill(LinearGradient(
                colors: [Color(red: 0.42, green: 0.6, blue: 0.98), Color(.systemGray3), Color(red: 1, green: 0.64, blue: 0.3)],
                startPoint: .leading, endPoint: .trailing))
                .opacity(colorScheme == .dark ? 0.55 : 0.45)
            shape.fill(LinearGradient(
                colors: [.white.opacity(0.4), .clear, .black.opacity(0.4)],
                startPoint: .top, endPoint: .bottom))
        }
    }

    /// A 7 × 7 dot grid; the centre dot is larger, marking "as designed".
    private func dots(_ size: CGSize) -> some View {
        Canvas { context, canvas in
            let cols = 7, rows = 7
            for c in 0..<cols {
                for r in 0..<rows {
                    let centre = c == cols / 2 && r == rows / 2
                    let x = canvas.width * (CGFloat(c) + 0.5) / CGFloat(cols)
                    let y = canvas.height * (CGFloat(r) + 0.5) / CGFloat(rows)
                    let d: CGFloat = centre ? 4.5 : 2
                    context.fill(Path(ellipseIn: CGRect(x: x - d / 2, y: y - d / 2, width: d, height: d)),
                                 with: .color(.white.opacity(centre ? 0.9 : 0.45)))
                }
            }
        }
        .allowsHitTesting(false)
    }

    private var edgeIcons: some View {
        ZStack {
            Image(systemName: "sun.max.fill").frame(maxHeight: .infinity, alignment: .top)
            Image(systemName: "moon.fill").frame(maxHeight: .infinity, alignment: .bottom)
            Image(systemName: "snowflake").frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "flame.fill").frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(.system(size: 9, weight: .bold))
        .foregroundStyle(.white.opacity(0.85))
        .shadow(color: .black.opacity(0.25), radius: 1)
        .padding(5)
        .allowsHitTesting(false)
    }

    private var knob: some View {
        Circle()
            .fill(.white)
            .frame(width: isDragging ? 24 : 18, height: isDragging ? 24 : 18)
            .overlay { Circle().strokeBorder(Color.accentColor, lineWidth: 2) }
            .shadow(color: .black.opacity(0.3), radius: isDragging ? 6 : 3, y: 1)
            .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.7), value: isDragging)
            .allowsHitTesting(false)
    }

    private func readout(_ symbol: String, _ title: String, _ value: Double) -> some View {
        let n = Int((value * 100).rounded())
        return HStack(spacing: MarkepiSpacing.xs) {
            Image(systemName: symbol).imageScale(.small).foregroundStyle(.secondary)
                .frame(width: 16)
            Text(title).markepiTypography(.metadata)
            Spacer(minLength: MarkepiSpacing.sm)
            Text(n == 0 ? "0" : (n > 0 ? "+\(n)" : "\(n)"))
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(n)))
                .foregroundStyle(n == 0 ? .secondary : .primary)
        }
        .frame(maxWidth: 150)
    }

    // MARK: Interaction

    private func drag(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !isDragging { isDragging = true; onEditingChanged(true) }
                warmth = snapped(Double(value.location.x / max(size.width, 1)) * 2 - 1)
                tone = snapped(1 - Double(value.location.y / max(size.height, 1)) * 2)
            }
            .onEnded { _ in
                isDragging = false
                onEditingChanged(false)
            }
    }

    /// Clamped to −1…1, with a small dead zone that settles on 0.
    private func snapped(_ v: Double) -> Double {
        let c = min(max(v, -1), 1)
        return abs(c) < snap ? 0 : c
    }

    private func reset() {
        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.75)) {
            tone = 0
            warmth = 0
        }
    }
}

/// The look strip: the frame-style strip's cell, so both strips read as one
/// family — the photo at its own shape on a pale ground, square corners, a
/// 3-pt accent ring and an accent caption on the chosen one.
private struct LookStrip: View {
    let looks: [PhotoLook]
    let thumbnails: [PhotoLook: UIImage]
    let selected: PhotoLook
    let fallbackAspect: CGFloat
    let isLocked: (PhotoLook) -> Bool
    let select: (PhotoLook) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var cellHeight: CGFloat { MarkepiMetrics.thumbnailCellSize(dynamicTypeSize: dynamicTypeSize) * 1.1 }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(looks) { look in
                        cell(look).id(look)
                    }
                }
                .padding(.horizontal, MarkepiSpacing.lg)
                .padding(.vertical, 2)
            }
            .onAppear { proxy.scrollTo(selected, anchor: .center) }
            .onChange(of: looks) { proxy.scrollTo(selected, anchor: .center) }
        }
        .accessibilityLabel("Looks")
        .accessibilityHint("Shows this photo in each look. Double tap one to use it.")
    }

    private func aspect(_ look: PhotoLook) -> CGFloat {
        let size = thumbnails[look]?.size
        let raw = size.map { $0.height > 0 ? $0.width / $0.height : fallbackAspect } ?? fallbackAspect
        return min(max(raw, 0.6), 1.6)
    }

    private func cell(_ look: PhotoLook) -> some View {
        let isSelected = look == selected
        return Button { select(look) } label: {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    Rectangle().fill(Color(.systemGray6))
                    if let image = thumbnails[look] {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .id(ObjectIdentifier(image))
                            .transition(.opacity)
                    } else {
                        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    if isLocked(look) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.yellow)
                            .padding(4)
                            .background(.black.opacity(0.45), in: Circle())
                            .padding(4)
                    }
                }
                .frame(width: cellHeight * aspect(look), height: cellHeight)
                .clipShape(Rectangle())
                .overlay {
                    Rectangle()
                        .strokeBorder(isSelected ? Color.accentColor : MarkepiColors.controlStroke,
                                      lineWidth: isSelected ? 3 : 0.5)
                        .animation(reduceMotion ? nil : .easeInOut, value: selected)
                }
                Text(look.title)
                    .font(.caption2.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(look.title + (isLocked(look) ? ", Pro" : ""))
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}
