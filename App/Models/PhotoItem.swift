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

enum RenderingState: Equatable {
    case idle
    case rendering
    case done
    case error(Error)

    static func == (lhs: RenderingState, rhs: RenderingState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.rendering, .rendering), (.done, .done):
            return true
        case (.error, .error):
            return true
        default:
            return false
        }
    }
}
