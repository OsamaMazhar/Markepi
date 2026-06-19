import SwiftUI
import WatermarkCore
import CoreImage

/// Renders a 48x48pt watermark preview for a template applied to current media.
///
/// Follows the async thumbnail loading pattern from `ThumbnailStripView`
/// and the `createThumbnail` function from `WatermarkViewModel`.
/// Caches results via `TemplateStore` so scrolling is smooth.
struct TemplatePreviewThumbnail: View {
    let template: Template
    let sourceURL: URL?
    @State private var thumbnail: UIImage?
    @State private var isLoading = false

    private let engine = WatermarkEngine.shared
    private let store = TemplateStore.shared

    var body: some View {
        Group {
            if let thumbnail = thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else if isLoading {
                ProgressView()
                    .frame(width: 48, height: 48)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 6))
            } else {
                Image(systemName: "doc.text")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
                    .frame(width: 48, height: 48)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .task {
            await generateThumbnail()
        }
    }

    /// Lazily generates or loads a cached 48x48pt preview thumbnail
    /// showing the template's watermark config applied to the current media.
    private func generateThumbnail() async {
        // A) Check cache first
        if let cached = store.loadThumbnail(for: template.id),
           let image = UIImage(data: cached) {
            thumbnail = image
            return
        }

        // B) Need source media to render
        guard let url = sourceURL else { return }

        // C) Set loading state
        isLoading = true
        defer { isLoading = false }

        // D) Process with engine
        guard let result = try? await engine.process(sourceURL: url, config: template.config) else {
            return
        }

        // E) Create downsized thumbnail via ImageIO
        guard let data = try? Data(contentsOf: result.outputURL),
              let cgThumb = createThumbnail(from: data, maxPixelSize: 48 * UIScreen.main.scale) else {
            // Clean up temp file
            try? FileManager.default.removeItem(at: result.outputURL)
            return
        }

        let uiImage = UIImage(cgImage: cgThumb)
        thumbnail = uiImage

        // F) Cache as PNG
        if let pngData = uiImage.pngData() {
            store.saveThumbnail(pngData, for: template.id)
        }

        // Clean up temp result file
        try? FileManager.default.removeItem(at: result.outputURL)
    }

    /// Creates a downsized thumbnail from image data using ImageIO.
    /// Replicates the pattern from WatermarkViewModel.createThumbnail (lines 703-714).
    private func createThumbnail(from data: Data, maxPixelSize: CGFloat) -> CGImage? {
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
    }
}
