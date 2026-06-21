import SwiftUI
import WatermarkCore

/// Toggle switch for enabling/disabling the white frame overlay.
///
/// Generic over any `WatermarkConfigurable & Observable` ViewModel.
public struct WhiteFrameToggleView<ViewModel: WatermarkConfigurable & Observable>: View {
    @Bindable var viewModel: ViewModel

    public init(viewModel: ViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        // Read the observable value here in `body` so SwiftUI tracks it and
        // re-renders the toggle when the frame is enabled/disabled elsewhere.
        let isEnabled = viewModel.whiteFrameEnabled
        VStack(spacing: 0) {
            Toggle(isOn: Binding(
                get: { isEnabled },
                set: { viewModel.setWhiteFrameEnabled($0) }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("White Frame")
                        .markepiTypography(.controlLabel)
                    Text("Adds a white border with device name")
                        .markepiTypography(.metadata)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .accessibilityLabel("White frame")
        .accessibilityHint("Add a white border with device model text to your photo")
    }
}
