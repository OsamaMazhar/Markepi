import AVFoundation
import CoreImage
import Foundation
import Observation
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import WatermarkCore

/// @Observable ViewModel for the Photo Editing extension's watermarking flow.
///
/// Handles `PHContentEditingInput` media loading, `WatermarkEngine` delegation
/// for preview + full-resolution rendering, `PHAdjustmentData` serialization
/// for undo/re-edit support, and App Group config sync.
///
/// Follows the same `@Observable @MainActor` + `WatermarkConfigurable` pattern
/// as `WatermarkViewModel` (main app) and `ShareExtensionViewModel` (share
/// extension). Key differences: uses `PHContentEditingInput` instead of
/// `PhotosPickerItem` or `NSItemProvider`, has a "Done" commit flow instead
/// of a share sheet, and handles `PHAdjustmentData` for non-destructive editing.
@Observable @MainActor
final class PhotosExtensionViewModel: PhotosExtensionRendering {

    // MARK: - Configuration

    /// Watermark configuration, synced bidirectionally with the main app
    /// via App Group UserDefaults.
    ///
    /// Loads saved config on init. Saves on every mutation via `didSet`.
    var config: WatermarkConfiguration {
        didSet {
            AppGroupConfigSync.save(config)
            hasUnsavedChanges = true
        }
    }

    // MARK: - Media State

    /// File URL of the source photo from `PHContentEditingInput.fullSizeImageURL`.
    var sourceURL: URL?

    /// Whether the source media is a video (set during `startEditing`).
    var isVideo: Bool = false

    /// True while loading media from the `PHContentEditingInput`.
    var isLoadingMedia: Bool = true

    // MARK: - Preview State

    /// Watermarked preview image displayed in the preview area.
    /// Updated after each debounced preview generation.
    var previewImage: UIImage?

    /// Guards against overlapping preview generation calls.
    var isGeneratingPreview: Bool = false

    // MARK: - Rendering State

    /// Tracks the full-resolution rendering lifecycle for UI feedback.
    var renderingState: RenderingState = .idle

    // MARK: - Error State

    /// Error message displayed in the alert when `showError` is true.
    var errorMessage: String?

    /// When true, an error alert is presented to the user.
    var showError: Bool = false

    // MARK: - HDR Warning State

    /// D-10: HDR could not be preserved in the output.
    var showHDRWarning: Bool = false

    /// Detailed HDR warning text.
    var hdrWarningMessage: String?

    public var sourceHasHDR: Bool = false

    public var sourceFormatLabel: String? = nil

    // MARK: - Layer Management

    /// Index of the currently active watermark layer for editing.
    var activeLayerIndex: Int = 0

    /// When true, presents the PhotosPicker for selecting a logo image.
    var showLogoPicker: Bool = false

    // MARK: - Template Management (Phase 12)

    /// When true, presents the Save Template alert for the current config.
    var showSaveTemplateAlert: Bool = false

    /// When true, presents the TemplateListView sheet.
    var showTemplateList: Bool = false

    // MARK: - Unsaved Changes

    /// Drives `shouldShowCancelConfirmation` in the ViewController (Pitfall 5).
    var hasUnsavedChanges: Bool = false

    // MARK: - Private

    /// Shared engine instance for photo processing.
    private let engine = WatermarkEngine.shared

    /// The `PHContentEditingInput` provided by Photos at the start of editing.
    private var input: PHContentEditingInput?

    /// Completion handler stored from `finishContentEditing`, called after
    /// rendering completes with the `PHContentEditingOutput`.
    private var finishHandler: ((PHContentEditingOutput?) -> Void)?

    // MARK: - Init

    init() {
        // Load saved config from App Group, or use default text watermark
        let defaultConfig = WatermarkConfiguration(watermarks: [
            .text(
                TextWatermarkInput(text: "", fontSize: 48, color: CGColor(gray: 1, alpha: 1), opacity: 1.0),
                position: .bottomRight,
                scale: 0.15,
                opacity: 1.0,
                isVisible: true
            )
        ])
        self.config = AppGroupConfigSync.load() ?? defaultConfig
    }

    // MARK: - PHContentEditingController Lifecycle

    /// Returns whether this extension can handle the given `PHAdjustmentData`.
    ///
    /// Validates the `formatIdentifier` and `formatVersion` against our
    /// canonical constants (D-09). Returns `false` for foreign adjustment
    /// data to prevent Photos from presenting our extension for uneditable
    /// content.
    func canHandle(_ adjustmentData: PHAdjustmentData) -> Bool {
        return adjustmentData.formatIdentifier == AdjustmentConstants.formatIdentifier
            && adjustmentData.formatVersion == AdjustmentConstants.formatVersion
    }

    /// Called when Photos presents the extension for editing.
    ///
    /// Sets up the source media from `PHContentEditingInput`, displays the
    /// `placeholderImage`, and starts preview generation. If the input
    /// contains prior `adjustmentData` (re-edit scenario), decodes it to
    /// restore the previous watermark configuration (D-05).
    ///
    /// - Parameters:
    ///   - input: The `PHContentEditingInput` with source media and adjustment data
    ///   - placeholderImage: Low-resolution thumbnail for initial display
    func startEditing(with input: PHContentEditingInput, placeholderImage: UIImage) {
        self.input = input
        self.previewImage = placeholderImage

        // D-06: Source URL from PHContentEditingInput
        if let imageURL = input.fullSizeImageURL {
            self.sourceURL = imageURL
            self.isVideo = false
        } else if let avAsset = input.audiovisualAsset {
            // D-08: Video source — AVAsset may be URL-based
            if let urlAsset = avAsset as? AVURLAsset {
                self.sourceURL = urlAsset.url
            }
            self.isVideo = true
        }

        self.isLoadingMedia = false

        // Phase 11: Detect HDR and source format for HDR→JPEG warning (PHDR-01)
        detectSourceProperties()

        // D-05: Re-load config from prior adjustment data (re-edit scenario)
        if let adjustmentData = input.adjustmentData,
           canHandle(adjustmentData),
           let savedConfig = decodeAdjustmentData(adjustmentData) {
            self.config = savedConfig
        }

        // Phase 12: Auto-apply default template on fresh edit only (not re-edit)
        if input.adjustmentData == nil,
           let defaultTemplate = TemplateStore.shared.defaultTemplate {
            self.config = defaultTemplate.config
        }

        // Trigger debounced preview generation
        Task { await generatePreview() }
    }

    // MARK: - Source Detection (Phase 11 / PHDR-01)

    /// Detects HDR capability and source format from the `PHContentEditingInput`.
    ///
    /// Photo path: Uses `CGImageSourceCreateWithURL` to read the file header UTI
    /// without loading pixel data. HEIC (`public.heic`) → HDR capable.
    /// Video path: Uses `AVAsset.tracks(withMediaType:)` and checks
    /// `hasMediaCharacteristic(.containsHDRVideo)`.
    ///
    /// Sets `sourceHasHDR` and `sourceFormatLabel`, which drive the HDR→JPEG
    /// warning alert and "Match Source (FORMAT)" label in `ControlsView`.
    private func detectSourceProperties() {
        guard let sourceURL = sourceURL else { return }

        if isVideo {
            detectVideoProperties(sourceURL: sourceURL)
        } else {
            detectPhotoProperties(sourceURL: sourceURL)
        }
    }

    /// Detects HDR and format label for photo sources via CGImageSource UTI.
    ///
    /// Uses `CGImageSourceCreateWithURL` to read only the file header (~4KB),
    /// not the full pixel data. Guards against nil source and nil UTI.
    ///
    /// - Parameter sourceURL: The file URL from `PHContentEditingInput.fullSizeImageURL`
    private func detectPhotoProperties(sourceURL: URL) {
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
              let uti = CGImageSourceGetType(source) else {
            return
        }
        let utiString = uti as String

        // D-01: HEIC UTI heuristic — potential HDR carrier
        sourceHasHDR = (utiString == "public.heic")

        // D-05: Format label from UTI (4-way mapping)
        switch utiString {
        case "public.heic": sourceFormatLabel = "HEIC"
        case "public.jpeg": sourceFormatLabel = "JPEG"
        case "public.png":  sourceFormatLabel = "PNG"
        case "public.tiff": sourceFormatLabel = "TIFF"
        default:            sourceFormatLabel = nil
        }
    }

    /// Detects HDR and format label for video sources via AVAssetTrack.
    ///
    /// Uses synchronous `tracks(withMediaType:)` API (deprecated but functional)
    /// because `startEditing` is a synchronous method. Checks
    /// `AVMediaCharacteristic.containsHDRVideo` for HDR detection.
    /// Format label derived from path extension (mov/mp4/m4v).
    ///
    /// - Parameter sourceURL: The file URL from `PHContentEditingInput.audiovisualAsset`
    private func detectVideoProperties(sourceURL: URL) {
        // D-03: Video HDR detection via AVAssetTrack
        if let asset = input?.audiovisualAsset {
            let videoTracks = asset.tracks(withMediaType: .video)
            sourceHasHDR = videoTracks.contains { track in
                track.hasMediaCharacteristic(.containsHDRVideo)
            }
        }

        // D-04/D-06: Video format label from path extension
        switch sourceURL.pathExtension.lowercased() {
        case "mov": sourceFormatLabel = "MOV"
        case "mp4": sourceFormatLabel = "MP4"
        case "m4v": sourceFormatLabel = "M4V"
        default:    sourceFormatLabel = nil
        }
    }

    /// Called when the user taps Done. Stores the completion handler and
    /// begins the render-and-commit pipeline.
    ///
    /// - Parameter completionHandler: The `finishContentEditing` callback
    ///   to invoke with the `PHContentEditingOutput` (or nil on error)
    func finishEditing(completionHandler: @escaping (PHContentEditingOutput?) -> Void) {
        self.finishHandler = completionHandler
        Task { await renderAndCommit() }
    }

    /// Cancels the editing session. Calls the finish handler with nil to
    /// signal that no edit was committed, then resets state.
    func cancelEditing() {
        hasUnsavedChanges = false
        finishHandler?(nil)
        finishHandler = nil
    }

    // MARK: - Render and Commit

    /// Renders the watermarked output at full resolution and commits the edit
    /// to Photos via `PHContentEditingOutput` with `PHAdjustmentData`.
    ///
    /// Pipeline:
    ///   1. Guard: input and sourceURL must be non-nil
    ///   2. Detect media type — branch to photo or video path
    ///   3. Render via WatermarkEngine (process for photos, processVideo for videos)
    ///   4. Create `PHContentEditingOutput` from the input
    ///   5. Copy rendered data to `renderedContentURL` with format-aware extension
    ///   6. Attach `PHAdjustmentData` with JSON-encoded config (D-04)
    ///   7. For videos: check HDR preservation and surface warnings
    ///   8. Call `finishHandler` with the output (or nil on error)
    ///
    /// Source format preservation (D-07): `engine.process()` uses the
    /// default `.preserveSource` output format, which matches the source
    /// format (HEIC→HEIC, JPEG→JPEG, PNG→PNG). Non-destructive editing
    /// via `PHAdjustmentData` + undo means the original format is always
    /// recoverable via "Revert to Original" in the Photos app.
    ///
    /// D-08: Video processing reuses the existing VideoProcessor via
    /// `engine.processVideo(sourceURL:config:)`. AVAssetExportSession
    /// streams frames without loading the full video into memory, making
    /// it safe for the extension's ~120 MB sandbox limit.
    private func renderAndCommit() async {
        guard let input = input, let sourceURL = sourceURL else {
            finishHandler?(nil)
            return
        }

        renderingState = .rendering

        do {
            let result: ProcessingResult

            // D-08: Video path — process via VideoProcessor
            if isVideo {
                result = try await engine.processVideo(sourceURL: sourceURL, config: config)
            } else {
                // D-06: Photo path — process via existing pipeline
                // D-07: Uses .preserveSource output format by default
                result = try await engine.process(sourceURL: sourceURL, config: config)
            }

            // D-06: Create PHContentEditingOutput from the input
            let output = PHContentEditingOutput(contentEditingInput: input)

            // Copy rendered data to renderedContentURL with format-aware extension
            if let renderedURL = result.url {
                let renderedData = try Data(contentsOf: renderedURL)
                let targetURL = formatAwareOutputURL(from: output.renderedContentURL,
                                                     sourceURL: sourceURL,
                                                     isVideo: isVideo)
                try renderedData.write(to: targetURL, options: .atomic)

                // Cleanup engine temp file after writing to Photos output path
                try? TempFileManager.cleanup(url: renderedURL)
            }

            // D-04: Attach PHAdjustmentData (config as JSON for undo/re-edit)
            if let adjustmentPayload = encodeAdjustmentData(config) {
                output.adjustmentData = PHAdjustmentData(
                    formatIdentifier: AdjustmentConstants.formatIdentifier,
                    formatVersion: AdjustmentConstants.formatVersion,
                    data: adjustmentPayload
                )
            }

            // D-08: HDR preservation check for video output
            if let validation = result.videoValidation {
                if !validation.hdrPreserved {
                    showHDRWarning = true
                    hdrWarningMessage = validation.warnings.first(where: { $0.contains("HDR") })
                        ?? "HDR could not be preserved. Video was exported in standard dynamic range."
                } else {
                    showHDRWarning = false
                    hdrWarningMessage = nil
                }
            }

            hasUnsavedChanges = false
            renderingState = .done
            finishHandler?(output)
        } catch {
            renderingState = .error(error)
            errorMessage = error.localizedDescription
            showError = true
            finishHandler?(nil)
        }
    }

    // MARK: - Format-Aware Output URL

    /// Returns a URL with the appropriate file extension for the rendered output.
    ///
    /// PHContentEditingOutput.renderedContentURL provides a system path, but the
    /// extension may not match the source format. This method adjusts the extension:
    /// - JPEG/HEIC source → .jpg (safe for both per Research Pitfall 3)
    /// - PNG source → .png
    /// - Video source → .mov
    ///
    /// - Parameters:
    ///   - systemURL: The system-provided renderedContentURL
    ///   - sourceURL: The source media URL (for format detection)
    ///   - isVideo: Whether the source is a video
    /// - Returns: URL with format-appropriate file extension
    private func formatAwareOutputURL(from systemURL: URL, sourceURL: URL, isVideo: Bool) -> URL {
        if isVideo {
            return systemURL.deletingPathExtension().appendingPathExtension("mov")
        }

        // Determine appropriate extension from source format
        let ext = sourceURL.pathExtension.lowercased()
        switch ext {
        case "png":
            return systemURL.deletingPathExtension().appendingPathExtension("png")
        case "heic", "heif":
            // JPEG is safer for HEIC at renderedContentURL (Research Pitfall 3)
            // The non-destructive undo preserves original HEIC quality
            return systemURL.deletingPathExtension().appendingPathExtension("jpg")
        default:
            // Default to .jpg for JPEG and unknown formats
            return systemURL.deletingPathExtension().appendingPathExtension("jpg")
        }
    }

    // MARK: - Preview Generation

    /// Generates a debounced watermark preview for the loaded photo or video.
    ///
    /// Waits 350ms (photo) or 500ms (video) to debounce rapid config changes,
    /// then renders via the engine. For photos, calls `engine.process()`.
    /// For videos, calls `engine.processVideo()` and extracts the first frame
    /// via `AVAssetImageGenerator` for the preview image. Errors are silently
    /// ignored — preview is best-effort.
    func generatePreview() async {
        guard !isGeneratingPreview, sourceURL != nil else { return }
        guard let sourceURL = sourceURL else { return }
        isGeneratingPreview = true
        defer { isGeneratingPreview = false }

        let mediaType = WatermarkEngine.mediaType(for: sourceURL)
        let debounceMs = (mediaType == .video || isVideo) ? 500 : 350

        // Debounce: wait to avoid rapid re-renders during config changes
        try? await Task.sleep(for: .milliseconds(debounceMs))
        guard !Task.isCancelled else { return }

        if mediaType == .video || isVideo {
            // D-08: Video preview — process video, extract first frame
            guard let result = try? await engine.processVideo(sourceURL: sourceURL, config: config),
                  let outputURL = result.url else { return }
            defer { try? TempFileManager.cleanup(url: outputURL) }

            // Extract first frame for preview using AVAssetImageGenerator
            let asset = AVAsset(url: outputURL)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 480, height: 480)

            let time = CMTime.zero
            if let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) {
                previewImage = UIImage(cgImage: cgImage)
            }
        } else {
            // Photo preview — best-effort, errors silently ignored
            let result = try? await engine.process(sourceURL: sourceURL, config: config)
            if let url = result?.url,
               let data = try? Data(contentsOf: url),
               let uiImage = UIImage(data: data) {
                previewImage = uiImage
            }
        }
    }

    // MARK: - Preview Identifier

    /// Identifier that changes when config or source changes — drives
    /// `.task(id:)` preview regeneration in the root view.
    var previewIdentifier: String {
        var parts: [String] = ["\(sourceURL?.lastPathComponent ?? "nil")"]
        for layer in config.watermarks {
            switch layer {
            case .text(let input, let pos, let scl, _, _):
                parts.append("t:\(input.text)-pos:\(pos.rawValue)-s:\(String(format: "%.3f", scl))")
            case .image(let input, let pos, let scl, _, _):
                parts.append("im:\(input.pngData.hashValue)-pos:\(pos.rawValue)-s:\(String(format: "%.3f", scl))")
            case .signature(let input, let pos, let scl, _, _):
                parts.append("sig:\(input.strokeData.hashValue)-pos:\(pos.rawValue)-s:\(String(format: "%.3f", scl))")
            }
        }
        parts.append("wf:\(config.whiteFrame?.isEnabled == true ? "1" : "0")")
        return parts.joined(separator: "-")
    }

    /// Triggers full-resolution rendering and commit to Photos.
    ///
    /// Adapted from `WatermarkConfigurable.renderAndPrepareShare()` —
    /// in the Photos extension, this triggers the Done flow instead of
    /// a share sheet. The actual rendering happens in `renderAndCommit()`
    /// which creates `PHContentEditingOutput`.
    func renderAndPrepareShare() async {
        // In the Photos extension, "share" is replaced by "commit to Photos"
        // This is called by ControlsView's action button; we trigger the
        // finishEditing flow which the root view's Done button also calls.
        // For now, delegates to the same render-and-commit path.
        // Note: ControlsView in this context uses a "Done" button from
        // the root view's toolbar, not the share button.
        await renderAndCommit()
    }

    /// Presents the share sheet — not applicable to the Photos extension.
    ///
    /// The Photos extension commits edits directly to the Photos library
    /// via `PHContentEditingOutput`. There is no share sheet step (D-02).
    func presentShareSheet() {
        // No-op: Photos extension doesn't have a share sheet
    }

    /// Cancels an in-progress video export (no-op for Photos extension).
    func cancelVideoExport() {
        // No-op: Photos extension doesn't support video export
    }

    // MARK: - PHAdjustmentData Encode/Decode

    /// Canonical adjustment data constants for the Watermark Photos extension.
    private enum AdjustmentConstants {
        static let formatIdentifier = "com.watermark.app.adjustment"
        static let formatVersion = "1.0"
    }

    /// Encodes a `WatermarkConfiguration` for storage in `PHAdjustmentData`.
    ///
    /// Strips image watermark PNG data (replaced with 67-byte 1×1 placeholder)
    /// before JSON encoding to stay safely under the PHAdjustmentData ~2 MB
    /// effective size limit (Pitfall 1, T-04-09). The full image data is
    /// stored in App Group UserDefaults for rehydration on re-edit.
    ///
    /// - Parameter config: The watermark configuration to encode
    /// - Returns: JSON-encoded `Data` with stripped image PNG data, or `nil` on failure
    private func encodeAdjustmentData(_ config: WatermarkConfiguration) -> Data? {
        let strippedConfig = config.strippingImageData()
        return try? JSONEncoder().encode(strippedConfig)
    }

    /// Decodes a `PHAdjustmentData` back into a `WatermarkConfiguration`.
    ///
    /// Validates the `formatIdentifier` and `formatVersion` before decoding.
    /// After decoding, rehydrates image watermark PNG data from App Group
    /// storage via `rehydrateImageData()` (D-05: re-edit restores full config).
    /// Returns `nil` if the adjustment data is from a foreign extension or
    /// the JSON cannot be decoded (D-09).
    ///
    /// - Parameter adjustmentData: The `PHAdjustmentData` from the Photos library
    /// - Returns: Decoded and rehydrated configuration, or `nil` on failure
    private func decodeAdjustmentData(_ adjustmentData: PHAdjustmentData) -> WatermarkConfiguration? {
        guard adjustmentData.formatIdentifier == AdjustmentConstants.formatIdentifier,
              adjustmentData.formatVersion == AdjustmentConstants.formatVersion else { return nil }
        guard var config = try? JSONDecoder().decode(WatermarkConfiguration.self, from: adjustmentData.data) else { return nil }
        config.rehydrateImageData()
        return config
    }

    // MARK: - Logo Picker

    /// Handles PhotosPicker selection for logo images.
    ///
    /// Loads the selected item's PNG data and delegates to `addLogoLayer(pngData:)`.
    /// - Parameter items: Selected PhotosPicker items (expected single item)
    func handleLogoSelection(_ items: [PhotosPickerItem]) {
        guard let item = items.first else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self) {
                addLogoLayer(pngData: data)
            }
            showLogoPicker = false
        }
    }
}
