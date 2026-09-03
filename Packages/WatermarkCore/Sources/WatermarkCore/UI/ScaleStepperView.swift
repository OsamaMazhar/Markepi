// iOS-only UI. Guarded so WatermarkCore also builds for macOS, where the
// `markepi` CLI target links the engine without the SwiftUI layer.
#if canImport(UIKit)
import SwiftUI

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
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Size")
                    .markepiTypography(.controlLabel)
                Text("Same size on photos and video")
                    .markepiTypography(.metadata)
            }
            Spacer()
            Text(String(format: "%.1f mm", currentMillimetres))
                .markepiTypography(.value)
                .monospacedDigit()
            Stepper(
                "",
                value: millimetreBinding,
                in: Self.range,
                step: 0.5
            )
            .labelsHidden()
            .frame(width: 100)
            .accessibilityIdentifier("layer.size.mm")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityLabel("Watermark size")
        .accessibilityValue(String(format: "%.1f millimetres", currentMillimetres))
        .accessibilityHint("Adjusts the watermark's size, measured on a standard print")
    }

    /// The same 1%–90% of the frame the stepper always allowed, stated in the
    /// millimetres the user now sets it in.
    private static var range: ClosedRange<CGFloat> {
        WatermarkScaling.millimetres(forScale: 0.01)...WatermarkScaling.millimetres(forScale: 0.90)
    }

    /// Millimetres on a reference print, which is a fixed share of the frame —
    /// so one setting is the same size on a still and on footage, whatever
    /// either one's resolution.
    private var currentMillimetres: CGFloat {
        WatermarkScaling.millimetres(forScale: currentScale)
    }

    private var millimetreBinding: Binding<CGFloat> {
        Binding(
            get: { currentMillimetres },
            set: { viewModel.updateLayerScale(
                at: layerIndex, scale: WatermarkScaling.scale(forMillimetres: $0)) }
        )
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
#endif
