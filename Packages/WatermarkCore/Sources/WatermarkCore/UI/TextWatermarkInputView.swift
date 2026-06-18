import SwiftUI
import WatermarkCore
#if canImport(UIKit)
import UIKit
#endif

/// Text watermark input view — editable text field bound to the first watermark layer.
///
/// Generic over any `WatermarkConfigurable & Observable` ViewModel so both
/// the main app and share extension can reuse it without code duplication.
public struct TextWatermarkInputView<ViewModel: WatermarkConfigurable & Observable>: View {
    @Bindable var viewModel: ViewModel

    public init(viewModel: ViewModel) {
        self.viewModel = viewModel
    }

    /// Returns the appropriate semantic placeholder text color for the current platform.
    private var placeholderColor: Color {
        #if canImport(UIKit)
        Color(UIColor.placeholderText)
        #else
        Color(.placeholderTextColor)
        #endif
    }

    /// Returns the appropriate semantic separator color for the current platform.
    private var separatorColor: Color {
        #if canImport(UIKit)
        Color(UIColor.separator)
        #else
        Color(.separatorColor)
        #endif
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Watermark Text")
                .font(.title3.weight(.semibold))

            ZStack(alignment: .topLeading) {
                if currentText.isEmpty {
                    Text("Watermark text")
                        .foregroundColor(placeholderColor)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 8)
                }
                TextEditor(text: textBinding)
                    .font(.body)
                    .frame(minHeight: 80, maxHeight: 120)
                    .scrollContentBackground(.hidden)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(separatorColor)
            )
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
                        opacity: input.opacity
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
