import Foundation
import UIKit
import WatermarkCore

struct PhotoItem: Identifiable, Hashable, Sendable {
    let id: UUID
    let thumbnail: UIImage?
    let sourceURL: URL

    /// For Live Photo pairs: the URL to the video component.
    /// Nil for regular photos, videos, and unknown media types.
    var videoSourceURL: URL?

    /// The media type detected from the source URL.
    var mediaType: WatermarkEngine.MediaType = .unknown

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: PhotoItem, rhs: PhotoItem) -> Bool {
        lhs.id == rhs.id
    }
}
