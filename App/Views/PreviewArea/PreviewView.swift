import SwiftUI

struct PreviewView: View {
    @Bindable var viewModel: WatermarkViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @GestureState private var pinchScale: CGFloat = 1.0
    @State private var committedScale: CGFloat = 1.0
    @GestureState private var isComparing: Bool = false

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
                    // NOTE: do NOT add `.drawingGroup()` here. It flattens the
                    // image into a Metal layer whose size is cached at composite
                    // time, so when the bottom tool panel closes (shrinking the
                    // `.safeAreaInset`) the preview kept its old, smaller frame
                    // until the next `previewImage` swap forced a re-composite.
                    // Letting SwiftUI render the image natively makes it resize
                    // in lock-step with the surrounding layout.
                    .scaleEffect(effectiveScale)
                    .gesture(combinedGesture)
                    .sensoryFeedback(.impact(weight: .light), trigger: isComparing)
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
                        if viewModel.isGeneratingPreview && viewModel.previewImage == nil {
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
                // Empty state is now handled by EmptyStateView at ContentView level
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Respect all safe areas: the top keeps the image below the status bar /
        // toolbar, and the host's `.safeAreaInset(edge: .bottom)` keeps it clear
        // of the bottom chrome. The full-bleed black canvas behind fills the rest.
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

    /// Press-and-hold to compare against the original. A plain `LongPressGesture`
    /// *completes* once recognized, so `isComparing` would flip back to false even
    /// while the finger stays down. Sequencing it into a 0-distance drag keeps the
    /// gesture — and thus the original image — active for the whole hold, reverting
    /// only on release. The 0.25s threshold keeps it from firing on taps/pinches.
    private var comparisonGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.25)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .updating($isComparing) { value, state, _ in
                switch value {
                case .second(true, _): state = true   // held past threshold → show original
                default:               state = false
                }
            }
    }

    private var combinedGesture: some Gesture {
        comparisonGesture.simultaneously(with: magnifyGesture)
    }
}
