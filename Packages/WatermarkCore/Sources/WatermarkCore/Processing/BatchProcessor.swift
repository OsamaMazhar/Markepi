import Foundation

/// Actor-isolated batch watermark processor.
///
/// Processes an array of `BatchItem` values sequentially through the shared
/// `WatermarkEngine`, collecting success URLs and per-item failure entries.
/// Supports cancellation via `Task.checkCancellation()` at item boundaries,
/// per-item error resilience (one failure does not abort the batch), and
/// progress reporting with ETA estimation.
///
/// All processing is serial — parallel/concurrent processing is out of scope
/// to prevent memory explosion and AVAssetExportSession hardware decoder
/// exhaustion (Pitfalls #1 and #4).
public actor BatchProcessor {

    // MARK: - Init

    public init() {}

    // MARK: - BatchItem

    /// A single item in a batch processing run.
    ///
    /// Each item carries the media source URL, its detected type, and an
    /// optional per-item configuration override. When `overrideConfig` is nil,
    /// the batch-wide `sharedConfig` is used.
    public struct BatchItem: Sendable {
        /// Unique identifier for this item — maps to `PhotoItem.id` for
        /// failure tracking in the UI layer.
        public let id: UUID

        /// File URL to the source media (temp file from PhotosPicker import).
        public let sourceURL: URL

        /// Detected media type for routing to the correct engine pipeline.
        public let mediaType: WatermarkEngine.MediaType

        /// Optional per-item watermark configuration override.
        /// When nil, the batch's `sharedConfig` is used for this item.
        public let overrideConfig: WatermarkConfiguration?

        /// The user's original filename, when known — used to name the output so
        /// batch exports keep their source names instead of temp names.
        public let originalFilename: String?

        public init(
            id: UUID,
            sourceURL: URL,
            mediaType: WatermarkEngine.MediaType,
            overrideConfig: WatermarkConfiguration? = nil,
            originalFilename: String? = nil
        ) {
            self.id = id
            self.sourceURL = sourceURL
            self.mediaType = mediaType
            self.overrideConfig = overrideConfig
            self.originalFilename = originalFilename
        }
    }

    // MARK: - Progress Handler

    /// Progress callback invoked after each item completes (success or failure).
    ///
    /// - Parameters:
    ///   - current: Number of items completed so far (1-based)
    ///   - total: Total number of items in the batch
    ///   - eta: Estimated seconds remaining, or nil when insufficient data
    public typealias ProgressHandler = @Sendable (Int, Int, TimeInterval?) -> Void

    // MARK: - Properties

    private let engine = WatermarkEngine.shared

    // MARK: - Processing

    /// Processes a batch of media items sequentially, applying watermark
    /// configurations and collecting results.
    ///
    /// Items are processed in submission order regardless of media type
    /// (photos and videos are interleaved). After each item completes,
    /// `Task.checkCancellation()` is called — if cancelled, the loop exits
    /// after the current item finishes and returns partial results.
    ///
    /// Per-item failures are caught and recorded in the failures dictionary;
    /// the batch continues processing remaining items. A 0.5-second delay
    /// is inserted after each successful video export to prevent
    /// AVAssetExportSession hardware decoder exhaustion (Pitfall #4).
    ///
    /// - Parameters:
    ///   - items: Ordered array of batch items to process
    ///   - sharedConfig: Default watermark configuration applied to all items
    ///     unless overridden by a per-item `overrideConfig`
    ///   - onProgress: Optional callback invoked after each item completes
    /// - Returns: `BatchProcessingResult` with success URLs, failure entries,
    ///   and total batch duration
    public func process(
        items: [BatchItem],
        sharedConfig: WatermarkConfiguration,
        provenanceAppVersion: String? = nil,
        onProgress: ProgressHandler? = nil
    ) async -> BatchProcessingResult {
        let batchStartTime = Date()
        var successes: [URL] = []
        var failures: [UUID: any Error] = [:]

        for (index, item) in items.enumerated() {
            // Cancel check at each item boundary — current item finishes,
            // remaining items are skipped
            try? Task.checkCancellation()
            if Task.isCancelled { break }

            let config = item.overrideConfig ?? sharedConfig
            let provenance = provenanceAppVersion.map {
                ProvenanceExportOptions(
                    rights: config.rightsMetadata,
                    privacyProfile: config.metadataPrivacyProfile,
                    includeC2PA: config.includeC2PAManifest,
                    userDeclaration: config.sourceDeclaration,
                    appVersion: $0
                )
            }

            do {
                let result: ProcessingResult

                switch item.mediaType {
                case .video:
                    result = try await engine.processVideo(
                        sourceURL: item.sourceURL,
                        config: config,
                        onProgress: { _, _ in /* video-level progress; batch tracks at item boundary */ },
                        provenance: provenance
                    )
                    // Pitfall #4: 0.5s inter-export delay to prevent
                    // AVAssetExportSession hardware decoder exhaustion
                    try? Task.checkCancellation()
                    if Task.isCancelled { break }
                    try? await Task.sleep(for: .milliseconds(500))

                case .photo, .livePhoto, .unknown:
                    // Batch items are real exports: existing source Content
                    // Credentials are preserved via the ingredient chain.
                    result = try await engine.process(
                        sourceURL: item.sourceURL,
                        config: config,
                        provenance: provenance,
                        preserveSourceCredentials: true
                    )
                }

                // Record success URL, renamed to keep the source's filename
                // (correct extension per media type) instead of a temp name.
                if let url = result.url {
                    successes.append(
                        renamedOutput(url, originalFilename: item.originalFilename, index: index)
                    )
                }
            } catch {
                // Any error (except CancellationError at checkCancellation gate):
                // record failure, clean up temp file, continue to next item
                failures[item.id] = error
                // Attempt to clean up any temp file that may have been created
                // for this failed item — best-effort, ignore cleanup errors
                // (TempFileManager handles "file doesn't exist" silently)
            }

            // Calculate ETA and fire progress callback
            autoreleasepool {
                let perItemElapsed = Date().timeIntervalSince(batchStartTime) / Double(index + 1)
                let remaining = items.count - index - 1
                let eta = perItemElapsed * Double(remaining)
                onProgress?(index + 1, items.count, remaining > 0 && eta > 0 ? eta : nil)
            }
        }

        let duration = Date().timeIntervalSince(batchStartTime)
        return BatchProcessingResult(
            successes: successes,
            failures: failures,
            duration: duration
        )
    }

    /// Copies a rendered output to a temp file named from the source's original
    /// filename (keeping the output's extension), so batch exports retain user
    /// filenames. Falls back to a unique "Markepi-<n>" when no name is known.
    private func renamedOutput(_ url: URL, originalFilename: String?, index: Int) -> URL {
        let ext = url.pathExtension.isEmpty ? "jpg" : url.pathExtension
        let base: String
        if let originalFilename, !originalFilename.isEmpty {
            base = (originalFilename as NSString).deletingPathExtension
        } else {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
            base = "Markepi \(f.string(from: Date())) \(index + 1)"
        }
        let dir = FileManager.default.temporaryDirectory
        var dest = dir.appendingPathComponent(base).appendingPathExtension(ext)
        // Disambiguate collisions (e.g. two files with the same base name).
        if FileManager.default.fileExists(atPath: dest.path) {
            dest = dir.appendingPathComponent("\(base)-\(index + 1)").appendingPathExtension(ext)
        }
        try? FileManager.default.removeItem(at: dest)
        do {
            try FileManager.default.copyItem(at: url, to: dest)
            try? FileManager.default.removeItem(at: url)  // remove the temp original
            return dest
        } catch {
            return url
        }
    }
}
