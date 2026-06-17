import Foundation
import UIKit

struct PhotoItem: Identifiable, Hashable, Sendable {
    let id: UUID
    let thumbnail: UIImage?
    let sourceURL: URL

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: PhotoItem, rhs: PhotoItem) -> Bool {
        lhs.id == rhs.id
    }
}
