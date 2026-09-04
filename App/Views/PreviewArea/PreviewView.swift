import OSLog
import SwiftUI
import WatermarkCore

#if DEBUG
/// Drag placement is a gesture, a lifted layer and a background render moving
/// in step, and none of it leaves a trace to inspect afterwards. Read it on a
/// device with:
/// `log stream --device --predicate 'category == "drag"'`
private let dragLog = Logger(subsystem: "com.osamamazhar.markepi", category: "drag")
#endif

struct PreviewView: View {
    @Bindable var viewModel: WatermarkViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Canvas zoom. `pan` is in screen points and is applied *after* the
    /// scale, which is what lets a pinch hold the point under the fingers
    /// still instead of always growing out of the centre.
    @State private var zoom: CGFloat = 1.0
    @State private var pan: CGSize = .zero
    @GestureState private var pinchZoom: CGFloat = 1.0
    @GestureState private var pinchFocus: CGPoint = .zero
    @GestureState private var isComparing: Bool = false
    @GestureState private var isPinching: Bool = false

    /// `pan` as it was when a canvas-panning drag began; nil while a drag is
    /// moving a layer instead.
    @State private var panStart: CGSize?

    /// Displayed size of the preview image itself (not the container), so a
    /// drag in points can be converted into the layer's placement fractions.
    @State private var imageDisplaySize: CGSize = .zero

    /// The whole preview area. A zoomed photo may fill it, black bars included,
    /// and it bounds how far the photo can be panned.
    @State private var containerSize: CGSize = .zero

    /// Untransformed space to measure drags in. Measuring them in the zoomed
    /// photo's own space fed the pan back into its own input — every pan moved
    /// the view the translation was measured against, so it juddered.
    private static let canvasSpace = "markepi.preview.canvas"

    /// Live drag state, nil when nothing is being dragged.
    ///
    /// The config is written ONCE, when the drag ends. Writing it per finger
    /// movement asked for a full-resolution re-render each frame, and every
    /// frame cancelled the previous one — so the element only appeared to move
    /// when the finger lifted. Instead the layer is lifted out of the composite
    /// and `ghost` follows the finger at screen speed.
    @State private var drag: DragState?

    /// The just-dropped drag, kept on screen until the composite catches up.
    /// Without it the element vanishes at the drop point and reappears at the
    /// old one for as long as the re-render takes.
    @State private var settling: DragState?

    /// Whatever the overlay should be drawing right now.
    private var activeDrag: DragState? { drag ?? settling }

    private struct DragState {
        let index: Int
        /// The layer rendered on its own. Nil when it draws nothing (empty text).
        let ghost: CGImage?
        let opacity: CGFloat
        let wasVisible: Bool
        /// Normalized (y-down) geometry captured when the drag began.
        let frame: CGRect
        let photo: CGRect
        var translation: CGSize = .zero
    }

    private var liveZoom: CGFloat { clampedZoom(zoom * pinchZoom) }

    private var livePan: CGSize { panOffset(forZoom: liveZoom, focus: pinchFocus) }

    private func clampedZoom(_ value: CGFloat) -> CGFloat { min(max(value, 1.0), 6.0) }

    /// The pan that keeps `focus` — a point in the photo's own coordinates,
    /// measured from its centre — under the fingers as the zoom changes.
    private func panOffset(forZoom newZoom: CGFloat, focus: CGPoint) -> CGSize {
        clampedPan(
            CGSize(width: pan.width + (zoom - newZoom) * focus.x,
                   height: pan.height + (zoom - newZoom) * focus.y),
            zoom: newZoom
        )
    }

    /// Holds the zoomed photo's edges outside the preview area, so it can never
    /// be pushed off far enough to show a gap. An axis the photo doesn't fill
    /// yet has no travel at all, which keeps it centred.
    private func panLimits(zoom: CGFloat) -> CGSize {
        CGSize(width: max((zoom * imageDisplaySize.width - containerSize.width) / 2, 0),
               height: max((zoom * imageDisplaySize.height - containerSize.height) / 2, 0))
    }

    private func clampedPan(_ offset: CGSize, zoom: CGFloat) -> CGSize {
        let limit = panLimits(zoom: zoom)
        return CGSize(width: min(max(offset.width, -limit.width), limit.width),
                      height: min(max(offset.height, -limit.height), limit.height))
    }

    /// A point in the preview area's coordinates as a point in the photo's own,
    /// undoing the zoom. The photo is centred, so the two centres coincide.
    private func contentPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: imageDisplaySize.width / 2 + (point.x - containerSize.width / 2 - pan.width) / zoom,
            y: imageDisplaySize.height / 2 + (point.y - containerSize.height / 2 - pan.height) / zoom
        )
    }

    /// A pinch's anchor as a point in the photo's own coordinates, from centre.
    private func focus(of anchor: UnitPoint) -> CGPoint {
        CGPoint(x: (anchor.x - 0.5) * imageDisplaySize.width,
                y: (anchor.y - 0.5) * imageDisplaySize.height)
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
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { imageDisplaySize = $0 }
                    // The gestures live on a transparent overlay, NOT on the
                    // Image: a new preview lands mid-drag now that renders are
                    // fast, and a recognizer attached to the Image itself is
                    // rebuilt along with it. This layer never changes.
                    .overlay {
                        Color.clear
                            .contentShape(Rectangle())
                            .gesture(combinedGesture)
                    }
                    .overlay(alignment: .topLeading) {
                        if let drag = activeDrag, let ghost = drag.ghost, imageDisplaySize.width > 0 {
                            let origin = ghostOrigin(drag)
                            Image(decorative: ghost, scale: 1)
                                .resizable()
                                .frame(
                                    width: drag.frame.width * imageDisplaySize.width,
                                    height: drag.frame.height * imageDisplaySize.height
                                )
                                .opacity(drag.opacity)
                                .offset(x: origin.x, y: origin.y)
                                .allowsHitTesting(false)
                        }
                    }
                    // Photo, gesture layer and ghost zoom as one, so gesture
                    // locations and the ghost's placement stay in the photo's
                    // own coordinates however far it is zoomed in.
                    .scaleEffect(liveZoom)
                    .offset(livePan)
                    .sensoryFeedback(.impact(weight: .light), trigger: isComparing)
                    .overlay(alignment: .topTrailing) {
                        if liveZoom != 1.0 {
                            ScaleLabelView(scale: liveZoom)
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
                    .accessibilityHint("Drag to move the watermark, pinch to zoom the photo")
                    .accessibilityZoomAction { action in
                        let factor: CGFloat
                        switch action.direction {
                        case .zoomIn:  factor = 1.5
                        case .zoomOut: factor = 1 / 1.5
                        @unknown default: return
                        }
                        let newZoom = clampedZoom(zoom * factor)
                        pan = panOffset(forZoom: newZoom, focus: .zero)
                        zoom = newZoom
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
        .onGeometryChange(for: CGSize.self) { $0.size } action: { containerSize = $0 }
        // Clipping the preview area rather than the photo's fitted frame is
        // what lets a zoomed photo spread into the black bars beside it.
        .clipped()
        .coordinateSpace(.named(Self.canvasSpace))
        .onChange(of: viewModel.previewRevision) {
            // The composite now shows the element where it was dropped.
            if drag == nil { settling = nil }
        }
        // Respect all safe areas: the top keeps the image below the status bar /
        // toolbar, and the host's `.safeAreaInset(edge: .bottom)` keeps it clear
        // of the bottom chrome. The full-bleed black canvas behind fills the rest.
    }

    /// Pinch to zoom the photo, anchored on the point between the fingers, and
    /// the zoom stays where it is left. Sizing a layer is the size control's
    /// job, so nothing here writes to the config.
    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .updating($pinchZoom) { value, state, _ in
                state = value.magnification
            }
            .updating($pinchFocus) { value, state, _ in
                state = focus(of: value.startAnchor)
            }
            .updating($isPinching) { _, state, _ in
                state = true
            }
            .onEnded { value in
                let newZoom = clampedZoom(zoom * value.magnification)
                pan = panOffset(forZoom: newZoom, focus: focus(of: value.startAnchor))
                zoom = newZoom
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

    /// Free placement: drag the layer under the finger (or the active one)
    /// anywhere on the photo, bounded by the photo's edges.
    private var dragGesture: some Gesture {
        // 12pt beats the long-press-to-compare gesture's 10pt slop, so holding
        // still to compare doesn't nudge the watermark.
        DragGesture(minimumDistance: 12, coordinateSpace: .named(Self.canvasSpace))
            .onChanged { value in
                // A pinch moves its centroid; without this the watermark would
                // fly across the photo while being resized.
                guard !isPinching, imageDisplaySize.width > 0 else {
                    #if DEBUG
                    dragLog.debug("ignored: pinching=\(isPinching) size=\(imageDisplaySize.width)")
                    #endif
                    return
                }
                if let panStart {
                    // Both the translation and the pan are in preview-area
                    // points, so the photo tracks the finger exactly.
                    pan = clampedPan(
                        CGSize(width: panStart.width + value.translation.width,
                               height: panStart.height + value.translation.height),
                        zoom: zoom
                    )
                    return
                }
                if drag == nil { beginDrag(at: contentPoint(value.startLocation)) }
                // Nothing under the finger and the photo has somewhere to go:
                // move the photo instead, so a zoomed-in area can be reached.
                let limits = panLimits(zoom: zoom)
                if drag == nil, limits.width > 0 || limits.height > 0 {
                    panStart = pan
                    return
                }
                // A layer moves with the finger, so its travel is the on-screen
                // distance measured back in the photo's own points.
                drag?.translation = CGSize(width: value.translation.width / zoom,
                                           height: value.translation.height / zoom)
            }
            .onEnded { _ in
                panStart = nil
                endDrag()
            }
    }

    /// Picks the layer to move, snapshots the geometry the drag is relative to,
    /// and lifts the layer out of the composite so the ghost isn't a duplicate.
    private func beginDrag(at location: CGPoint) {
        let layers = viewModel.config.watermarks
        guard !layers.isEmpty else { return }
        let layout = viewModel.previewLayout

        // The topmost layer under the finger, and only that. Falling back to
        // whichever layer the tool panel was editing meant a drag anywhere on
        // the photo — empty sky included — picked up the text and carried it
        // off, whether or not the panel was open.
        let point = CGPoint(
            x: location.x / imageDisplaySize.width,
            y: location.y / max(imageDisplaySize.height, 1)
        )
        guard let index = layout?.layerIndex(at: point),
              layers.indices.contains(index) else {
            #if DEBUG
            dragLog.debug("no layer under \(point.debugDescription) — nothing to move")
            #endif
            return
        }
        viewModel.activeLayerIndex = index

        let layer = layers[index]
        let ghost = LayerPreviewImage.render(layer, metadata: viewModel.sourceMetadata)
        let photo = layout?.photoRect ?? CGRect(x: 0, y: 0, width: 1, height: 1)
        // Deferred config saving, so the temporarily-hidden layer is never
        // persisted — only the finished position is.
        viewModel.beginInteractiveConfigChange()
        let state = DragState(
            index: index,
            ghost: ghost,
            opacity: layer.opacity,
            wasVisible: layer.isVisible,
            frame: frame(of: layer, at: index, ghost: ghost, in: photo, layout: layout),
            photo: photo
        )
        drag = state
        if state.ghost != nil {
            viewModel.setLayerVisibility(at: index, isVisible: false)
        }
        #if DEBUG
        dragLog.debug(
            "begin idx=\(index) ghost=\(state.ghost != nil) frame=\(state.frame.debugDescription) photo=\(photo.debugDescription) display=\(imageDisplaySize.debugDescription) layoutHadFrame=\(layout?.layerFrames[index] != nil)"
        )
        #endif
    }

    /// Where the layer sits in the composite, normalized and y-down.
    ///
    /// The last render is the exact answer, but it only knows about layers it
    /// actually drew — a layer hidden for a previous drag has no entry, and a
    /// zero rect meant an invisible, apparently-dead ghost. So fall back to the
    /// same arithmetic the renderer uses: scale is a fraction of the photo
    /// (height for text, width for everything else) and the position is a
    /// fraction of the leftover travel.
    private func frame(
        of layer: WatermarkLayer,
        at index: Int,
        ghost: CGImage?,
        in photo: CGRect,
        layout: RenderLayout?
    ) -> CGRect {
        if let rendered = layout?.layerFrames[index], rendered.width > 0, rendered.height > 0 {
            return rendered
        }
        guard let ghost, ghost.width > 0, ghost.height > 0,
              imageDisplaySize.width > 0, imageDisplaySize.height > 0 else { return .zero }
        // Normalized width and height are fractions of DIFFERENT sides, so the
        // ghost's pixel aspect has to be converted through the canvas aspect.
        let canvasAspect = imageDisplaySize.width / imageDisplaySize.height
        let ghostAspect = CGFloat(ghost.height) / CGFloat(ghost.width)
        // `scale` is a fraction of the photo's SHORTER side, whichever that is
        // (WatermarkScaling.reference), expressed here in normalized units.
        let photoPixels = CGSize(width: photo.width * imageDisplaySize.width,
                                 height: photo.height * imageDisplaySize.height)
        let shorterIsWidth = photoPixels.width <= photoPixels.height
        let size: CGSize
        if case .text = layer {
            let height = shorterIsWidth
                ? layer.scale * photo.width * canvasAspect
                : layer.scale * photo.height
            size = CGSize(width: height / ghostAspect / canvasAspect, height: height)
        } else {
            let width = shorterIsWidth
                ? layer.scale * photo.width
                : layer.scale * photo.height / canvasAspect
            size = CGSize(width: width, height: width * ghostAspect * canvasAspect)
        }
        let placement = layer.position.fraction
        return CGRect(
            x: photo.minX + placement.x * max(photo.width - size.width, 0),
            y: photo.minY + placement.y * max(photo.height - size.height, 0),
            width: size.width,
            height: size.height
        )
    }

    private func endDrag() {
        guard let drag else { return }
        let placement = travelFraction(drag)
        // Hand the ghost over to `settling` in the same update: it keeps drawing
        // the element exactly where it was dropped while the composite re-renders
        // behind it, so the swap when the new image lands is invisible.
        self.drag = nil
        settling = drag
        viewModel.setLayerVisibility(at: drag.index, isVisible: drag.wasVisible)
        viewModel.updateLayerPosition(
            at: drag.index,
            position: .custom(x: placement.x, y: placement.y)
        )
        viewModel.endInteractiveConfigChange()
        #if DEBUG
        dragLog.debug(
            "end idx=\(drag.index) moved=\(drag.translation.debugDescription) placed=\(placement.debugDescription)"
        )
        #endif
    }

    /// Top-left of the ghost in the image's own points, clamped to the photo so
    /// the element can never be dragged off it — the same bound the renderer
    /// applies, so what is dropped is what is rendered.
    private func ghostOrigin(_ drag: DragState) -> CGPoint {
        let bounds = dragBounds(drag)
        return CGPoint(
            x: min(max(drag.frame.minX * imageDisplaySize.width + drag.translation.width,
                       bounds.minX), bounds.maxX),
            y: min(max(drag.frame.minY * imageDisplaySize.height + drag.translation.height,
                       bounds.minY), bounds.maxY)
        )
    }

    /// The range the ghost's origin may take, in points: the photo inset by the
    /// element's own size.
    private func dragBounds(_ drag: DragState) -> CGRect {
        let minX = drag.photo.minX * imageDisplaySize.width
        let minY = drag.photo.minY * imageDisplaySize.height
        return CGRect(
            x: minX,
            y: minY,
            width: max((drag.photo.width - drag.frame.width) * imageDisplaySize.width, 0),
            height: max((drag.photo.height - drag.frame.height) * imageDisplaySize.height, 0)
        )
    }

    /// Where the ghost ended up, as the travel fractions `.custom` stores.
    private func travelFraction(_ drag: DragState) -> CGPoint {
        let bounds = dragBounds(drag)
        let origin = ghostOrigin(drag)
        return CGPoint(
            x: bounds.width > 0 ? (origin.x - bounds.minX) / bounds.width : 0.5,
            y: bounds.height > 0 ? (origin.y - bounds.minY) / bounds.height : 0.5
        )
    }

    private var combinedGesture: some Gesture {
        comparisonGesture
            .simultaneously(with: magnifyGesture)
            .simultaneously(with: dragGesture)
    }
}
