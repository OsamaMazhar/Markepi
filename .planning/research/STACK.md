# Stack Research: v2.0 Batch, Templates & Process

**Domain:** iOS Photo/Video Watermarking App — Batch Processing, Template Management, Process Hardening
**Researched:** 2026-06-19
**Confidence:** HIGH

## Recommended Stack

### New Additions (v2.0)

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| **PhotosPicker (multi-select)** | iOS 18 SDK | Batch media import | Already in use (`maxSelectionCount: 20`). Increase to `0` for unlimited batch selection. No new framework needed — PhotosPicker handles multi-select natively via `selection: Binding<[PhotosPickerItem]>`. Live Photo pair detection (`detectLivePhotoPairs`) already handles mixed photo/video batches. |
| **Swift Concurrency `TaskGroup`** | Swift 6 | Parallel batch processing | `withThrowingTaskGroup(of:returning:body:)` processes multiple media items concurrently with built-in cancellation propagation. Throttle to 3–4 concurrent tasks to prevent memory pressure (each watermarking operation loads a full-res CIImage into GPU memory). **Already in Swift 6 stdlib — no dependency.** |
| **`Foundation.Progress`** | iOS 18 SDK | Batch progress tracking | Parent-child `Progress` hierarchy: parent tracks `N` items, each child tracks per-item export (0.0–1.0). Parent's `fractionCompleted` auto-aggregates from children. Bridge to SwiftUI via `@Observable @MainActor` wrapper with KVO (`progress.observe(\.fractionCompleted)`). **No dependency — Foundation built-in.** |
| **`FileManager` App Group container** | iOS 18 SDK | Template JSON persistence | Store each template as a separate `.json` file in `{AppGroupContainer}/templates/`. Uses the existing App Group (`group.com.watermark.app`) configured for the main app and Share Extension. `Codable` serialization via `JSONEncoder`/`JSONDecoder`. No new framework. |
| **`UserDefaults(suiteName:)`** | iOS 18 SDK | Default template reference | Single string key `"defaultTemplateID"` in existing `AppGroupConfigSync.suiteName` UserDefaults suite. Already used for `watermarkConfiguration` blob — just add one more key. No new setup needed. |

### Existing Stack (Unchanged — Confirmed Compatible)

| Technology | Version | v2.0 Relevance |
|------------|---------|----------------|
| **Swift** | 6.x (Xcode 18) | Strict concurrency checking ensures batch `TaskGroup` code is data-race free |
| **SwiftUI** | iOS 18 SDK | Batch UI (grid of thumbnails, progress overlay) uses existing `@Observable` pattern |
| **WatermarkCore Swift Package** | — | New `TemplateStore`, `BatchProcessor`, `BatchProgressTracker` added here. Both targets consume it. |
| **App Groups capability** | — | Template JSON files + default template ID shared via existing `group.com.watermark.app` |
| **AVFoundation** | iOS 18 SDK | Video batch processing reuses existing `VideoProcessor` with CALayer overlay |
| **Core Image** | iOS 18 SDK | Photo batch processing reuses existing `WatermarkEngine.process(sourceURL:config:)` |
| **ImageIO** | iOS 18 SDK | Metadata/HDR preservation unchanged — one-at-a-time per-item pipeline |

### Supporting Libraries

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| — _(none)_ | — | — | No third-party libraries needed. All batch processing, template persistence, and progress tracking are covered by Apple system frameworks. Adding third-party deps would violate the privacy constraint (on-device only, no network calls). |

### Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| **Xcode 18** | IDE | Already configured for iOS 18 SDK, Swift 6. No changes needed. |
| **Swift Testing** | Unit + integration tests | Test `TemplateStore` CRUD, `BatchProcessor` concurrency, `ProgressTracker` KVO bridge. |
| **Instruments (Allocations, Leaks)** | Memory profiling | **Critical for batch** — verify memory pressure stays flat during 10+ item batch processing. Watch for GPU memory accumulation from concurrent CIContext renders. |
| **exiftool** (CLI) | Metadata validation | Verify per-item metadata preservation in batch output (no cross-contamination between items). |
| **Xcode Previews** | SwiftUI iteration | Preview template list UI, batch thumbnail grid, progress overlay without building to device. |

## Installation

```
# No new dependencies. All additions use existing Apple frameworks.
# Project changes:
# 1. Add TemplateStore.swift → WatermarkCore/Sources/WatermarkCore/Storage/
# 2. Add WatermarkTemplate.swift → WatermarkCore/Sources/WatermarkCore/Models/
# 3. Add BatchProcessor.swift → WatermarkCore/Sources/WatermarkCore/Processing/
# 4. Add BatchProgressTracker.swift → WatermarkCore/Sources/WatermarkCore/UI/
# 5. Update ContentView.swift: maxSelectionCount → 0 for batch mode
# 6. Update WatermarkViewModel: add batch processing state + template methods
# 7. Update ShareExtensionViewModel: add template loading
```

## Alternatives Considered

| Recommended | Alternative | Why Not |
|-------------|-------------|---------|
| **JSON files in App Group container** for template persistence | **SwiftData** (`@Model` + `ModelContainer`) | SwiftData requires SQLite store, migration management, `ModelContainer` initialization overhead, and shared container URL configuration. For storing ~dozens of small `WatermarkConfiguration` JSON blobs (each <10KB), a full ORM is architectural overkill. SwiftData also carries the risk of schema migration failures when `Codable` structs change — JSON files degrade gracefully (decode failure → skip file). |
| **JSON files in App Group container** | **Core Data** (`NSManagedObjectModel`) | Even more overkill than SwiftData. Requires `.xcdatamodeld` file, `NSPersistentContainer`, manual `NSManagedObject` subclasses, and merge policy configuration for cross-target access. Adds ~500+ lines of boilerplate for simple CRUD. |
| **UserDefaults for ALL templates** | JSON files in App Group container | UserDefaults stores a single `WatermarkConfiguration` blob (`watermarkConfiguration` key). Storing multiple templates as separate UserDefaults keys requires UUID-prefixed key management, has no directory listing (can't enumerate templates), and risks hitting the UserDefaults plist size limit. JSON files in a `templates/` subdirectory give free enumeration via `FileManager.contentsOfDirectory`. |
| **`TaskGroup` with throttling** (max 3–4 concurrent) | **Unlimited `TaskGroup`** (one task per item) | Processing 20 full-resolution photos in parallel would allocate 20 CIContext-backed CIImage objects simultaneously, risking OOM crashes on devices with <6GB RAM. Throttling to 3–4 concurrent tasks keeps memory pressure predictable. |
| **`TaskGroup` with throttling** | **Serial processing** (one-at-a-time `for` loop) | Serial processing leaves 5+ CPU cores idle on modern iPhones. A16+ chips have 6 cores — batch watermarking is CPU-bound (CIFilter compositing + CGImageDestination encode), so parallel processing yields 2–3× throughput improvement. |
| **`Progress` parent-child hierarchy** | **Custom actor-based progress tracking** | `Progress` auto-aggregates child completion into parent `fractionCompleted`. Custom actor requires manual math, race-condition handling, and doesn't integrate with `ProgressView`'s `observedProgress` binding. `Progress` is the system-standard approach. |
| **`@Observable @MainActor` KVO bridge** for Progress | **`@unchecked Sendable`** on Progress wrapper | `@unchecked Sendable` silences Swift 6 warnings but provides no actual thread safety. The KVO bridge with `@MainActor` isolation is the safe-by-default approach. |

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| **SwiftData** for template persistence | ORM overhead for ~dozens of small JSON configs. Schema migration complexity. Shared container configuration adds failure points. Violates "simplest thing that works" principle. | JSON files in App Group container `templates/` directory + `Codable` serialization |
| **Core Data** for template persistence | Massive boilerplate (`.xcdatamodeld`, `NSPersistentContainer`, merge policies). No benefit over JSON files for this data shape. | JSON files in App Group container |
| **Third-party database libraries** (Realm, Firebase, GRDB) | Add dependency risk, often have networking components (violates privacy constraint), and are unnecessary for local-only config storage. | Apple FileManager + Codable |
| **`UIImage` intermediate representation** in batch pipeline | Converts to/from `UIImage` strips EXIF, color profile, and HDR gain maps. The existing `CGImageSource → CIImage → CGImageDestination` pipeline must be preserved per-item. | Existing `WatermarkEngine.process(sourceURL:config:)` pipeline |
| **`AVAssetWriter`** for batch video | More complex than `AVAssetExportSession + CALayer` overlay. Not needed for watermark compositing (no per-frame Metal shader logic). | Existing `VideoProcessor` with `AVAssetExportSession` |
| **`@unchecked Sendable`** on Progress wrappers | Silences compiler but provides no actual thread safety. Data races on `fractionCompleted` would cause UI glitches. | `@MainActor` `@Observable` class with KVO bridge |
| **Cloud sync** for templates | Violates privacy constraint (no network calls). Templates are device-local configuration. | App Group container for cross-target local sync only |
| **Batch save to camera roll** | Core product anti-feature — clutters library. The "watermark and share" value proposition applies to batch too. | Batch export to temp directory → share sheet per item → cleanup |
| **Real-time preview for ALL batch items** | Rendering full-res previews for 20+ items would consume GPU memory equivalent to 20× the pipeline. | Thumbnail grid from ImageIO downsampling (already in use: `createThumbnail(maxPixelSize: 200)`) |

## Stack Patterns by Variant

### Batch Photo Processing

```
For each item in batch (via throttled TaskGroup, max 3 concurrent):
  1. await engine.process(sourceURL: itemURL, config: config)  // reuse shared config
  2. Attach child Progress(totalUnitCount: 100, parent: batchProgress, pendingUnitCount: 1)
  3. Report per-item progress via child.completedUnitCount
  4. Collect ProcessingResult → temp file URL
  5. Present share sheet for each item OR collect all for batch share
  6. Cleanup temp files after sharing
```

### Batch Video Processing

```
For each video in batch (serial processing recommended — video export is already GPU-saturated):
  1. await engine.processVideo(sourceURL: itemURL, config: config, onProgress: { ... })
  2. Map video's own onProgress callback → child Progress
  3. Collect ProcessingResult + videoValidation
  4. Schedule background notification per item (reuse existing VIDX-03 pattern)
```

### Template CRUD

```
Load all templates:
  - Enumerate {AppGroupContainer}/templates/*.json
  - Decode each as WatermarkTemplate via JSONDecoder
  - Sort by createdAt (newest first)
  - Mark isDefault via UserDefaults "defaultTemplateID" match

Save template:
  - Assign UUID, name, createdAt
  - Encode as JSON → write to templates/{uuid}.json with .atomic option
  - If marked isDefault, update UserDefaults "defaultTemplateID"

Delete template:
  - Remove templates/{uuid}.json
  - If was default, clear UserDefaults "defaultTemplateID"

Rename template:
  - Decode existing file → modify name → re-encode → write .atomic

Auto-apply default on import:
  - On media import: check UserDefaults "defaultTemplateID"
  - If exists and template file found: decode → set as current config
  - If not found: fall back to built-in default config
```

### Progress Tracking

```
Create parent Progress(totalUnitCount: batchSize)

For each batch item:
  let child = Progress(totalUnitCount: 100, parent: parent, pendingUnitCount: 1)
  // For video: bridge existing onProgress callback to child.completedUnitCount
  // For photo: set child.completedUnitCount = 100 when engine.process completes

@Observable @MainActor wrapper:
  class BatchProgressTracker {
      var fractionCompleted: Double = 0.0
      private var progress: Progress?
      private var observer: NSKeyValueObservation?

      func startTracking(_ progress: Progress) {
          self.progress = progress
          observer = progress.observe(\.fractionCompleted, options: [.new]) { [weak self] p, _ in
              Task { @MainActor in self?.fractionCompleted = p.fractionCompleted }
          }
      }
  }

SwiftUI:
  ProgressView(value: tracker.fractionCompleted)
```

### Template Sync Across Targets

```
App Group container (group.com.watermark.app):
  /templates/
    {uuid1}.json  ← WatermarkTemplate (name + WatermarkConfiguration)
    {uuid2}.json
    ...

UserDefaults(suiteName: "group.com.watermark.app"):
  "watermarkConfiguration" → Data (current config — existing, unchanged)
  "defaultTemplateID" → String (UUID of default template — NEW)

Both targets (Main App and ShareExtension) read from
the same App Group container — no additional sync mechanism needed.
Changes in one target are immediately visible to others via FileManager.
```

## Version Compatibility

| Component | Minimum iOS | v2.0 Notes |
|-----------|-------------|------------|
| `PhotosPicker` multi-select | iOS 16 | Already in use. `maxSelectionCount: 0` (unlimited) works from iOS 16. |
| `TaskGroup` (`withThrowingTaskGroup`) | iOS 15 (Swift 5.5+) | Available since Swift Concurrency introduction. Full maturity in Swift 6. |
| `Progress` parent-child | iOS 8+ | Foundation class, stable across all iOS versions. |
| `NSKeyValueObservation` | iOS 11+ | Used for Progress → @Observable KVO bridge. Available since iOS 11. |
| `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)` | iOS 8+ | Already in use for App Group access. |
| `JSONEncoder`/`JSONDecoder` | iOS 8+ (Foundation) | Already in use for `WatermarkConfiguration` Codable. |
| `@Observable` macro | iOS 17 | Already the project's state management pattern. |

**Target: iOS 18 minimum (unchanged).** All v2.0 additions work on iOS 16+ (some iOS 15+). No minimum deployment target change needed.

## Integration Points with Existing Architecture

### New Files in WatermarkCore Swift Package

```
Packages/WatermarkCore/Sources/WatermarkCore/
  Storage/
    TemplateStore.swift          ← NEW: actor for template CRUD
    AppGroupConfigSync.swift     ← MODIFIED: add defaultTemplateID key
  Models/
    WatermarkTemplate.swift      ← NEW: template model (Codable)
    WatermarkConfiguration.swift ← UNCHANGED: already Codable
  Processing/
    BatchProcessor.swift         ← NEW: actor for batch orchestration
  UI/
    BatchProgressTracker.swift   ← NEW: @Observable Progress wrapper
```

### Integration into 2 Targets

| Target | Integration Point | What Changes |
|--------|-------------------|--------------|
| **Main App** | `WatermarkViewModel` | Add `batchMode: Bool`, `templates: [WatermarkTemplate]`, `TemplateStore` reference, batch `handleSelection` with TaskGroup, template save/load/delete/rename methods |
| **ShareExtension** | `ShareExtensionViewModel` | Add template loading (read from App Group), auto-apply default template on share import |

### No Changes to Existing Engine

The `WatermarkEngine` actor (`process`, `processVideo`, `processLivePhoto`) is called per-item — same as current single-item flow. Batch processing is purely ViewModel-level orchestration:

```
BatchProcessor (ViewModel level)
  → for each item in throttled TaskGroup:
      → WatermarkEngine.shared.process(sourceURL: itemURL, config: config)
      → returns ProcessingResult per item
      → update Progress
```

The engine is already `actor`-isolated and `Sendable`-safe — concurrent calls from TaskGroup are naturally serialized by the actor, preventing race conditions on the shared `CIContext`.

### Memory Safety in Batch

| Concern | Mitigation |
|---------|-----------|
| GPU memory from concurrent CIContext renders | Throttle to max 3 concurrent tasks. Each `process()` call uses the shared `CIContext` (actor-isolated), so only 3 CIImage graphs exist simultaneously. |
| Temp file accumulation | `TempFileManager.cleanupOldFiles(olderThan: 3600)` already runs on engine init. Per-item cleanup after sharing. |
| Video export memory | Video processing is serial in batch mode (AVAssetExportSession already saturates media engine). |
| Full-res image retention | `PhotoItem` stores thumbnail (ImageIO-downsampled, <200px) and `sourceURL`. Full-res CIImage is scoped to the `process()` call and released when the `TaskGroup` child task completes. |

## Sources

- Apple Developer Documentation — `Progress`, `withThrowingTaskGroup`, `FileManager.containerURL`, `PhotosPicker`, `NSKeyValueObservation`
- Apple Developer — Swift Concurrency: `TaskGroup` and structured concurrency (Swift 5.5+)
- Apple Developer — "What's new in SwiftUI" (WWDC24) — `@Observable` macro and Swift 6 strict concurrency
- Swift Evolution SE-0414 — Region-based isolation for Swift 6 Sendable checking
- Multiple sources (2025–2026) — SwiftData is overkill for simple Codable config persistence; JSON files + App Group container are the industry-standard approach for cross-target iOS app configuration
- Kodeco (formerly raywenderlich.com) — Batch photo loading with PhotosPicker + TaskGroup patterns
- Swift.org — `withThrowingTaskGroup` documentation and cancellation semantics
- Stack Overflow, Apple Developer Forums — Community-validated pattern for bridging NSProgress KVO to @Observable in Swift 6
- Apple Developer Forums — App Group container file coordination patterns; `NSFileCoordinator` for cross-process access (optional — our single-writer pattern avoids contention)

---

*Stack research for: v2.0 Batch Processing, Template Management, Process Hardening*
*Researched: 2026-06-19*
