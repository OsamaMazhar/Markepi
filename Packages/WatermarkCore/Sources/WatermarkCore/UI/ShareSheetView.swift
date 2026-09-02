// iOS-only UI. Guarded so WatermarkCore also builds for macOS, where the
// `markepi` CLI target links the engine without the SwiftUI layer.
#if canImport(UIKit)
import SwiftUI
import UIKit

/// UIKit bridge for presenting `UIActivityViewController` from SwiftUI.
///
/// Used by `ShareExtensionRootView` in WatermarkCore for the share sheet
/// presentation after watermarking completes.
///
/// Honors the caller's `excludedActivityTypes` (default: none). Callers sharing
/// SIGNED exports should exclude `.saveToCameraRoll` and pass a
/// `SaveToPhotosActivity` in `applicationActivities` instead — the system
/// "Save Image" re-encodes through UIImage and strips the C2PA manifest, while
/// the custom activity saves the original bytes. Both save paths require
/// `NSPhotoLibraryAddUsageDescription` in the host app's Info.plist.
public struct ShareSheetView: UIViewControllerRepresentable {
    let activityItems: [Any]
    let applicationActivities: [UIActivity]?
    let excludedActivityTypes: [UIActivity.ActivityType]?
    let onComplete: ((Bool) -> Void)?
    let onDismiss: () -> Void

    /// - Parameters:
    ///   - applicationActivities: Custom activities appended to the sheet
    ///     (e.g. the metadata-preserving `SaveToPhotosActivity`). Optional.
    ///   - onComplete: Called with the activity's `completed` flag when the
    ///     sheet finishes — `true` if the user actually saved/shared, `false`
    ///     if they cancelled. Runs before `onDismiss`. Optional.
    ///   - onDismiss: Always called when the sheet finishes (cleanup hook).
    public init(
        activityItems: [Any],
        applicationActivities: [UIActivity]? = nil,
        excludedActivityTypes: [UIActivity.ActivityType]? = nil,
        onComplete: ((Bool) -> Void)? = nil,
        onDismiss: @escaping () -> Void
    ) {
        self.activityItems = activityItems
        self.applicationActivities = applicationActivities
        self.excludedActivityTypes = excludedActivityTypes
        self.onComplete = onComplete
        self.onDismiss = onDismiss
    }

    public func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: applicationActivities
        )
        controller.excludedActivityTypes = excludedActivityTypes
        controller.modalPresentationStyle = .pageSheet
        controller.completionWithItemsHandler = { _, completed, _, _ in
            onComplete?(completed)
            onDismiss()
        }
        return controller
    }

    public func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif
