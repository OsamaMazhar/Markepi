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
            Text(Self.label(currentMillimetres))
                .markepiTypography(.value)
                .monospacedDigit()
            Stepper(
                "",
                value: millimetreBinding,
                in: Self.range,
                step: WatermarkScaling.millimetreStep
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
        .onAppear(perform: snapToGrid)
    }

    /// "12 mm", not "12.0 mm".
    static func label(_ millimetres: CGFloat) -> String {
        millimetres == millimetres.rounded()
            ? String(format: "%.0f mm", millimetres)
            : String(format: "%.1f mm", millimetres)
    }

    /// Brings a size set before the grid existed onto it.
    ///
    /// Without this the stepper reads a snapped 11 mm while the layer is still
    /// drawn at the 10.92 mm behind it, and every step carries that offset
    /// along — 11.4, 11.9. Writing the snapped value back once makes what is
    /// shown and what is drawn the same number.
    private func snapToGrid() {
        guard let layer = viewModel.config.watermarks[safe: layerIndex] else { return }
        let snapped = WatermarkScaling.scale(forMillimetres: currentMillimetres)
        guard abs(layer.scale - snapped) > 0.00001 else { return }
        viewModel.updateLayerScale(at: layerIndex, scale: snapped)
    }

    /// The same 1%–90% of the frame the stepper always allowed, stated in the
    /// millimetres the user now sets it in and pulled onto the grid so the
    /// bounds are reachable values rather than 2.54 and 228.6.
    private static var range: ClosedRange<CGFloat> {
        // Kept on one expression: a line starting with "..." parses as the
        // prefix range operator, which quietly splits this in two.
        let low = WatermarkScaling.snapped(millimetres: WatermarkScaling.millimetres(forScale: 0.01))
        let high = WatermarkScaling.snapped(millimetres: WatermarkScaling.millimetres(forScale: 0.90))
        return low...high
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

}
#endif
