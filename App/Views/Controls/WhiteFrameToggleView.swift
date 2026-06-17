import SwiftUI

struct WhiteFrameToggleView: View {
    @Bindable var viewModel: WatermarkViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: Binding(
                get: { viewModel.whiteFrameEnabled },
                set: { _ in viewModel.toggleWhiteFrame() }
            )) {
                Text("White Frame")
                    .font(.title3.weight(.semibold))
            }

            Text("Adds a white border with device name")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .opacity(viewModel.currentPhoto == nil ? 0.4 : 1.0)
        .disabled(viewModel.currentPhoto == nil)
        .accessibilityLabel("White frame")
        .accessibilityHint("Add a white border with device model text to your photo")
    }
}
