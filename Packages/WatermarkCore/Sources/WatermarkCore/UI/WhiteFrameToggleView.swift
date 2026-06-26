import CoreImage
import SwiftUI
import WatermarkCore
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
                    Text("White Frame")
                        .markepiTypography(.controlLabel)
                    Text("Adds a white border with an optional caption")
                        .markepiTypography(.metadata)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .accessibilityLabel("White frame")
            .accessibilityHint("Add a white border with device model text to your photo")

            if isEnabled {
                Divider().padding(.leading, 16)
                thicknessRow
                Divider().padding(.leading, 16)
                captionToggleRow

                if viewModel.config.whiteFrame?.metadataTextEnabled == true {
                    Divider().padding(.leading, 16)
                    captionPrefixRow
                    Divider().padding(.leading, 16)
                    captionFieldsRow
                    Divider().padding(.leading, 16)
                    captionSizeRow
                    Divider().padding(.leading, 16)
                    captionColorRow
                }
            }
        }
    }

    // MARK: - Rows

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
