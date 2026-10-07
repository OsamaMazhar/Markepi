// iOS-only UI. Guarded so MarkepiCore also builds for macOS, where the
// `markepi` CLI target links the engine without the SwiftUI layer.
#if canImport(UIKit)
import CoreImage
import SwiftUI
import UIKit

/// Frame controls, as grouped cards: the frame switch, its style and border,
/// what the caption says (toggle chips, grouped like the caption reads), and
/// the brand logo. Each style shows only the controls it reads.
///
/// Draws its own cards, so hosts place it directly rather than inside an
/// `EditorCard` (no glass on glass).
///
/// Generic over any `WatermarkConfigurable & Observable` ViewModel.
public struct WhiteFrameToggleView<ViewModel: WatermarkConfigurable & Observable>: View {
    @Bindable var viewModel: ViewModel
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public init(viewModel: ViewModel) {
        self.viewModel = viewModel
    }

    /// The Include list, grouped the way the caption reads.
    private static var fieldGroups: [(title: String, fields: [CaptionField])] { [
        ("Camera", [.maker, .cameraModel, .lens]),
        ("Exposure", [.focalLength, .aperture, .shutterSpeed, .iso]),
        ("When", [.date, .time]),
        ("Where", [.landmark, .city, .gps]),
        ("File", [.format, .dimensions]),
    ] }

    private static func icon(for field: CaptionField) -> String {
        switch field {
        case .maker: return "tag"
        case .cameraModel: return "camera"
        case .lens: return "circle.circle"
        case .focalLength: return "arrow.left.and.right"
        case .aperture: return "camera.aperture"
        case .shutterSpeed: return "timer"
        case .iso: return "sun.max"
        case .date: return "calendar"
        case .time: return "clock"
        case .landmark: return "building.columns"
        case .city: return "building.2"
        case .gps: return "flag"
        case .format: return "doc"
        case .dimensions: return "aspectratio"
        }
    }

    public var body: some View {
        // Read the observable values here in `body` so SwiftUI tracks them.
        let isEnabled = viewModel.whiteFrameEnabled
        let style = styleBinding.wrappedValue
        let captionOn = viewModel.config.whiteFrame?.metadataTextEnabled == true

        VStack(spacing: MarkepiSpacing.lg) {
            card {
                switchRow("Frame", icon: "rectangle.inset.filled",
                          subtitle: "A mat with the camera, date and place",
                          isOn: Binding(get: { isEnabled }, set: { viewModel.setWhiteFrameEnabled($0) }))
                    .accessibilityIdentifier("frame.enable")
            }

            if isEnabled {
                section("Style") {
                    styleRow
                    divider
                    sliderRow("Border", identifier: "border", binding: borderMMBinding,
                              range: 1...25)
                    if style.offersKeyline || style.offersGradient || style.castsShadow {
                        divider
                        optionChips(style)
                    }
                }

                section("Caption", isOn: metadataTextBinding) {
                    if captionOn {
                        fieldGroups
                        divider
                        if style.offersCreditText { creditTextRow } else { captionPrefixRow }
                        divider
                        sliderRow("Text size", identifier: "caption", binding: captionMMBinding,
                                  range: matRange(upTo: 10, value: captionMMBinding.wrappedValue))
                        if style.offersCaptionColor {
                            divider
                            captionColorRow
                        }
                    }
                }

                if captionOn, style.drawsBrandMark {
                    section("Brand logo", isOn: logoEnabledBinding) {
                        // The modern styles size the mark from the caption and
                        // tint it to their ink, so these are theirs. Gallery and
                        // banner size it to the caption lines too.
                        if viewModel.config.whiteFrame?.logoEnabled != false, style.offersCaptionColor {
                            if style != .gallery, style != .banner {
                                sliderRow("Logo size", identifier: "logo", binding: logoMMBinding,
                                          range: matRange(upTo: 15, value: logoMMBinding.wrappedValue))
                                divider
                            }
                            logoVariantRow
                        }
                    }
                }
            }
        }
        .animation(.snappy(duration: 0.25), value: isEnabled)
        .animation(.snappy(duration: 0.25), value: captionOn)
    }

    // MARK: - Building blocks

    private var divider: some View {
        Divider().padding(.leading, MarkepiSpacing.lg)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .markepiGlass(
                shape: RoundedRectangle(cornerRadius: MarkepiRadius.lg, style: .continuous),
                isEnabled: !reduceTransparency
            )
            .clipShape(RoundedRectangle(cornerRadius: MarkepiRadius.lg, style: .continuous))
            .padding(.horizontal, MarkepiSpacing.lg)
    }

    /// A titled card; with `isOn`, the title carries the section's switch and
    /// the card shows only while it is on.
    @ViewBuilder
    private func section<Content: View>(_ title: String, isOn: Binding<Bool>? = nil,
                                        @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: MarkepiSpacing.sm) {
            HStack {
                Text(title).markepiTypography(.sectionHeader)
                Spacer()
                if let isOn {
                    Toggle(title, isOn: isOn).labelsHidden()
                }
            }
            .padding(.horizontal, MarkepiSpacing.lg + MarkepiSpacing.xs)
            if isOn?.wrappedValue ?? true {
                card(content)
            }
        }
    }

    private func switchRow(_ title: String, icon: String, subtitle: String?,
                           isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: MarkepiSpacing.md) {
                Image(systemName: icon)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).markepiTypography(.controlLabel)
                    if let subtitle { Text(subtitle).markepiTypography(.metadata) }
                }
            }
        }
        .padding(.horizontal, MarkepiSpacing.lg)
        .padding(.vertical, MarkepiSpacing.md)
    }

    /// A capsule that is on or off — the one control for every yes/no choice
    /// in the panel, so they all read and behave alike.
    private func chip(_ title: String, icon: String, isOn: Bool,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .markepiTypography(.pillLabel)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, MarkepiSpacing.sm + 1)
                .padding(.horizontal, MarkepiSpacing.sm)
                .foregroundStyle(isOn ? Color.accentColor : Color.primary)
                .background(Capsule().fill(isOn ? Color.accentColor.opacity(0.18)
                                                : Color.primary.opacity(0.06)))
                .overlay(Capsule().strokeBorder(isOn ? Color.accentColor.opacity(0.55) : .clear,
                                                lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isOn)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(isOn ? [.isSelected, .isButton] : .isButton)
    }

    private var chipColumns: [GridItem] {
        // Wide enough for the longest label ("Dimensions") at one size, so no
        // chip ever shrinks its text to fit.
        [GridItem(.adaptive(minimum: 150), spacing: MarkepiSpacing.sm)]
    }

    // MARK: - Style card

    /// A menu, not segments: it stays legible at any number of styles and can
    /// show each style's summary beside its name.
    private var styleRow: some View {
        Menu {
            Picker("Style", selection: styleBinding) {
                ForEach(FrameStyle.allCases) { style in
                    VStack(alignment: .leading) {
                        Text(style.displayName)
                        Text(style.summary)
                    }
                    .tag(style)
                }
            }
        } label: {
            HStack(spacing: MarkepiSpacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(styleBinding.wrappedValue.displayName)
                        .markepiTypography(.controlLabel)
                        .foregroundStyle(Color.primary)
                    Text(styleBinding.wrappedValue.summary)
                        .markepiTypography(.metadata)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, MarkepiSpacing.lg)
            .padding(.vertical, MarkepiSpacing.md)
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier("frame.style")
        .accessibilityLabel("Frame style")
        .accessibilityValue(styleBinding.wrappedValue.displayName)
    }

    /// Keyline, gradient and shadow — whichever this style reads — as chips.
    private func optionChips(_ style: FrameStyle) -> some View {
        LazyVGrid(columns: chipColumns, spacing: MarkepiSpacing.sm) {
            if style.offersKeyline {
                chip("Keyline", icon: "square.dashed", isOn: keylineBinding.wrappedValue) {
                    keylineBinding.wrappedValue.toggle()
                }
                .accessibilityIdentifier("frame.keyline")
            }
            if style.offersGradient {
                chip("Gradient", icon: "circle.lefthalf.filled", isOn: gradientBinding.wrappedValue) {
                    gradientBinding.wrappedValue.toggle()
                }
                .accessibilityIdentifier("frame.gradient")
            }
            if style.castsShadow {
                ForEach(FrameShadow.allCases) { shadow in
                    chip(shadow == .bottom ? "Shadow below" : "Shadow all round",
                         icon: shadow == .bottom ? "square.bottomhalf.filled" : "square.dashed.inset.filled",
                         isOn: shadowBinding.wrappedValue == shadow) {
                        shadowBinding.wrappedValue = shadow
                    }
                }
            }
        }
        .padding(.horizontal, MarkepiSpacing.lg)
        .padding(.vertical, MarkepiSpacing.md)
    }

    /// A millimetre slider: name and value on one line, the slider beneath.
    /// Physical sizes, so the same setting prints the same at any resolution.
    private func sliderRow(_ title: String, identifier: String, binding: Binding<CGFloat>,
                           range: ClosedRange<CGFloat>) -> some View {
        VStack(alignment: .leading, spacing: MarkepiSpacing.xs) {
            HStack {
                Text(title).markepiTypography(.controlLabel)
                Spacer()
                Text(Self.millimetreLabel(binding.wrappedValue))
                    .markepiTypography(.value)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            Slider(value: binding, in: range, step: WatermarkScaling.millimetreStep) { editing in
                if editing { viewModel.beginInteractiveConfigChange() } else { viewModel.endInteractiveConfigChange() }
            }
            .accessibilityIdentifier("frame.mm.\(identifier)")
            .accessibilityLabel(title)
            .accessibilityValue(String(format: "%.1f millimetres", binding.wrappedValue))
        }
        .padding(.horizontal, MarkepiSpacing.lg)
        .padding(.vertical, MarkepiSpacing.md)
    }

    /// "8 mm", not "8.0 mm" — the grid is halves, so a trailing zero is noise.
    static func millimetreLabel(_ millimetres: CGFloat) -> String {
        let snapped = WatermarkScaling.snapped(millimetres: millimetres)
        return snapped == snapped.rounded()
            ? String(format: "%.0f mm", snapped)
            : String(format: "%.1f mm", snapped)
    }

    /// A slider span that moves with the mat: these sizes follow its width
    /// until set, so a fixed span would pin a grown size to its end.
    private func matRange(upTo top: CGFloat, value: CGFloat) -> ClosedRange<CGFloat> {
        let mat = viewModel.config.whiteFrame?.borderMillimetres ?? FrameMetrics.defaultBorderMillimetres
        return 1...max(value, top * mat / FrameMetrics.defaultBorderMillimetres)
    }

    // MARK: - Caption card

    /// Every caption field as a chip, in the groups the caption reads in.
    private var fieldGroups: some View {
        VStack(alignment: .leading, spacing: MarkepiSpacing.md) {
            ForEach(Self.fieldGroups, id: \.title) { group in
                VStack(alignment: .leading, spacing: MarkepiSpacing.xs + 2) {
                    Text(group.title)
                        .markepiTypography(.controlLabel)
                        .foregroundStyle(.secondary)
                    LazyVGrid(columns: chipColumns, spacing: MarkepiSpacing.sm) {
                        ForEach(group.fields) { field in
                            chip(field.displayName, icon: Self.icon(for: field),
                                 isOn: isFieldEnabled(field)) { toggleField(field) }
                        }
                    }
                    if group.title == "Where", CaptionField.placeFields.contains(where: isFieldEnabled),
                       styleBinding.wrappedValue.offersPlaceOnOwnLine {
                        // A layout choice, not another field, so a switch
                        // rather than a chip that would read as one.
                        Toggle(isOn: placeOnOwnLineBinding) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Place on a third line").markepiTypography(.controlLabel)
                                Text("Under the details, on the right").markepiTypography(.metadata)
                            }
                        }
                        .padding(.top, MarkepiSpacing.xs)
                        .accessibilityIdentifier("frame.placeOnOwnLine")
                    }
                    if group.title == "Where", isFieldEnabled(.landmark) || isFieldEnabled(.city) {
                        Label("Landmark and city are looked up with Apple Maps. Offline, the country shows.",
                              systemImage: "network")
                            .markepiTypography(.metadata)
                    }
                }
            }
        }
        .padding(.horizontal, MarkepiSpacing.lg)
        .padding(.vertical, MarkepiSpacing.md)
    }

    /// The user's own text around `print`'s "Shot on" credit.
    private var creditTextRow: some View {
        VStack(alignment: .leading, spacing: MarkepiSpacing.sm) {
            Text("Your credit").markepiTypography(.controlLabel)
            TextField("Before, e.g. © Your Name", text: creditPrefixBinding)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.done)
                .accessibilityIdentifier("frame.creditPrefix")
                .accessibilityLabel("Credit before the device")
            TextField("After, e.g. 2026", text: creditSuffixBinding)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.done)
                .accessibilityIdentifier("frame.creditSuffix")
                .accessibilityLabel("Credit after the device")
        }
        .padding(.horizontal, MarkepiSpacing.lg)
        .padding(.vertical, MarkepiSpacing.md)
    }

    /// Text before the device name (classic leads its whole line with it).
    private var captionPrefixRow: some View {
        HStack(spacing: MarkepiSpacing.md) {
            Text("Prefix").markepiTypography(.controlLabel)
            TextField("e.g. Shot on", text: captionPrefixBinding)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.done)
                .accessibilityLabel("Caption prefix text")
        }
        .padding(.horizontal, MarkepiSpacing.lg)
        .padding(.vertical, MarkepiSpacing.md)
    }

    private var captionColorRow: some View {
        ColorPicker(selection: captionColorBinding, supportsOpacity: false) {
            Text("Text colour").markepiTypography(.controlLabel)
        }
        .padding(.horizontal, MarkepiSpacing.lg)
        .padding(.vertical, MarkepiSpacing.md)
        .accessibilityLabel("Caption text colour")
    }

    // MARK: - Logo card

    private var logoVariantRow: some View {
        Picker("Logo colour", selection: logoVariantBinding) {
            ForEach(LogoVariant.allCases) { variant in
                Text(variant.displayName).tag(variant)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, MarkepiSpacing.lg)
        .padding(.vertical, MarkepiSpacing.md)
        .accessibilityIdentifier("frame.logoVariant")
    }

    // MARK: - Bindings

    /// Mutates a field on the white-frame config, creating an enabled config if
    /// one does not yet exist so a slider/toggle never silently no-ops.
    /// Every settings row writes through here, so one edit reaches one style
    /// or all of them according to the user's choice — the rule itself lives on
    /// `WatermarkConfiguration`, where the style strip reads it too.
    private func mutateFrame(_ transform: (inout WhiteFrameConfig) -> Void) {
        viewModel.config.editFrame(transform)
    }

    private var styleBinding: Binding<FrameStyle> {
        Binding(
            get: { viewModel.config.whiteFrame?.style ?? .classic },
            // Not `mutateFrame`: switching style has to put the settings of the
            // style being left somewhere before loading the next one, which is
            // what `selectFrameStyle` is for.
            set: { viewModel.config.selectFrameStyle($0) }
        )
    }

    private var gradientBinding: Binding<Bool> {
        Binding(
            get: { viewModel.config.whiteFrame?.gradientEnabled ?? true },
            set: { newValue in mutateFrame { $0.gradientEnabled = newValue } }
        )
    }

    private var shadowBinding: Binding<FrameShadow> {
        Binding(
            get: { viewModel.config.whiteFrame?.shadow ?? .bottom },
            set: { newValue in mutateFrame { $0.shadow = newValue } }
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
            get: { WatermarkScaling.snapped(
                millimetres: viewModel.config.whiteFrame?.borderMillimetres ?? 5) },
            set: { newValue in
                mutateFrame { $0.borderMillimetres = WatermarkScaling.snapped(millimetres: newValue) }
            }
        )
    }

    private var captionMMBinding: Binding<CGFloat> {
        Binding(
            get: { WatermarkScaling.snapped(
                millimetres: viewModel.config.whiteFrame?.captionTextMillimetres ?? 2.5) },
            set: { newValue in
                mutateFrame { $0.captionTextMillimetres = WatermarkScaling.snapped(millimetres: newValue) }
            }
        )
    }

    private var logoMMBinding: Binding<CGFloat> {
        Binding(
            get: { WatermarkScaling.snapped(
                millimetres: viewModel.config.whiteFrame?.logoHeightMillimetres ?? 4) },
            set: { newValue in
                mutateFrame { $0.logoHeightMillimetres = WatermarkScaling.snapped(millimetres: newValue) }
            }
        )
    }

    private var logoEnabledBinding: Binding<Bool> {
        Binding(
            get: { viewModel.config.whiteFrame?.logoEnabled ?? true },
            set: { newValue in mutateFrame { $0.logoEnabled = newValue } }
        )
    }

    private var logoVariantBinding: Binding<LogoVariant> {
        Binding(
            get: { viewModel.config.whiteFrame?.logoVariant ?? .color },
            set: { newValue in mutateFrame { $0.logoVariant = newValue } }
        )
    }

    private var placeOnOwnLineBinding: Binding<Bool> {
        Binding(
            get: { viewModel.config.whiteFrame?.placeOnOwnLine ?? false },
            set: { newValue in mutateFrame { $0.placeOnOwnLine = newValue } }
        )
    }

    private var metadataTextBinding: Binding<Bool> {
        Binding(
            get: { viewModel.config.whiteFrame?.metadataTextEnabled ?? true },
            set: { newValue in mutateFrame { $0.metadataTextEnabled = newValue } }
        )
    }

    private var creditPrefixBinding: Binding<String> {
        Binding(
            get: { viewModel.config.whiteFrame?.creditPrefixText ?? "" },
            set: { newValue in mutateFrame { $0.creditPrefixText = newValue } }
        )
    }

    private var creditSuffixBinding: Binding<String> {
        Binding(
            get: { viewModel.config.whiteFrame?.creditSuffixText ?? "" },
            set: { newValue in mutateFrame { $0.creditSuffixText = newValue } }
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
