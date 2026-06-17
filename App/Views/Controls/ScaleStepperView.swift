import SwiftUI
import WatermarkCore

struct ScaleStepperView: View {
    @Bindable var viewModel: WatermarkViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Scale")
                .font(.title3.weight(.semibold))

            HStack {
                Text("Scale: \(Int(currentScale * 100))%")
                    .font(.body)
                    .foregroundStyle(.secondary)

                Spacer()

                Stepper(
                    "",
                    value: scaleBinding,
                    in: 0.01...0.90,
                    step: 0.05
                )
                .labelsHidden()
            }
        }
        .opacity(viewModel.currentPhoto == nil ? 0.4 : 1.0)
        .disabled(viewModel.currentPhoto == nil)
    }

    private var currentScale: CGFloat {
        guard let layer = viewModel.config.watermarks.first else { return 0.15 }
        switch layer {
        case .text(_, _, let scale): return scale
        case .image(_, _, let scale): return scale
        }
    }

    private var scaleBinding: Binding<CGFloat> {
        Binding(
            get: { currentScale },
            set: { newValue in
                guard var layer = viewModel.config.watermarks.first else { return }
                let clamped = min(max(newValue, 0.01), 0.90)
                switch layer {
                case .text(let input, let position, _):
                    viewModel.config.watermarks[0] = .text(input, position: position, scale: clamped)
                case .image(let input, let position, _):
                    viewModel.config.watermarks[0] = .image(input, position: position, scale: clamped)
                }
            }
        )
    }
}
