import SwiftUI
import UIKit

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
        controller.excludedActivityTypes = excludedActivityTypes
        controller.completionWithItemsHandler = { _, _, _, _ in
            onDismiss()
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
