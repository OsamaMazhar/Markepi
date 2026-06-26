import AVFoundation
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

    /// Freshly imported photos awaiting the user's decision (add vs replace)
    /// when an import happens while photos are already loaded. Empty otherwise.
    var pendingImport: [PhotoItem] = []

    /// Drives the "Add to Batch / Replace / Cancel" dialog. Set when an import
    /// completes while `photos` is non-empty.
    var showImportChoice: Bool = false
    var config = WatermarkViewModel.makeDefaultConfig() {
        didSet {
            AppGroupConfigSync.save(config)
            if config.sourceDeclaration != analyzedDeclaration {
                analyzeCurrentSource()
            }
        }
    }

    /// A clean starting configuration: a single empty text layer at bottom-right.
    static func makeDefaultConfig() -> WatermarkConfiguration {
        WatermarkConfiguration(watermarks: [
            .text(
                TextWatermarkInput(text: "", fontSize: 48, color: CGColor(gray: 1, alpha: 1), opacity: 1.0, fontName: WatermarkConfiguration.defaultFontPostScriptName),
                position: .bottomRight,
                // For text, scale is the font height as a fraction of image
                // height (see WatermarkEngine). A tasteful signature default
                // (~4.5%); 10% rendered far too large.
                scale: WatermarkConfiguration.defaultTextScale,
                opacity: 1.0,
                isVisible: true
            )
        ])
    }

    private static let rememberSettingsKey = "rememberLastSettings"

    /// When true, the app reopens with the watermark used last time; when false
    /// (default), each launch starts from a clean slate. Persisted in UserDefaults
    /// and toggled from the Settings pane (gear icon).
    var rememberLastSettings: Bool = UserDefaults.standard.bool(forKey: WatermarkViewModel.rememberSettingsKey) {
        didSet { UserDefaults.standard.set(rememberLastSettings, forKey: Self.rememberSettingsKey) }
    }

    private static let openPickerOnLaunchKey = "openPickerOnLaunch"

    /// When true (default), the photo picker opens automatically on launch if no
    /// media is loaded. Users can disable it in Settings to land on the start
    /// screen instead. `object(forKey:)` is used so the *unset* default is true.
    var openPickerOnLaunch: Bool = (UserDefaults.standard.object(forKey: WatermarkViewModel.openPickerOnLaunchKey) as? Bool) ?? true {
        didSet { UserDefaults.standard.set(openPickerOnLaunch, forKey: Self.openPickerOnLaunchKey) }
    }

    /// Discards the current watermark (text, logo, signature, frame) and returns
    /// to the clean default. Used by the Settings "Start From Scratch" action.
    func resetToDefaults() {
        config = WatermarkViewModel.makeDefaultConfig()
        activeLayerIndex = 0
    }

    var previewImage: UIImage?
    var originalSourceImage: UIImage?
    var isGeneratingPreview: Bool = false

    /// True while picked media is being loaded/copied (drives the import
    /// loading animation so the UI isn't a frozen blank during the hand-off).
    var isImportingMedia: Bool = false

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

    /// True once the default template has been applied for this editing session.
    /// Prevents importing a second image from silently overwriting the watermark
    /// settings (font, color, position…) the user just configured for the first
    /// image. The default template is a *starting point*, applied once — not on
    /// every import.
    private var hasAppliedDefaultTemplate = false

    init() {
        // Bundled fonts are needed for both the font picker previews and the
        // render pipeline; register up-front so the dropdown always shows real
        // typefaces instead of falling back to the system font on first open.
        FontRegistry.registerBundledFonts()
        // Only restore the previous session's watermark when the user has opted
        // in (Settings → Remember Last Settings). By default each launch starts
        // from a clean slate so old signatures/borders don't reappear.
        if rememberLastSettings, let saved = AppGroupConfigSync.load() {
            config = saved
        }
        checkPendingIntent()
    }

    /// Applies the user's default template exactly once per session, the first
    /// time media is imported. Subsequent imports keep the current configuration
    /// so settings carry across images instead of being reset.
    private func applyDefaultTemplateIfNeeded() {
        guard !hasAppliedDefaultTemplate else { return }
        hasAppliedDefaultTemplate = true
        if let defaultTemplate = TemplateStore.shared.defaultTemplate {
            config = defaultTemplate.config
        }
    }

    var currentPhoto: PhotoItem? {
        guard !photos.isEmpty, currentIndex >= 0, currentIndex < photos.count else { return nil }
        return photos[currentIndex]
    }

    var hasMultiplePhotos: Bool { photos.count > 1 }

    // MARK: - Provenance (Plan 19-03)

    /// Analyzer verdict for the currently-loaded source. Runtime-only — NOT persisted.
    var sourceProvenanceReport: SourceProvenanceReport?

    /// Receipt returned by the engine after a provenance-enabled export.
    var lastExportReceipt: ExportReceipt?

    /// Last declaration sent to the analyzer — used to avoid redundant re-analysis.
    private var analyzedDeclaration: UserSourceDeclaration = .none

    var showExportReceipt = false

    /// Runs whenever the current source changes (import funnels + index change)
    /// and when the user changes the source declaration.
    func analyzeCurrentSource() {
        guard let photo = currentPhoto else {
            sourceProvenanceReport = nil; return
        }
        let url = photo.sourceURL
        let declaration = config.sourceDeclaration
        if photo.mediaType == .video {
            sourceProvenanceReport = SourceProvenanceReport(
                state: .unknown, evidence: [],
                warnings: ["Video source provenance is not analyzed in this version."],
                userDeclaration: declaration)
        } else {
            sourceProvenanceReport = SourceProvenanceAnalyzer()
                .analyze(imageURL: url, userDeclaration: declaration)
                ?? SourceProvenanceReport(state: .unknown, evidence: [], userDeclaration: declaration)
        }
        analyzedDeclaration = declaration
    }

    /// True when the current item is a video (drives the frame scrubber UI).
    var isCurrentVideo: Bool { currentPhoto?.mediaType == .video }

    /// Scrub position (0...1) of the previewed video frame. Changing it refreshes
    /// the watermarked preview at that point in the timeline so the user can see
    /// how the rendered video will look at any frame.
    var videoPreviewFraction: Double = 0.5

    var previewIdentifier: String {
        // The preview's `.task(id:)` re-runs only when this string changes, so
        // it MUST capture EVERY config field that affects the rendered pixels.
        // Previously it omitted font, color, opacity, font size, and all
        // white-frame parameters — so changing a font/color/border-size did not
        // refresh the preview, and toggling the frame off/on was the only way to
        // force a redraw. Include the photo's identity (not just currentIndex)
        // so a fresh import at index 0 also re-triggers the preview.
        var parts: [String] = ["\(currentIndex)", currentPhoto?.id.uuidString ?? "none"]
        parts.append("pad:\(String(format: "%.1f", config.padding))")
        // Video scrub position — re-extracts the previewed frame when scrubbed.
        parts.append("vf:\(String(format: "%.4f", videoPreviewFraction))")
        for layer in config.watermarks {
            switch layer {
            case .text(let input, let pos, let scl, let op, let vis):
                parts.append(
                    "t:\(input.text)|fn:\(input.fontName ?? "sys")|fs:\(String(format: "%.2f", input.fontSize))"
                    + "|c:\(Self.colorKey(input.color))|to:\(String(format: "%.3f", input.opacity))"
                    + "|pos:\(pos.rawValue)|s:\(String(format: "%.4f", scl))"
                    + "|lo:\(String(format: "%.3f", op))|v:\(vis ? 1 : 0)"
                )
            case .image(let input, let pos, let scl, let op, let vis):
                parts.append(
                    "im:\(input.pngData.count)x\(input.pngData.hashValue)|io:\(String(format: "%.3f", input.opacity))"
                    + "|pos:\(pos.rawValue)|s:\(String(format: "%.4f", scl))"
                    + "|lo:\(String(format: "%.3f", op))|v:\(vis ? 1 : 0)"
                )
            case .signature(let input, let pos, let scl, let op, let vis):
                parts.append(
                    "sig:\(input.strokeData.count)x\(input.strokeData.hashValue)|sc:\(Self.colorKey(input.inkColor))"
                    + "|sw:\(String(format: "%.2f", input.strokeWidth))"
                    + "|pos:\(pos.rawValue)|s:\(String(format: "%.4f", scl))"
                    + "|lo:\(String(format: "%.3f", op))|v:\(vis ? 1 : 0)"
                )
            }
        }
        if let wf = config.whiteFrame {
            parts.append(
                "wf:\(wf.isEnabled ? 1 : 0)|fw:\(String(format: "%.4f", wf.frameWidthRatio))"
                + "|mt:\(wf.metadataTextEnabled ? 1 : 0)|at:\(wf.customAttributionText ?? "auto")"
                + "|cpfx:\(wf.captionPrefix)|cf:\(wf.captionFields.map(\.rawValue).joined(separator: ","))"
                + "|tc:\(Self.colorKey(wf.textColor))|tfs:\(String(format: "%.4f", wf.textFontSizeRatio))"
            )
        } else {
            parts.append("wf:none")
        }
        if let ds = config.dateStamp {
            parts.append(
                "ds:\(ds.isEnabled ? 1 : 0)|df:\(ds.format.rawValue)"
                + "|dz:\(String(format: "%.4f", ds.sizeRatio))|dp:\(ds.position.rawValue)"
            )
        } else {
            parts.append("ds:none")
        }
        return parts.joined(separator: "~")
    }

    /// Compact, stable string key for a CGColor's components, used to make
    /// `previewIdentifier` change when any element/frame color changes.
    private static func colorKey(_ color: CGColor) -> String {
        (color.components ?? []).map { String(format: "%.3f", $0) }.joined(separator: ",")
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
        guard !items.isEmpty else { return }
        Task {
            isImportingMedia = true
            defer { isImportingMedia = false }
            var loaded: [PhotoItem] = []
            var failedCount = 0

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
                    // Reject placeholder/corrupt still data before accepting the pair.
                    guard isDecodableImage(stillData) else {
                        failedCount += 1
                        continue
                    }
                    let thumb = createThumbnail(from: stillData, maxPixelSize: 200)
                    let stillURL = await copyToTemp(data: stillData)
                    let videoURL = await copyToTemp(data: videoData, ext: videoExtension(for: pair.video))
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

                guard let data = try? await item.loadTransferable(type: Data.self) else {
                    failedCount += 1
                    continue
                }

                // Validate that image-typed items actually decode to a real image
                // before accepting them. Videos legitimately aren't images, so they
                // skip this check and are validated downstream by the video pipeline.
                if !isVideoItem(item), !isDecodableImage(data) {
                    failedCount += 1
                    continue
                }

                let isVid = isVideoItem(item)
                let sourceURL = await copyToTemp(
                    data: data,
                    ext: isVid ? videoExtension(for: item) : "jpg"
                )
                // Videos need a frame-extracted thumbnail; image thumbnailing
                // returns nil for video data and leaves the cell spinning.
                let thumb = isVid
                    ? await videoThumbnail(from: sourceURL, maxPixelSize: 200)
                    : createThumbnail(from: data, maxPixelSize: 200)
                // Trust the picker's own type classification (isVideoItem) over a
                // round-trip through the file extension, which can misdetect.
                let mediaType: WatermarkEngine.MediaType = isVid ? .video : WatermarkEngine.mediaType(for: sourceURL)
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
            showPicker = false
            if !loaded.isEmpty {
                applyImportedPhotos(loaded)
            }

            // Surface a clear, up-front message when items couldn't be read,
            // instead of letting unreadable data fail later in the render pipeline.
            if failedCount > 0 {
                if loaded.isEmpty {
                    errorMessage = "The selected photo couldn’t be read. If it’s stored in iCloud, make sure it’s fully downloaded, then try again.\n\n(On the Simulator, some built-in sample photos return placeholder data — test with a real image or on a device.)"
                } else {
                    errorMessage = "\(failedCount) item\(failedCount == 1 ? "" : "s") couldn’t be read and \(failedCount == 1 ? "was" : "were") skipped."
                }
                showError = true
            }
        }
    }

    /// Routes freshly imported photos: on a clean slate they load immediately;
    /// when photos are already loaded the user is asked whether to add them to
    /// the current batch or replace what's loaded (D: import flow).
    private func applyImportedPhotos(_ loaded: [PhotoItem]) {
        guard !loaded.isEmpty else { return }
        if photos.isEmpty {
            photos = loaded
            currentIndex = 0
            Task { await loadSourceForComparison() }
            analyzeCurrentSource()
            // Phase 12: Auto-apply default template once per session on first import
            applyDefaultTemplateIfNeeded()
        } else {
            pendingImport = loaded
            showImportChoice = true
        }
    }

    /// Appends the pending import to the current batch (keeps existing photos,
    /// per-item overrides, and the current selection).
    func confirmImportAppend() {
        guard !pendingImport.isEmpty else { return }
        photos.append(contentsOf: pendingImport)
        pendingImport = []
        // Surface the freshly added items by jumping to the first of them.
        currentIndex = max(0, photos.count - 1)
        Task { await loadSourceForComparison() }
        analyzeCurrentSource()
    }

    /// Replaces the current batch with the pending import, discarding the
    /// previously loaded photos and their per-item overrides.
    func confirmImportReplace() {
        guard !pendingImport.isEmpty else { return }
        cleanupPhotoTempFiles(photos)
        photos = pendingImport
        pendingImport = []
        currentIndex = 0
        perItemOverrides.removeAll()
        fullResResult = nil
        batchResults = nil
        renderingState = .idle
        Task { await loadSourceForComparison() }
        analyzeCurrentSource()
        applyDefaultTemplateIfNeeded()
    }

    /// Discards the pending import, cleaning up its temp files. The current
    /// batch is left untouched.
    func cancelImport() {
        cleanupPhotoTempFiles(pendingImport)
        pendingImport = []
    }

    /// Removes the temp files backing a set of photo items.
    private func cleanupPhotoTempFiles(_ items: [PhotoItem]) {
        for item in items {
            try? FileManager.default.removeItem(at: item.sourceURL)
            if let videoURL = item.videoSourceURL {
                try? FileManager.default.removeItem(at: videoURL)
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

    /// Returns true if `data` decodes as a real, readable image. Guards against
    /// placeholder/corrupt bytes — notably the Simulator's 2 KB `DEADBEEF`
    /// sentinel returned by `loadTransferable` for some stock photos — being
    /// accepted at import and only failing later in the render pipeline with a
    /// confusing "image data is empty or corrupt" error.
    private func isDecodableImage(_ data: Data) -> Bool {
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              CGImageSourceGetType(source) != nil else {
            return false
        }
        return true
    }

    /// Whether a picked item represents a movie/video rather than a still image.
    /// Used to skip image-decode validation for video imports, which flow through
    /// the same `loadTransferable(type: Data.self)` path.
    private func isVideoItem(_ item: PhotosPickerItem) -> Bool {
        item.supportedContentTypes.contains { $0.conforms(to: .movie) || $0.conforms(to: .video) }
    }

    func goToNext() {
        guard currentIndex < photos.count - 1 else { return }
        currentIndex += 1
        analyzeCurrentSource()
    }

    func goToPrev() {
        guard currentIndex > 0 else { return }
        currentIndex -= 1
        analyzeCurrentSource()
    }

    func generatePreview() async {
        guard let photo = currentPhoto else { return }
        let sourceURL = photo.sourceURL
        isGeneratingPreview = true
        defer { isGeneratingPreview = false }

        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }

        // The image pipeline can't decode a movie file. For videos, preview a
        // watermarked still extracted from the video; Live Photos already point
        // `sourceURL` at their still-image component, so they take the image path.
        var frameTempURL: URL?
        defer {
            if let frameTempURL { try? FileManager.default.removeItem(at: frameTempURL) }
        }

        do {
            let imageURL: URL
            // For video, render the extracted frame but caption it with the
            // VIDEO's metadata (device · dimensions · MOV) so the live preview
            // matches the exported video exactly — not the PNG frame's metadata.
            var metadataOverride: [String: Any]?
            if photo.mediaType == .video {
                frameTempURL = try await extractVideoFrameToTempImage(from: sourceURL)
                imageURL = frameTempURL!
                metadataOverride = await VideoProcessor.captionMetadata(for: sourceURL)
            } else {
                imageURL = sourceURL
            }
            guard !Task.isCancelled else { return }

            let result = try await engine.process(
                sourceURL: imageURL, config: config, metadataOverride: metadataOverride
            )
            // The .task may have been cancelled (e.g. config changed) while the
            // engine was running; don't clobber state for a stale render.
            guard !Task.isCancelled else { return }
            guard let url = result.url else { throw PipelineError.renderFailed }
            let data = try Data(contentsOf: url)
            guard let uiImage = UIImage(data: data) else {
                throw PipelineError.renderFailed
            }
            previewImage = uiImage
        } catch is CancellationError {
            // Superseded by a newer preview request — not a user-facing error.
            return
        } catch {
            // A genuine processing failure: surface it instead of spinning forever.
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
            showError = true
        }
    }

    /// Extracts a representative frame from a video and writes it to a temp PNG
    /// so the still-image watermark pipeline can render an accurate preview.
    /// The caller is responsible for deleting the returned file.
    private func extractVideoFrameToTempImage(from videoURL: URL) async throws -> URL {
        // Map the scrub fraction (0...1) to a timestamp in the clip.
        let asset = AVURLAsset(url: videoURL)
        let duration = (try? await asset.load(.duration)) ?? .zero
        let seconds = duration.seconds.isFinite ? duration.seconds * videoPreviewFraction : 0
        let time = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        let frame = try await VideoFrameExtractor.extract(from: videoURL, at: time)
        guard let pngData = UIImage(cgImage: frame).pngData() else {
            throw PipelineError.videoFrameExtractionFailed
        }
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("preview_\(UUID().uuidString)")
            .appendingPathExtension("png")
        try pngData.write(to: tempURL)
        return tempURL
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
            let prov = ProvenanceExportOptions(
                rights: config.rightsMetadata,
                privacyProfile: config.metadataPrivacyProfile,
                includeC2PA: config.includeC2PAManifest,
                userDeclaration: config.sourceDeclaration,
                appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
            )
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
            } else {
                presentShareSheet()
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
                    // Auto-open the share sheet when the export finishes in the
                    // foreground (matches the photo path). If backgrounded, the
                    // notification brings the user back and they can share.
                    if UIApplication.shared.applicationState == .active {
                        presentShareSheet()
                    }
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
            presentShareSheet()
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
                presentShareSheet()
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

        // Never PROMPT for notifications — only post if the user has already
        // granted them (e.g. via Settings). Requesting at export time produced a
        // confusing "would like to send you notifications" alert mid-task.
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }

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

    /// A dated, Apple-style filename base that always keeps the "Markepi" brand,
    /// e.g. "Markepi 2026-06-24 at 09.42.15" (colons → dots for filesystem safety).
    static func timestampedName() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Markepi \(f.string(from: Date()))"
    }

    /// Copies a rendered output file to a temp file named after the user's
    /// original media (when known), so the shared/saved file keeps that name
    /// instead of the internal "watermark_UUID" temp name. Falls back to a clean
    /// "Markepi" name when the original filename isn't available (e.g. photo
    /// picker imports, which don't expose a filename).
    func shareReadyURL(_ url: URL, originalFilename: String?) -> URL {
        let ext = url.pathExtension.isEmpty ? "jpg" : url.pathExtension
        let base: String
        if let originalFilename, !originalFilename.isEmpty {
            base = (originalFilename as NSString).deletingPathExtension
        } else {
            // No source name (photo-picker imports) — use a dated, Apple-style
            // name like "Markepi 2026-06-24 at 09.42.15" instead of bare "Markepi".
            base = Self.timestampedName()
        }
        let dir = FileManager.default.temporaryDirectory
        var dest = dir.appendingPathComponent(base).appendingPathExtension(ext)
        if FileManager.default.fileExists(atPath: dest.path) {
            dest = dir.appendingPathComponent("\(base)-\(Int(Date().timeIntervalSince1970))")
                .appendingPathExtension(ext)
        }
        try? FileManager.default.removeItem(at: dest)
        do {
            try FileManager.default.copyItem(at: url, to: dest)
            return dest
        } catch {
            return url
        }
    }

    /// Share items for the single (non-batch) result, named from the original file.
    var singleShareItems: [Any] {
        guard let url = fullResResult?.url else { return [] }
        return [shareReadyURL(url, originalFilename: currentPhoto?.originalFilename)]
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
                overrideConfig: perItemOverrides[photo.id],
                originalFilename: photo.originalFilename
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

        // Only post if notifications are already authorized — never prompt.
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }

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
        // Starting a fresh session: allow the default template to seed the next
        // import again (it was applied once for the previous session).
        hasAppliedDefaultTemplate = false
        showPicker = true
    }

    func addSignatureLayer(strokeData: Data, inkColor: CGColor, strokeWidth: CGFloat) {
        let input = SignatureInput(strokeData: strokeData, inkColor: inkColor, strokeWidth: strokeWidth)
        // Editing an existing signature replaces it in place (preserving its
        // position/scale/opacity/visibility) rather than stacking a duplicate
        // layer — re-capturing previously left two signatures behind.
        if let existing = config.watermarks.firstIndex(where: { if case .signature = $0 { return true }; return false }) {
            let layer = config.watermarks[existing]
            config.watermarks[existing] = .signature(
                input,
                position: layer.position,
                scale: layer.scale,
                opacity: layer.opacity,
                isVisible: layer.isVisible
            )
            activeLayerIndex = existing
        } else {
            config.watermarks.append(.signature(input, position: .bottomRight, scale: 0.15, opacity: 1.0, isVisible: true))
            activeLayerIndex = config.watermarks.count - 1
        }
    }

    public var sourceHasHDR: Bool = false
    public var sourceFormatLabel: String? = nil

    /// Writes picked media to a temp file. The extension matters: downstream
    /// `WatermarkEngine.mediaType(for:)` classifies photo vs. video from the
    /// file's type identifier, so a video must NOT be saved with an image
    /// extension — otherwise it is misrouted into the image pipeline and fails
    /// with "image data is empty or corrupt". Image loading itself sniffs the
    /// content (CGImageSource), so a `.jpg`-named HEIC/PNG still decodes fine.
    private func copyToTemp(data: Data, ext: String = "jpg") async -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let filename = "photo_\(UUID().uuidString).\(ext)"
        let url = tempDir.appendingPathComponent(filename)
        try? data.write(to: url)
        return url
    }

    /// The preferred filename extension for a picked video item, falling back
    /// to `mov` so the temp file is always classified as a movie.
    private func videoExtension(for item: PhotosPickerItem) -> String {
        item.supportedContentTypes
            .first { $0.conforms(to: .movie) || $0.conforms(to: .video) }?
            .preferredFilenameExtension ?? "mov"
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
            Task {
                let thumb = mediaType == .video
                    ? await videoThumbnail(from: tempURL, maxPixelSize: 200)
                    : createThumbnail(from: data, maxPixelSize: 200)
                let item = PhotoItem(id: UUID(), thumbnail: thumb, sourceURL: tempURL, videoSourceURL: nil, mediaType: mediaType, originalFilename: url.lastPathComponent)
                if !sourceHasHDR { sourceHasHDR = detectHDRSource(from: data) }
                if sourceFormatLabel == nil { sourceFormatLabel = detectSourceFormatLabel(from: data) }
                // Routes through the add-vs-replace prompt when photos already loaded.
                applyImportedPhotos([item])
            }
        }
    }

    // MARK: - Share Extension Handoff

    /// Reentrancy guard so the URL-open and scene-activation drains don't both
    /// import the same files.
    private var isImportingShares = false

    /// Drains the Share Extension inbox (App Group container) and loads any
    /// shared photos/videos into the full editor, then clears the inbox.
    ///
    /// Called when the app is opened via `watermark://shared` or becomes active
    /// with pending shares. Mirrors the normal import path so shared media gets
    /// every editor feature; routes through the add-vs-replace prompt when photos
    /// are already loaded.
    func importPendingShares() {
        guard !isImportingShares else { return }
        let pending = SharedInboxStore.pendingURLs()
        os_log("[Markepi] importPendingShares: %d pending item(s)", pending.count)
        guard !pending.isEmpty else { return }
        isImportingShares = true
        // Stop the empty-state launch picker from popping over the incoming media.
        showPicker = false

        Task {
            defer { isImportingShares = false }
            var items: [PhotoItem] = []

            for sharedURL in pending {
                let mediaType = WatermarkEngine.mediaType(for: sharedURL)
                guard mediaType != .unknown else {
                    SharedInboxStore.remove(sharedURL)
                    continue
                }

                // Copy into the app's own temp sandbox, then clear from the inbox.
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("import_\(UUID().uuidString)")
                    .appendingPathExtension(sharedURL.pathExtension)
                do {
                    try FileManager.default.copyItem(at: sharedURL, to: tempURL)
                } catch {
                    SharedInboxStore.remove(sharedURL)
                    continue
                }
                SharedInboxStore.remove(sharedURL)

                let thumb: UIImage?
                if mediaType == .video {
                    thumb = await videoThumbnail(from: tempURL, maxPixelSize: 200)
                } else if let data = try? Data(contentsOf: tempURL) {
                    thumb = createThumbnail(from: data, maxPixelSize: 200)
                    if !sourceHasHDR { sourceHasHDR = detectHDRSource(from: data) }
                    if sourceFormatLabel == nil { sourceFormatLabel = detectSourceFormatLabel(from: data) }
                } else {
                    thumb = nil
                }

                items.append(PhotoItem(
                    id: UUID(),
                    thumbnail: thumb,
                    sourceURL: tempURL,
                    videoSourceURL: nil,
                    mediaType: mediaType,
                    originalFilename: sharedURL.lastPathComponent
                ))
            }

            applyImportedPhotos(items)
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
        analyzeCurrentSource()
        // Phase 12: Auto-apply default template once per session on first import
        applyDefaultTemplateIfNeeded()
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
        // Phase 12: Auto-apply default template once per session on first import
        applyDefaultTemplateIfNeeded()
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
                    Task {
                        let thumb = engine == .video
                            ? await videoThumbnail(from: url, maxPixelSize: 200)
                            : createThumbnail(from: data, maxPixelSize: 200)
                        photos = [PhotoItem(id: UUID(), thumbnail: thumb, sourceURL: url, videoSourceURL: nil, mediaType: engine)]
                        currentIndex = 0
                        if !sourceHasHDR { sourceHasHDR = detectHDRSource(from: data) }
                        if sourceFormatLabel == nil { sourceFormatLabel = detectSourceFormatLabel(from: data) }
                        // Phase 12: Auto-apply default template once per session on first import
                        applyDefaultTemplateIfNeeded()
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

/// Builds a preview thumbnail for a video by extracting a frame with
/// `AVAssetImageGenerator`. The image-based `createThumbnail(from:)` cannot
/// decode video data (CGImageSource returns nil), which left video items with
/// a nil thumbnail and a forever-spinning placeholder in the thumbnail strip.
private func videoThumbnail(from url: URL, maxPixelSize: Int) async -> UIImage? {
    guard let cgImage = try? await VideoFrameExtractor.extract(from: url, maxPixelSize: maxPixelSize) else {
        return nil
    }
    return UIImage(cgImage: cgImage)
}
