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

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                        thumbnailCell(for: photo, index: index)
                            .id(photo.id)
                            // A plain tap switches the editor to that photo.
                            // Adjusting a single item's watermark is a
                            // deliberate, less-frequent action, so it lives
                            // behind a long-press context menu instead of
                            // hijacking every tap.
                            .onTapGesture {
                                currentIndex = index
                            }
                            .contextMenu {
                                Button {
                                    currentIndex = index
                                    onItemTapped?(index)
                                } label: {
                                    Label("Adjust This Photo", systemImage: "slider.horizontal.3")
                                }
                            }
                            .onDrag {
                                NSItemProvider(object: String(index) as NSString)
                            }
                            .accessibilityLabel(accessibilityLabel(for: photo, index: index))
                            .accessibilityHint("Double tap to view this photo. Touch and hold to adjust its watermark.")
                            .accessibilityAction(named: "Adjust this photo") {
                                currentIndex = index
                                onItemTapped?(index)
                            }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .dropDestination(for: String.self) { items, _ in
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
            }
            .frame(height: 72)
            .background(.ultraThinMaterial)
            .onChange(of: currentIndex) { _, newIndex in
                guard newIndex >= 0, newIndex < photos.count else { return }
                withAnimation {
                    proxy.scrollTo(photos[newIndex].id, anchor: .center)
                }
            }
        }
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
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                placeholderCell
            }
        }
        .frame(width: 60, height: 60)
        .overlay(alignment: .topTrailing) {
            if perItemOverrides[photo.id] != nil {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 6, height: 6)
                    .padding(4)
                    .accessibilityLabel("Custom watermark applied")
            }
        }
        .overlay(alignment: .center) {
            if isCurrent {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.accentColor, lineWidth: 3)
                    .animation(.easeInOut, value: currentIndex)
            }
        }
    }

    private var placeholderCell: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color(.systemGray6))
            .frame(width: 60, height: 60)
            .overlay {
                ProgressView()
            }
    }
}
