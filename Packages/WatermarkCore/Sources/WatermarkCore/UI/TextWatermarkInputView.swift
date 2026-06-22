import CoreImage
import SwiftUI
import WatermarkCore
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Text watermark input view — editable text field bound to the first watermark layer.
///
/// Generic over any `WatermarkConfigurable & Observable` ViewModel so both
/// the main app and share extension can reuse it without code duplication.
public struct TextWatermarkInputView<ViewModel: WatermarkConfigurable & Observable>: View {
    @Bindable var viewModel: ViewModel
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @FocusState private var isTextFocused: Bool

    public init(viewModel: ViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            Text("Text")
                .markepiTypography(.sectionHeader)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                // A single-line TextField (not TextEditor): TextEditor has its own
                // internal scroll view that fought the panel's surrounding
                // ScrollView and swallowed taps/keystrokes. A watermark is a
                // single line, which also matches the renderer (it crops to one
                // line's glyph bounds), so Return dismisses the keyboard instead
                // of inserting a newline that would render clipped.
                TextField("Enter your watermark text", text: textBinding)
                    .font(.body)
                    .focused($isTextFocused)
                    .submitLabel(.done)
                    .onSubmit { isTextFocused = false }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                    .frame(minHeight: 56, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { isTextFocused = true }

                Divider()
                    .padding(.leading, 52)

                HStack {
                    Text("Font")
                        .markepiTypography(.controlLabel)
                    Spacer()
                    FontPickerView(selectedFontID: fontNameBinding)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider()
                    .padding(.leading, 16)

                HStack {
                    Text("Color")
                        .markepiTypography(.controlLabel)
                    Spacer()
                    ColorPicker("", selection: textColorBinding, supportsOpacity: false)
                        .labelsHidden()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Text color")

                Divider()
                    .padding(.leading, 16)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Opacity")
                            .markepiTypography(.controlLabel)
                        Spacer()
                        Text("\(Int((textOpacityBinding.wrappedValue * 100).rounded()))%")
                            .markepiTypography(.value)
                            .monospacedDigit()
                    }
                    Slider(value: textOpacityBinding, in: 0.1...1.0)
                        .accessibilityLabel("Text opacity")
                        .accessibilityValue("\(Int((textOpacityBinding.wrappedValue * 100).rounded())) percent")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .markepiGlass(
                shape: RoundedRectangle(cornerRadius: 12, style: .continuous),
                isEnabled: !reduceTransparency
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Text layer access (robust: first text layer, create on demand)

    /// Index of the first `.text` layer, wherever it sits in the stack. The
    /// previous code hard-coded index 0 and silently no-opped once the user
    /// added/removed/reordered layers — so typed text never reached the model.
    private var textLayerIndex: Int? {
        viewModel.config.watermarks.firstIndex { if case .text = $0 { return true }; return false }
    }

    private var currentTextInput: TextWatermarkInput? {
        guard let i = textLayerIndex,
              case .text(let input, _, _, _, _) = viewModel.config.watermarks[i] else { return nil }
        return input
    }

    private var currentText: String { currentTextInput?.text ?? "" }

    private var currentFontID: String? {
        guard let fontName = currentTextInput?.fontName,
              let font = FontCatalog.font(byPostScriptName: fontName) else { return nil }
        return font.id
    }

    /// Updates the text layer's fields, creating a text layer if none exists
    /// (so the very first keystroke always lands). `fontNameChange` is a double
    /// optional: `nil` = leave unchanged, `.some(nil)` = system font,
    /// `.some(name)` = that PostScript name.
    private func updateText(
        text: String? = nil,
        fontNameChange: String?? = nil,
        color: CGColor? = nil,
        opacity: CGFloat? = nil,
        createIfMissing: Bool = true
    ) {
        func resolvedFont(_ current: String?) -> String? {
            if let change = fontNameChange { return change }
            return current
        }
        // Watermarks are single-line; collapse any pasted newlines and cap length.
        func sanitize(_ s: String) -> String {
            String(s.replacingOccurrences(of: "\n", with: " ").prefix(500))
        }

        if let i = textLayerIndex,
           case let .text(input, position, scale, layerOpacity, isVisible) = viewModel.config.watermarks[i] {
            let updated = TextWatermarkInput(
                text: text.map(sanitize) ?? input.text,
                fontSize: input.fontSize,
                color: color ?? input.color,
                opacity: opacity ?? input.opacity,
                fontName: resolvedFont(input.fontName)
            )
            viewModel.config.watermarks[i] = .text(
                updated, position: position, scale: scale, opacity: layerOpacity, isVisible: isVisible
            )
            viewModel.activeLayerIndex = i
        } else if createIfMissing {
            let seed = TextWatermarkInput(
                text: text.map(sanitize) ?? "",
                fontSize: 48,
                color: color ?? CGColor(gray: 1, alpha: 1),
                opacity: opacity ?? 1.0,
                fontName: resolvedFont(nil)
            )
            viewModel.config.watermarks.append(
                .text(seed, position: .bottomRight, scale: 0.30, opacity: 1.0, isVisible: true)
            )
            viewModel.activeLayerIndex = viewModel.config.watermarks.count - 1
        }
    }

    private var textBinding: Binding<String> {
        Binding(get: { currentText }, set: { updateText(text: $0) })
    }

    private var textColorBinding: Binding<Color> {
        Binding(
            get: { currentTextInput.map { Color(cgColor: $0.color) } ?? .white },
            set: { updateText(color: Self.cgColor(from: $0), createIfMissing: false) }
        )
    }

    private var textOpacityBinding: Binding<Double> {
        Binding(
            get: { Double(currentTextInput?.opacity ?? 1.0) },
            set: { updateText(opacity: CGFloat($0), createIfMissing: false) }
        )
    }

    private var fontNameBinding: Binding<String?> {
        Binding(
            get: { currentFontID },
            set: { newFontID in
                let ps = newFontID.flatMap { FontCatalog.font(byID: $0)?.postScriptName }
                updateText(fontNameChange: .some(ps), createIfMissing: false)
            }
        )
    }

    /// Converts a SwiftUI `Color` to a `CGColor` on either platform.
    private static func cgColor(from color: Color) -> CGColor {
        #if canImport(UIKit)
        return UIColor(color).cgColor
        #elseif canImport(AppKit)
        return NSColor(color).cgColor
        #else
        return CGColor(red: 1, green: 1, blue: 1, alpha: 1)
        #endif
    }
}
