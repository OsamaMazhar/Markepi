import SwiftUI
import WatermarkCore

struct TextWatermarkInputView: View {
    @Bindable var viewModel: WatermarkViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Watermark Text")
                .font(.title3.weight(.semibold))

            ZStack(alignment: .topLeading) {
                if currentText.isEmpty {
                    Text("Watermark text")
                        .foregroundColor(Color(.placeholderText))
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
                    .stroke(Color(.separator))
            )
        }
        .opacity(viewModel.currentPhoto == nil ? 0.4 : 1.0)
        .disabled(viewModel.currentPhoto == nil)
        .onChange(of: currentText) { _, newValue in
            if newValue.count > 500 {
                textBinding.wrappedValue = String(newValue.prefix(500))
            }
        }
    }

    private var currentText: String {
        if let layer = viewModel.config.watermarks.first,
           case .text(let input, _, _) = layer {
            return input.text
        }
        return ""
    }

    private var textBinding: Binding<String> {
        Binding(
            get: { currentText },
            set: { newValue in
                guard var layer = viewModel.config.watermarks.first,
                      case let .text(input, position, scale) = layer else { return }
                let truncated = String(newValue.prefix(500))
                viewModel.config.watermarks[0] = .text(
                    TextWatermarkInput(
                        text: truncated,
                        fontSize: input.fontSize,
                        color: input.color,
                        opacity: input.opacity
                    ),
                    position: position,
                    scale: scale
                )
            }
        )
    }
}
