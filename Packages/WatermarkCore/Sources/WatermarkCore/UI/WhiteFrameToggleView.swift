// iOS-only UI. Guarded so WatermarkCore also builds for macOS, where the
// `markepi` CLI target links the engine without the SwiftUI layer.
#if canImport(UIKit)
import CoreImage
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// White-frame controls: an enable toggle plus, when enabled, the parameters
/// that shape the border and its attribution text — thickness, whether the
/// device/metadata caption is shown, the caption size, and its color.
///
/// Previously this was an on/off toggle only, which meant the border caption
/// size was uncontrollable; combined with a stale-preview bug it appeared to
/// "become too big or small". The preview now refreshes on every parameter
/// change, so these controls take effect live.
///
/// Generic over any `WatermarkConfigurable & Observable` ViewModel.
public struct WhiteFrameToggleView<ViewModel: WatermarkConfigurable & Observable>: View {
    @Bindable var viewModel: ViewModel

    public init(viewModel: ViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        // Read the observable value here in `body` so SwiftUI tracks it and
        // re-renders when the frame is enabled/disabled elsewhere.
        let isEnabled = viewModel.whiteFrameEnabled

        VStack(spacing: 0) {
            Toggle(isOn: Binding(
                get: { isEnabled },
                set: { viewModel.setWhiteFrameEnabled($0) }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Frame")
                        .markepiTypography(.controlLabel)
                    Text("A mat around the photo with the camera, date and shooting details")
                        .markepiTypography(.metadata)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .accessibilityIdentifier("frame.enable")
            .accessibilityLabel("Frame")
            .accessibilityHint("Add a mat around your photo with its camera and shooting details")

            if isEnabled {
                Divider().padding(.leading, 16)
                styleRow
                Divider().padding(.leading, 16)
                keylineRow
                Divider().padding(.leading, 16)

                // Each style measures its border in its own unit: classic as a
                // proportion of the photo, gallery in millimetres on paper.
                if styleBinding.wrappedValue == .classic {
                    thicknessRow
                } else {
                    borderMillimetresRow
                }

                Divider().padding(.leading, 16)
                captionToggleRow

                if viewModel.config.whiteFrame?.metadataTextEnabled == true {
                    if styleBinding.wrappedValue == .classic {
                        Divider().padding(.leading, 16)
                        captionPrefixRow
                        Divider().padding(.leading, 16)
                        captionFieldsRow
                        Divider().padding(.leading, 16)
                        captionSizeRow
                    } else {
                        Divider().padding(.leading, 16)
                        slotRow("Top left", identifier: "leftPrimary", binding: slotBinding(\.leftPrimary))
                        Divider().padding(.leading, 16)
                        slotRow("Bottom left", identifier: "leftSecondary", binding: slotBinding(\.leftSecondary))
                        Divider().padding(.leading, 16)
                        slotRow("Top right", identifier: "rightPrimary", binding: slotBinding(\.rightPrimary))
                        Divider().padding(.leading, 16)
                        slotRow("Bottom right", identifier: "rightSecondary", binding: slotBinding(\.rightSecondary))
                        Divider().padding(.leading, 16)
                        captionMillimetresRow
                        Divider().padding(.leading, 16)
                        logoMillimetresRow
                        Divider().padding(.leading, 16)
                        logoVariantRow
                    }
                    Divider().padding(.leading, 16)
                    captionColorRow
                }
            }
        }
    }

    // MARK: - Rows

    private var styleRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Style")
                .markepiTypography(.controlLabel)
            Picker("Style", selection: styleBinding) {
                ForEach(FrameStyle.allCases) { style in
                    Text(style.displayName).tag(style)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("frame.style")
            .accessibilityLabel("Frame style")
            Text(styleBinding.wrappedValue.summary)
                .markepiTypography(.metadata)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var keylineRow: some View {
        Toggle(isOn: keylineBinding) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Keyline")
                    .markepiTypography(.controlLabel)
                Text("A thin black line between the photo and the border")
                    .markepiTypography(.metadata)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .accessibilityIdentifier("frame.keyline")
        .accessibilityHint("Adds a thin black outline around the photo")
    }

    /// A millimetre control. Physical sizes, so the same setting prints the
    /// same whatever the photo's pixel dimensions.
    private func millimetreRow(
        _ title: String,
        identifier: String,
        subtitle: String? = nil,
        binding: Binding<CGFloat>,
        range: ClosedRange<CGFloat>,
        step: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).markepiTypography(.controlLabel)
                    if let subtitle {
                        Text(subtitle).markepiTypography(.metadata)
                    }
                }
                Spacer()
                Text(String(format: "%.1f mm", binding.wrappedValue))
                    .markepiTypography(.value)
                    .monospacedDigit()
            }
            Slider(value: binding, in: range, step: step)
                .accessibilityIdentifier("frame.mm.\(identifier)")
                .accessibilityLabel(title)
                .accessibilityValue(String(format: "%.1f millimetres", binding.wrappedValue))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var borderMillimetresRow: some View {
        millimetreRow("Border", identifier: "border", subtitle: "The bottom widens with it",
                      binding: borderMMBinding, range: 1...25, step: 0.5)
    }

    private var captionMillimetresRow: some View {
        millimetreRow("Text size", identifier: "caption",
                      binding: captionMMBinding, range: 1...10, step: 0.25)
    }

    private var logoMillimetresRow: some View {
        millimetreRow("Logo size", identifier: "logo",
                      subtitle: "Set by the camera in the photo's metadata",
                      binding: logoMMBinding, range: 1...15, step: 0.25)
    }

    private var logoVariantRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Logo")
                .markepiTypography(.controlLabel)
            Picker("Logo", selection: logoVariantBinding) {
                ForEach(LogoVariant.allCases) { variant in
                    Text(variant.displayName).tag(variant)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("frame.logoVariant")
            .accessibilityLabel("Logo colour")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    /// One caption line: a metadata field, free text, or nothing.
    private func slotRow(_ title: String, identifier: String, binding: Binding<CaptionSlot>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).markepiTypography(.controlLabel)
                Spacer()
                Menu {
                    Button("None") { binding.wrappedValue = .empty }
                    Button("Custom text…") {
                        if case .text = binding.wrappedValue {} else {
                            binding.wrappedValue = .text("")
                        }
                    }
                    Divider()
                    ForEach(CaptionField.allCases) { field in
                        Button(field.displayName) { binding.wrappedValue = .field(field) }
                    }
                } label: {
                    Text(slotLabel(binding.wrappedValue))
                        .markepiTypography(.value)
                }
                .accessibilityIdentifier("frame.slot.\(identifier)")
                .accessibilityLabel("\(title) content")
                .accessibilityValue(slotLabel(binding.wrappedValue))
            }
            if case .text(let text) = binding.wrappedValue {
                TextField("Your name or handle", text: Binding(
                    get: { text },
                    set: { binding.wrappedValue = .text($0) }
                ))
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .accessibilityIdentifier("frame.slotText.\(identifier)")
                .accessibilityLabel("\(title) text")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func slotLabel(_ slot: CaptionSlot) -> String {
        switch slot {
        case .empty: return "None"
        case .field(let field): return field.displayName
        case .text(let text): return text.isEmpty ? "Custom text" : text
        }
    }

    private var thicknessRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Thickness")
                    .markepiTypography(.controlLabel)
                Spacer()
                Text("\(Int((frameWidthBinding.wrappedValue * 100).rounded()))%")
                    .markepiTypography(.value)
                    .monospacedDigit()
            }
            // D-05 keeps the border within 3–5% of the shorter dimension.
            Slider(value: frameWidthBinding, in: 0.03...0.05)
                .accessibilityLabel("Frame thickness")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var captionToggleRow: some View {
        Toggle(isOn: metadataTextBinding) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Caption Text")
                    .markepiTypography(.controlLabel)
                Text("Show a caption on the bottom border")
                    .markepiTypography(.metadata)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    /// Free-text prefix shown before the metadata fields (e.g. "Shot on").
    private var captionPrefixRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Prefix")
                .markepiTypography(.controlLabel)
            TextField("e.g. Shot on", text: captionPrefixBinding)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.done)
                .accessibilityLabel("Caption prefix text")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    /// A two-column grid of checkboxes, one per metadata field, letting the user
    /// pick exactly which details appear in the caption.
    private var captionFieldsRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Include")
                .markepiTypography(.controlLabel)
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), alignment: .leading),
                    GridItem(.flexible(), alignment: .leading),
                ],
                alignment: .leading,
                spacing: 10
            ) {
                ForEach(CaptionField.allCases) { field in
                    captionFieldCheckbox(field)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func captionFieldCheckbox(_ field: CaptionField) -> some View {
        let isOn = isFieldEnabled(field)
        return Button {
            toggleField(field)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                    .font(.body)
                    .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                Text(field.displayName)
                    .markepiTypography(.value)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(field.displayName)
        .accessibilityValue(isOn ? "Included" : "Not included")
        .accessibilityAddTraits(isOn ? [.isSelected, .isButton] : .isButton)
        .accessibilityHint("Double tap to \(isOn ? "remove from" : "add to") the caption")
    }

    private var captionSizeRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Caption Size")
                    .markepiTypography(.controlLabel)
                Spacer()
                Text("\(String(format: "%.1f", captionSizeBinding.wrappedValue * 100))%")
                    .markepiTypography(.value)
                    .monospacedDigit()
            }
            // Caption font size as a fraction of the shorter image dimension.
            Slider(value: captionSizeBinding, in: 0.010...0.030)
                .accessibilityLabel("Caption text size")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var captionColorRow: some View {
        HStack {
            Text("Caption Color")
                .markepiTypography(.controlLabel)
            Spacer()
            ColorPicker("", selection: captionColorBinding, supportsOpacity: false)
                .labelsHidden()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Caption text color")
    }

    // MARK: - Bindings

    /// Mutates a field on the white-frame config, creating an enabled config if
    /// one does not yet exist so a slider/toggle never silently no-ops.
    private func mutateFrame(_ transform: (inout WhiteFrameConfig) -> Void) {
        var frame = viewModel.config.whiteFrame ?? WhiteFrameConfig(isEnabled: true)
        transform(&frame)
        viewModel.config.whiteFrame = frame
    }

    private var frameWidthBinding: Binding<CGFloat> {
        Binding(
            get: { viewModel.config.whiteFrame?.frameWidthRatio ?? 0.04 },
            set: { newValue in mutateFrame { $0.frameWidthRatio = newValue } }
        )
    }

    private var styleBinding: Binding<FrameStyle> {
        Binding(
            get: { viewModel.config.whiteFrame?.style ?? .classic },
            set: { newValue in mutateFrame { $0.style = newValue } }
        )
    }

    private var keylineBinding: Binding<Bool> {
        Binding(
            get: { viewModel.config.whiteFrame?.keylineEnabled ?? false },
            set: { newValue in mutateFrame { $0.keylineEnabled = newValue } }
        )
    }

    private var borderMMBinding: Binding<CGFloat> {
        Binding(
            get: { viewModel.config.whiteFrame?.borderMillimetres ?? 5 },
            set: { newValue in mutateFrame { $0.borderMillimetres = newValue } }
        )
    }

    private var captionMMBinding: Binding<CGFloat> {
        Binding(
            get: { viewModel.config.whiteFrame?.captionTextMillimetres ?? 2.5 },
            set: { newValue in mutateFrame { $0.captionTextMillimetres = newValue } }
        )
    }

    private var logoMMBinding: Binding<CGFloat> {
        Binding(
            get: { viewModel.config.whiteFrame?.logoHeightMillimetres ?? 4 },
            set: { newValue in mutateFrame { $0.logoHeightMillimetres = newValue } }
        )
    }

    private var logoVariantBinding: Binding<LogoVariant> {
        Binding(
            get: { viewModel.config.whiteFrame?.logoVariant ?? .color },
            set: { newValue in mutateFrame { $0.logoVariant = newValue } }
        )
    }

    private func slotBinding(_ keyPath: WritableKeyPath<WhiteFrameConfig, CaptionSlot>) -> Binding<CaptionSlot> {
        Binding(
            get: { viewModel.config.whiteFrame?[keyPath: keyPath] ?? .empty },
            set: { newValue in mutateFrame { $0[keyPath: keyPath] = newValue } }
        )
    }

    private var metadataTextBinding: Binding<Bool> {
        Binding(
            get: { viewModel.config.whiteFrame?.metadataTextEnabled ?? true },
            set: { newValue in mutateFrame { $0.metadataTextEnabled = newValue } }
        )
    }

    private var captionPrefixBinding: Binding<String> {
        Binding(
            get: { viewModel.config.whiteFrame?.captionPrefix ?? "" },
            set: { newValue in mutateFrame { $0.captionPrefix = newValue } }
        )
    }

    /// Whether a given metadata field is currently included in the caption.
    private func isFieldEnabled(_ field: CaptionField) -> Bool {
        viewModel.config.whiteFrame?.captionFields.contains(field) ?? false
    }

    /// Adds or removes a field, keeping the stored list in canonical
    /// `CaptionField.allCases` order so the rendered caption order is stable.
    private func toggleField(_ field: CaptionField) {
        mutateFrame { frame in
            if let idx = frame.captionFields.firstIndex(of: field) {
                frame.captionFields.remove(at: idx)
            } else {
                frame.captionFields.append(field)
                frame.captionFields = CaptionField.allCases.filter { frame.captionFields.contains($0) }
            }
        }
    }

    private var captionSizeBinding: Binding<CGFloat> {
        Binding(
            get: { viewModel.config.whiteFrame?.textFontSizeRatio ?? 0.018 },
            set: { newValue in mutateFrame { $0.textFontSizeRatio = newValue } }
        )
    }

    private var captionColorBinding: Binding<Color> {
        Binding(
            get: {
                guard let cg = viewModel.config.whiteFrame?.textColor else {
                    return Color(white: 0.333)
                }
                return Color(cgColor: cg)
            },
            set: { newColor in mutateFrame { $0.textColor = Self.cgColor(from: newColor) } }
        )
    }

    /// Converts a SwiftUI `Color` to a `CGColor` on either platform.
    private static func cgColor(from color: Color) -> CGColor {
        #if canImport(UIKit)
        return UIColor(color).cgColor
        #elseif canImport(AppKit)
        return NSColor(color).cgColor
        #else
        return CGColor(gray: 0.333, alpha: 1.0)
        #endif
    }
}
#endif
