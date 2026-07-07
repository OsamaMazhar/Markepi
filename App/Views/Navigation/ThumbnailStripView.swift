import SwiftUI
import WatermarkCore

struct ThumbnailStripView: View {
    let photos: [PhotoItem]
    @Binding var currentIndex: Int

    /// Per-item watermark override configs for showing dot indicators.
    var perItemOverrides: [UUID: WatermarkConfiguration] = [:]

    /// Callback when a thumbnail is tapped (for opening BatchItemDetailSheet).
    var onItemTapped: ((Int) -> Void)? = nil

    /// Callback when thumbnails are reordered via drag-and-drop.
    /// The caller updates the photos array and re-evaluates currentIndex.
    var onReorder: (([PhotoItem]) -> Void)? = nil

    /// Whether the red remove (✕) affordance is available right now. Gated by
    /// the caller (e.g. disabled while a render/export is in progress).
    var allowsRemoval: Bool = true

    /// Callback when a thumbnail's red ✕ is tapped. The caller owns the
    /// confirmation step before actually removing the item.
    var onRequestRemoval: ((PhotoItem) -> Void)? = nil

    /// `.horizontal` for the portrait bottom strip, `.vertical` for the
    /// landscape right-rail strip (a slim column between the panel and the tool
    /// dock). Mirrors `EditorToolDock`'s axis switch.
    var axis: Axis = .horizontal

    /// Cap on the scrollable thumbnail region's length in vertical mode. The
    /// strip hugs its content (so 3 photos don't stretch a full-height pill) but
    /// won't exceed this — beyond it the thumbnails scroll. Ignored horizontally.
    var verticalMaxLength: CGFloat = 400

    /// Local edit-mode toggle for the "Edit ⇄ Done" affordance. Lives on the
    /// strip so it doesn't leak global state into the view model; resets
    /// naturally when the strip is recreated as the batch changes.
    @State private var isEditMode: Bool = false

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let stripCornerRadius: CGFloat = MarkepiRadius.xxl
    private var cellSize: CGFloat { MarkepiMetrics.thumbnailCellSize(dynamicTypeSize: dynamicTypeSize) }
    private let cellSpacing: CGFloat = 10
    private let contentLeadingPadding: CGFloat = 12
    private let removeBadgeOffset: CGFloat = -6

    var body: some View {
        Group {
            if axis == .horizontal {
                horizontalBody
            } else {
                verticalBody
            }
        }
        .markepiGlass(
            shape: RoundedRectangle(cornerRadius: stripCornerRadius, style: .continuous),
            isEnabled: !reduceTransparency
        )
        .overlay {
            RoundedRectangle(cornerRadius: stripCornerRadius, style: .continuous)
                .strokeBorder(MarkepiColors.controlStroke, lineWidth: 0.5)
        }
    }

    /// Portrait layout: thumbnails scroll horizontally, Edit toggle pinned to the
    /// trailing edge. The scroll content + toggle share ONE rounded glass
    /// container so the strip reads as a single cohesive control bar.
    private var horizontalBody: some View {
        HStack(spacing: 4) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: cellSpacing) {
                        ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                            decoratedCell(for: photo, index: index)
                        }
                    }
                    // Inset the scroll content so the leading/trailing thumbnails
                    // never disappear under the shared container's rounded corners.
                    .padding(.horizontal, contentLeadingPadding)
                    .padding(.vertical, 6)
                    .dropDestination(for: String.self) { items, _ in handleDrop(items) }
                }
                .onChange(of: currentIndex) { _, newIndex in scrollToCurrent(proxy, newIndex) }
            }

            editToggle
                .padding(.trailing, 8)
        }
        .frame(height: MarkepiMetrics.thumbnailStripHeight(dynamicTypeSize: dynamicTypeSize))
    }

    /// Landscape layout: thumbnails scroll vertically in a slim column, Edit
    /// toggle pinned to the bottom. The strip hugs its content up to
    /// `verticalMaxLength`, then scrolls.
    private var verticalBody: some View {
        // Ideal scroll height for the current photo count; capped so a short
        // batch doesn't stretch a full-height pill and a long one scrolls.
        let ideal = CGFloat(photos.count) * cellSize
            + CGFloat(max(0, photos.count - 1)) * cellSpacing
            + contentLeadingPadding * 2
        let scrollLength = min(ideal, verticalMaxLength)
        return VStack(spacing: 4) {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: cellSpacing) {
                        ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                            decoratedCell(for: photo, index: index)
                        }
                    }
                    .padding(.vertical, contentLeadingPadding)
                    .padding(.horizontal, 6)
                    .dropDestination(for: String.self) { items, _ in handleDrop(items) }
                }
                .frame(height: scrollLength)
                .onChange(of: currentIndex) { _, newIndex in scrollToCurrent(proxy, newIndex) }
            }

            editToggle
                .padding(.bottom, 8)
        }
        .padding(.top, 6)
        .frame(width: MarkepiMetrics.thumbnailStripHeight(dynamicTypeSize: dynamicTypeSize))
    }

    /// A thumbnail cell plus every shared interaction (tap-to-select, reorder
    /// drag, context menu, VoiceOver actions). Used by both axes so the two
    /// layouts differ only in stack/scroll direction.
    private func decoratedCell(for photo: PhotoItem, index: Int) -> some View {
        thumbnailCell(for: photo, index: index)
            .id(photo.id)
            // A plain tap switches the editor to that photo — but NOT in edit
            // mode, where taps are reserved for the remove badges. Adjusting a
            // single item's watermark is a deliberate, less-frequent action, so
            // it lives behind a long-press context menu instead of hijacking
            // every tap.
            .onTapGesture {
                guard !isEditMode else { return }
                currentIndex = index
            }
            .contextMenu {
                Button {
                    currentIndex = index
                    onItemTapped?(index)
                } label: {
                    Label("Adjust This Photo", systemImage: "slider.horizontal.3")
                }
                if allowsRemoval {
                    Button(role: .destructive) {
                        onRequestRemoval?(photo)
                    } label: {
                        Label("Remove from Batch", systemImage: "trash")
                    }
                }
            }
            .onDrag {
                NSItemProvider(object: String(index) as NSString)
            }
            .accessibilityLabel(accessibilityLabel(for: photo, index: index))
            .accessibilityHint(isEditMode
                ? "Double tap the remove button to delete this photo from the batch."
                : "Double tap to view this photo. Touch and hold to adjust its watermark.")
            .accessibilityAction(named: "Adjust this photo") {
                currentIndex = index
                onItemTapped?(index)
            }
            .accessibilityAction(named: "Remove from batch") {
                onRequestRemoval?(photo)
            }
    }

    /// Shared reorder drop handler (moves the dragged item to the end).
    private func handleDrop(_ items: [String]) -> Bool {
        guard let sourceStr = items.first,
              let sourceIndex = Int(sourceStr),
              sourceIndex >= 0, sourceIndex < photos.count else {
            return false
        }
        var reordered = photos
        let moved = reordered.remove(at: sourceIndex)
        reordered.append(moved)
        onReorder?(reordered)
        return true
    }

    /// Keep the current photo scrolled into view when the index changes.
    private func scrollToCurrent(_ proxy: ScrollViewProxy, _ newIndex: Int) {
        guard newIndex >= 0, newIndex < photos.count else { return }
        withAnimation { proxy.scrollTo(photos[newIndex].id, anchor: .center) }
    }

    // MARK: - Remove badge

    /// The red ✕ control. Filled red circle, white xmark, hairline white border,
    /// and a soft shadow so it lifts off busy imagery and the highlight ring.
    private func removeBadge(for photo: PhotoItem, index: Int) -> some View {
        Button {
            onRequestRemoval?(photo)
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: MarkepiSizing.removeBadgeSize, height: MarkepiSizing.removeBadgeSize)
                .background(
                    Circle()
                        .fill(Color.red)
                        .overlay(Circle().strokeBorder(.white.opacity(0.95), lineWidth: 1.5))
                        .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove photo \(index + 1) from batch")
    }

    // MARK: - Edit / Done toggle

    /// A compact liquid-glass capsule pinned to the trailing edge of the strip.
    /// Idle: translucent glass with a muted label. Active (editing): accent-tinted
    /// glass so the user can tell at a glance they're in removal mode. Tapping it
    /// swaps between revealing the per-thumbnail red ✕ badges and hiding them.
    private var editToggle: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isEditMode.toggle()
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: isEditMode ? "checkmark" : "pencil")
                    .font(.system(size: 12, weight: .semibold))
                Text(isEditMode ? "Done" : "Edit")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
            }
            .foregroundStyle(isEditMode ? Color.white : Color.primary)
            .padding(.vertical, 7)
            .padding(.horizontal, 12)
            .frame(minWidth: 64)
            .background {
                if isEditMode {
                    Capsule().fill(Color.accentColor.opacity(0.92))
                } else {
                    Capsule().fill(MarkepiColors.pillBackground)
                }
            }
            .overlay {
                Capsule().strokeBorder(MarkepiColors.pillStroke, lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
        .disabled(!allowsRemoval)
        .accessibilityLabel(isEditMode ? "Done editing batch" : "Edit Batch")
        .accessibilityHint(isEditMode
            ? "Hides the remove buttons on each thumbnail."
            : "Shows a remove button on each thumbnail.")
    }

    /// VoiceOver label noting position and whether the item carries a
    /// custom (overridden) watermark.
    private func accessibilityLabel(for photo: PhotoItem, index: Int) -> String {
        let base = "Photo \(index + 1) of \(photos.count)"
        return perItemOverrides[photo.id] != nil ? "\(base), custom watermark" : base
    }

    @ViewBuilder
    private func thumbnailCell(for photo: PhotoItem, index: Int) -> some View {
        let isCurrent = index == currentIndex

        Group {
            if let thumbnail = photo.thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: cellSize, height: cellSize)
                    .clipShape(RoundedRectangle(cornerRadius: MarkepiRadius.md, style: .continuous))
            } else {
                placeholderCell
            }
        }
        .frame(width: cellSize, height: cellSize)
        .overlay(alignment: .center) {
            if isCurrent {
                RoundedRectangle(cornerRadius: MarkepiRadius.md, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .animation(.easeInOut, value: currentIndex)
            }
        }
        .overlay(alignment: .topTrailing) {
            if perItemOverrides[photo.id] != nil {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 7, height: 7)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 1))
                    .padding(3)
                    .accessibilityLabel("Custom watermark applied")
            }
        }
        .overlay(alignment: .topLeading) {
            if isEditMode && allowsRemoval {
                removeBadge(for: photo, index: index)
                    .offset(x: removeBadgeOffset, y: removeBadgeOffset)
                    .zIndex(1)
            }
        }
    }

    private var placeholderCell: some View {
        RoundedRectangle(cornerRadius: MarkepiRadius.md, style: .continuous)
            .fill(Color(.systemGray5))
            .frame(width: cellSize, height: cellSize)
            .overlay {
                ProgressView()
            }
    }
}
