import SwiftUI
import UIKit

/// UIKit bridge for presenting `UIActivityViewController` from SwiftUI.
///
/// Copied from the main app target (`App/Views/Share/ShareSheetView.swift`)
/// so the share extension can present the share sheet without depending on
/// the main app target.
///
/// Excludes `.saveToCameraRoll` per project constraint — watermarked output
/// is shared without saving to the camera roll.
struct ShareSheetView: UIViewControllerRepresentable {
    let activityItems: [Any]
    let excludedActivityTypes: [UIActivity.ActivityType]?
    let onDismiss: () -> Void

    init(
        activityItems: [Any],
        excludedActivityTypes: [UIActivity.ActivityType]? = nil,
        onDismiss: @escaping () -> Void
    ) {
        self.activityItems = activityItems
        self.excludedActivityTypes = excludedActivityTypes
        self.onDismiss = onDismiss
    }

    func makeUIViewController(context: Context) -> UIActivityViewController {
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

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}