import CoreImage
import Foundation
import ImageIO
import Observation
import os.log
import Photos
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import UserNotifications
import WatermarkCore

@Observable @MainActor
final class WatermarkViewModel: WatermarkConfigurable {
    var selectedItems: [PhotosPickerItem] = []
    var photos: [PhotoItem] = []
    var currentIndex: Int = 0
    var config = WatermarkConfiguration(watermarks: [
        .text(
            TextWatermarkInput(text: "", fontSize: 48, color: CGColor(gray: 1, alpha: 1), opacity: 1.0),
            position: .bottomRight,
            scale: 0.15,
            opacity: 1.0,
            isVisible: true
        )
    ]) {
        didSet { AppGroupConfigSync.save(config) }
    }

    var previewImage: UIImage?
    var originalSourceImage: UIImage?
    var isGeneratingPreview: Bool = false

    var renderingState: RenderingState = .idle
    var fullResResult: ProcessingResult?
    var showPicker: Bool = false
    var showShareSheet: Bool = false
    var showCancelAlert: Bool = false
    var errorMessage: String?
    var showError: Bool = false

    // MARK: - Template Management (Phase 12)

    /// When true, presents the Save Template alert for the current config.
    var showSaveTemplateAlert: Bool = false

    /// When true, presents the TemplateListView sheet.
    var showTemplateList: Bool = false

    var activeLayerIndex: Int = 0

    // MARK: - Batch Processing (Phase 13)

    /// Shared actor instance for batch watermark processing.
    var batchProcessor: BatchProcessor = BatchProcessor()

    /// Populated after batch completes; nil on cancel/cleanup.
    var batchResults: BatchProcessingResult? = nil

    /// Per-item watermark configuration overrides keyed by PhotoItem.id.
    /// Nil entries use the shared `config`. Only populated items override.
    var perItemOverrides: [UUID: WatermarkConfiguration] = [:]

    /// Whether any per-item overrides exist.
    var hasBatchOverrides: Bool { !perItemOverrides.isEmpty }

    /// Reference to the in-flight batch processing Task for cancellation.
    private var batchProcessingTask: Task<Void, Never>?

    private let engine = WatermarkEngine.shared

    /// Tracks the in-progress video export task for cancellation support.
    private var videoExportTask: Task<Void, Never>?

    // MARK: - Init

    init() {
        // Load saved config from App Group if available (D-08 bidirectional sync)
        if let saved = AppGroupConfigSync.load() {
            config = saved
        }
        checkPendingIntent()
    }

    var currentPhoto: PhotoItem? {
        guard !photos.isEmpty, currentIndex >= 0, currentIndex < photos.count else { return nil }
        return photos[currentIndex]
    }

    var hasMultiplePhotos: Bool { photos.count > 1 }

    var previewIdentifier: String {
        var parts: [String] = ["\(currentIndex)"]
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

    /// Detects Live Photo pairs from a collection of PhotosPickerItems by
    /// grouping items that share a base identifier (D-03: detect Live Photos
    /// as paired assets).
    ///
    /// Per RESEARCH.md Pattern 1: PhotosPickerItem.itemIdentifier has format
    /// `"BASEID/public.jpeg"` for the still image and `"BASEID/public.movie"`
    /// for the video component. This method strips the `/public.*` suffix to
    /// extract the shared base ID, then returns still+video pairs.
    ///
    /// Pitfall 1 guard: if string parsing fails for any item, the item is
    /// excluded from pairing and treated as individual photo/video.
    ///
    /// - Parameter items: The PhotosPickerItems to group
    /// - Returns: Array of paired still+video tuples
    private func detectLivePhotoPairs(
        _ items: [PhotosPickerItem]
    ) -> [(still: PhotosPickerItem, video: PhotosPickerItem)] {
        // Group items by base identifier (strip /public.* suffix)
        var stillMap: [String: PhotosPickerItem] = [:]
        var videoMap: [String: PhotosPickerItem] = [:]

        for item in items {
            guard let identifier = item.itemIdentifier else { continue }
            // Pitfall 1: guard against malformed identifiers
            guard let slashIndex = identifier.lastIndex(of: "/") else { continue }
            let baseID = String(identifier[..<slashIndex])
            let suffix = String(identifier[identifier.index(after: slashIndex)...])

            if suffix == "public.jpeg" || suffix == "public.heic" {
                stillMap[baseID] = item
            } else if suffix == "public.movie" {
                videoMap[baseID] = item
            }
            // Unknown suffixes are intentionally ignored — treated as individual items
        }

        // Pair items where both still and video exist for the same base ID
        var pairs: [(still: PhotosPickerItem, video: PhotosPickerItem)] = []
        for (baseID, stillItem) in stillMap {
            if let videoItem = videoMap[baseID] {
                pairs.append((still: stillItem, video: videoItem))
                // Remove paired items from maps so they're not double-counted
                videoMap.removeValue(forKey: baseID)
            }
        }
        return pairs
    }

    func handleSelection(_ items: [PhotosPickerItem]) {
        Task {
            var loaded: [PhotoItem] = []

            // D-03: Detect Live Photo pairs before processing
            let livePhotoPairs = detectLivePhotoPairs(items)

            // Track paired item identifiers to skip in individual loop
            var pairedItemIDs: Set<String?> = []
            for pair in livePhotoPairs {
                pairedItemIDs.insert(pair.still.itemIdentifier)
                pairedItemIDs.insert(pair.video.itemIdentifier)
            }

            // Process Live Photo pairs first
            for pair in livePhotoPairs {
                if let stillData = try? await pair.still.loadTransferable(type: Data.self),
                   let videoData = try? await pair.video.loadTransferable(type: Data.self) {
                    let thumb = createThumbnail(from: stillData, maxPixelSize: 200)
                    let stillURL = await copyToTemp(data: stillData)
                    let videoURL = await copyToTemp(data: videoData)
                    loaded.append(PhotoItem(
                        id: UUID(),
                        thumbnail: thumb,
                        sourceURL: stillURL,
                        videoSourceURL: videoURL,
                        mediaType: .livePhoto
                    ))
                    // D-01: Detect HDR source for warning dialog
                    if !sourceHasHDR {
                        sourceHasHDR = detectHDRSource(from: stillData)
                    }
                    if sourceFormatLabel == nil {
                        sourceFormatLabel = detectSourceFormatLabel(from: stillData)
                    }
                }
            }

            // Process unpaired items individually
            for item in items {
                // Skip items that were processed as part of a Live Photo pair
                if pairedItemIDs.contains(item.itemIdentifier) { continue }

                if let data = try? await item.loadTransferable(type: Data.self) {
                    let thumb = createThumbnail(from: data, maxPixelSize: 200)
                    let sourceURL = await copyToTemp(data: data)
                    let mediaType = WatermarkEngine.mediaType(for: sourceURL)
                    loaded.append(PhotoItem(
                        id: UUID(),
                        thumbnail: thumb,
                        sourceURL: sourceURL,
                        mediaType: mediaType
                    ))
                    // D-01: Detect HDR source for warning dialog
                    if !sourceHasHDR {
                        sourceHasHDR = detectHDRSource(from: data)
                    }
                    if sourceFormatLabel == nil {
                        sourceFormatLabel = detectSourceFormatLabel(from: data)
                    }
                }
            }
            photos = loaded
            currentIndex = 0
            Task { await loadSourceForComparison() }
            showPicker = false
            // Phase 12: Auto-apply default template on import
            if let defaultTemplate = TemplateStore.shared.defaultTemplate {
                config = defaultTemplate.config
            }
        }
    }

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

    func goToNext() {
        guard currentIndex < photos.count - 1 else { return }
        currentIndex += 1
    }

    func goToPrev() {
        guard currentIndex > 0 else { return }
        currentIndex -= 1
    }

    func generatePreview() async {
        // Live Photo: generate preview from still image source URL
        // (video frame extraction is unnecessary for thumbnail strip)
        guard let sourceURL = currentPhoto?.sourceURL else { return }
        isGeneratingPreview = true
        defer { isGeneratingPreview = false }

        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }

        let result = try? await engine.process(sourceURL: sourceURL, config: config)
        if let url = result?.url,
           let data = try? Data(contentsOf: url),
           let uiImage = UIImage(data: data) {
            previewImage = uiImage
        }
    }

    /// Caches the un-watermarked original source image for before/after comparison
    /// toggling (D-06, D-08). Called once on media import. The cached image persists
    /// across all watermark config changes and is only cleared on media unload.
    func loadSourceForComparison() async {
        guard let sourceURL = currentPhoto?.sourceURL else { return }
        // Live Photo: use still image for comparison source
        // (video frame extraction is unnecessary for preview comparison)
        let type = currentPhoto?.mediaType ?? WatermarkEngine.mediaType(for: sourceURL)
        switch type {
        case .video:
            if let frame = try? await VideoFrameExtractor.extract(from: sourceURL) {
                originalSourceImage = UIImage(cgImage: frame)
            }
        case .photo, .livePhoto:
            if let data = try? Data(contentsOf: sourceURL),
               let image = UIImage(data: data) {
                originalSourceImage = image
            }
        case .unknown:
            break
        }
    }

    func renderAndPrepareShare() async {
        // Batch mode: when multiple photos are selected, trigger batch processing
        // and return — the single-item rendering path is skipped entirely.
        if hasMultiplePhotos {
            await processBatch()
            return
        }

        guard let photo = currentPhoto else { return }

        // D-13: Branch by media type
        switch photo.mediaType {
        case .video:
            await renderAndShareVideo()
            return

        case .livePhoto:
            await renderAndShareLivePhoto()
            return

        case .photo, .unknown:
            break
        }

        // Photo rendering path
        guard let sourceURL = currentPhoto?.sourceURL else { return }
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

    /// Renders watermarked video at full resolution with progress tracking,
    /// cancel support, and background notification (VIDX-01, VIDX-02, VIDX-03).
    func renderAndShareVideo() async {
        guard let sourceURL = currentPhoto?.sourceURL else { return }
        renderingState = .renderingVideo(progress: 0.0, estimatedTimeRemaining: nil)

        // D-14: Request background execution time for export + notification
        var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
        backgroundTaskID = UIApplication.shared.beginBackgroundTask {
            // Expiration handler: system is about to suspend — cancel export gracefully
            self.videoExportTask?.cancel()
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
            backgroundTaskID = .invalid
        }

        let task = Task {
            defer {
                UIApplication.shared.endBackgroundTask(backgroundTaskID)
                backgroundTaskID = .invalid
            }

            do {
                let result = try await engine.processVideo(
                    sourceURL: sourceURL,
                    config: config,
                    onProgress: { [weak self] progress, eta in
                        Task { @MainActor in
                            self?.renderingState = .renderingVideo(
                                progress: progress,
                                estimatedTimeRemaining: eta
                            )
                        }
                    }
                )
                await MainActor.run {
                    fullResResult = result
                    renderingState = .done
                    // D-14: Schedule notification for background completion
                    scheduleCompletionNotification(success: true)
                }
            } catch is CancellationError {
                // D-12: Export was cancelled — cleanup and return to idle
                await MainActor.run {
                    renderingState = .idle
                    // Cleanup incomplete temp file
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
                    scheduleCompletionNotification(success: false)
                }
            }
        }
        videoExportTask = task
    }

    /// Processes a Live Photo pair by watermarking both the still image
    /// and video component, then presenting the pair for sharing (D-02).
    ///
    /// Falls back to still-only watermarking with a user alert if
    /// LivePhotoProcessor fails (Pitfall 2: iCloud asset missing or
    /// format unsupported).
    func renderAndShareLivePhoto() async {
        guard let stillURL = currentPhoto?.sourceURL,
              let videoURL = currentPhoto?.videoSourceURL else {
            renderingState = .error(PipelineError.livePhotoUnsupported)
            errorMessage = PipelineError.livePhotoUnsupported.errorDescription
            showError = true
            return
        }

        renderingState = .rendering

        do {
            let result = try await engine.processLivePhoto(
                stillImageURL: stillURL,
                videoURL: videoURL,
                config: config
            )
            fullResResult = result
            renderingState = .done
            if let url = result.url,
               let data = try? Data(contentsOf: url),
               let uiImage = UIImage(data: data) {
                previewImage = uiImage
            }
        } catch {
            // Pitfall 2: Fall back to still-only watermarking with user alert
            do {
                let stillResult = try await engine.process(
                    sourceURL: stillURL,
                    config: config
                )
                fullResResult = stillResult
                renderingState = .done
                errorMessage = "Live Photo animation could not be preserved. The still image has been watermarked."
                showError = true
                if let url = stillResult.url,
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
    }

    /// Schedules a local notification for video export completion/failure (D-14).
    private func scheduleCompletionNotification(success: Bool) {
        let center = UNUserNotificationCenter.current()

        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }

            let content = UNMutableNotificationContent()
            if success {
                content.title = "Watermark Complete"
                content.body = "Video watermarked"
            } else {
                content.title = "Export Failed"
                content.body = "Video export failed"
            }
            content.sound = .default

            // Store output URL in App Group UserDefaults for notification tap deep-link
            if success, let url = self.fullResResult?.url {
                UserDefaults(suiteName: AppGroupConfigSync.suiteName)?
                    .set(url.absoluteString, forKey: "completedExportURL")
            }

            let identifier = "com.watermark.app.video-export-\(UUID().uuidString)"
            let request = UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: nil
            )

            center.add(request) { error in
                if let error = error {
                    os_log(.error, "Failed to schedule notification: %{public}@",
                           error.localizedDescription)
                }
            }
        }
    }

    func presentShareSheet() {
        guard renderingState == .done else { return }
        showShareSheet = true
    }

    func cancelVideoExport() {
        videoExportTask?.cancel()
        videoExportTask = nil
        // State cleanup handled in renderAndShareVideo's CancellationError catch
    }

    // MARK: - Batch Processing Methods

    /// Unified cancel entry point for ControlsView buttons.
    /// Routes to the correct cancel method based on active processing state.
    func cancelProcessing() {
        if batchProcessingTask != nil {
            cancelBatch()
        } else {
            cancelVideoExport()
        }
    }

    /// Cancels the in-progress batch processing task.
    /// State cleanup (temp file removal, renderingState = .idle) happens
    /// in processBatch()'s CancellationError catch block.
    func cancelBatch() {
        batchProcessingTask?.cancel()
        batchProcessingTask = nil
    }

    /// Processes all loaded photos sequentially through BatchProcessor.
    ///
    /// Only runs when renderingState is .idle and more than one photo is loaded.
    /// Requests background execution time for completion notification delivery.
    /// On completion: stores batchResults, sets .done, schedules notification.
    /// On cancellation: cleans up partial temp files, returns to .idle.
    func processBatch() async {
        guard renderingState == .idle, photos.count > 1 else { return }

        renderingState = .batchProcessing(current: 0, total: photos.count, eta: nil)

        let items: [BatchProcessor.BatchItem] = photos.map { photo in
            BatchProcessor.BatchItem(
                id: photo.id,
                sourceURL: photo.sourceURL,
                mediaType: photo.mediaType,
                overrideConfig: perItemOverrides[photo.id]
            )
        }

        var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
        backgroundTaskID = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.cancelBatch()
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
            backgroundTaskID = .invalid
        }

        let task = Task { [weak self] in
            guard let self = self else { return }
            defer {
                UIApplication.shared.endBackgroundTask(backgroundTaskID)
                backgroundTaskID = .invalid
            }

            let result = await self.batchProcessor.process(
                items: items,
                sharedConfig: self.config,
                onProgress: { @Sendable current, total, eta in
                    Task { @MainActor [weak self] in
                        self?.renderingState = .batchProcessing(current: current, total: total, eta: eta)
                    }
                }
            )

            if Task.isCancelled {
                // Clean up partial temp files from completed items
                for url in result.successes {
                    try? TempFileManager.cleanup(url: url)
                }
                await MainActor.run {
                    self.renderingState = .idle
                }
            } else {
                await MainActor.run {
                    self.batchResults = result
                    self.renderingState = .done
                    self.scheduleBatchCompletionNotification(
                        successCount: result.successCount,
                        failureCount: result.failureCount
                    )
                }
            }
        }
        batchProcessingTask = task
        await task.value
    }

    // MARK: - Per-Item Override Methods

    /// Returns the effective watermark configuration for a given item.
    /// Uses the per-item override if set, otherwise falls back to the shared config.
    func overrideConfig(for id: UUID) -> WatermarkConfiguration {
        perItemOverrides[id] ?? config
    }

    /// Stores a per-item watermark configuration override.
    /// Does NOT modify the shared `config` (per CONTEXT.md decision D7).
    func setOverride(_ newConfig: WatermarkConfiguration, for id: UUID) {
        perItemOverrides[id] = newConfig
    }

    /// Returns true if a per-item override exists for the given UUID.
    func hasOverride(for id: UUID) -> Bool {
        perItemOverrides[id] != nil
    }

    /// Removes the per-item override for the given UUID.
    /// The item reverts to using the shared config.
    func resetOverride(for id: UUID) {
        perItemOverrides.removeValue(forKey: id)
    }

    /// Removes all per-item overrides, reverting every item to the shared config.
    func resetAllOverrides() {
        perItemOverrides.removeAll()
    }

    // MARK: - Batch Completion Notification

    /// Schedules a local notification for batch processing completion.
    /// Stores result count in App Group UserDefaults for notification tap handling.
    private func scheduleBatchCompletionNotification(successCount: Int, failureCount: Int) {
        let center = UNUserNotificationCenter.current()

        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }

            let content = UNMutableNotificationContent()
            content.title = "Batch Complete"
            if failureCount == 0 {
                content.body = "\(successCount) of \(self.photos.count) items watermarked"
            } else {
                content.body = "\(successCount) watermarked, \(failureCount) failed"
            }
            content.sound = .default

            // Store batch result count for notification tap handling
            UserDefaults(suiteName: AppGroupConfigSync.suiteName)?
                .set(successCount, forKey: "batchCompletedResultCount")

            let identifier = "com.watermark.app.batch-complete-\(UUID().uuidString)"
            let request = UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: nil
            )

            center.add(request) { error in
                if let error = error {
                    os_log(.error, "Failed to schedule batch notification: %{public}@",
                           error.localizedDescription)
                }
            }
        }
    }

    func cleanupTempFile() {
        if let url = fullResResult?.url {
            try? TempFileManager.cleanup(url: url)
        }
        fullResResult = nil
        batchResults = nil
        perItemOverrides.removeAll()
        renderingState = .idle
    }

    func requestCancel() {
        showCancelAlert = true
    }

    func confirmCancel() {
        videoExportTask?.cancel()
        videoExportTask = nil
        batchProcessingTask?.cancel()
        batchProcessingTask = nil
        photos = []
        currentIndex = 0
        originalSourceImage = nil
        fullResResult = nil
        batchResults = nil
        perItemOverrides.removeAll()
        renderingState = .idle
        showPicker = true
    }

    func addSignatureLayer(strokeData: Data, inkColor: CGColor, strokeWidth: CGFloat) {
        let input = SignatureInput(strokeData: strokeData, inkColor: inkColor, strokeWidth: strokeWidth)
        config.watermarks.append(.signature(input, position: .bottomRight, scale: 0.15, opacity: 1.0, isVisible: true))
        activeLayerIndex = config.watermarks.count - 1
    }

    public var sourceHasHDR: Bool = false
    public var sourceFormatLabel: String? = nil

    private func copyToTemp(data: Data) async -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let filename = "photo_\(UUID().uuidString).jpg"
        let url = tempDir.appendingPathComponent(filename)
        try? data.write(to: url)
        return url
    }

    // MARK: - Files Import (IMPS-01)

    func handleIncomingFile(url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        let mediaType = WatermarkEngine.mediaType(for: url)
        guard mediaType != .unknown else {
            errorMessage = "Unsupported file format. Supported formats: HEIC, JPEG, PNG, TIFF, DNG, MOV, MP4."
            showError = true
            return
        }

        guard let uti = UTType(filenameExtension: url.pathExtension)?.identifier else { return }
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("import_\(UUID().uuidString)")
            .appendingPathExtension(url.pathExtension)

        do {
            try FileManager.default.copyItem(at: url, to: tempURL)
        } catch {
            errorMessage = "Could not open the selected file."
            showError = true
            return
        }

        if let data = try? Data(contentsOf: tempURL) {
            let thumb = createThumbnail(from: data, maxPixelSize: 200)
            photos = [PhotoItem(id: UUID(), thumbnail: thumb, sourceURL: tempURL, videoSourceURL: nil, mediaType: mediaType)]
            currentIndex = 0
            if !sourceHasHDR { sourceHasHDR = detectHDRSource(from: data) }
            if sourceFormatLabel == nil { sourceFormatLabel = detectSourceFormatLabel(from: data) }
        }
        Task { await loadSourceForComparison() }
        // Phase 12: Auto-apply default template on import
        if let defaultTemplate = TemplateStore.shared.defaultTemplate {
            config = defaultTemplate.config
        }
    }

    // MARK: - Quick Actions (IMPS-02)

    func handleQuickAction(_ type: String) {
        switch type {
        case "com.watermark.app.watermark-last-photo":
            Task { await fetchMostRecentPhoto() }
        case "com.watermark.app.watermark-from-clipboard":
            Task { await loadFromClipboard() }
        default:
            break
        }
    }

    func fetchMostRecentPhoto() async {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .notDetermined:
            let granted = await withCheckedContinuation { continuation in
                PHPhotoLibrary.requestAuthorization(for: .readWrite) { newStatus in
                    continuation.resume(returning: newStatus == .authorized || newStatus == .limited)
                }
            }
            guard granted else {
                errorMessage = "Photo library access is needed to use this feature."
                showError = true
                return
            }
        case .denied, .restricted:
            errorMessage = "Photo library access is needed to use this feature."
            showError = true
            return
        case .authorized, .limited:
            break
        @unknown default:
            errorMessage = "Photo library access is needed to use this feature."
            showError = true
            return
        }

        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.fetchLimit = 1
        fetchOptions.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.image.rawValue)

        let result = PHAsset.fetchAssets(with: fetchOptions)
        guard let asset = result.firstObject else {
            errorMessage = "No photos found in your library."
            showError = true
            return
        }

        let (data, _) = await withCheckedContinuation { (continuation: CheckedContinuation<(Data?, [AnyHashable: Any]?), Never>) in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { imageData, _, _, _ in
                continuation.resume(returning: (imageData, nil))
            }
        }

        guard let imageData = data else {
            errorMessage = "Could not load the most recent photo."
            showError = true
            return
        }

        let ext = "heic"
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("lastphoto_\(UUID().uuidString)")
            .appendingPathExtension(ext)
        try? imageData.write(to: tempURL)

        let thumb = createThumbnail(from: imageData, maxPixelSize: 200)
        let mediaType = WatermarkEngine.mediaType(for: tempURL)
        photos = [PhotoItem(id: UUID(), thumbnail: thumb, sourceURL: tempURL, videoSourceURL: nil, mediaType: mediaType)]
        currentIndex = 0
        if !sourceHasHDR { sourceHasHDR = detectHDRSource(from: imageData) }
        if sourceFormatLabel == nil { sourceFormatLabel = detectSourceFormatLabel(from: imageData) }
        Task { await loadSourceForComparison() }
        // Phase 12: Auto-apply default template on import
        if let defaultTemplate = TemplateStore.shared.defaultTemplate {
            config = defaultTemplate.config
        }
    }

    func loadFromClipboard() async {
        guard UIPasteboard.general.hasImages else {
            errorMessage = "No image found on clipboard."
            showError = true
            return
        }

        guard let image = UIPasteboard.general.image else {
            errorMessage = "No image found on clipboard."
            showError = true
            return
        }

        guard let pngData = image.pngData() ?? image.jpegData(compressionQuality: 1.0) else {
            errorMessage = "Could not read clipboard image."
            showError = true
            return
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("clipboard_\(UUID().uuidString).png")
        try? pngData.write(to: tempURL)

        let thumb = createThumbnail(from: pngData, maxPixelSize: 200)
        let mediaType = WatermarkEngine.mediaType(for: tempURL)
        photos = [PhotoItem(id: UUID(), thumbnail: thumb, sourceURL: tempURL, videoSourceURL: nil, mediaType: mediaType)]
        currentIndex = 0
        if !sourceHasHDR { sourceHasHDR = detectHDRSource(from: pngData) }
        if sourceFormatLabel == nil { sourceFormatLabel = detectSourceFormatLabel(from: pngData) }
        Task { await loadSourceForComparison() }
        // Phase 12: Auto-apply default template on import
        if let defaultTemplate = TemplateStore.shared.defaultTemplate {
            config = defaultTemplate.config
        }
    }

    // MARK: - App Intents (SYSI-01, SYSI-02)

    func checkPendingIntent() {
        guard let defaults = UserDefaults(suiteName: AppGroupConfigSync.suiteName) else { return }
        guard let mediaURLString = defaults.string(forKey: "pendingIntentMediaURL") else { return }

        let mediaType = defaults.string(forKey: "pendingIntentMediaType") ?? "photo"
        let configJSON = defaults.string(forKey: "pendingIntentConfigJSON")

        if let json = configJSON, let jsonData = json.data(using: .utf8) {
            if let decodedConfig = try? JSONDecoder().decode(WatermarkConfiguration.self, from: jsonData) {
                config = decodedConfig
            }
        }

        let url = URL(fileURLWithPath: mediaURLString)
        if FileManager.default.fileExists(atPath: url.path) {
            let engine = WatermarkEngine.mediaType(for: url)
            if engine != .unknown {
                if let data = try? Data(contentsOf: url) {
                    let thumb = createThumbnail(from: data, maxPixelSize: 200)
                    photos = [PhotoItem(id: UUID(), thumbnail: thumb, sourceURL: url, videoSourceURL: nil, mediaType: engine)]
                    currentIndex = 0
                    if !sourceHasHDR { sourceHasHDR = detectHDRSource(from: data) }
                    if sourceFormatLabel == nil { sourceFormatLabel = detectSourceFormatLabel(from: data) }
                    // Phase 12: Auto-apply default template on import
                    if let defaultTemplate = TemplateStore.shared.defaultTemplate {
                        config = defaultTemplate.config
                    }
                }
            }
        }

        defaults.removeObject(forKey: "pendingIntentMediaURL")
        defaults.removeObject(forKey: "pendingIntentConfigJSON")
        defaults.removeObject(forKey: "pendingIntentMediaType")
    }
}

private func createThumbnail(from data: Data, maxPixelSize: CGFloat) -> UIImage? {
    let options = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
    ] as CFDictionary
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
        return nil
    }
    return UIImage(cgImage: cgImage)
}
