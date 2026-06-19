# Pitfalls Research

**Domain:** iOS Photo/Video Watermarking App — Batch Processing, Template Management, Process Hardening
**Researched:** 2026-06-19
**Confidence:** HIGH

## Critical Pitfalls

### Pitfall 1: Parallel Batch Processing Memory Explosion

**What goes wrong:**
When processing multiple items simultaneously in a batch (even as few as 3-5 items), all items' pixel buffers can coexist in memory. A 48MP ProRAW photo consumes ~192MB uncompressed (8064×6048 × 4 bytes RGBA). Three such items exceed the ~500MB safe ceiling and trigger a jetsam kill. For video, each concurrent `AVAssetExportSession` holds decoded frame buffers, pushing memory pressure past safe limits even faster. The system terminates the app with `EXC_RESOURCE RESOURCE_TYPE_MEMORY` — no crash log, just a silent kill.

**Why it happens:**
- The current `WatermarkEngine.process()` pipeline loads full-resolution data via `ImageLoader.load(from:)`, which extracts CIImage + metadata + gain map. When multiple tasks run in parallel (e.g., `TaskGroup`), each holds its own full-res pixel buffer simultaneously.
- The current `handleSelection()` already loads all `PhotosPickerItem` data into `Data` objects and copies to temp files — storing all source data in `photos: [PhotoItem]` array. Each `PhotoItem.sourceURL` references a temp copy of the full file, but the decompressed pipeline data is what matters during processing.
- `AVAssetExportSession` uses hardware video decoders that are finite resources. Running multiple concurrent exports exhausts these, producing `AVFoundationErrorDomain Code=-11839 "Cannot Decode"`.
- Training-data patterns default to `TaskGroup` parallelism without understanding the memory implication per task.

**How to avoid:**
1. **Serial processing queue:** Process ONE item at a time. Use an `Actor`-isolated `BatchProcessor` with a sequential queue. Never use `TaskGroup` with `addTask` for batch exports.
2. **Per-item cleanup between items:** Call `TempFileManager.cleanup(url:)` on each item's temp output immediately after the share sheet dismisses for that item. Set `fullResResult = nil` and `previewImage = nil` before loading the next item.
3. **Video serialization guard:** `BatchProcessor` must hold `maxConcurrentVideoExports = 1`. Queue videos sequentially; photos can be interleaved but never process >1 video at a time.
4. **Memory budget tracking:** Before processing each item, check `os_proc_available_memory()` — if below 200MB free, pause and wait for cleanup.
5. **autoreleasepool wrapping:** Wrap each batch iteration in `autoreleasepool { ... }` to force intermediate CIImage/CGImage deallocation between items.
6. **PhotosPicker `.loadTransferable` lazy loading:** Don't eagerly load all items in `handleSelection()`. Load only the thumbnails for the strip. Defer full `Data` loading to on-demand during processing.

**Warning signs:**
- App works fine with 1-3 items but silently crashes with 5+ items
- Instruments Allocations shows heap growth without corresponding deallocation between items
- Video batch: second export fails with "Cannot Decode" / error -11839
- Xcode Organizer shows jetsam events with `reason: per-process-limit`

**Phase to address:**
Batch Processing Phase. Must be designed with serial execution and per-item cleanup from day one.

---

### Pitfall 2: Concurrent AVAssetExportSession Hardware Decoder Exhaustion

**What goes wrong:**
When batch-processing multiple videos, even with sequential execution, if a previous `AVAssetExportSession` hasn't fully released its hardware decoder resources, the next export fails with `AVFoundationErrorDomain Code=-11839 "Cannot Decode"`. The hardware video decoder pipeline is a finite, shared system resource — iOS devices have a limited number of concurrent decode sessions.

**Why it happens:**
- `AVAssetExportSession` internally uses `VTDecompressionSession` (hardware-accelerated). These sessions are reference-counted by the system and may not release immediately when the session completes.
- The current `VideoProcessor.process()` creates `AVAssetExportSession`, calls `export(to:as:)`, then returns — but the session object may still hold decoder resources until deallocated.
- `AVMutableComposition` holds references to source `AVAsset` tracks. If the composition isn't fully released, the underlying decoder sessions remain allocated.

**How to avoid:**
1. **Single export at a time:** `BatchProcessor` must use a serial `OperationQueue` with `maxConcurrentOperationCount = 1` for ALL exports (photo and video).
2. **Explicit resource release:** After each export completes, explicitly set the export session, composition, videoComposition, and source asset references to `nil`. Then call `await Task.yield()` to give the system a scheduler tick to release resources.
3. **Throttle between video exports:** Insert a minimum 0.5s delay between consecutive video exports to allow hardware decoder cleanup.
4. **Pre-export availability check:** Before starting a video export, attempt a lightweight `AVAsset.load(.duration)` on a small test asset to verify the decoder pipeline is available. If it fails with -11839, delay and retry.
5. **Use `@available(iOS 18, *)` `export(to:as:)` async API exclusively** (already done) — the older `exportAsynchronously(completionHandler:)` callback API has worse resource management.

**Warning signs:**
- First video exports fine; second immediately fails with error -11839
- Error message: "Cannot Decode" or "The operation could not be completed"
- Works in Simulator but fails on device (hardware decoder limits don't apply in Simulator)
- Export failures are inconsistent — sometimes 3 videos work, sometimes only 1

**Phase to address:**
Batch Processing Phase — specifically the video batch sub-path.

---

### Pitfall 3: Share Extension Memory Crash With Multiple NSItemProvider Items

**What goes wrong:**
The share extension has a hard ~120MB memory ceiling (Pitfall 4 from v1.0 research). When a user selects multiple photos/videos from the Photos app and shares to Watermark, each `NSItemProvider.loadItem(forTypeIdentifier:completionHandler:)` or `loadFileRepresentation(forTypeIdentifier:)` call can load full-resolution data into the extension's memory space. Multiple items loaded simultaneously trigger a jetsam kill within seconds.

**Why it happens:**
- The current `ShareExtensionViewModel` loads one item at a time (from `extensionContext.inputItems`), which is safe for single-item shares. Batch share from Photos sends multiple `NSExtensionItem`s, and iterating through them while holding previous item data causes accumulation.
- Each `NSItemProvider.loadFileRepresentation` copies the file to a temp URL within the extension sandbox. These temp files + any decoded preview data accumulate.
- Photos app batch share sends ALL items as a single `inputItems` array. The naive iteration pattern processes them sequentially but doesn't release previous item data before loading the next.

**How to avoid:**
1. **Single-item-only for share extension batch:** The share extension should process ONE item at a time. For multi-item shares, present the batch UI (thumbnail strip) using only thumbnails, then for full-resolution processing, write the config + source URL references to App Group container and prompt the user to open the main app.
2. **Thumbnail-only pattern in extension:** Use `CGImageSourceCreateThumbnailAtIndex` with `kCGImageSourceThumbnailMaxPixelSize: 300` for all extension previews. Never load full-resolution data in the extension.
3. **Pass-through for batch share:** The share extension's role for batch should be: receive items → save file URLs to App Group container → call `completeRequest()` → main app handles batch processing. Extension does NOT render.
4. **Limit `NSExtensionActivationRule`:** Set `NSExtensionActivationSupportsImageWithMaxCount: 10` (not unlimited) to prevent the extension from appearing for enormous selections.
5. **Release guards in item iteration:** After processing each `NSExtensionItem`, set local variables to `nil` and call `autoreleasepool` explicitly.

**Warning signs:**
- Share extension works for single item, silently crashes for 3+ items
- Extension appears briefly then vanishes (jetsam before UI renders)
- Xcode Organizer jetsam reports from share extension process
- Works in Simulator (no memory limit enforcement); fails on device

**Phase to address:**
Batch Processing Phase — specifically the share extension batch sub-path.

---

### Pitfall 4: Codable Template Schema Evolution Breaking Saved Templates

**What goes wrong:**
When the `WatermarkConfiguration` Codable model evolves (new fields added to `WatermarkLayer`, new watermark types, new properties on `WhiteFrameConfig`), templates saved in the previous schema version fail to decode. `JSONDecoder` throws a `DecodingError` because keys are missing or enum cases are unrecognized. All user-saved templates become unreadable — the user loses their customization work.

**Why it happens:**
- The current `WatermarkConfiguration` uses `decodeIfPresent` with defaults for most fields (good), but `WatermarkLayer` uses a discriminator pattern (`LayerType` enum with `.text`, `.image`, `.signature` cases). Adding a new layer type (e.g., `.shape`) without a migration path causes old templates to fail on the unknown enum case.
- `Codable` synthesis doesn't handle unknown enum cases gracefully unless you implement custom `init(from:)` with a fallback.
- `AppGroupConfigSync.save()` overwrites the config with the new schema version, but old copies in the Photos extension's `PHAdjustmentData` may still reference the old schema.
- Users may share configs across devices (via iCloud backup) — template version drift between app versions.

**How to avoid:**
1. **Template version field:** Add a `schemaVersion: Int` property to `WatermarkConfiguration`. Current version = 1. Increment on any breaking change.
2. **Migration function:** Implement `WatermarkConfiguration.migrate(from oldVersion: Int)` that transforms v1→v2→v3 etc. Call on decode before using.
3. **`LayerType` fallback in `init(from:)`:** When decoding an unknown `LayerType`, fall back to a `.text` placeholder with the text "[Unknown Layer]" rather than throwing.
4. **`decodeIfPresent` on ALL new fields:** Every new property added to `WatermarkConfiguration`, `WatermarkLayer`, `TextWatermarkInput`, `ImageWatermarkInput`, `WhiteFrameConfig`, etc. MUST use `decodeIfPresent` with a sensible default. Never add a non-optional decoded field.
5. **Template storage format versioning:** Prefix template JSON files with a version header (e.g., `{"schemaVersion": 1, "config": {...}}`). Decode the header first, then pass to the version-appropriate decoder.
6. **Testing:** Maintain a "template museum" — a directory of test fixtures with templates saved in every historical schema version. Unit tests decode each and verify the migration produces a valid config.
7. **`PHAdjustmentData.formatVersion`:** The Photos extension's `PHAdjustmentData(formatIdentifier:formatVersion:data:)` already has a `formatVersion` string. Keep this in sync with `schemaVersion` and use it to select the correct migration path.

**Warning signs:**
- After app update, previously saved templates fail to load (silently returns default config)
- `JSONDecoder.decode` throws `keyNotFound` or `DecodingError.typeMismatch` for old templates
- Photos edit extension can't restore previous edits after app update
- `AppGroupConfigSync.load()` returns `nil` when it previously returned valid configs

**Phase to address:**
Template Management Phase. Must be implemented BEFORE the first template save feature ships — retrofitting migrations after users have data is 3-5x more expensive.

---

### Pitfall 5: App Group Template Sync Race Conditions (Last-Writer-Wins)

**What goes wrong:**
When the main app saves a template and the share extension simultaneously loads or saves a different config, the last writer silently overwrites the other's changes. `AppGroupConfigSync` uses `UserDefaults(suiteName:)` which provides atomic file writes (no corruption) but does NOT provide transactional read-modify-write semantics across processes. If the main app updates the default template setting while the share extension is auto-applying it to an import, the extension may read a partially-updated or stale config.

**Why it happens:**
- `UserDefaults` writes are atomic per-key (the `set(_:forKey:)` call atomically writes the whole plist), but there's no cross-process locking.
- The current `AppGroupConfigSync.save()` is called on every config mutation via `didSet` in the ViewModel. `AppGroupConfigSync.load()` is called on init. If the main app and share extension are both active, they can read/write the same key simultaneously.
- `UserDefaults.didChangeNotification` does NOT fire across processes — the extension can't know the main app wrote a new default template.
- The `WatermarkConfiguration` with image watermark layers contains `Data` blobs (PNG data). Writing large `Data` to `UserDefaults` is slow enough that a window for write overlap exists.

**How to avoid:**
1. **Template storage as individual files:** Store each saved template as a separate JSON file in the App Group container directory (e.g., `Shared/Templates/{uuid}.json`). File-level operations (create, rename, delete) are atomic at the filesystem level.
2. **Template index as a lightweight manifest:** Maintain a `templates.json` manifest file that lists template UUIDs, names, and the UUID of the current default. This file is small and written atomically using `FileManager` with a temp-file → rename pattern (atomic on APFS).
3. **Config sync vs template sync separation:** `AppGroupConfigSync` remains for the current "active" watermark config (settings like last-used position, default text). Templates get a separate `TemplateStore` that operates on the file-based storage.
4. **File coordination for manifest:** Use `NSFileCoordinator` with `NSFilePresenter` when reading/writing the template manifest to prevent cross-process corruption.
5. **Template default marker:** Store the default template UUID as a separate small key in `UserDefaults` (atomic per-key). The manifest file is the source of truth for template contents; the `UserDefaults` key is just a pointer.

**Warning signs:**
- Template list is inconsistent between main app and extension (missing templates)
- Default template changes get "lost" after using the extension
- Template rename/deletion in main app doesn't reflect in extension until next cold launch
- Intermittent failures reading templates — sometimes works, sometimes `nil`

**Phase to address:**
Template Management Phase. Must be architected before any template persistence code is written.

---

### Pitfall 6: UserDefaults Size Limit for Configs With Image Watermark Data

**What goes wrong:**
The current `AppGroupConfigSync` stores the entire `WatermarkConfiguration` (including image watermark PNG `Data` blobs) as a single `UserDefaults` key. When templates are introduced, there's a natural temptation to store the template list similarly. But `UserDefaults` loads the **entire** property list file into memory at app launch. A user with 10 templates, each containing a 2MB logo PNG, causes a 20MB `UserDefaults` plist. This increases cold-launch memory pressure by 20MB per process (main app + extension) and slows `UserDefaults` initialization.

**Why it happens:**
- `UserDefaults` is a flat plist file — `~/Library/Preferences/group.com.watermark.app.plist`. Every key's value is deserialized on first access.
- Image watermark PNG data is stored inline in the `WatermarkConfiguration`'s `ImageWatermarkInput.pngData`. When saved to `UserDefaults`, the entire JSON-encoded config (including the base64-represented PNG blob) is written as one value.
- Developers default to `UserDefaults` because it's simple and already used for config sync. Adding templates to the same storage path seems natural.

**How to avoid:**
1. **Templates as files, not UserDefaults:** Each template is a separate JSON file in `AppGroupContainer/Shared/Templates/`. The manifest is a small index file referencing them by UUID.
2. **Image data in App Group file storage:** Store watermark logo images separately as PNG files in `AppGroupContainer/Shared/Images/{uuid}.png`. Templates reference the UUID, not the raw data.
3. **`AppGroupConfigSync` keeps only the active config:** Reduce the stored config to text-only + references (no inline image data). Image data for the *active* watermark layer is loaded from its template's PNG file at processing time.
4. **Size guard:** On template save, if the combined JSON + image data exceeds 1MB, refuse to save and show a warning. Logos over 1MB are unnecessary for watermark use.

**Warning signs:**
- App launch time increases noticeably after saving 5+ templates
- `UserDefaults` reads become slow (>50ms for a single key)
- Memory usage at launch increases linearly with template count
- `AppGroupConfigSync.load()` call on init blocks the main thread perceptibly

**Phase to address:**
Template Management Phase. File-based storage must be the architecture from the start.

---

### Pitfall 7: PhotosPicker `.loadTransferable` Eager Batch Data Retention

**What goes wrong:**
The current `WatermarkViewModel.handleSelection()` iterates through all selected `PhotosPickerItem`s and calls `item.loadTransferable(type: Data.self)` for each, storing the full `Data` in temp files and keeping `PhotoItem` objects with `sourceURL` references. For a batch of 20 48MP ProRAW photos, this is ~20 × 75MB = 1.5GB of data copied to temp files, plus the memory overhead of decoding each for thumbnail generation. On devices with 4GB RAM, this depletes memory budget before processing even begins.

**Why it happens:**
- The current implementation eagerly loads all items because it was designed for single-item or small selection use. The `maxSelectionCount: 20` was set optimistically without considering the memory implication of 20 ProRAW files.
- `loadTransferable(type: Data.self)` copies the full media data into memory. For ProRAW DNG files that are 75MB each, this is catastrophic at scale.
- The `createThumbnail(from:maxPixelSize:)` call per-item also decodes each image, adding another 10-20MB per image during the import phase.

**How to avoid:**
1. **Lazy loading:** In `handleSelection()`, store `PhotosPickerItem` references (or their `itemIdentifier` strings) in the `PhotoItem` struct. Do NOT load data until the user navigates to that item's preview or processes it. Use `PhotoItem(id:itemIdentifier:mediaType:)` with deferred data loading.
2. **Thumbnail generation from `PhotosPickerItem` directly:** Use `PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)` + `PHImageManager.requestImage(for:targetSize:contentMode:options:)` with `targetSize: CGSize(width: 200, height: 200)` for thumbnails. This avoids loading the full file at all.
3. **Batch import limit:** Reduce `maxSelectionCount` from 20 to 10 for memory safety. Warn user via alert when selecting >10 items.
4. **Streaming copy to temp:** When data MUST be loaded (for processing), use `item.loadFileRepresentation(forTypeIdentifier:)` which provides a URL to a temp copy, then hard-link or copy the file without reading into memory.
5. **Progressive import:** Import thumbnails first (fast, low memory), then show the batch UI. Load full data on-demand per item as the user swipes through the batch.

**Warning signs:**
- Memory spikes to 1.5GB+ during `handleSelection` with 10+ items
- UI freezes for 10-30 seconds during import (all items loading on main actor)
- Jetsam kill occurs before the user sees any UI
- Thumbnail strip takes 5+ seconds to appear after picker dismisses

**Phase to address:**
Batch Processing Phase. Import strategy must be redesigned for scale.

---

### Pitfall 8: Batch Cancellation Leaving Orphaned Temp Files and Partial State

**What goes wrong:**
When a user cancels a batch operation mid-way (e.g., after processing 3 of 10 items), the system leaves behind: (1) temp files for already-processed items that were shared, (2) temp files for the current partially-processed item, (3) source temp files from import, (4) export session resources still holding decoder sessions. Over multiple batch sessions, the caches directory fills with orphaned files, and hardware decoder resources leak.

**Why it happens:**
- The current single-item flow has a clear completion path: process → share → cleanup temp file. In batch, the user may cancel after sharing some items but before processing others.
- `Task.cancel()` cancels the async work but doesn't trigger cleanup of already-written temp files.
- `AVAssetExportSession.cancelExport()` cancels the encoding but the session object and its decoder resources may not be released.
- `TempFileManager.cleanupOldFiles(olderThan: 3600)` only cleans files >1 hour old — files from a cancelled batch 5 minutes ago persist.

**How to avoid:**
1. **Batch session lifecycle:** Create a `BatchSession` actor that tracks all temp files created during a batch operation (source copies, processed outputs). On cancellation or completion, iterate and clean up ALL tracked files.
2. **Cancellation cleanup path:** When cancellation is requested, call `batchSession.cleanupAll()` which deletes every temp file associated with the session, regardless of processing state.
3. **Per-item processing state tracking:** Each item in the batch has a state: `.pending`, `.processing`, `.completed`, `.shared`, `.failed`. Only transition to `.shared` after the share sheet dismisses with a completion. Cleanup `.shared` items immediately after share. Cleanup `.failed` and `.pending` items on batch completion/cancellation.
4. **Resource release on cancel:** When cancelling video export, call `exportSession.cancelExport()`, then set `exportSession = nil`, `composition = nil`, `videoComposition = nil`, and call `await Task.yield()` to allow deallocation.
5. **Aggressive temp file cleanup:** Reduce `TempFileManager` cleanup age from 3600s to 300s (5 minutes) for batch mode. Add a `cleanupAllWatermarkFiles()` that deletes ALL `watermark_*` prefixed files on batch cancellation.

**Warning signs:**
- caches directory grows unboundedly after repeated batch use
- "Storage Almost Full" warnings after batch processing sessions
- App launch progressively slower (checking/staling temp files)
- Video exports start failing with "Cannot Decode" after 2-3 cancelled batches (decoder leak)

**Phase to address:**
Batch Processing Phase. Cleanup strategy is not an afterthought — it's part of the core batch lifecycle design.

---

### Pitfall 9: Per-Item Config Adjustment State Bleeding Across Batch Items

**What goes wrong:**
In batch mode, the user can adjust the watermark config per-item (e.g., different text on photo 3 vs photo 5). If the ViewModel's `config` property is shared across all items without per-item snapshots, navigating back to a previously-configured item shows the *current* config (from the last-edited item), not the config the user set for that specific item.

**Why it happens:**
- The current `WatermarkViewModel` has a single `config: WatermarkConfiguration` property bound to the UI. When the user changes position/text/scale, `config` updates globally.
- For batch, the natural extension is: swipe to item → config shows current state → user changes → config is now different. But when the user swipes back to item 1, config hasn't been saved per-item, so item 1 now shows item 5's config.
- The `didSet { AppGroupConfigSync.save(config) }` saves the last-edited config globally, not per-item.

**How to avoid:**
1. **Per-item config storage:** Store a `[Int: WatermarkConfiguration]` dictionary in the ViewModel, keyed by batch item index. Each item has its own config snapshot.
2. **Config copy-on-switch:** When the user navigates to a new batch item, save the current config to the dictionary for the *previous* index, then load (or initialize from global default) the config for the *new* index.
3. **"Apply to All" action:** Provide a button that copies the current item's config to ALL items in the batch, overwriting their individual configs. This is the primary batch user need — set once, apply everywhere.
4. **Per-item config dirty tracking:** Mark items as `configModified: true` when their config differs from the batch default. Show a visual indicator (e.g., dot on thumbnail) so users know which items have custom configs.
5. **Batch config as a template:** The batch's "base" config is the template/default. Per-item configs are overlays/diffs from the base. On batch start, all items inherit the base. As users customize per-item, the overlay records the diff.

**Warning signs:**
- User sets watermark text on photo 3, swipes to photo 7 and back — photo 3 shows photo 7's text
- Config changes "bleed" across items unpredictably
- "Apply to All" applies unexpected config because the base config drifted
- User frustration: "I already set this!" — indicates state bleeding

**Phase to address:**
Batch Processing Phase. Per-item config state must be part of the batch data model from the start.

---

### Pitfall 10: Template Auto-Apply Race With Import Flow

**What goes wrong:**
When a default template is configured to auto-apply on import, and the user selects multiple items via PhotosPicker, there's a race between: (a) the import flow loading thumbnails and creating `PhotoItem`s, (b) the template auto-apply setting `config` from the template, and (c) the UI rendering the first item's preview. If the template loads after the first preview renders, the user briefly sees the default config, then it snaps to the template config — a visual jank.

**Why it happens:**
- `WatermarkViewModel.init()` loads `AppGroupConfigSync.load()` synchronously, which is correct for initial config. But the "default template" feature loads a *different* config from the template store, which may involve file I/O from the App Group container.
- If template loading is async (file read), the `config` starts as the last-used config, then updates to the template config after I/O completes. This causes a double-render: first with stale config, then with template config.
- For batch, this multiplies: each item's per-item config must be initialized from the template, and if done lazily, the user sees configs pop in one by one.

**How to avoid:**
1. **Template preload on app launch:** Load the default template (if set) in `WatermarkViewModel.init()` BEFORE the first render. Make template loading synchronous (file read is fast for small JSON files).
2. **Template config as the initial state:** If a default template is set, initialize `config` from the template directly instead of from `AppGroupConfigSync.load()`. Only fall back to the last-used config if no default template exists.
3. **Batch initialization with template:** When `handleSelection()` runs, immediately clone the default template config for every item in the batch. Store all per-item configs before the UI renders.
4. **No async template loading for auto-apply:** Template auto-apply MUST be synchronous. The template JSON is <10KB — file read is sub-millisecond. Defer async operations (image data hydration) to background.
5. **Preview suppression during template load:** Set a `isApplyingTemplate = true` flag that suppresses preview generation until all per-item configs are initialized. Show a brief "Applying template..." indicator if needed.

**Warning signs:**
- First preview render shows wrong config for 100-500ms, then snaps to template
- In batch, items flash with default config before template applies
- Template config "flickers" during import
- "Apply to All" sometimes misses the first item (race window)

**Phase to address:**
Template Management Phase. Auto-apply must be synchronous and preloaded.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Storing templates in `UserDefaults` alongside config sync | Zero new storage infrastructure | Template count limits, launch slowdown, memory bloat, race conditions with config sync | Never — templates need file-based storage from day one |
| `maxSelectionCount: 20` without changing import to lazy loading | No code change needed for batch | Memory crashes with 10+ ProRAW photos, import freezes UI for 30+ seconds | Only if batch ships with maxSelectionCount=5 and explicit ProRAW warning |
| Adding template fields to `WatermarkConfiguration` without schema versioning | No migration infrastructure needed | First model change breaks all saved templates irreversibly, user data loss | Never — schema versioning must ship with the first template save |
| Processing batch items in `TaskGroup` for "performance" | Perceived speed gain | Memory explosion, decoder exhaustion, non-deterministic crashes on different devices | Never — serial processing is the only safe approach for media batch |
| Using existing `AppGroupConfigSync` for template list storage | Reuses proven sync mechanism | Template list corruption under concurrent access, last-writer-wins data loss | Never — templates need independent file-based storage |
| Eagerly loading all `PhotosPickerItem` data on selection | Simple, matches current single-item flow | 1.5GB+ memory spike for 20 photos, UI freeze, jetsam kill | Only with maxSelectionCount=1 |
| Skipping batch cancellation cleanup (relying on hourly sweep) | Fewer code paths to test | Orphaned temp files accumulate, decoder resource leaks, storage pressure | Never for a share-oriented app that processes media frequently |

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| **PhotosPicker → Batch ViewModel** | Eager `loadTransferable(type: Data.self)` for all items | Store `PhotosPickerItem` references; load on-demand per item. Use `PHImageManager` for thumbnails. |
| **Batch Processor → WatermarkEngine** | Calling `engine.process()` in a `TaskGroup` with concurrent tasks | Serial `Actor`-based queue. One item at a time. `autoreleasepool` per item. |
| **Video Batch → AVFoundation** | Running multiple `AVAssetExportSession` concurrently or back-to-back without delay | Serial queue with 0.5s inter-export delay. Release all session/composition references between exports. |
| **Template Store → App Group Container** | Reading/writing template manifest without file coordination | Use `NSFileCoordinator` with `NSFilePresenter` for manifest access. Atomic write-via-temp-file pattern. |
| **Default Template → Import Flow** | Async loading of default template after UI renders | Synchronous preload in `ViewModel.init()`. Template JSON is <10KB — file read is instantaneous. |
| **Per-Item Config → Batch UI** | Single shared `config` property mutated in place | Per-item config dictionary `[Int: WatermarkConfiguration]`. Copy-on-switch. "Apply to All" action. |
| **Batch Cancel → Resource Cleanup** | Just `Task.cancel()` without cleanup | `BatchSession` actor tracks all temp files. On cancel: cleanup all, nil out AVFoundation references, yield to system. |
| **Share Extension Batch → Main App** | Trying to process multiple items in the extension | Extension saves file URLs to App Group container, completes immediately. Main app picks up batch processing on next foreground. |

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Parallel batch processing with TaskGroup | Jetsam kill at 3-5 items, inconsistent crash point | Serial processing queue. `maxConcurrentVideoExports = 1`. `autoreleasepool` per item. | Immediate with 48MP photos or 4K video on device |
| 20-item PhotosPicker eager import | 1.5GB memory spike, 30s UI freeze, jetsam kill | Lazy loading: store item references, load on-demand. `maxSelectionCount = 10`. | At ~7 ProRAW or ~12 12MP photos |
| Multiple video exports without resource release | Second export fails with error -11839 "Cannot Decode" | 0.5s delay between exports, explicit nil-out of AV objects | First batch with 2+ videos |
| Growing caches directory from batch temp files | Storage pressure, slow launch | `BatchSession` per-session cleanup. Reduce sweep age to 300s. | After 3-4 batch sessions of 10+ items |
| Template manifest contention under concurrent access | Missing/duplicate templates, default template reset | `NSFileCoordinator` for manifest access. Atomic write-via-temp-file. | When main app and extension are both active (e.g., app in background, extension foreground) |
| `UserDefaults` bloated with template image data | 20MB+ plist, slow launch, memory overhead | Templates as files + image data as separate PNGs. `UserDefaults` for pointers only. | At 5+ templates with 1MB+ logo images |
| Per-item config rebuild on every navigation | Thumbnail strip swipe stutter, 200ms+ lag | Cache rendered previews per item. Invalidate only when config changes. | At 5+ items with complex multi-layer configs |

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Template JSON files executable via malicious file injection | If App Group container is writable by another app with known group ID (unlikely but possible: App Group IDs are discoverable via provisioning profile enumeration), a crafted template JSON could contain script injection if rendered in web views | Validate all template JSON before parsing. Schema-validate against known structure. Reject templates with unexpected keys. |
| Per-item configs exposing previous item's EXIF tokens | If EXIF token substitution (`{camera}`, `{lens}`) in watermark text isn't re-evaluated per item, the watermark on photo 2 may show photo 1's camera model | Re-evaluate ALL EXIF tokens for each item's config just before processing, not at config-set time |
| Batch share extension preserving photo library identifiers across processes | Storing `PHAsset.localIdentifier` in App Group container for cross-process access violates user privacy expectations (the main app may not have photo library access for those specific assets) | Only pass file URLs and `Data` between processes. Never pass `PHAsset.localIdentifier`. Use `PHAsset.fetchAssets` with the identifier only in the process that has explicit photo library authorization |

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| No per-item progress during batch processing | User sees single "Processing..." spinner for 5 minutes with 10 items — doesn't know if it's stuck or progressing | Show "Processing 3 of 10" with per-item progress bar. Show thumbnail of current item being processed. ETA for full batch. |
| Batch processing blocks all UI interaction | User can't cancel, can't preview other items, can't adjust configs for pending items | Allow config editing for PENDING items while current item processes. Only lock the current item's preview. |
| "Apply to All" irreversible without undo | User accidentally applies wrong config to all 20 items, must undo one by one | Snapshot entire batch config before "Apply to All". Provide single "Undo Apply to All" action within 30s. |
| Template delete without "in use" warning | User deletes template that's currently applied to an in-progress batch; configs break silently | Before deleting: check if template is currently applied to any active batch item or set as default. Warn with count of affected items. |
| Batch share from extension shows all items but processes none | User selects 5 photos in Photos app, shares to Watermark, sees UI but can only process 1 (or none) | Extension receives items → shows "Processing {count} items? Open Watermark app to complete." with "Open App" button. |
| Template list in main app doesn't update after extension creates a template | User creates template in extension, opens main app — template missing until cold restart | Use `CFNotificationCenter` Darwin notification to ping the main app when template store changes. Main app refreshes on notification. |
| No "what changed?" on batch preview after config adjustment | User adjusts position on item 4 of 10, then views item 4's thumbnail in the strip — it looks identical because the strip shows source, not watermarked preview | Thumbnail strip should show watermarked preview (low-res, fast render) for each item once its per-item config is set. |

## "Looks Done But Isn't" Checklist

- [ ] **Batch memory safe with ProRAW:** Tested with 10 48MP ProRAW files on iPhone 14 Pro (6GB RAM)? Peak memory < 400MB during entire batch session?
- [ ] **Batch video serialization:** Two consecutive 4K60 videos export without "Cannot Decode" errors? 0.5s delay enforced between exports?
- [ ] **Share extension batch handoff:** 5+ items sent from Photos share sheet → extension appears → items visible → "Open in Watermark" works → main app receives all items?
- [ ] **Template schema migration:** Test fixtures from v1 schema decode successfully after adding new fields? All existing templates survive app update?
- [ ] **Template file storage, not UserDefaults:** Template JSON files are individual files in App Group container? Manifest file written atomically via temp-file → rename?
- [ ] **App Group template sync:** Template created in main app appears in extension within 2 seconds (Darwin notification)? Template deleted in extension is gone from main app?
- [ ] **Per-item config isolation:** Config change on item 3 doesn't affect item 1? "Apply to All" correctly propagates to all items, including previously customized ones?
- [ ] **Batch cancellation cleanup:** Cancel mid-batch (after 4 of 10 processed) → all temp files cleaned? Video decoder resources released? Subsequent batch works without -11839 error?
- [ ] **Default template auto-apply:** Open app with default template set → picker opens → select items → first preview shows template config immediately (no flicker)?
- [ ] **Template delete safety:** Delete template that's the current default → default falls back to last-used config? Delete template applied to active batch item → item falls back to batch base config?
- [ ] **EXIF token per-item evaluation:** Batch of 3 photos from different cameras → watermark text with `{camera}` shows each photo's correct camera model (not first photo's for all)?
- [ ] **Thumbnail strip reflects per-item configs:** After customizing item 3's watermark position, item 3's thumbnail in the strip shows the watermark in the new position (not the batch default)?
- [ ] **Batch export all same format:** All 10 items export in their source format (not all forced to HEIC)? OutputFormat.preserveSource works per-item?
- [ ] **Cancel during video export in batch:** Cancel button works mid-video-export? Remaining items still processable? No orphaned export sessions?
- [ ] **Share without save for batch:** Each shared item goes to share sheet individually? No items saved to camera roll unless user explicitly chooses "Save" from share sheet?

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Parallel batch memory crash | MEDIUM | Convert `TaskGroup` to serial `Actor`-based queue. Add memory budget check before each item. Wrap in `autoreleasepool`. 1-2 day refactor. |
| Template schema migration missing | HIGH | Write migration function from each historical schema version. Build "template museum" test fixtures. Add `schemaVersion` to all Codable types. 3-5 day effort if >1 schema version exists. |
| Templates stored in UserDefaults with image blobs | MEDIUM | Write migration: read all templates from `UserDefaults`, write to individual files, remove `UserDefaults` keys. Update all access points to file-based storage. 1-2 days. |
| App Group template race condition | MEDIUM | Replace `UserDefaults` template list with file-based manifest + `NSFileCoordinator`. Add Darwin notification for cross-process change propagation. 2-3 days. |
| PhotosPicker eager import memory spike | LOW-MEDIUM | Refactor `handleSelection` to store `PhotosPickerItem` references. Add on-demand loading via `PHImageManager`. Rebuild thumbnail strip to use PHImageManager requests. 1-2 days. |
| Batch cancellation resource leak | LOW | Centralize temp file tracking in `BatchSession` actor. Add cleanup-on-cancel path. Reduce sweep age. 0.5-1 day. |
| Per-item config state bleeding | LOW | Add `[Int: WatermarkConfiguration]` dictionary. Copy-on-switch logic. "Apply to All" action. 0.5 day. |
| Default template race with import | LOW | Make template auto-apply synchronous. Preload in `init()`. Suppress preview until applied. 0.5 day. |

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| Parallel batch memory explosion | Batch Processing | Test with 10 48MP ProRAW on iPhone 14 Pro; verify peak memory < 400MB in Instruments |
| AVAssetExportSession decoder exhaustion | Batch Processing (video sub-path) | Two consecutive 4K60 exports pass; no -11839 error on 5 consecutive exports |
| Share extension batch memory crash | Batch Processing (extension sub-path) | 5+ items from Photos share sheet; extension stable; handoff to main app |
| Codable template schema evolution | Template Management | Template museum fixtures from all schema versions decode successfully |
| App Group template sync races | Template Management | Template created in app appears in extension; delete in extension reflected in app |
| UserDefaults template size bloat | Template Management | 10 templates with 2MB logos: launch time unchanged, memory overhead < 5MB |
| PhotosPicker eager batch import | Batch Processing | 10 ProRAW selections: import completes in < 2s, memory < 200MB during import |
| Batch cancellation orphaned files | Batch Processing | Cancel mid-batch: all watermark_* temp files cleaned; caches dir size back to pre-batch level |
| Per-item config state bleeding | Batch Processing | Customize item 3, swipe to item 1 and back to 3: config unchanged; "Apply to All" works correctly |
| Template auto-apply race with import | Template Management | Open app with default template → select items → first preview shows template config (no flicker) |

## Sources

- **Apple Developer Documentation** — `AVAssetExportSession`, `AVMutableComposition`, hardware decoder limits, async export API (developer.apple.com). HIGH confidence.
- **Apple Developer Documentation** — `UserDefaults`, App Group sharing, `NSExtensionActivationRule`, `PHContentEditingController` (developer.apple.com). HIGH confidence.
- **Apple Developer Documentation** — `PhotosPicker`, `PhotosPickerItem`, `Transferable`, `PHImageManager` (developer.apple.com). HIGH confidence.
- **Apple Developer Documentation** — `NSFileCoordinator`, `NSFilePresenter`, atomic file writes (developer.apple.com). HIGH confidence.
- **Stack Overflow** — iOS concurrent `AVAssetExportSession` "Cannot Decode" error -11839; verified by multiple sources across iOS 14-18. HIGH confidence.
- **Kulman.sk (iOS developer blog)** — Share extension memory limits and batch processing strategies (2024). MEDIUM confidence.
- **Cedric Bahirwe (iOS dev blog)** — PhotosPicker multiple image memory management patterns (2025). MEDIUM confidence.
- **Swift by Sundell** — Codable backward compatibility strategies for evolving data models (2024). MEDIUM confidence.
- **Merowing.info** — Codable schema versioning and migration techniques (2024). MEDIUM confidence.
- **Christian Selig (Apollo dev)** — App Group communication patterns, Darwin notifications for cross-process sync (2024). MEDIUM confidence.
- **Community discussions (Reddit r/iOSProgramming, r/swift)** — Batch processing memory crashes, template persistence, App Group races. MEDIUM confidence (consistent patterns across multiple threads).
- **Existing codebase analysis** — `WatermarkViewModel.handleSelection()` eager loading, `AppGroupConfigSync` single-key pattern, `VideoProcessor` export session lifecycle, `WatermarkConfiguration` Codable design. HIGH confidence (direct code inspection).
- **Apple WWDC sessions** — "What's new in Photos" (2024), "Supporting HDR images in your app" (2024), "Modernizing your app for iOS 18" (2024). HIGH confidence.

---

*Pitfalls research for: iOS Photo/Video Watermarking App — Batch Processing, Template Management, Process Hardening*
*Researched: 2026-06-19*
