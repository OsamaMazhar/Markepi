# Phase 13: Batch Processing - Context

**Gathered:** 2026-06-19
**Status:** Ready for planning

<domain>
## Phase Boundary

Batch watermark processing for multiple photos and videos in one operation. Users select multiple items, apply a shared watermark configuration, optionally override settings per individual item, and process all items sequentially with progress tracking, cancellation, background support, and error resilience. Results are shared together in a single share sheet.

This phase delivers BATC-01 through BATC-07 — the batch processing requirements deferred from v1.0. Builds on Phase 12 templates (auto-default-on-import for batch workflows). Applies to the main app only (share extension and Photos extension process single items by design).

Out of scope: parallel/concurrent batch processing (guaranteed memory explosion), batch-wide auto-positioning, batch format conversion, per-item format override.
</domain>

<decisions>
## Implementation Decisions

### Batch Processing Architecture
- New `BatchProcessor` actor in WatermarkCore — reusable by all 3 targets, keeps WatermarkViewModel lean
- Interleave photo and video processing — process items in order regardless of type, video progress callbacks update same progress bar
- `[PhotoItem.ID: WatermarkConfiguration]` delta dictionary for per-item overrides — nil means use shared config
- `BatchProcessingResult` struct with `[URL]` successes, `[PhotoItem.ID: Error]` failures, and batch duration

### Per-Item Adjustment UX
- `BatchItemDetailSheet` modal overlay — shown when user taps an item in the thumbnail strip. Full controls scoped to that item with "Reset to Batch Config" button
- Thumbnail dot indicator for items that have custom per-item overrides
- Per-item override wins for overridden fields; shared config change propagates to non-overridden fields; "Reset all overrides" button available
- Drag-to-reorder items in thumbnail strip via `.onMove` — cosmetic only, doesn't affect output

### Progress & Cancellation UX
- Determinate progress bar with "X of Y — ETA: Z min" overlaid on preview area during batch processing, Cancel button below
- `Task.checkCancellation()` at each item boundary — current item finishes processing, remaining items skipped, temp files cleaned up for cancelled items
- `UNUserNotificationCenter` "Batch Complete" notification with success/failure counts — tap notification opens app to share sheet
- `beginBackgroundTask` with expiration handler that cancels active processing; AVAssetExportSession handles video backgrounding natively

### Batch Result Handling
- Single share sheet with `[URL]` array of all successful items
- Post-batch summary alert — "N of M processed. K failed." with detail disclosure showing which items failed and why
- Shared config's format/quality applies to all items — no per-item format override
- All items remain in photo strip after batch completion for retry/adjustment; share sheet opens automatically
</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `WatermarkViewModel.photos: [PhotoItem]` — already supports multi-select with thumbnail strip
- `WatermarkViewModel.hasMultiplePhotos` — gating logic for batch vs single mode
- `VideoProcessor.process(sourceURL:config:onProgress:)` — provides `(Double, TimeInterval?)` progress callback pattern
- `WatermarkEngine.process(sourceURL:config:)` — shared engine with single-item processing pipeline
- `ThumbnailStripView` — existing per-item thumbnail display with currentIndex binding
- `PhotoItem` model — has `id: UUID`, `sourceURL: URL?`, `thumbnail: UIImage?`, `mediaType: MediaType`
- `ProcessingResult` — has `url: URL?` for output, `videoValidation` for HDR/audio warnings
- `RenderingState` enum — existing `.idle`, `.renderingVideo(progress, eta)` states
- `TemplateStore.shared.defaultTemplate` — Phase 12 auto-default-on-import

### Established Patterns
- `@Observable @MainActor` for ViewModels (WatermarkViewModel, ShareExtensionViewModel, PhotosExtensionViewModel)
- `WatermarkConfigurable` protocol with `config: WatermarkConfiguration`, `showSaveTemplateAlert`, `showTemplateList`, `applyTemplate(_:)`
- `async/await` with `Task` for all processing operations
- `os_log` for error and lifecycle logging
- `UserDefaults(suiteName: "group.com.watermark.app")` for App Group persistence
- CGImageSource → CIImage → CGImageDestination pipeline for metadata/HDR preservation
- AVAssetExportSession with `onProgress` for video progress tracking

### Integration Points
- `ContentView.body` — attach `.sheet` for BatchItemDetailSheet, overlay for progress bar, alerts for batch results
- `ControlsView` — export button needs batch-awareness (trigger batch processing when >1 item)
- `ThumbnailStripView` — add dot indicator for override, drag-to-reorder support, tap to open BatchItemDetailSheet
- `WatermarkViewModel` — new `batchProcessor` property, batch processing methods, override dict, progress/cancellation state
- App Group UserDefaults — batch results temp URLs shared across processes
</code_context>

<specifics>
## Specific Ideas

- Batch processing is sequential by design (phrased as requirement BATC-07's "mixed photo+video single batch") — parallel processing is explicitly out of scope per REQUIREMENTS.md
- Existing `beginBackgroundTask` + UNNotificationCenter patterns for video export should be generalized for batch processing
- The `RenderingState` enum can be extended with `.batchProcessing(current: Int, total: Int, eta: TimeInterval?)` for batch progress
- Per-item override dict uses the existing `WatermarkConfiguration` — no new config types needed
- Temp files follow the existing `TempFileManager` pattern with cleanup on cancel/error
</specifics>

<deferred>
## Deferred Ideas

- Batch-wide "smart auto-position" using Vision framework — deferred to v2.1+ (BATC-F01)
- Batch preview — "spot check" watermark on one item before full batch — deferred to v2.1+ (BATC-F02)
- Template folders/categories — deferred to v2.1+ (TMPL-F01)
</deferred>
