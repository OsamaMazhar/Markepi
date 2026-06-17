import SwiftUI

struct ControlsView: View {
    @Bindable var viewModel: WatermarkViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 20) {
                TextWatermarkInputView(viewModel: viewModel)
                PositionGridView(viewModel: viewModel)
                ScaleStepperView(viewModel: viewModel)
                LogoPickerView(viewModel: viewModel)
                WhiteFrameToggleView(viewModel: viewModel)
                LayerListView(viewModel: viewModel)

                Divider()
                    .padding(.vertical, 4)

                shareButton
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
    }

    private var shareButton: some View {
        Group {
            switch viewModel.renderingState {
            case .idle:
                Button {
                    Task { await viewModel.renderAndPrepareShare() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.up")
                        Text("Share")
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.currentPhoto == nil)
                .opacity(viewModel.currentPhoto == nil ? 0.4 : 1.0)

            case .rendering:
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.regular)
                    Text("Rendering...")
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                .disabled(true)
                .transition(.opacity.combined(with: .scale))

            case .done:
                Button {
                    if !reduceMotion {
                        withAnimation(.easeOut(duration: 0.3)) {}
                    }
                    viewModel.presentShareSheet()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Ready to Share")
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .scaleEffect(viewModel.renderingState == .done && !reduceMotion ? 1.0 : 1.0)

            case .error:
                Button {
                    Task { await viewModel.renderAndPrepareShare() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.up")
                        Text("Share")
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.currentPhoto == nil)
                .opacity(viewModel.currentPhoto == nil ? 0.4 : 1.0)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: viewModel.renderingState)
    }
}
