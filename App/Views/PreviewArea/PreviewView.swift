import SwiftUI

struct PreviewView: View {
    @Bindable var viewModel: WatermarkViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @GestureState private var pinchScale: CGFloat = 1.0
    @State private var committedScale: CGFloat = 1.0
    @GestureState private var isComparing: Bool = false
    @State private var hapticTrigger: Bool = false

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
                Image(uiImage: isComparing ? (viewModel.originalSourceImage ?? preview) : preview)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .drawingGroup()
                    .scaleEffect(effectiveScale)
                    .gesture(combinedGesture)
                    .sensoryFeedback(.impact(weight: .light), trigger: hapticTrigger)
                    .overlay(alignment: .topTrailing) {
                        if pinchScale != 1.0 {
                            ScaleLabelView(scale: effectiveScale * layerScale)
                                .padding(12)
                        }
                    }
                    .overlay(alignment: .center) {
                        if isComparing {
                            Text("Original")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(.ultraThinMaterial, in: Capsule())
                                .transition(.opacity.animation(.easeInOut(duration: 0.15)))
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
                            // Only spin while a preview is actually being
                            // generated. If generation finished (e.g. failed),
                            // show the thumbnail rather than spinning forever —
                            // any failure is surfaced via the error alert.
                            if viewModel.isGeneratingPreview {
                                ProgressView()
                            }
                        }
                } else if viewModel.isGeneratingPreview {
                    ProgressView()
                }
            } else {
                pickerButton
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
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

    private var comparisonGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.15)
            .updating($isComparing) { value, state, _ in
                let wasComparing = state
                state = value
                if wasComparing != value {
                    hapticTrigger.toggle()
                }
            }
    }

    private var combinedGesture: some Gesture {
        comparisonGesture.simultaneously(with: magnifyGesture)
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
