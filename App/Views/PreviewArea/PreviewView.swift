import SwiftUI

struct PreviewView: View {
    @Bindable var viewModel: WatermarkViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @GestureState private var pinchScale: CGFloat = 1.0
    @State private var committedScale: CGFloat = 1.0

    private var effectiveScale: CGFloat {
        committedScale * pinchScale
    }

    private var layerScale: CGFloat {
        let idx = viewModel.activeLayerIndex
        guard idx >= 0, idx < viewModel.config.watermarks.count else { return 1.0 }
        return viewModel.config.watermarks[idx].scale
    }

    var body: some View {
        Group {
            if let preview = viewModel.previewImage {
                Image(uiImage: preview)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .drawingGroup()
                    .scaleEffect(effectiveScale)
                    .gesture(magnifyGesture)
                    .overlay(alignment: .topTrailing) {
                        if pinchScale != 1.0 {
                            ScaleLabelView(scale: effectiveScale * layerScale)
                                .padding(12)
                        }
                    }
                    .overlay {
                        if viewModel.isGeneratingPreview {
                            Color.black.opacity(0.4)
                            ProgressView()
                                .tint(.white)
                        }
                    }
                    .accessibilityLabel("Watermark preview")
                    .accessibilityHint("Pinch to resize the watermark")
                    .accessibilityZoomAction { action in
                        let idx = viewModel.activeLayerIndex
                        guard idx >= 0, idx < viewModel.config.watermarks.count else { return }
                        let currentScale = viewModel.config.watermarks[idx].scale
                        let newScale: CGFloat
                        switch action.direction {
                        case .zoomIn:
                            newScale = min(currentScale + 0.05, 0.90)
                        case .zoomOut:
                            newScale = max(currentScale - 0.05, 0.01)
                        @unknown default:
                            return
                        }
                        viewModel.updateLayerScale(at: idx, scale: newScale)
                    }
            } else if viewModel.currentPhoto != nil {
                if let thumbnail = viewModel.currentPhoto?.thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .overlay {
                            ProgressView()
                        }
                } else {
                    ProgressView()
                }
            } else {
                pickerButton
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .edgesIgnoringSafeArea(.top)
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .updating($pinchScale) { value, state, _ in
                state = value.magnification
            }
            .onEnded { value in
                committedScale *= value.magnification
                let clamped = min(max(committedScale, 0.01 / layerScale), 0.90 / layerScale)
                let finalScale = clamped * layerScale
                committedScale = 1.0
                let idx = viewModel.activeLayerIndex
                guard idx >= 0, idx < viewModel.config.watermarks.count else { return }
                viewModel.updateLayerScale(at: idx, scale: finalScale)
            }
    }

    private var pickerButton: some View {
        Button {
            viewModel.showPicker = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 24, weight: .regular))
                Text("Add Photos")
                    .font(.body.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(width: 200, height: 56)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28))
        }
    }
}
