import AVFoundation
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

    // MARK: - Progress

    /// How far a batch has got, and how much longer it is expected to take.
    public struct Progress: Sendable, Equatable {
        /// Items finished, successfully or not.
        public let completedItems: Int
        /// Items in the batch.
        public let totalItems: Int
        /// How much of the batch's *work* is done, 0...1 — not how many of its
        /// items. A video among photos is most of the work and a fraction of
        /// the count, and a bar driven by the count sits still through it.
        public let fractionCompleted: Double
        /// Seconds remaining, or nil until there is enough to say.
        public let estimatedTimeRemaining: TimeInterval?

        public init(completedItems: Int, totalItems: Int,
                    fractionCompleted: Double, estimatedTimeRemaining: TimeInterval?) {
            self.completedItems = completedItems
            self.totalItems = totalItems
            self.fractionCompleted = fractionCompleted
            self.estimatedTimeRemaining = estimatedTimeRemaining
        }
    }

    /// Progress callback, invoked as each item advances as well as when it
    /// completes — a long video reports every tenth of a second, so the bar
    /// moves while one is exporting instead of waiting for it to finish.
    public typealias ProgressHandler = @Sendable (Progress) -> Void

    // MARK: - What an item is expected to cost

    /// Nominal seconds for one photo. Only the *ratio* between these matters:
    /// the estimate is recalibrated against the clock as the batch runs, so a
    /// device faster or slower than these numbers converges within an item.
    static let photoCost: Double = 0.8

    /// Nominal seconds a video costs before a frame is encoded — session
    /// set-up, metadata, and the deliberate pause between exports.
    static let videoFixedCost: Double = 1.2

    /// Nominal seconds of work per second of video. Export runs faster than
    /// realtime on device hardware.
    static let videoCostPerSecond: Double = 0.45

    /// What each item is expected to cost, in nominal seconds.
    ///
    /// A video's cost follows its duration, which is what makes a mixed batch
    /// estimable at all: twenty photos and one two-minute clip is not
    /// twenty-one equal items, and treating it as such is why the estimate was
    /// wrong every time the mix was uneven.
    static func estimatedCosts(for items: [BatchItem]) async -> [Double] {
        var costs: [Double] = []
        costs.reserveCapacity(items.count)
        for item in items {
            switch item.mediaType {
            case .video:
                let seconds = (try? await AVURLAsset(url: item.sourceURL)
                    .load(.duration).seconds) ?? 0
                let duration = seconds.isFinite && seconds > 0 ? seconds : 0
                costs.append(videoFixedCost + videoCostPerSecond * duration)
            case .photo, .livePhoto, .unknown:
                costs.append(photoCost)
            }
        }
        return costs
    }

    /// The progress to report, given how much of the expected work is done.
    ///
    /// The estimate is the elapsed time per unit of work done so far, applied
    /// to the work left — so a device slower than the priors above is measured
    /// rather than assumed, and a batch of similar items converges after the
    /// first one.
    ///
    /// Nil until there is enough to divide by: an estimate made from the first
    /// few milliseconds is a wild number, and a wild number that then collapses
    /// reads worse than "Estimating…".
    static func progress(
        completedItems: Int, totalItems: Int,
        doneCost: Double, totalCost: Double, elapsed: TimeInterval
    ) -> Progress {
        let total = max(totalCost, 0.0001)
        let done = min(max(doneCost, 0), total)
        let fraction = done / total

        var eta: TimeInterval?
        if elapsed > 0.4, done > 0, fraction > 0.01 {
            eta = max(0, (total - done) * (elapsed / done))
        }
        return Progress(completedItems: completedItems, totalItems: totalItems,
                        fractionCompleted: fraction, estimatedTimeRemaining: eta)
    }

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

        // What the batch is expected to cost, so progress is measured in work
        // rather than in items.
        let costs = await Self.estimatedCosts(for: items)
        let totalCost = max(costs.reduce(0, +), 0.0001)
        var doneCost = 0.0

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
                    // The export reports every tenth of a second; that is what
                    // moves the bar through the longest item in the batch.
                    let itemCost = costs[index]
                    let costBefore = doneCost
                    let completed = index
                    let count = items.count
                    result = try await engine.processVideo(
                        sourceURL: item.sourceURL,
                        config: config,
                        onProgress: { fraction, _ in
                            onProgress?(Self.progress(
                                completedItems: completed, totalItems: count,
                                doneCost: costBefore + itemCost * min(max(fraction, 0), 1),
                                totalCost: totalCost,
                                elapsed: Date().timeIntervalSince(batchStartTime)))
                        },
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

            // The item is done, whether it succeeded or failed: it cost what it
            // cost either way.
            doneCost += costs[index]
            autoreleasepool {
                onProgress?(Self.progress(
                    completedItems: index + 1, totalItems: items.count,
                    doneCost: doneCost, totalCost: totalCost,
                    elapsed: Date().timeIntervalSince(batchStartTime)))
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
