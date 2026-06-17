import SwiftUI
import WatermarkCore

/// Scale stepper control for adjusting watermark size.
///
/// Generic over any `WatermarkConfigurable & Observable` ViewModel.
public struct ScaleStepperView<ViewModel: WatermarkConfigurable & Observable>: View {
    @Bindable var viewModel: ViewModel

    public init(viewModel: ViewModel) {
        self.viewModel = viewModel
    }

    private var layerIndex: Int {
        let idx = viewModel.activeLayerIndex
        guard idx >= 0, idx < viewModel.config.watermarks.count else { return 0 }
        return idx
    }

    public var body: some View {
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
        .accessibilityLabel("Watermark scale")
        .accessibilityHint("Adjust watermark size. Current value: \(Int(currentScale * 100)) percent")
    }

    private var currentScale: CGFloat {
        guard let layer = viewModel.config.watermarks[safe: layerIndex] else { return 0.15 }
        return layer.scale
    }

    private var scaleBinding: Binding<CGFloat> {
        Binding(
            get: { currentScale },
            set: { viewModel.updateLayerScale(at: layerIndex, scale: $0) }
        )
    }
}
