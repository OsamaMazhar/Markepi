import CoreImage
import Foundation
import ImageIO
import Observation
import os.log
import PhotosUI
import SwiftUI
import UIKit
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
            scale: 0.15
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

    var activeLayerIndex: Int = 0

    private let engine = WatermarkEngine.shared

    /// Tracks the in-progress video export task for cancellation support.
    private var videoExportTask: Task<Void, Never>?

    // MARK: - Init

    override init() {
        // Load saved config from App Group if available (D-08 bidirectional sync)
        if let saved = AppGroupConfigSync.load() {
            config = saved
        }
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
            case .text(let input, let pos, let scl):
                parts.append("t:\(input.text)-pos:\(pos.rawValue)-s:\(String(format: "%.3f", scl))")
            case .image(let input, let pos, let scl):
                parts.append("im:\(input.pngData.hashValue)-pos:\(pos.rawValue)-s:\(String(format: "%.3f", scl))")
            }
        }
        parts.append("wf:\(config.whiteFrame?.isEnabled == true ? "1" : "0")")
        return parts.joined(separator: "-")
    }

    func handleSelection(_ items: [PhotosPickerItem]) {
        Task {
            var loaded: [PhotoItem] = []
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    let thumb = createThumbnail(from: data, maxPixelSize: 200)
                    let sourceURL = await copyToTemp(data: data)
                    loaded.append(PhotoItem(
                        id: UUID(),
                        thumbnail: thumb,
                        sourceURL: sourceURL
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
        case .unknown:
            break
        }
    }

    func renderAndPrepareShare() async {
        guard let sourceURL = currentPhoto?.sourceURL else { return }

        // D-13: Branch by media type — video uses progress-tracked export
        let mediaType = WatermarkEngine.mediaType(for: sourceURL)
        if mediaType == .video {
            await renderAndShareVideo()
            return
        }

        // Photo rendering path (unchanged)
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

    func cleanupTempFile() {
        if let url = fullResResult?.url {
            try? TempFileManager.cleanup(url: url)
        }
        fullResResult = nil
        renderingState = .idle
    }

    func requestCancel() {
        showCancelAlert = true
    }

    func confirmCancel() {
        videoExportTask?.cancel()
        videoExportTask = nil
        photos = []
        currentIndex = 0
        originalSourceImage = nil
        fullResResult = nil
        renderingState = .idle
        showPicker = true
    }

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

    func removeLayer(at index: Int) {
        guard index >= 0, index < config.watermarks.count else { return }
        config.watermarks.remove(at: index)
        if activeLayerIndex >= config.watermarks.count {
            activeLayerIndex = max(0, config.watermarks.count - 1)
        }
    }

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

    func toggleWhiteFrame() {
        if config.whiteFrame?.isEnabled == true {
            config.whiteFrame = nil
        } else {
            config.whiteFrame = WhiteFrameConfig(isEnabled: true)
        }
    }

    var whiteFrameEnabled: Bool {
        config.whiteFrame?.isEnabled ?? false
    }

    var outputFormat: OutputFormat {
        get { config.outputFormat }
        set { config.outputFormat = newValue }
    }

    var outputQuality: Float {
        get { config.outputQuality }
        set { config.outputQuality = newValue }
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
