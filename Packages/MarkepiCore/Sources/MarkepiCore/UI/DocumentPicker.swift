#if canImport(UIKit)
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The Files picker, presented in a sheet.
///
/// Used instead of `.fileImporter` because SwiftUI presents only one
/// `.fileImporter` per view hierarchy reliably: the editor's photo import and
/// the logo panel's import sat in the same tree and the logo one never opened.
/// `asCopy` hands back a copy inside the app's sandbox, so there is no
/// security-scoped access to forget.
public struct DocumentPicker: UIViewControllerRepresentable {
    let types: [UTType]
    let onPick: (URL) -> Void

    public init(types: [UTType], onPick: @escaping (URL) -> Void) {
        self.types = types
        self.onPick = onPick
    }

    public func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    public func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    public func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    public final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }

        public func documentPicker(_ controller: UIDocumentPickerViewController,
                                   didPickDocumentsAt urls: [URL]) {
            if let url = urls.first { onPick(url) }
        }
    }
}
#endif
