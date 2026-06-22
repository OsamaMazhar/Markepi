import SwiftUI
import UIKit

/// UIKit bridge for presenting `UIActivityViewController` from SwiftUI.
///
/// Used by `ShareExtensionRootView` in WatermarkCore for the share sheet
/// presentation after watermarking completes.
///
/// Excludes `.saveToCameraRoll` per project constraint — watermarked output
/// is shared without saving to the camera roll.
public struct ShareSheetView: UIViewControllerRepresentable {
    let activityItems: [Any]
    let excludedActivityTypes: [UIActivity.ActivityType]?
    let onDismiss: () -> Void

    public init(
        activityItems: [Any],
        excludedActivityTypes: [UIActivity.ActivityType]? = nil,
        onDismiss: @escaping () -> Void
    ) {
        self.activityItems = activityItems
        self.excludedActivityTypes = excludedActivityTypes
        self.onDismiss = onDismiss
    }

    public func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
        controller.excludedActivityTypes = [.saveToCameraRoll]
        controller.modalPresentationStyle = .pageSheet
        controller.completionWithItemsHandler = { _, _, _, _ in
            onDismiss()
        }
        return controller
    }

    public func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
