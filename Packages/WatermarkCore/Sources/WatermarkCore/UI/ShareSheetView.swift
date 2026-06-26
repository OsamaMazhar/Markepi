import SwiftUI
import UIKit

/// UIKit bridge for presenting `UIActivityViewController` from SwiftUI.
///
/// Used by `ShareExtensionRootView` in WatermarkCore for the share sheet
/// presentation after watermarking completes.
///
/// Honors the caller's `excludedActivityTypes` (default: none), so the system
/// "Save Image"/"Save Video" action (`.saveToCameraRoll`) is offered — this
/// requires `NSPhotoLibraryAddUsageDescription` in the host app's Info.plist.
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
        controller.excludedActivityTypes = excludedActivityTypes
        controller.modalPresentationStyle = .pageSheet
        controller.completionWithItemsHandler = { _, _, _, _ in
            onDismiss()
        }
        return controller
    }

    public func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
