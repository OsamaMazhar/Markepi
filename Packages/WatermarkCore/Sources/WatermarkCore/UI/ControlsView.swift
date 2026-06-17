import SwiftUI
import WatermarkCore

/// Composite view combining all watermarking controls: text input, position
/// grid, scale stepper, logo picker, white frame toggle, and layer list.
///
/// Generic over any `WatermarkConfigurable & Observable` ViewModel so both
/// the main app and share extension can reuse it with their own ViewModels.
///
/// Includes the Share/Render button which adapts to the ViewModel's
/// `renderingState` (idle/rendering/done/error).
public struct ControlsView<ViewModel: WatermarkConfigurable & Observable>: View {
    @State var viewModel: ViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(viewModel: ViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
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

            case .error:
                Button {
                    Task { await viewModel.renderAndPrepareShare() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise")
                        Text("Retry")
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                }
                .buttonStyle(.bordered)
                .tint(.orange)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: viewModel.renderingState)
    }
}
