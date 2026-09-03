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

/// Text watermark input view — editable text field bound to the first watermark layer.
///
/// The font selector uses the sheet-based `FontPickerView` so each typeface
/// previews in its OWN font (a `Menu` routes labels through UIKit and strips the
/// custom face, flattening every name to San Francisco). The color selector
/// stays `Menu`-based for a compact preset list.
public struct TextWatermarkInputView<ViewModel: WatermarkConfigurable & Observable>: View {
    @Bindable var viewModel: ViewModel
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @FocusState private var isTextFocused: Bool

    private let showsSectionHeader: Bool

    public init(viewModel: ViewModel, showsSectionHeader: Bool = true) {
        self.viewModel = viewModel
        self.showsSectionHeader = showsSectionHeader
    }

    public var body: some View {
        VStack(spacing: 0) {
            if showsSectionHeader {
                Text("Text")
                    .markepiTypography(.sectionHeader)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }

            if textLayers.count > 1 {
                textLayerSelector
            }

            VStack(spacing: 0) {
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

                // Font picker — sheet-based so each typeface previews in its own font.
                HStack {
                    Text("Font")
                        .markepiTypography(.controlLabel)
                    Spacer()
                    FontPickerView(selectedFontID: fontIDBinding)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider()
                    .padding(.leading, 16)

                // Color picker — Menu with preset swatches for compact,
                // extension-safe presentation.
                HStack {
                    Text("Color")
                        .markepiTypography(.controlLabel)
                    Spacer()
                    Menu {
                        ForEach(presetColors, id: \.name) { preset in
                            Button {
                                updateText(color: preset.cgColor, createIfMissing: false)
                            } label: {
                                HStack {
                                    Text(preset.name)
                                    if isCurrentColor(preset.cgColor) {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color(cgColor: currentTextInput?.color ?? CGColor(gray: 1, alpha: 1)))
                                .frame(width: 18, height: 18)
                                .overlay(Circle().stroke(.secondary, lineWidth: 1))
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                    }
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

            addTextButton
                .padding(.horizontal, 16)
                .padding(.top, 12)
        }
    }

    // MARK: - Preset Colors

    private struct PresetColor {
        let name: String
        let cgColor: CGColor
    }

    private var presetColors: [PresetColor] {
        [
            .init(name: "White", cgColor: CGColor(red: 1, green: 1, blue: 1, alpha: 1)),
            .init(name: "Black", cgColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1)),
            .init(name: "Red", cgColor: CGColor(red: 1, green: 0.23, blue: 0.19, alpha: 1)),
            .init(name: "Orange", cgColor: CGColor(red: 1, green: 0.58, blue: 0, alpha: 1)),
            .init(name: "Yellow", cgColor: CGColor(red: 1, green: 0.8, blue: 0, alpha: 1)),
            .init(name: "Green", cgColor: CGColor(red: 0.2, green: 0.78, blue: 0.35, alpha: 1)),
            .init(name: "Blue", cgColor: CGColor(red: 0, green: 0.48, blue: 1, alpha: 1)),
            .init(name: "Purple", cgColor: CGColor(red: 0.55, green: 0.35, blue: 0.77, alpha: 1)),
            .init(name: "Pink", cgColor: CGColor(red: 1, green: 0.18, blue: 0.58, alpha: 1)),
            .init(name: "Gray", cgColor: CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)),
        ]
    }

    private func isCurrentColor(_ color: CGColor) -> Bool {
        guard let current = currentTextInput?.color else { return false }
        return current == color
    }

    /// Bridges `FontPickerView`'s font-ID selection to the layer's stored
    /// PostScript name, updating the active text layer (never a hardcoded index).
    private var fontIDBinding: Binding<String?> {
        Binding(
            get: {
                guard let fontName = currentTextInput?.fontName else { return nil }
                return FontCatalog.font(byPostScriptName: fontName)?.id
            },
            set: { newFontID in
                let postScriptName = newFontID.flatMap { FontCatalog.font(byID: $0)?.postScriptName }
                updateText(fontNameChange: .some(postScriptName), createIfMissing: false)
            }
        )
    }

    // MARK: - Text Layer Selector

    private var textLayerSelector: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Editing")
                .markepiTypography(.metadata)
                .frame(maxWidth: .infinity, alignment: .leading)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(textLayers, id: \.index) { entry in
                        textLayerChip(entry)
                    }
                }
                .padding(.horizontal, 1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private func textLayerChip(_ entry: TextLayerEntry) -> some View {
        let isActive = entry.index == textLayerIndex
        Button {
            viewModel.activeLayerIndex = entry.index
        } label: {
            Text(chipLabel(for: entry))
                .markepiTypography(.controlLabel)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isActive ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.10))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(isActive ? Color.accentColor : Color.clear, lineWidth: 1.5)
                )
                .foregroundStyle(isActive ? Color.accentColor : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Edit \(chipLabel(for: entry))")
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    private func chipLabel(for entry: TextLayerEntry) -> String {
        let trimmed = entry.input.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Text \(entry.ordinal)" }
        let truncated = String(trimmed.prefix(20))
        return truncated.count < trimmed.count ? truncated + "…" : truncated
    }

    private var addTextButton: some View {
        Button {
            appendTextLayer()
        } label: {
            Label(textLayers.isEmpty ? "Add Text" : "Add Another Text",
                  systemImage: "textbox")
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.markepiPrimary())
        .accessibilityHint("Adds a new text watermark you can position and style on its own")
    }

    private func appendTextLayer() {
        let seed = TextWatermarkInput(
            text: "",
            fontSize: 48,
            color: CGColor(gray: 1, alpha: 1),
            opacity: 1.0,
            fontName: WatermarkConfiguration.defaultFontPostScriptName
        )
        viewModel.config.watermarks.append(
            .text(seed, position: viewModel.config.nextFreePosition, scale: WatermarkConfiguration.defaultTextScale, opacity: 1.0, isVisible: true)
        )
        viewModel.activeLayerIndex = viewModel.config.watermarks.count - 1
    }

    private struct TextLayerEntry {
        let index: Int
        let ordinal: Int
        let input: TextWatermarkInput
    }

    private var textLayers: [TextLayerEntry] {
        var entries: [TextLayerEntry] = []
        for (index, layer) in viewModel.config.watermarks.enumerated() {
            if case .text(let input, _, _, _, _) = layer {
                entries.append(TextLayerEntry(index: index, ordinal: entries.count + 1, input: input))
            }
        }
        return entries
    }

    private var textLayerIndex: Int? {
        let wms = viewModel.config.watermarks
        let active = viewModel.activeLayerIndex
        if active >= 0, active < wms.count, case .text = wms[active] { return active }
        return wms.firstIndex { if case .text = $0 { return true }; return false }
    }

    private var currentTextInput: TextWatermarkInput? {
        guard let i = textLayerIndex,
              case .text(let input, _, _, _, _) = viewModel.config.watermarks[i] else { return nil }
        return input
    }

    private var currentText: String { currentTextInput?.text ?? "" }

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
                fontName: resolvedFont(WatermarkConfiguration.defaultFontPostScriptName)
            )
            viewModel.config.watermarks.append(
                .text(seed, position: viewModel.config.nextFreePosition, scale: WatermarkConfiguration.defaultTextScale, opacity: 1.0, isVisible: true)
            )
            viewModel.activeLayerIndex = viewModel.config.watermarks.count - 1
        }
    }

    private var textBinding: Binding<String> {
        Binding(get: { currentText }, set: { updateText(text: $0) })
    }

    private var textOpacityBinding: Binding<Double> {
        Binding(
            get: { Double(currentTextInput?.opacity ?? 1.0) },
            set: { updateText(opacity: CGFloat($0), createIfMissing: false) }
        )
    }
}
#endif
