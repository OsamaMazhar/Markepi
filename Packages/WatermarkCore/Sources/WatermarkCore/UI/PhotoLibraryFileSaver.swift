// iOS-only UI. Guarded so WatermarkCore also builds for macOS, where the
// `markepi` CLI target links the engine without the SwiftUI layer.
#if canImport(UIKit)
import Foundation
import Photos
import UIKit
import UniformTypeIdentifiers

/// Byte-exact "Save to Photos" for exported files.
///
/// The share sheet's built-in "Save Image" (`UIActivity.ActivityType
/// .saveToCameraRoll`) decodes the shared item into a `UIImage` and re-encodes
/// it on save. That round-trip strips everything ImageIO doesn't carry —
/// including the C2PA Content Credentials manifest (JUMBF), which lives outside
/// the EXIF/TIFF metadata dictionaries. The result in Photos looked fine but
/// had no Content Credentials.
///
/// `PHAssetCreationRequest.addResource(with:fileURL:options:)` instead stores
/// the file's ORIGINAL BYTES as the asset's original resource — Photos never
/// re-encodes it — so the C2PA manifest, signature, and every other byte of
/// metadata survive. This is the only correct way to save a signed export.
public enum PhotoLibraryFileSaver {

    public enum SaveError: LocalizedError {
        case accessDenied
        case nothingToSave

        public var errorDescription: String? {
            switch self {
            case .accessDenied:
                return "Markepi needs permission to add photos to your library. You can allow this in Settings."
            case .nothingToSave:
                return "There was nothing to save to your photo library."
            }
        }
    }

    /// Saves each file URL into the photo library as a new asset, preserving
    /// the original bytes (and therefore the C2PA manifest) exactly.
    ///
    /// - Parameter urls: Image and/or video FILE urls. Unsupported types are
    ///   skipped; throws `.nothingToSave` if none are savable.
    public static func save(_ urls: [URL]) async throws {
        let savable = urls.filter { resourceType(for: $0) != nil }
        guard !savable.isEmpty else { throw SaveError.nothingToSave }

        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw SaveError.accessDenied
        }

        try await PHPhotoLibrary.shared().performChanges {
            for url in savable {
                guard let type = resourceType(for: url) else { continue }
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                // Keep the temp file — the share sheet may still be presenting
                // it to other activities, and cleanup owns its lifetime.
                options.shouldMoveFile = false
                options.originalFilename = url.lastPathComponent
                request.addResource(with: type, fileURL: url, options: options)
            }
        }
    }

    /// Photo/video resource type for a file URL, or nil when the file isn't a
    /// media type Photos can store.
    static func resourceType(for url: URL) -> PHAssetResourceType? {
        guard url.isFileURL,
              let type = UTType(filenameExtension: url.pathExtension) else { return nil }
        if type.conforms(to: .image) { return .photo }
        if type.conforms(to: .movie) || type.conforms(to: .audiovisualContent) { return .video }
        return nil
    }
}

/// Share-sheet activity that saves the shared files to Photos WITHOUT
/// re-encoding them, so Content Credentials (C2PA) and all metadata survive.
///
/// Offered in place of the system "Save Image" activity (which is excluded by
/// the callers) because the system activity's UIImage round-trip strips the
/// C2PA manifest from signed exports.
/// `@unchecked Sendable`: UIActivity is main-thread-only by contract (the
/// share sheet drives every callback on the main thread), but the class itself
/// isn't annotated, so the async save's `@MainActor` continuation capturing
/// `self` needs the manual conformance.
public final class SaveToPhotosActivity: UIActivity, @unchecked Sendable {
    private var fileURLs: [URL] = []

    /// Called on the main actor after the save finishes. `.success` carries the
    /// number of saved assets; `.failure` carries the save/permission error so
    /// the host can surface it (a UIActivity has no view controller to alert from).
    public var onFinished: (@MainActor (Result<Int, Error>) -> Void)?

    public init(onFinished: (@MainActor (Result<Int, Error>) -> Void)? = nil) {
        self.onFinished = onFinished
        super.init()
    }

    public override class var activityCategory: UIActivity.Category { .action }

    public override var activityType: UIActivity.ActivityType? {
        UIActivity.ActivityType("com.osamamazhar.markepi.save-to-photos")
    }

    public override var activityTitle: String? {
        String(localized: "Save to Photos")
    }

    public override var activityImage: UIImage? {
        UIImage(systemName: "square.and.arrow.down")
    }

    public override func canPerform(withActivityItems activityItems: [Any]) -> Bool {
        activityItems.contains {
            guard let url = $0 as? URL else { return false }
            return PhotoLibraryFileSaver.resourceType(for: url) != nil
        }
    }

    public override func prepare(withActivityItems activityItems: [Any]) {
        fileURLs = activityItems.compactMap { $0 as? URL }
            .filter { PhotoLibraryFileSaver.resourceType(for: $0) != nil }
    }

    public override func perform() {
        let urls = fileURLs
        Task { @MainActor in
            do {
                try await PhotoLibraryFileSaver.save(urls)
                onFinished?(.success(urls.count))
                activityDidFinish(true)
            } catch {
                onFinished?(.failure(error))
                activityDidFinish(false)
            }
        }
    }
}
#endif
