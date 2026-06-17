import SwiftUI

struct ThumbnailStripView: View {
    let photos: [PhotoItem]
    @Binding var currentIndex: Int

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                        thumbnailCell(for: photo, index: index)
                            .id(photo.id)
                            .onTapGesture {
                                currentIndex = index
                            }
                            .accessibilityLabel("Photo \(index + 1) of \(photos.count)")
                            .accessibilityHint("Double tap to select")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
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
