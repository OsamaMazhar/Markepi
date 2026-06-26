import CoreImage
import Foundation
import ImageIO
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
final class ShareExtensionViewModel: ShareExtensionRendering {

    // MARK: - Configuration

    /// Watermark configuration, synced bidirectionally with the main app
    /// via App Group UserDefaults (D-08).
    ///
    /// Loads saved config on init. Saves on every mutation via `didSet`.
    var config: WatermarkConfiguration {
        didSet {
            AppGroupConfigSync.save(config)
            if config.sourceDeclaration != analyzedDeclaration {
                analyzeCurrentSource()
            }
            if !config.provenanceEnabled && oldValue.provenanceEnabled {
                config.includeC2PAManifest = false
                lastExportReceipt = nil
            }
        }
    }

    // MARK: - Media State

    /// File URL of the shared photo after NSItemProvider loading completes.
    /// Written to the extension's temp directory for sandbox isolation (T-03-02).
    var sourceURL: URL?

    /// Whether the shared media is a video.
    /// Gated by media type detection.
    var isVideo: Bool = false

    /// True while NSItemProvider is loading the shared media.
    /// Drives the loading spinner in the root view.
    var isLoadingMedia: Bool = true

    // MARK: - Provenance (Plan 19-03)

    var sourceProvenanceReport: SourceProvenanceReport?
    var lastExportReceipt: ExportReceipt?
    private var analyzedDeclaration: UserSourceDeclaration = .none

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private func provenanceOptions(for config: WatermarkConfiguration) -> ProvenanceExportOptions {
        ProvenanceExportOptions(
            rights: config.rightsMetadata,
            privacyProfile: config.metadataPrivacyProfile,
            includeC2PA: config.includeC2PAManifest,
            userDeclaration: config.sourceDeclaration,
            appVersion: appVersion
        )
    }

    /// Provenance options for an export, gated by the master switch. Returns nil
    /// when provenance is disabled, so the engine produces no receipt and the
    /// share opens directly with no signing or metadata changes.
    private func exportProvenance(for config: WatermarkConfiguration) -> ProvenanceExportOptions? {
        config.provenanceEnabled ? provenanceOptions(for: config) : nil
    }

    func analyzeCurrentSource() {
        guard let url = sourceURL else {
            sourceProvenanceReport = nil; return
        }
        let declaration = config.sourceDeclaration
        let mediaIsVideo = isVideo
        let client = provenanceOptions(for: config).c2paClient
        Task { [weak self] in
            guard let self else { return }
            let report: SourceProvenanceReport
            if mediaIsVideo {
                report = SourceProvenanceReport(
                    state: .unknown, evidence: [],
                    warnings: ["Video source provenance is not analyzed in this version."],
                    userDeclaration: declaration)
            } else {
                let c2paSummary = await client.readSourceSummary(from: url)
                report = SourceProvenanceAnalyzer()
                    .analyze(imageURL: url, userDeclaration: declaration, c2paSummary: c2paSummary)
                    ?? SourceProvenanceReport(state: .unknown, evidence: [], userDeclaration: declaration)
            }
            guard self.sourceURL == url,
                  self.config.sourceDeclaration == declaration else { return }
            self.sourceProvenanceReport = report
            self.analyzedDeclaration = declaration
        }
    }

    var showExportReceipt = false

    // MARK: - Video Warning State

    /// D-10: HDR could not be preserved in the output video.
    /// Surfaced as a warning banner in the root view.
    var showHDRWarning: Bool = false

    /// Audio track count mismatch detected during export (informational).
    var showAudioWarning: Bool = false

    /// Detailed HDR warning text from ExportValidationResult.
    var hdrWarningMessage: String?

    // MARK: - Preview State

    /// Watermarked preview image displayed in the preview area.
    /// Updated after each debounced preview generation.
    var previewImage: UIImage?
    var originalSourceImage: UIImage?

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

    // MARK: - Template Management (Phase 12)

    /// When true, presents the Save Template alert for the current config.
    var showSaveTemplateAlert: Bool = false

    /// When true, presents the TemplateListView sheet.
    var showTemplateList: Bool = false

    /// When true, presents the PhotosPicker for selecting a logo image.
    var showLogoPicker: Bool = false

    // MARK: - Layer Management

    /// Index of the currently active watermark layer for editing.
    var activeLayerIndex: Int = 0

    // MARK: - Extension Lifecycle

    /// Closure set by `ShareViewController` to call `completeRequest`
    /// after the share sheet dismisses (D-07 one-shot workflow).
    /// For multi-item shares, this is called only after ALL items are done.
    var completeRequest: (() -> Void)?

    /// Closure for opening URLs from the extension (e.g., main app fallback).
    /// Set by ShareViewController to call `extensionContext.open(url:)`.
    var openURL: ((URL) -> Void)?

    // MARK: - Multi-Item State (D-14)

    /// All NSItemProviders from the extension context input items.
    /// Collected by ShareViewController during setup.
    var sharedItems: [NSItemProvider] = []

    /// Index of the item currently being processed (0-based).
    var currentItemIndex: Int = 0

    /// Accumulated results for batch cleanup tracking.
    var itemResults: [ProcessingResult] = []

    /// Indices of items that failed during processing.
    var failedItemIndices: [Int] = []

    /// Total number of items to process.
    var totalItemCount: Int { get { sharedItems.count } set { /* computed from sharedItems */ } }

    /// Whether this is a multi-item share (>1 item).
    var isMultiItem: Bool { get { sharedItems.count > 1 } set { /* computed from sharedItems */ } }

    /// Human-readable progress label for multi-item UI.
    var multiItemProgress: String {
        get { "Item \(currentItemIndex + 1) of \(totalItemCount)" }
        set { /* computed from currentItemIndex + totalItemCount */ }
    }

    // MARK: - Private

    /// Shared engine instance for photo processing.
    private let engine = WatermarkEngine.shared

    /// Tracks the in-progress video export task for cancellation support.
    private var videoExportTask: Task<Void, Never>?

    // MARK: - Init

    init() {
        // Load saved config from App Group, or use default
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

    // MARK: - Media Type Detection

    /// Detected media type for the shared item.
    enum MediaType {
        case photo
        case video
        case unsupported
    }

    /// Detects the media type of an NSItemProvider by checking UTI conformance.
    ///
    /// Checks video FIRST (some video formats also match image UTIs).
    /// Returns `.unsupported` if neither photo nor video UTIs match.
    ///
    /// - Parameter provider: The NSItemProvider from the extension context
    /// - Returns: The detected media type
    func detectMediaType(from provider: NSItemProvider) -> MediaType {
        // Check video first — some video containers also conform to public.image
        if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
            return .video
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            return .photo
        }
        return .unsupported
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
        // Detect media type first (video BEFORE photo — some video containers also match image UTIs)
        let mediaType = detectMediaType(from: provider)

        switch mediaType {
        case .video:
            await loadVideoFromProvider(provider)
        case .photo:
            await loadPhotoFromProvider(provider)
        case .unsupported:
            unsupportedType = true
            isLoadingMedia = false
        }
    }

    /// Loads shared photo data from an NSItemProvider into the extension sandbox.
    ///
    /// Handles both `URL` and `Data` return types from `loadItem`. Data is
    /// immediately copied to a temp file in the extension sandbox to prevent
    /// ephemeral URL expiry (Pitfall 5 — RESEARCH.md lines 593-598).
    ///
    /// - Parameter provider: The NSItemProvider from the share extension context
    private func loadPhotoFromProvider(_ provider: NSItemProvider) async {
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

            // D-01: Detect HDR source for JPEG warning dialog
            sourceHasHDR = detectHDRSource(from: data)
            sourceFormatLabel = detectSourceFormatLabel(from: data)

            // Write to extension temp directory
            let destURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("shared_photo_\(UUID().uuidString).jpg")
            try data.write(to: destURL)

            sourceURL = destURL
            isVideo = false
            isLoadingMedia = false
            Task { await loadSourceForComparison() }
            analyzeCurrentSource()

            // Trigger debounced preview generation
            await generatePreview()

            // Phase 12: Auto-apply default template on import
            if let defaultTemplate = TemplateStore.shared.defaultTemplate {
                config = defaultTemplate.config
            }
        } catch {
            await setError("Failed to load photo: \(error.localizedDescription)")
        }
    }

    // MARK: - Video Loading (Pitfall 2 + Pitfall 5)

    /// Loads a video from an NSItemProvider using `loadFileRepresentation`
    /// for memory efficiency (Pitfall 2: ~120MB extension memory ceiling).
    ///
    /// The temp URL provided by `loadFileRepresentation` is ephemeral —
    /// immediately copies to the extension sandbox (Pitfall 5).
    ///
    /// - Parameter provider: The NSItemProvider from the extension context
    private func loadVideoFromProvider(_ provider: NSItemProvider) async {
        do {
            let url = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
                provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                        return
                    }
                    guard let url = url else {
                        continuation.resume(throwing: PipelineError.invalidSource)
                        return
                    }
                    // Pitfall 5: copy immediately — temp URL expires after this block
                    let destURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent("shared_video_\(UUID().uuidString).mp4")
                    do {
                        try FileManager.default.copyItem(at: url, to: destURL)
                        continuation.resume(returning: destURL)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }

            sourceURL = url
            isVideo = true
            isLoadingMedia = false
            Task { await loadSourceForComparison() }
            analyzeCurrentSource()

            // Generate static frame preview (D-03)
            await generateVideoPreview()

            // Phase 12: Auto-apply default template on import
            if let defaultTemplate = TemplateStore.shared.defaultTemplate {
                config = defaultTemplate.config
            }
        } catch {
            await setError("Failed to load video: \(error.localizedDescription)")
        }
    }

    // MARK: - Video Preview Generation (D-03)

    /// Generates a static frame preview for video content.
    ///
    /// Extracts the midpoint frame via `VideoFrameExtractor`, then applies
    /// watermark layers using the Core Image compositing pipeline (same as the
    /// photo preview path) for true WYSIWYG preview.
    ///
    /// No white frame is applied to preview — white frame compositing requires
    /// knowledge of final frame dimensions which may differ in the export.
    func generateVideoPreview() async {
        guard let sourceURL = sourceURL, isVideo else { return }
        isGeneratingPreview = true
        defer { isGeneratingPreview = false }

        // Debounce: wait 350ms to avoid rapid re-renders during config changes
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }

        // Extract midpoint frame
        guard let frame = try? await VideoFrameExtractor.extract(from: sourceURL) else {
            previewImage = nil
            return
        }

        let frameUIImage = UIImage(cgImage: frame)

        // If no watermark layers, use raw frame as preview
        guard !config.watermarks.isEmpty else {
            previewImage = frameUIImage
            return
        }

        // Build CIImage watermark layers on static frame
        guard let baseCIImage = CIImage(image: frameUIImage) else {
            previewImage = frameUIImage
            return
        }

        let extent = baseCIImage.extent
        var layers: [(CIImage, CGPoint)] = []

        for watermark in config.watermarks {
            let watermarkImage: CIImage
            switch watermark {
            case .text(let textConfig, _, _, _, _):
                watermarkImage = TextWatermarkRenderer.render(config: textConfig)
            case .image(let imageConfig, _, _, _, _):
                guard let rendered = try? ImageWatermarkRenderer.render(config: imageConfig) else { continue }
                watermarkImage = rendered
            case .signature(let signatureInput, _, _, _, _):
                guard let rendered = try? SignatureRenderer.render(input: signatureInput) else { continue }
                watermarkImage = rendered
            }

            let scaled = watermarkImage.transformed(
                by: CGAffineTransform(scaleX: watermark.scale, y: watermark.scale)
            )
            let position = PositionCalculator.position(
                for: watermark.position,
                watermarkExtent: scaled.extent,
                baseExtent: extent,
                padding: config.padding
            )
            layers.append((scaled, position))
        }

        let composited = WatermarkRenderer.composite(layers: layers, onto: baseCIImage)

        guard let cgImage = CIContextProvider.shared.createCGImage(
            composited,
            from: composited.extent
        ) else {
            previewImage = frameUIImage
            return
        }

        previewImage = UIImage(cgImage: cgImage)
    }

    // MARK: - Source Image Caching for Comparison (D-06, D-08)

    /// Caches the un-watermarked original source image for before/after comparison
    /// toggling. Called once on media import. The cached image persists across all
    /// watermark config changes and is only cleared on media unload.
    func loadSourceForComparison() async {
        guard let sourceURL = sourceURL else { return }
        let type = WatermarkEngine.mediaType(for: sourceURL)
        switch type {
        case .video:
            if let frame = try? await VideoFrameExtractor.extract(from: sourceURL) {
                originalSourceImage = UIImage(cgImage: frame)
            }
        case .photo:
            if let data = try? Data(contentsOf: sourceURL),
               let image = UIImage(data: data) {
                originalSourceImage = image
            }
        case .livePhoto:
            break
        case .unknown:
            break
        }
    }

    // MARK: - Video Rendering

    /// Renders the watermarked video at full resolution with progress tracking
    /// and cancel support. Share extension does NOT schedule notifications
    /// (extensions terminate after completeRequest()).
    func renderAndShareVideo() async {
        guard let sourceURL = sourceURL, isVideo else { return }
        renderingState = .renderingVideo(progress: 0.0, estimatedTimeRemaining: nil)

        let exportConfig = config
        let provenance = exportProvenance(for: exportConfig)
        let task = Task {
            do {
                let result = try await engine.processVideo(
                    sourceURL: sourceURL,
                    config: exportConfig,
                    onProgress: { [weak self] progress, eta in
                        Task { @MainActor in
                            self?.renderingState = .renderingVideo(
                                progress: progress,
                                estimatedTimeRemaining: eta
                            )
                        }
                    },
                    provenance: provenance
                )
                await MainActor.run {
                    fullResResult = result
                    lastExportReceipt = result.provenanceReceipt
                    renderingState = .done
                    // Check HDR/audio warnings
                    if let validation = result.videoValidation {
                        if !validation.hdrPreserved {
                            showHDRWarning = true
                            hdrWarningMessage = validation.warnings.first(where: { $0.contains("HDR") })
                        }
                        if !validation.audioTrackCountMatch {
                            showAudioWarning = true
                        }
                    }
                    if lastExportReceipt != nil {
                        showExportReceipt = true
                    }
                }
            } catch is CancellationError {
                await MainActor.run {
                    renderingState = .idle
                    if let url = fullResResult?.url {
                        try? TempFileManager.cleanup(url: url)
                        fullResResult = nil
                    }
                }
            } catch {
                await MainActor.run {
                    renderingState = .error(error)
                    errorMessage = error.localizedDescription
                    showError = true
                    if isMultiItem {
                        failedItemIndices.append(currentItemIndex)
                    }
                }
            }
        }
        videoExportTask = task
    }

    /// Generates a debounced watermark preview for the loaded media.
    ///
    /// Branches by media type: video uses `generateVideoPreview()` for static
    /// frame extraction + CIImage watermark compositing. Photo uses
    /// `engine.process()` for full photo pipeline preview.
    func generatePreview() async {
        guard !isGeneratingPreview, sourceURL != nil else { return }

        if isVideo {
            await generateVideoPreview()
            return
        }

        guard let sourceURL = sourceURL else { return }
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
    /// Branches by media type: video uses `renderAndShareVideo()` which delegates
    /// to `engine.processVideo()`. Photo uses `engine.process()`.
    func renderAndPrepareShare() async {
        if isVideo {
            await renderAndShareVideo()
            return
        }

        guard let sourceURL = sourceURL else { return }
        renderingState = .rendering

        do {
            let prov = exportProvenance(for: config)
            let result = try await engine.process(sourceURL: sourceURL, config: config, provenance: prov)
            fullResResult = result
            renderingState = .done
            if let url = result.url,
               let data = try? Data(contentsOf: url),
               let uiImage = UIImage(data: data) {
                previewImage = uiImage
            }
            lastExportReceipt = result.provenanceReceipt
            if lastExportReceipt != nil {
                showExportReceipt = true
            }
        } catch {
            renderingState = .error(error)
            errorMessage = error.localizedDescription
            showError = true
            // Track failure for multi-item sequential processing
            if isMultiItem {
                failedItemIndices.append(currentItemIndex)
            }
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

    /// Cancels an in-progress video export.
    func cancelVideoExport() {
        videoExportTask?.cancel()
        videoExportTask = nil
    }

    /// Handles share sheet dismissal — cleans up temp files and closes the
    /// extension via `completeRequest()` (D-07 one-shot workflow).
    func handleShareDismiss() {
        if let url = fullResResult?.url {
            try? TempFileManager.cleanup(url: url)
        }
        // Track result for batch cleanup
        if let result = fullResResult {
            itemResults.append(result)
        }
        fullResResult = nil
        lastExportReceipt = nil
        showExportReceipt = false
        renderingState = .idle

        if isMultiItem {
            // D-14: sequential processing — load next item
            Task { await processNextItem() }
        } else {
            completeRequest?()
        }
    }

    // MARK: - Multi-Item Sequential Processing (D-14)

    /// Loads the next item after the current item's share sheet dismisses.
    ///
    /// Resets state for the next item, loads it via `loadSharedMedia(from:)`,
    /// and presents the watermarking UI for the user to configure and share.
    /// Calls `completeRequest()` after ALL items are processed.
    ///
    /// Error handling (per RESEARCH.md Open Question #3): failed items are
    /// tracked but don't block remaining items. A summary is shown after
    /// all items are processed.
    func processNextItem() async {
        // Track current result before moving on
        currentItemIndex += 1

        guard currentItemIndex < sharedItems.count else {
            // All items processed — show summary for failures, then close
            if !failedItemIndices.isEmpty {
                let successCount = sharedItems.count - failedItemIndices.count
                errorMessage = "Processed \(successCount) of \(sharedItems.count) items. \(failedItemIndices.count) failed."
                showError = true
                // After user dismisses the error alert, complete the extension
                // The root view alert's "OK" button calls completeRequest
            } else {
                completeRequest?()
            }
            return
        }

        // Reset state for next item
        videoExportTask?.cancel()
        videoExportTask = nil
        sourceURL = nil
        previewImage = nil
        originalSourceImage = nil
        fullResResult = nil
        lastExportReceipt = nil
        showExportReceipt = false
        renderingState = .idle
        isVideo = false
        isLoadingMedia = true
        showHDRWarning = false
        showAudioWarning = false
        hdrWarningMessage = nil

        let provider = sharedItems[currentItemIndex]
        await loadSharedMedia(from: provider)
    }

    /// Called when the dismiss-alert is shown for multi-item failure summary.
    /// Dismisses the extension after the user acknowledges.
    func dismissAfterFailureSummary() {
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

    public var sourceHasHDR: Bool = false
    public var sourceFormatLabel: String? = nil

    // MARK: - URL Scheme Fallback (D-16)

    /// Opens the containing main app via URL scheme when an unsupported media
    /// type is received (D-16).
    ///
    /// Uses the `openURL` closure set by ShareViewController which calls
    /// `extensionContext.open(url:completionHandler:)`. The main app must
    /// register the "watermark" URL scheme in its Info.plist.
    func openInMainApp() {
        guard let url = URL(string: "watermark://open") else { return }
        openURL?(url)
        completeRequest?()
    }

    /// Whether the shared item has an unsupported media type.
    var unsupportedType: Bool = false

    // MARK: - Preview Identifier (for task-driven preview updates)

    /// Identifier that changes when config or source changes — drives
    /// `.task(id:)` preview regeneration in the root view.
    var previewIdentifier: String {
        get {
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
        set { /* no-op: computed from sourceURL + config */ }
    }

    // MARK: - Private Helpers

    /// Detects whether the source data is HEIC (potential HDR carrier).
    /// Heuristic: checks UTI via CGImageSource. Full HDR gain map detection is deferred.
    private func detectHDRSource(from data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let uti = CGImageSourceGetType(source) else {
            return false
        }
        return (uti as String) == "public.heic"
    }

    /// Detects the source format label (e.g., "HEIC", "JPEG") from data for display.
    private func detectSourceFormatLabel(from data: Data) -> String? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let uti = CGImageSourceGetType(source) else {
            return nil
        }
        switch uti as String {
        case "public.heic": return "HEIC"
        case "public.jpeg": return "JPEG"
        case "public.png": return "PNG"
        case "public.tiff": return "TIFF"
        default: return nil
        }
    }

    @MainActor
    private func setError(_ message: String) {
        errorMessage = message
        showError = true
        isLoadingMedia = false
    }
}
