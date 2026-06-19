# Architecture Research: Batch Processing, Template Management & Process Hardening

**Domain:** iOS Photo/Video Watermarking — v2.0 Feature Integration
**Researched:** 2026-06-19
**Confidence:** HIGH
**Based on:** v1.0 + v1.1 shipped codebase (13,820 lines, 82+ files, 233 tests)

## Executive Summary

The v2.0 milestone adds three feature clusters to an already-shipped iOS watermarking app:
1. **Batch processing** — watermarking multiple photos/videos with shared config + per-item adjustments
2. **Template management** — CRUD for saved watermark configurations + auto-default on import
3. **Process hardening** — per-phase VERIFICATION.md templating + worktree-safety fix

The existing architecture (WatermarkCore Swift Package → 3 targets, App Group sync, actor-based WatermarkEngine, `WatermarkConfigurable` protocol with default implementations) provides strong foundations for all three. No existing component needs to be broken — integration is additive.

**The key architectural insight:** Template management is a new data concern (persisted named configurations) that lives in WatermarkCore for cross-target access. Batch processing is a new orchestration concern (sequential multi-item processing with progress aggregation) that also lives in WatermarkCore but is primarily driven by the main app's ViewModel. Process hardening is a GSD tooling concern that does not affect app architecture at all — it modifies scripts and GSD workflow files.

## New Components

### 1. WatermarkTemplate (Model — WatermarkCore)

```swift
/// A named, persisted watermark configuration used across sessions.
/// Stored as JSON in the App Group container for cross-target access.
public struct WatermarkTemplate: Codable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var config: WatermarkConfiguration
    public let createdAt: Date
    public var updatedAt: Date
}
```

**Why a new model instead of reusing WatermarkConfiguration:** WatermarkConfiguration is the config itself — it has no name, no identity, no creation metadata. Templates add a persistence wrapper: name for UI display, UUID for stable identification across renames, and timestamps for sorting. The config field IS a WatermarkConfiguration — no duplication.

**Codable compatibility:** WatermarkConfiguration, WatermarkLayer, WhiteFrameConfig, and all nested types are already fully Codable. WatermarkTemplate adds no new serialization complexity — just a wrapper around existing Codable types.

### 2. TemplateStore (Storage — WatermarkCore)

```swift
/// CRUD store for WatermarkTemplate instances persisted as a single JSON file
/// in the App Group shared container.
///
/// Uses file-based storage (one JSON dictionary file) rather than UserDefaults
/// because:
/// - CRUD operations on a list are awkward with UserDefaults key-per-template
/// - File-based approach enables atomic read-modify-write for rename/delete
/// - Single file is easier to inspect during development
public struct TemplateStore {
    public static let shared = TemplateStore()
    
    private let storeURL: URL  // App Group container + "templates.json"
    
    // CRUD
    public func save(_ template: WatermarkTemplate) throws
    public func loadAll() -> [WatermarkTemplate]
    public func load(id: UUID) -> WatermarkTemplate?
    public func update(_ template: WatermarkTemplate) throws   // rename, modify config
    public func delete(id: UUID) throws
    
    // Default template
    public var defaultTemplateID: UUID?     // persisted in UserDefaults(suiteName:)
    public func defaultTemplate() -> WatermarkTemplate?
}
```

**Storage location:** `{AppGroupContainer}/Library/Application Support/templates.json`. The App Group container is already wired (all 3 targets have the entitlement). `UserDefaults(suiteName:)` stores only the `defaultTemplateID` pointer — the actual template data lives in the JSON file.

**Why not AppGroupConfigSync:** AppGroupConfigSync is designed for a single "current config" key-value pair. TemplateStore is a CRUD list manager. They coexist in WatermarkCore but serve different concerns. When the user loads a template, the flow is: TemplateStore.load(id) → assign to WatermarkConfiguration → AppGroupConfigSync.save(config) as normal.

### 3. BatchProcessor (Processing — WatermarkCore)

```swift
/// Actor-isolated batch processing coordinator.
///
/// Processes multiple media items sequentially with a shared watermark
/// configuration, reporting aggregate progress and collecting results.
/// Sequential processing avoids memory pressure from concurrent
/// video exports (each export already uses AVAssetWriter streaming).
public actor BatchProcessor {
    public static let shared = BatchProcessor()
    
    private let engine = WatermarkEngine.shared
    
    /// Result for a single item in a batch.
    public struct BatchItemResult: Sendable {
        public let itemIndex: Int
        public let processingResult: ProcessingResult
    }
    
    /// Progress reported during batch processing.
    public struct BatchProgress: Sendable {
        public let currentItemIndex: Int
        public let totalItems: Int
        public let currentItemProgress: Double?  // 0-1, nil for photos (fast)
        public let estimatedTotalTimeRemaining: TimeInterval?
    }
    
    /// Processes all items in the batch sequentially.
    /// - Parameters:
    ///   - items: Array of media item descriptors (URL + type + optional per-item config override)
    ///   - sharedConfig: Base watermark configuration applied to all items
    ///   - onProgress: Called after each item completes and during video exports
    /// - Returns: Array of results (one per successfully processed item)
    /// - Throws: Only if ALL items fail; partial failures are returned in results
    public func process(
        items: [BatchItem],
        sharedConfig: WatermarkConfiguration,
        onProgress: (@Sendable (BatchProgress) -> Void)?
    ) async throws -> [BatchItemResult]
    
    /// Cancels in-progress batch processing.
    public func cancel()
}
```

```swift
/// Descriptor for a single item in a batch.
public struct BatchItem: Sendable, Identifiable {
    public let id: UUID
    public let sourceURL: URL
    public let mediaType: WatermarkEngine.MediaType
    /// Optional per-item config override. Merged with sharedConfig
    /// during processing (override takes precedence for set fields).
    public let configOverride: PerItemConfigOverride?
}

/// Per-item adjustments that overlay on top of the shared batch config.
/// Only non-nil fields override; nil means "use shared config value."
public struct PerItemConfigOverride: Sendable, Codable {
    public var customText: String?
    public var position: WatermarkPosition?
    public var scale: CGFloat?
    public var outputFormat: OutputFormat?
    /// Allows the user to toggle white frame per item.
    /// true = force enabled, false = force disabled, nil = use shared config.
    public var whiteFrameEnabled: Bool?
}
```

**Why sequential not concurrent:** Video exports already consume significant GPU/encoder resources. Concurrent exports would cause thermal throttling, iOS jetsam termination, and unpredictable export times. Sequential processing lets each export complete before the next begins, with accurate progress reporting.

**PerItemConfigOverride design:** Rather than passing a full WatermarkConfiguration per item (which duplicates layers, output settings, etc.), per-item overrides are a lightweight struct. The most common batch scenario is: "same watermark, but each photo might need the text adjusted" or "same watermark, but this one video shouldn't have a white frame." Overrides cover these cases without config duplication. The merge is: `sharedConfig` with `override` fields replacing only the non-nil values.

### 4. BatchViewModel (ViewModel — Main App Only)

```swift
/// ViewModel for the batch processing flow in the main app.
///
/// Extends the single-item WatermarkViewModel with batch orchestration:
/// - Manages multi-item selection (already supported via PhotosPicker)
/// - Holds shared config + per-item overrides
/// - Coordinates batch processing via BatchProcessor
/// - Presents batch progress UI and batch share sheet
@Observable @MainActor
final class BatchViewModel {
    var items: [BatchItem] = []
    var sharedConfig: WatermarkConfiguration
    var perItemOverrides: [UUID: PerItemConfigOverride] = [:]
    var batchProgress: BatchProcessor.BatchProgress?
    var batchResults: [BatchProcessor.BatchItemResult] = []
    var batchState: BatchState = .idle
    
    enum BatchState {
        case idle
        case configuring    // User is reviewing/adjusting per-item configs
        case processing(BatchProcessor.BatchProgress)
        case completed
        case cancelled
        case error(Error)
    }
    
    func startBatch() async
    func cancelBatch()
    func shareResults()
}
```

**Why main app only:** The share extension and Photos edit extension are fundamentally single-item workflows. The share extension receives one item at a time (its multi-item flow is sequential one-at-a-time, not batch). The Photos edit extension edits one asset at a time. Batch processing is a main-app-only feature.

### 5. Template Management UI (Views — Main App Only)

New SwiftUI views in `App/Views/Templates/`:
- `TemplateListView` — Lists saved templates with swipe-to-delete
- `TemplateEditorView` — Name/rename a template
- `TemplateSaveView` — "Save current config as template" sheet with name input
- `TemplatePickerView` — Grid of templates for quick load (triggered from ControlsView)

These views consume `TemplateStore` directly. They are main-app-only because template management (saving, renaming, deleting, setting defaults) is a management operation, not a processing operation. Extensions only need to load templates (via TemplateStore.loadAll()) to apply them; they don't need management UI.

## Modified Components

### 1. WatermarkConfigurable Protocol Extension

**Adds:**
```swift
extension WatermarkConfigurable {
    // Template operations (new default implementations)
    public func applyTemplate(_ template: WatermarkTemplate) {
        config = template.config
        // If template has image watermark layers, their PNG data is already in the config.
        // No rehydration needed — WatermarkTemplate stores the full config, not stripped.
    }
    
    public func loadTemplates() -> [WatermarkTemplate] {
        (try? TemplateStore.shared.loadAll()) ?? []
    }
}
```

`applyTemplate` is a one-liner: set `config = template.config`. The existing `didSet { AppGroupConfigSync.save(config) }` in all 3 ViewModels handles cross-target sync automatically. This means loading a template in the main app immediately syncs to the share extension and Photos extension via the existing mechanism.

### 2. All 3 ViewModels — Auto-Default on Import

**Modified:** `WatermarkViewModel.handleSelection()`, `ShareExtensionViewModel.loadSharedMedia()`, `PhotosExtensionViewModel.startEditing()`

After loading media (but before generating preview), each ViewModel checks for a default template:

```swift
// Pseudo-code added to each ViewModel's media import path
if let defaultTemplate = TemplateStore.shared.defaultTemplate() {
    config = defaultTemplate.config
    // AppGroupConfigSync.save(config) fires via didSet
}
```

This is a 3-line addition in each ViewModel's import path. The `didSet` on `config` handles sync automatically.

### 2. WatermarkViewModel — Batch Mode Selection

The existing `WatermarkViewModel.handleSelection(_ items:)` already supports multi-select (it loads all selected `PhotosPickerItem`s into the `photos` array). For batch mode, when multiple items are selected, the ViewModel presents a "Configure Batch" mode instead of the single-item config flow. The existing `currentIndex` navigation via thumbnail strip becomes the per-item adjustment browser.

### 3. PhotoItem — No Change Needed

The existing `PhotoItem` struct already carries `sourceURL`, `videoSourceURL`, and `mediaType`. Batch processing maps `[PhotoItem]` → `[BatchItem]` with optional per-item overrides stored separately (in a `[UUID: PerItemConfigOverride]` dictionary keyed by PhotoItem.id). This avoids modifying the existing model.

## Data Flow Changes

### Template Flow
```
User opens template list → TemplateListView { templates: TemplateStore.loadAll() }
    ↓
User taps "Save Current" → TemplateSaveView(initialName: "")
    ↓ captures config from ViewModel
    → TemplateStore.save(WatermarkTemplate(name: "My Preset", config: currentConfig))
    → writes to App Group container JSON file
    ↓
User taps template → TemplateStore.load(id:)
    → ViewModel.config = template.config
    → AppGroupConfigSync.save(config)  (via existing didSet)
    ↓
User sets as default → TemplateStore.defaultTemplateID = template.id
    → UserDefaults(suiteName:).set(id.uuidString, forKey: "defaultTemplateID")
    ↓
On next media import → defaultTemplateID? → TemplateStore.load(id) → auto-apply config
```

### Batch Processing Flow
```
User selects 5 photos via PhotosPicker → WatermarkViewModel.handleSelection(items)
    ↓ photos array now has 5 items
    ↓ ViewModel detects batch mode (count > 1)
    ↓ Presents "Configure Batch" UI with shared config
    ↓
User configures shared watermark (text, position, white frame, etc.)
    ↓ config is the "base" applied to all items
    ↓
[Optional] User browses individual items via thumbnail strip
    ↓ tap item → see per-item override controls
    ↓ adjust text, toggle white frame for this specific item
    ↓ store in perItemOverrides[item.id]
    ↓
User taps "Process Batch" → WatermarkViewModel.startBatch()
    ↓
BatchProcessor.process(items: batchItems, sharedConfig: config, onProgress:)
    ↓ For each BatchItem:
    ↓   1. Merge sharedConfig with PerItemConfigOverride (if any)
    ↓   2. Detect media type (photo vs video)
    ↓   3. engine.process(sourceURL:config:) or engine.processVideo(sourceURL:config:onProgress:)
    ↓   4. Collect ProcessingResult
    ↓   5. Report BatchProgress(currentItemIndex, totalItems, currentItemProgress)
    ↓
All items processed → batchResults = [BatchItemResult]
    ↓
User taps "Share All" → presents UIActivityViewController for first result
    ↓ on dismiss → presents for next result (sequential sharing)
    ↓ OR presents combined share for all results (single share sheet with multiple URLs)
    ↓
TempFileManager cleanup after all shares complete
```

### Template + Batch Integration
```
User selects 10 photos → auto-default template applied to all
    ↓ watermark config pre-populated from default template
    ↓
User adjusts text for items 3 and 7 (different caption text per photo)
    ↓ perItemOverrides[3].customText = "© Alice Photography"
    ↓ perItemOverrides[7].customText = "© Alice Photography (2026)"
    ↓
BatchProcessor merges per-item on processing
```

## Architectural Boundaries

### What Lives in WatermarkCore (Shared)
| Component | Purpose |
|-----------|---------|
| `WatermarkTemplate` (Model) | Codable template struct |
| `PerItemConfigOverride` (Model) | Codable per-item override struct |
| `BatchItem` (Model) | Batch item descriptor |
| `TemplateStore` (Storage) | CRUD operations on templates JSON file |
| `BatchProcessor` (Processing) | Actor for batch orchestration |
| `BatchProcessor.BatchProgress` | Progress reporting struct |
| `BatchProcessor.BatchItemResult` | Per-item result struct |
| `WatermarkConfigurable.applyTemplate(_:)` | Protocol default implementation |

### What Lives in Main App Target Only
| Component | Purpose |
|-----------|---------|
| `BatchViewModel` | Batch mode ViewModel |
| `TemplateListView` | Template list UI |
| `TemplateSaveView` | Save template sheet |
| `TemplatePickerView` | Quick-template grid |
| `TemplateEditorView` | Template rename sheet |
| Template-related `@State` in ContentView | Show template sheet flags |

### What Lives in Extensions (Minimal Changes)
| Target | Change | Rationale |
|--------|--------|-----------|
| ShareExtensionViewModel | +3 lines for auto-default check on import | Templates should apply in extensions too |
| PhotosExtensionViewModel | +3 lines for auto-default check on import | Templates should apply in extensions too |
| ShareExtensionRootView | No changes | Template management is main app only |
| PhotosExtensionRootView | No changes | Template management is main app only |

## Build Order (Dependency Graph)

```
                              ┌─────────────────────────┐
                              │   PHASE 1: Templates    │  ← Foundation
                              │   (CUST-01 through      │
                              │    CUST-04)              │
                              │                         │
                              │  WatermarkCore:         │
                              │  - WatermarkTemplate     │
                              │  - TemplateStore         │
                              │  - applyTemplate default │
                              │                         │
                              │  All 3 ViewModels:      │
                              │  - auto-default on import│
                              │                         │
                              │  Main App:              │
                              │  - TemplateListView      │
                              │  - TemplateSaveView      │
                              │  - TemplatePickerView    │
                              │  - TemplateEditorView    │
                              └───────────┬─────────────┘
                                          │
                                          │ Templates provide
                                          │ default config for
                                          │ batch items
                                          ▼
                              ┌─────────────────────────┐
                              │   PHASE 2: Batch         │  ← Depends on templates
                              │   (BATC-01, BATC-02)     │
                              │                         │
                              │  WatermarkCore:         │
                              │  - BatchItem             │
                              │  - PerItemConfigOverride │
                              │  - BatchProcessor         │
                              │                         │
                              │  Main App:              │
                              │  - BatchViewModel        │
                              │  - Batch config UI       │
                              │  - Batch progress UI     │
                              │  - Batch share flow      │
                              │                         │
                              │  WatermarkViewModel:     │
                              │  - batch mode branching  │
                              └───────────┬─────────────┘
                                          │
                                          │ Independent
                                          ▼
                              ┌─────────────────────────┐
                              │   PHASE 3: Process       │  ← Independent
                              │   Hardening               │
                              │   (PHRO-01, PHRO-02)     │
                              │                         │
                              │  GSD tooling only:      │
                              │  - VERIFICATION.md tmpl  │
                              │  - worktree-safety fix   │
                              │                         │
                              │  Zero app code changes   │
                              └─────────────────────────┘
```

### Phase Ordering Rationale

**Phase 1 (Templates) before Phase 2 (Batch):**
- Templates are simpler — pure data layer + thin UI. They validate the persistence pattern.
- Batch processing benefits from templates: users want to select a template and apply it to every item in a batch. The auto-default feature (CUST-04) is the bridge — import 10 photos, they all get the default template, then the user tweaks per-item overrides.
- TemplateStore is a standalone component that can be fully tested in isolation before batch processing touches the processing pipeline.
- If templates ship first, the "load template → mark as default → import media → batch process" workflow is fully integrated from day one of batch.

**Phase 3 (Process Hardening) is independent:**
- PHRO-01 and PHRO-02 are GSD workflow/tooling changes that do not touch app Swift code. They can be done in parallel with templates or batch, or deferred to last. Placing them after the functional features avoids slowing down feature delivery with tooling work.

**Why batch and templates are separate phases, not one:**
- Templates have no processing dependency — they're a pure data persistence concern.
- Batch processing has both data (per-item overrides) and processing (BatchProcessor) concerns.
- Building templates first provides a clean "loading" integration point for batch.
- Each phase has clear, independently testable success criteria.

## App Group Sync Implications

| Concern | Current State | v2.0 Change |
|---------|---------------|-------------|
| Current config sync | `AppGroupConfigSync.save/load()` via UserDefaults | No change — loading a template triggers the existing save |
| Template storage | None | New JSON file in App Group container (`templates.json`) |
| Default template pointer | None | New `defaultTemplateID` key in UserDefaults(suiteName:) |
| Cross-target template access | N/A | All 3 targets read `templates.json` via TemplateStore |
| Template writes | N/A | Main app writes (CRUD UI); extensions are read-only consumers |
| Batch results | N/A | Temp files in each target's sandbox (existing TempFileManager pattern) |

**No new App Group entitlements needed.** The existing group container (`group.com.watermark.app`) is sufficient for both the `templates.json` file and the `defaultTemplateID` UserDefaults key.

## Components NOT Created

| What might seem needed | Why NOT needed |
|------------------------|----------------|
| `BatchEngine` (separate engine) | WatermarkEngine.process already takes config as a parameter. BatchProcessor wraps it with iteration + progress. No engine change required. |
| `TemplateSyncService` | Existing AppGroupConfigSync pattern proves simple static methods work. TemplateStore follows the same pattern. No service layer needed. |
| `PerItemConfig` (full config per batch item) | Users adjust 1-2 fields per item (text, maybe position). Full config duplication is wasteful and confusing. PerItemConfigOverride is a focused overlay. |
| `BatchShareViewModel` | Existing share sheet flow (fullResResult → UIActivityViewController) works for batch results one at a time. A simple loop in BatchViewModel suffices. |
| `BatchMode` enum in extensions | Extensions are single-item by design. Batch is main-app only. No extension protocol changes needed. |
| Template iCloud sync | Out of scope — local-only per project constraints. TemplateStore uses the on-device App Group container. |

## Anti-Patterns to Avoid

### Anti-Pattern 1: Concurrent Batch Processing
**What people do:** `TaskGroup` or `async let` to process all batch items in parallel.
**Why it's wrong:** Video exports each allocate AVAssetWriter encoder sessions. Two concurrent 4K HDR exports will trigger thermal throttling, increase export times beyond the sum of sequential, and risk iOS jetsam termination.
**Do this instead:** Sequential processing in BatchProcessor. Report progress per-item so the user sees forward motion. Support cancellation between items.

### Anti-Pattern 2: Templates as UserDefaults Keys
**What people do:** Store each template as a separate UserDefaults key: `template_<UUID>`.
**Why it's wrong:** UserDefaults is not a database. Listing all keys, iterating to find templates, and partial-write atomicity are all fragile. Rename/delete operations require multiple key mutations that can interleave.
**Do this instead:** A single JSON file in the App Group container. Load the full dictionary, modify in memory, write atomically (write to temp file, then `FileManager.replaceItemAt`). This is the pattern used by Apple's own apps for small, bounded collections.

### Anti-Pattern 3: Per-Item Full Config Duplication
**What people do:** Attach a full `WatermarkConfiguration` to each batch item for per-item adjustments.
**Why it's wrong:** A WatermarkConfiguration with multiple layers (text + image + signature + white frame + format settings) encodes to ~2-50KB (depending on image watermark size). For 20 items, that's ~1MB of config data. It's also confusing — which fields are shared vs per-item?
**Do this instead:** `PerItemConfigOverride` — a lightweight struct with only the fields users actually customize per-item (text, position, scale, output format, white frame toggle). Merge with shared config at processing time.

### Anti-Pattern 4: Template Management UI in Extensions
**What people do:** Put the full template CRUD UI in the share extension so users can manage templates during the share flow.
**Why it's wrong:** Extensions have strict memory limits (~120MB) and the expectation of a focused, quick interaction. Template management (saving, renaming, deleting) is a management task, not a processing task. Putting it in an extension bloats the extension and creates a confusing UX.
**Do this instead:** Extensions can load templates (read-only via TemplateStore.loadAll()) and apply them. All CRUD operations live in the main app. This matches user expectations: manage presets in the main app, use them everywhere.

## Integration Points Summary

| Integration Point | Type | New or Modified | Component |
|-------------------|------|-----------------|-----------|
| Template persistence | New | New file in App Group container | TemplateStore |
| Default template pointer | New | New key in UserDefaults(suiteName:) | TemplateStore.defaultTemplateID |
| Template application on config | Modified | Protocol default added | WatermarkConfigurable.applyTemplate |
| Auto-default on import | Modified | +3 lines per ViewModel | All 3 ViewModels |
| Batch item descriptor | New | New model | BatchItem (WatermarkCore) |
| Per-item config override | New | New model | PerItemConfigOverride (WatermarkCore) |
| Batch processing orchestration | New | New actor | BatchProcessor (WatermarkCore) |
| Batch UI coordination | New | New ViewModel | BatchViewModel (Main App) |
| Template management UI | New | New Views | TemplateListView, etc. (Main App) |
| WatermarkEngine.process | **None** | **Unchanged** | Already accepts config as parameter |

## Sources

- Existing codebase analysis — WatermarkCore Package.swift, WatermarkConfiguration.swift, WatermarkEngine.swift, AppGroupConfigSync.swift, WatermarkConfigurable.swift, WatermarkViewModel.swift, ShareExtensionViewModel.swift, PhotosExtensionViewModel.swift, PhotoItem.swift, TempFileManager.swift, ProcessingResult.swift, WhiteFrameConfig.swift. HIGH confidence.
- Apple Developer Documentation — Codable protocol, FileManager atomic writes, UserDefaults suite, App Group entitlements, Swift Concurrency actors. HIGH confidence.
- Apple Developer Documentation — AVAssetWriter encoder resource limits and thermal throttling guidance. MEDIUM confidence (informs sequential batch decision).
- GSD workflow documentation — VERIFICATION.md template pattern, worktree-safety concerns. HIGH confidence (informs Phase 3 independence).

---

*Architecture research for: Watermark v2.0 — Batch Processing, Template Management & Process Hardening*
*Researched: 2026-06-19*
*Confidence: HIGH*
