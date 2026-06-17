import Foundation
import Observation
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import WatermarkCore

/// @Observable ViewModel for the share extension's watermarking flow.
///
/// Handles NSItemProvider media loading, WatermarkEngine delegation for
/// preview + full-resolution rendering, App Group config sync, and share
/// sheet orchestration. Follows the same pattern as the main app's
/// `WatermarkViewModel` but uses NSItemProvider instead of PhotosPickerItem
/// as its input source.
@Observable @MainActor
final class ShareExtensionViewModel {

    // MARK: - Configuration

    /// Watermark configuration, synced bidirectionally with the main app
    /// via App Group UserDefaults (D-08).
    ///
    /// Loads saved config on init. Saves on every mutation via `didSet`.
    var config: WatermarkConfiguration {
        didSet { AppGroupConfigSync.save(config) }
    }

    // MARK: - Media State

    /// File URL of the shared photo after NSItemProvider loading completes.
    /// Written to the extension's temp directory for sandbox isolation (T-03-02).
    var sourceURL: URL?

    /// Whether the shared media is a video (always false for Plan 01 photos).
    /// Gated by media type detection; will be true in Plan 03.
    var isVideo: Bool = false

    /// True while NSItemProvider is loading the shared media.
    /// Drives the loading spinner in the root view.
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

    /// Result of the full-resolution render (contains output file URL).
    var fullResResult: ProcessingResult?

    // MARK: - Share Sheet State

    /// When true, presents the UIActivityViewController share sheet.
    var showShareSheet: Bool = false

    // MARK: - Error State

    /// Error message displayed in the alert when `showError` is true.
    var errorMessage: String?

    /// When true, an error alert is presented to the user.
    var showError: Bool = false

    /// When true, presents the PhotosPicker for selecting a logo image.
    var showLogoPicker: Bool = false

    // MARK: - Layer Management

    /// Index of the currently active watermark layer for editing.
    var activeLayerIndex: Int = 0

    // MARK: - Extension Lifecycle

    /// Closure set by `ShareViewController` to call `completeRequest`
    /// after the share sheet dismisses (D-07 one-shot workflow).
    var completeRequest: (() -> Void)?

    // MARK: - Private

    /// Shared engine instance for photo processing.
    private let engine = WatermarkEngine.shared

    // MARK: - Init

    init() {
        // Load saved config from App Group, or use default
        let defaultConfig = WatermarkConfiguration(watermarks: [
            .text(
                TextWatermarkInput(text: "", fontSize: 48, color: CGColor(gray: 1, alpha: 1), opacity: 1.0),
                position: .bottomRight,
                scale: 0.15
            )
        ])
        self.config = AppGroupConfigSync.load() ?? defaultConfig
    }

    // MARK: - Media Loading (D-13)

    /// Loads shared photo data from an NSItemProvider into the extension sandbox.
    ///
    /// Handles both `URL` and `Data` return types from `loadItem`. Data is
    /// immediately copied to a temp file in the extension sandbox to prevent
    /// ephemeral URL expiry (Pitfall 5 — RESEARCH.md lines 593-598).
    ///
    /// - Parameter provider: The NSItemProvider from the share extension context
    func loadSharedMedia(from provider: NSItemProvider) async {
        // T-03-01: Verify type conformance before loading
        guard provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) else {
            unsupportedType = true
            isLoadingMedia = false
            return
        }

        do {
            let item = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<NSSecureCoding, Error>) in
                provider.loadItem(forTypeIdentifier: UTType.image.identifier) { (item, error) in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else if let item = item {
                        continuation.resume(returning: item)
                    } else {
                        continuation.resume(throwing: PipelineError.invalidSource)
                    }
                }
            }

            let data: Data
            if let url = item as? URL {
                // T-03-02: Copy to extension sandbox immediately — the provided URL is ephemeral
                data = try Data(contentsOf: url)
            } else if let directData = item as? Data {
                data = directData
            } else {
                await setError("Could not read the shared photo.")
                return
            }

            // T-03-01: Validate file size (extension memory ceiling ~120MB)
            guard data.count <= 500_000_000 else {
                await setError("This photo is too large to process.")
                return
            }

            // Write to extension temp directory
            let destURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("shared_photo_\(UUID().uuidString).jpg")
            try data.write(to: destURL)

            sourceURL = destURL
            isVideo = false
            isLoadingMedia = false

            // Trigger debounced preview generation
            await generatePreview()
        } catch {
            await setError("Failed to load photo: \(error.localizedDescription)")
        }
    }

    // MARK: - Preview Generation (D-03)

    /// Generates a debounced watermark preview for the loaded media.
    ///
    /// Uses the same pattern as `WatermarkViewModel.generatePreview()`:
    /// 350ms debounce, Task.isCancelled guard, engine.process call,
    /// result loaded into UIImage for display.
    func generatePreview() async {
        guard !isGeneratingPreview, let sourceURL = sourceURL else { return }
        isGeneratingPreview = true
        defer { isGeneratingPreview = false }

        // Debounce: wait 350ms to avoid rapid re-renders during config changes
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }

        // Best-effort preview — errors are silently ignored
        let result = try? await engine.process(sourceURL: sourceURL, config: config)
        if let url = result?.url,
           let data = try? Data(contentsOf: url),
           let uiImage = UIImage(data: data) {
            previewImage = uiImage
        }
    }

    // MARK: - Full-Resolution Render

    /// Renders the watermarked output at full resolution, preparing for sharing.
    ///
    /// Mirrors `WatermarkViewModel.renderAndPrepareShare()`:
    /// sets `.rendering` state, calls engine.process, sets `.done` on success
    /// or `.error` on failure.
    func renderAndPrepareShare() async {
        guard let sourceURL = sourceURL else { return }
        renderingState = .rendering

        do {
            let result = try await engine.process(sourceURL: sourceURL, config: config)
            fullResResult = result
            renderingState = .done
            if let url = result.url,
               let data = try? Data(contentsOf: url),
               let uiImage = UIImage(data: data) {
                previewImage = uiImage
            }
        } catch {
            renderingState = .error(error)
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    // MARK: - Share Sheet

    /// Presents the share sheet for the rendered output.
    ///
    /// Guarded: only presents when `renderingState == .done`.
    func presentShareSheet() {
        guard renderingState == .done else { return }
        showShareSheet = true
    }

    /// Handles share sheet dismissal — cleans up temp files and closes the
    /// extension via `completeRequest()` (D-07 one-shot workflow).
    func handleShareDismiss() {
        if let url = fullResResult?.url {
            try? TempFileManager.cleanup(url: url)
        }
        fullResResult = nil
        renderingState = .idle
        completeRequest?()
    }

    // MARK: - Layer Management (D-05)

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

    /// Adds a PNG logo/image watermark layer to the configuration.
    ///
    /// Validates the PNG data via `CIImage(data:)` before appending.
    /// - Parameter pngData: Raw PNG image data
    func addLogoLayer(pngData: Data) {
        guard let _ = CIImage(data: pngData) else {
            errorMessage = "The selected image is not a valid PNG file."
            showError = true
            return
        }
        guard let input = try? ImageWatermarkInput(pngData: pngData) else {
            errorMessage = "The selected image is not a valid PNG file."
            showError = true
            return
        }
        config.watermarks.append(.image(input, position: .bottomRight, scale: 0.15))
        activeLayerIndex = config.watermarks.count - 1
    }

    /// Removes a watermark layer at the specified index.
    /// - Parameter index: The layer index to remove
    func removeLayer(at index: Int) {
        guard index >= 0, index < config.watermarks.count else { return }
        config.watermarks.remove(at: index)
        if activeLayerIndex >= config.watermarks.count {
            activeLayerIndex = max(0, config.watermarks.count - 1)
        }
    }

    /// Updates the position of a watermark layer.
    /// - Parameters:
    ///   - index: The layer index to update
    ///   - position: The new position preset
    func updateLayerPosition(at index: Int, position: WatermarkPosition) {
        guard index >= 0, index < config.watermarks.count else { return }
        let scale = config.watermarks[index].scale
        switch config.watermarks[index] {
        case .text(let input, _, _):
            config.watermarks[index] = .text(input, position: position, scale: scale)
        case .image(let input, _, _):
            config.watermarks[index] = .image(input, position: position, scale: scale)
        }
    }

    /// Updates the scale of a watermark layer (clamped to 0.01–0.90).
    /// - Parameters:
    ///   - index: The layer index to update
    ///   - scale: The new scale factor (will be clamped)
    func updateLayerScale(at index: Int, scale scaleInput: CGFloat) {
        guard index >= 0, index < config.watermarks.count else { return }
        let clamped = min(max(scaleInput, 0.01), 0.90)
        let position = config.watermarks[index].position
        switch config.watermarks[index] {
        case .text(let input, _, _):
            config.watermarks[index] = .text(input, position: position, scale: clamped)
        case .image(let input, _, _):
            config.watermarks[index] = .image(input, position: position, scale: clamped)
        }
    }

    /// Toggles the white frame overlay on/off.
    func toggleWhiteFrame() {
        if config.whiteFrame?.isEnabled == true {
            config.whiteFrame = nil
        } else {
            config.whiteFrame = WhiteFrameConfig(isEnabled: true)
        }
    }

    /// Whether the white frame overlay is currently enabled.
    var whiteFrameEnabled: Bool {
        config.whiteFrame?.isEnabled ?? false
    }

    // MARK: - URL Scheme Fallback (D-16)

    /// Opens the containing main app via URL scheme when an unsupported media
    /// type is received.
    func openInMainApp() {
        // Note: extensionContext?.open(url:) requires the main app to register
        // the "watermark" URL scheme in its Info.plist.
        guard let url = URL(string: "watermark://open") else { return }
        extensionContext?.open(url, completionHandler: nil)
    }

    /// Whether the shared item has an unsupported media type.
    var unsupportedType: Bool = false

    // MARK: - Preview Identifier (for task-driven preview updates)

    /// Identifier that changes when config or source changes — drives
    /// `.task(id:)` preview regeneration in the root view.
    var previewIdentifier: String {
        var parts: [String] = ["\(sourceURL?.lastPathComponent ?? "nil")"]
        for layer in config.watermarks {
            switch layer {
            case .text(let input, let pos, let scl):
                parts.append("t:\(input.text)-pos:\(pos.rawValue)-s:\(String(format: "%.3f", scl))")
            case .image(let input, let pos, let scl):
                parts.append("im:\(input.pngData.hashValue)-pos:\(pos.rawValue)-s:\(String(format: "%.3f", scl))")
            }
        }
        parts.append("wf:\(config.whiteFrame?.isEnabled == true ? "1" : "0")")
        return parts.joined(separator: "-")
    }

    // MARK: - Private Helpers

    /// Access to the extension context for URL scheme fallback.
    /// Set by ShareViewController during setup.
    var extensionContext: NSExtensionContext?

    @MainActor
    private func setError(_ message: String) {
        errorMessage = message
        showError = true
        isLoadingMedia = false
    }
}