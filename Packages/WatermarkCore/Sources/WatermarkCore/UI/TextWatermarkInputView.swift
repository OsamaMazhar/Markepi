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
                // A multi-line TextField is used instead of TextEditor: TextEditor
                // has its own internal scroll view, which conflicts with the
                // panel's surrounding ScrollView and intermittently swallows taps
                // and keystrokes. TextField(axis: .vertical) grows in place and
                // focuses reliably inside a ScrollView.
                TextField("Enter your watermark text", text: textBinding, axis: .vertical)
                    .font(.body)
                    .lineLimit(2...5)
                    .focused($isTextFocused)
                    .submitLabel(.done)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(minHeight: 80, alignment: .topLeading)
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
        .onChange(of: currentText) { _, newValue in
            if newValue.count > 500 {
                textBinding.wrappedValue = String(newValue.prefix(500))
            }
        }
    }

    private var currentText: String {
        if let layer = viewModel.config.watermarks.first,
           case .text(let input, _, _, _, _) = layer {
            return input.text
        }
        return ""
    }

    private var currentFontName: String? {
        if let layer = viewModel.config.watermarks.first,
           case .text(let input, _, _, _, _) = layer {
            return input.fontName
        }
        return nil
    }

    private var textBinding: Binding<String> {
        Binding(
            get: { currentText },
            set: { newValue in
                guard var layer = viewModel.config.watermarks.first,
                      case let .text(input, position, scale, opacity, isVisible) = layer else { return }
                let truncated = String(newValue.prefix(500))
                viewModel.config.watermarks[0] = .text(
                    TextWatermarkInput(
                        text: truncated,
                        fontSize: input.fontSize,
                        color: input.color,
                        opacity: input.opacity,
                        fontName: input.fontName
                    ),
                    position: position,
                    scale: scale,
                    opacity: opacity,
                    isVisible: isVisible
                )
            }
        )
    }

    private var currentFontID: String? {
        guard let fontName = currentFontName,
              let font = FontCatalog.font(byPostScriptName: fontName) else { return nil }
        return font.id
    }

    // MARK: - Color & Opacity

    private var currentTextInput: TextWatermarkInput? {
        if let layer = viewModel.config.watermarks.first,
           case .text(let input, _, _, _, _) = layer {
            return input
        }
        return nil
    }

    /// Rebuilds the first text layer in place, preserving every field except the
    /// ones the caller overrides. Keeps the per-element color/opacity edits from
    /// clobbering text, font, position, scale, or layer-level opacity/visibility.
    private func updateTextInput(color: CGColor? = nil, opacity: CGFloat? = nil) {
        guard let layer = viewModel.config.watermarks.first,
              case let .text(input, position, scale, layerOpacity, isVisible) = layer else { return }
        let updated = TextWatermarkInput(
            text: input.text,
            fontSize: input.fontSize,
            color: color ?? input.color,
            opacity: opacity ?? input.opacity,
            fontName: input.fontName
        )
        viewModel.config.watermarks[0] = .text(
            updated,
            position: position,
            scale: scale,
            opacity: layerOpacity,
            isVisible: isVisible
        )
    }

    private var textColorBinding: Binding<Color> {
        Binding(
            get: {
                guard let cg = currentTextInput?.color else { return .white }
                return Color(cgColor: cg)
            },
            set: { newColor in
                updateTextInput(color: Self.cgColor(from: newColor))
            }
        )
    }

    private var textOpacityBinding: Binding<Double> {
        Binding(
            get: { Double(currentTextInput?.opacity ?? 1.0) },
            set: { newValue in
                updateTextInput(opacity: CGFloat(newValue))
            }
        )
    }

    /// Converts a SwiftUI `Color` to a `CGColor` on either platform. Falls back
    /// to opaque white if the platform conversion fails.
    private static func cgColor(from color: Color) -> CGColor {
        #if canImport(UIKit)
        return UIColor(color).cgColor
        #elseif canImport(AppKit)
        return NSColor(color).cgColor
        #else
        return CGColor(red: 1, green: 1, blue: 1, alpha: 1)
        #endif
    }

    private var fontNameBinding: Binding<String?> {
        Binding(
            get: { currentFontID },
            set: { newFontID in
                guard var layer = viewModel.config.watermarks.first,
                      case let .text(input, position, scale, opacity, isVisible) = layer else { return }
                let resolvedFontName: String? = newFontID.flatMap { id in
                    FontCatalog.font(byID: id)?.postScriptName
                }
                viewModel.config.watermarks[0] = .text(
                    TextWatermarkInput(
                        text: input.text,
                        fontSize: input.fontSize,
                        color: input.color,
                        opacity: input.opacity,
                        fontName: resolvedFontName
                    ),
                    position: position,
                    scale: scale,
                    opacity: opacity,
                    isVisible: isVisible
                )
            }
        )
    }
}
