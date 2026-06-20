# Phase 12: Template Management — Research

**Researched:** 2026-06-19
**Domain:** iOS native (SwiftUI) — Template persistence, Codable schema evolution, cross-target state sharing via App Groups
**Confidence:** HIGH

## Summary

Phase 12 adds a full template CRUD system to the shipped Watermark app, layered on the existing Codable `WatermarkConfiguration`, `AppGroupConfigSync` (App Group UserDefaults), and three-target architecture. The core insight: the `WatermarkConfiguration` struct already serializes the entire watermark state — position, scale, text, images, output format, white frame, opacity, padding. A template is simply that config plus metadata (name, default flag, creation date) wrapped in a versioned Codable envelope.

The primary technical challenges are (a) **Codable schema versioning** that must ship with the first template save to avoid expensive retrofitting, (b) **cross-target consistency** — all three targets (main app, share extension, Photos extension) must read/write the same template store via App Group UserDefaults, (c) **48×48pt preview thumbnail generation** with in-memory caching for smooth scrolling, and (d) **default template auto-apply** triggered on media import across all entry points.

**Primary recommendation:** Persist templates as a `[Template]` JSON array in App Group UserDefaults (same suite `group.com.watermark.app` already used by `AppGroupConfigSync`). Use a new `"com.watermark.app.templates"` key. Ship with `schemaVersion: 1` in the Template model and a `MigrationChain` registry in `TemplateStore` so future fields can be added without data loss. Store preview thumbnails in `FileManager.default.cachesDirectory` keyed by template ID — NOT in the JSON blob (ImageWatermarkInput.pngData can be multi-MB).

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Template data model (Codable struct) | WatermarkCore (shared package) | — | All 3 targets must encode/decode the same struct |
| Template persistence (CRUD) | WatermarkCore (Storage/TemplateStore.swift) | — | App Group UserDefaults — all targets share read/write |
| Schema migration engine | WatermarkCore (Storage/MigrationChain.swift) | — | Must run identically across all targets before data is read |
| Template UI (list, rows, save dialog) | App target (App/Views/Templates/) | — | SwiftUI views are main app only (extensions use auto-apply, no UI) |
| Preview thumbnail generation | App target (called from TemplateListView) | WatermarkCore (WatermarkEngine) | Engine renders; app caches in caches directory |
| `.watermarktemplate` export/import | App target (ShareLink/fileImporter) | WatermarkCore (Template serialization) | UI is app-only; serialization logic is shared |
| Default template auto-apply on import | All 3 targets (ViewModel init/media-load path) | WatermarkCore (TemplateStore.loadDefault) | TemplateStore method returns default; each ViewModel calls it |
| Save Template button | App target (ControlsView modification) | — | Button adds to existing ControlsView VStack |
| Template sheet binding | App target (ContentView) | — | `.sheet` modifier on ContentView |

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Foundation (Codable/JSONEncoder/JSONDecoder) | iOS 18 SDK | Template serialization | Already used by WatermarkConfiguration; zero new dependencies |
| Foundation (UserDefaults) | iOS 18 SDK | App Group persistence | Already used by AppGroupConfigSync; `UserDefaults(suiteName:)` is the established cross-target storage pattern |
| SwiftUI (List, ForEach, .sheet, .alert, .contextMenu, .fileImporter) | iOS 18 SDK | Template list UI, save/rename alerts, import picker | Native components; no third-party needed |
| CoreImage (CIContext, CIFilter) | iOS 18 SDK | Preview thumbnail rendering | Already used by WatermarkEngine; reused for 48×48pt thumbnail generation |
| UniformTypeIdentifiers (UTType) | iOS 18 SDK | `.watermarktemplate` UTI registration and filtering | System framework; needed for `.fileImporter` content type filtering |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| — _(none)_ | — | — | No third-party libraries. System frameworks cover all needs. |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| App Group UserDefaults for template store | Core Data with shared container | Core Data adds ~3× complexity (NSPersistentContainer, model files, migration mappings). UserDefaults with JSON array is simpler and already proven in this codebase. Templates are <50 items — Core Data overkill. |
| App Group UserDefaults for template store | FileManager JSON file in App Group container | File-based storage is viable but requires manual atomic writes and read consistency. UserDefaults already handles atomicity. File-based approach preferred only if templates exceed ~500KB total (unlikely — most configs are <5KB of JSON). |
| Full CIContext render for preview thumbnails | SwiftUI `Image(uiImage:)` from CGImageSource thumbnail API | Thumbnail-only approach is faster but doesn't show watermark. Watermark preview requires actual compositing. |
| Separate Codable struct for template export | Same Template struct, but stripped of internal IDs | Internal IDs (UUID) are benign in export files; importing can regenerate or preserve. Simpler to use same struct. |

**Installation:**
```bash
# No package manager needed. All components are Swift system frameworks.
# New files to create:
# WatermarkCore/Sources/WatermarkCore/Models/Template.swift
# WatermarkCore/Sources/WatermarkCore/Storage/TemplateStore.swift
# WatermarkCore/Sources/WatermarkCore/Storage/MigrationChain.swift
# App/Views/Templates/TemplateListView.swift
# App/Views/Templates/TemplateRowView.swift
# App/Views/Templates/TemplatePreviewThumbnail.swift
# App/Views/Templates/SaveTemplateAlertModifier.swift
```

## Package Legitimacy Audit

> No external packages are installed or recommended for this phase. All functionality uses Apple system frameworks (Foundation, SwiftUI, CoreImage, UniformTypeIdentifiers) that ship with the iOS 18 SDK.

| Package | Registry | Age | Downloads | Source Repo | slopcheck | Disposition |
|---------|----------|-----|-----------|-------------|-----------|-------------|
| N/A | — | — | — | — | — | No third-party packages required |

**Packages removed due to slopcheck [SLOP] verdict:** none
**Packages flagged as suspicious [SUS]:** none

## Architecture Patterns

### System Architecture Diagram

```
┌──────────────────────────────────────────────────────────────────────┐
│                        APP GROUP: group.com.watermark.app            │
│                                                                      │
│  UserDefaults(suiteName:)                                            │
│  ┌───────────────────────────────────────────────────────────────┐   │
│  │  "watermarkConfiguration" → WatermarkConfiguration (JSON)      │   │
│  │  "com.watermark.app.templates" → [Template] (JSON) [NEW]       │   │
│  │  "com.watermark.app.templateSchemaVersion" → Int [NEW]         │   │
│  └───────────────────────────────────────────────────────────────┘   │
│                                                                      │
│  FileManager cachesDirectory (shared container)                      │
│  ┌───────────────────────────────────────────────────────────────┐   │
│  │  template_thumb_<UUID>.png → 48×48pt preview [NEW]             │   │
│  └───────────────────────────────────────────────────────────────┘   │
└──────────────────────────────┬───────────────────────────────────────┘
                               │
         ┌─────────────────────┼─────────────────────┐
         │                     │                     │
         ▼                     ▼                     ▼
┌─────────────────┐  ┌─────────────────┐  ┌──────────────────────┐
│   MAIN APP      │  │ SHARE EXTENSION │  │ PHOTO EDIT EXTENSION │
│                 │  │                 │  │                      │
│ ContentView ────┤  │ RootView ───────┤  │ RootView ────────────┤
│   │             │  │   │             │  │   │                  │
│   ├─ControlsView│  │   ├─ControlsView│  │   ├─ControlsView     │
│   │  [NEW: Save │  │   │  (auto-     │  │   │  (auto-apply     │
│   │   Template]  │  │   │   apply)    │  │   │   default)       │
│   │             │  │   │             │  │   │                  │
│   ├─[NEW:       │  │   └─ViewModel───┤  │   └─ViewModel────────┤
│   │ TemplateList │  │      │          │  │      │               │
│   │ View sheet]  │  │      │          │  │      │               │
│   │             │  │      ▼          │  │      ▼               │
│   └─ViewModel───┤  │  TemplateStore  │  │  TemplateStore       │
│       │         │  │  .loadDefault() │  │  .loadDefault()      │
│       ▼         │  │  (on import)    │  │  (on startEditing)   │
│   TemplateStore │  │                 │  │                      │
│   (full CRUD)   │  └─────────────────┘  └──────────────────────┘
│       │         │
│       ▼         │
│   App Group     │
│   UserDefaults  │
└─────────────────┘

Data Flow (Template Apply):
  1. User taps template row in TemplateListView
  2. TemplateListView calls viewModel.applyTemplate(template)
  3. ViewModel sets self.config = template.config 
  4. config.didSet triggers AppGroupConfigSync.save(config)
  5. Next time extension opens, it loads the updated config

Data Flow (Default Auto-Apply on Import):
  1. User imports media (picker/share sheet/Photos extension)
  2. ViewModel.handleSelection / loadSharedMedia / startEditing fires
  3. After media loaded: TemplateStore.loadDefaultIfNeeded(into: &viewModel)
  4. If default template exists AND config hasn't been modified by user:
     viewModel.config = defaultTemplate.config
```

### Recommended Project Structure
```
Packages/WatermarkCore/Sources/WatermarkCore/
├── Models/
│   ├── WatermarkConfiguration.swift  # Existing — unchanged
│   ├── WatermarkPosition.swift       # Existing — unchanged
│   ├── TextWatermarkInput.swift      # Existing — unchanged
│   ├── ImageWatermarkInput.swift     # Existing — unchanged
│   ├── SignatureInput.swift          # Existing — unchanged
│   ├── WhiteFrameConfig.swift        # Existing — unchanged
│   ├── ProcessingResult.swift        # Existing — unchanged
│   └── Template.swift                # [NEW] Template model (Codable, Sendable)
├── Storage/
│   ├── AppGroupConfigSync.swift      # Existing — unchanged
│   ├── TemplateStore.swift           # [NEW] CRUD + persistence for [Template]
│   └── MigrationChain.swift          # [NEW] Schema versioning registry
├── UI/
│   ├── ControlsView.swift            # [MODIFIED] Add Save Template button
│   ├── WatermarkConfigurable.swift   # [MODIFIED] Add applyTemplate method
│   └── ... (other views unchanged)
└── ... (other directories unchanged)

App/
├── Views/
│   ├── ContentView.swift             # [MODIFIED] Add sheet/alert bindings
│   ├── Templates/                    # [NEW]
│   │   ├── TemplateListView.swift
│   │   ├── TemplateRowView.swift
│   │   ├── TemplatePreviewThumbnail.swift
│   │   └── SaveTemplateAlertModifier.swift
│   └── ... (other views unchanged)
├── ViewModels/
│   └── WatermarkViewModel.swift      # [MODIFIED] Add template-related methods
└── WatermarkApp.swift                # Unchanged

ShareExtension/
├── ShareExtensionViewModel.swift     # [MODIFIED] Add default template auto-apply
└── ShareExtensionRootView.swift      # Unchanged

PhotoEditExtension/
├── PhotosExtensionViewModel.swift    # [MODIFIED] Add default template auto-apply
└── PhotosExtensionRootView.swift     # Unchanged
```

### Pattern 1: Template Codable Model with Schema Versioning

**What:** The `Template` struct wraps a `WatermarkConfiguration` with metadata and a `schemaVersion` field. `TemplateStore` maintains a `MigrationChain` — a registry of migration functions keyed by version number. On load, if `schemaVersion < currentVersion`, the chain runs each migration in order.

**When to use:** Any time templates are loaded from disk (App Group UserDefaults or import file).

**Example:**
```swift
// Source: NEW - Template.swift (to be created in WatermarkCore/Models/)
import Foundation

/// A saved watermark template with metadata and schema versioning.
public struct Template: Sendable, Codable, Identifiable {
    public let id: UUID
    public var name: String
    public var config: WatermarkConfiguration
    public var isDefault: Bool
    public let createdAt: Date
    public var schemaVersion: Int
    
    enum CodingKeys: String, CodingKey {
        case id, name, config, isDefault, createdAt, schemaVersion
    }
    
    /// Current schema version. Bump when adding new fields.
    public static let currentSchemaVersion = 1
    
    public init(
        id: UUID = UUID(),
        name: String,
        config: WatermarkConfiguration,
        isDefault: Bool = false,
        createdAt: Date = Date(),
        schemaVersion: Int = Template.currentSchemaVersion
    ) {
        self.id = id
        self.name = name
        self.config = config
        self.isDefault = isDefault
        self.createdAt = createdAt
        self.schemaVersion = schemaVersion
    }
}
```

### Pattern 2: TemplateStore with Migration Chain

**What:** `TemplateStore` is a class (not struct — needs `@MainActor` or internal locking for cross-target consistency) that manages the `[Template]` array in App Group UserDefaults. It exposes `@Published` array for SwiftUI binding, runs migrations on load, and provides CRUD operations.

**When to use:** All template operations route through `TemplateStore.shared`.

**Example:**
```swift
// Source: NEW - TemplateStore.swift (to be created in WatermarkCore/Storage/)
import Foundation
import os.log
import Combine

/// Manages template persistence in App Group UserDefaults with schema migration.
@MainActor
public final class TemplateStore: ObservableObject {
    public static let shared = TemplateStore()
    
    /// App Group suite — same as AppGroupConfigSync
    private let suiteName = "group.com.watermark.app"
    private let templatesKey = "com.watermark.app.templates"
    private let versionKey = "com.watermark.app.templateSchemaVersion"
    
    @Published public var templates: [Template] = []
    
    /// Registry: version → migration function that mutates a Template in-place.
    private let migrationChain: [Int: (inout Template) -> Void] = [
        // Example for future use:
        // 1: { template in /* v1→v2 migration */ }
    ]
    
    private init() {
        loadTemplates()
    }
    
    // MARK: - Load with Migration
    
    private func loadTemplates() {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            os_log(.error, "[TemplateStore] Failed to open App Group suite")
            return
        }
        
        guard let data = defaults.data(forKey: templatesKey) else {
            templates = []
            return
        }
        
        guard var decoded = try? JSONDecoder().decode([Template].self, from: data) else {
            templates = []
            return
        }
        
        // Run migration chain for each template
        for i in decoded.indices {
            let current = decoded[i].schemaVersion
            for version in current..<Template.currentSchemaVersion {
                if let migration = migrationChain[version] {
                    migration(&decoded[i])
                    decoded[i].schemaVersion = version + 1
                }
            }
        }
        
        templates = decoded
        
        // Persist migrated data
        saveToDefaults(decoded)
    }
    
    // MARK: - CRUD
    
    public func save(_ template: Template) throws {
        guard !template.name.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw TemplateStoreError.emptyName
        }
        guard !templates.contains(where: { $0.name == template.name && $0.id != template.id }) else {
            throw TemplateStoreError.duplicateName(template.name)
        }
        
        if let existingIndex = templates.firstIndex(where: { $0.id == template.id }) {
            templates[existingIndex] = template
        } else {
            templates.append(template)
        }
        
        if template.isDefault {
            clearOtherDefaults(except: template.id)
        }
        
        persist()
    }
    
    public func delete(id: UUID) {
        let wasDefault = templates.first(where: { $0.id == id })?.isDefault == true
        templates.removeAll(where: { $0.id == id })
        // If deleted template was default, no template is default — user must set new default
        persist()
    }
    
    public func duplicate(_ template: Template) throws {
        var copy = template
        copy.id = UUID()
        copy.name = uniqueName(from: template.name + " (copy)")
        copy.isDefault = false
        copy.createdAt = Date()
        try save(copy)
    }
    
    public func rename(id: UUID, to newName: String) throws {
        guard let index = templates.firstIndex(where: { $0.id == id }) else {
            throw TemplateStoreError.notFound
        }
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { throw TemplateStoreError.emptyName }
        guard !templates.contains(where: { $0.name == trimmed && $0.id != id }) else {
            throw TemplateStoreError.duplicateName(trimmed)
        }
        templates[index].name = trimmed
        persist()
    }
    
    public func setDefault(id: UUID) throws {
        guard let index = templates.firstIndex(where: { $0.id == id }) else {
            throw TemplateStoreError.notFound
        }
        clearOtherDefaults(except: id)
        templates[index].isDefault = true
        persist()
    }
    
    public func removeDefault(id: UUID) throws {
        guard let index = templates.firstIndex(where: { $0.id == id }) else {
            throw TemplateStoreError.notFound
        }
        templates[index].isDefault = false
        persist()
    }
    
    /// Returns the default template config, or nil if none is set.
    public var defaultTemplate: Template? {
        templates.first(where: { $0.isDefault })
    }
    
    // MARK: - Preview Thumbnail Caching
    
    /// Caches directory for template preview thumbnails.
    private var thumbnailCacheDir: URL? {
        try? FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("template_thumbnails")
    }
    
    /// Saves a 48×48pt PNG thumbnail for a template ID.
    public func saveThumbnail(_ pngData: Data, for templateID: UUID) {
        guard let dir = thumbnailCacheDir else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("thumb_\(templateID.uuidString).png")
        try? pngData.write(to: url)
    }
    
    /// Loads a cached thumbnail for a template ID.
    public func loadThumbnail(for templateID: UUID) -> Data? {
        guard let dir = thumbnailCacheDir else { return nil }
        let url = dir.appendingPathComponent("thumb_\(templateID.uuidString).png")
        return try? Data(contentsOf: url)
    }
    
    // MARK: - Export/Import
    
    /// Serializes a template for export as `.watermarktemplate` file.
    public func exportData(for template: Template) throws -> Data {
        // Export version of the template — strip internal ID, set export metadata
        var exportTemplate = template
        // Keep id for re-import deduplication, but could be regenerated
        exportTemplate.isDefault = false  // Imported templates never auto-become default
        return try JSONEncoder().encode(exportTemplate)
    }
    
    /// Imports a template from `.watermarktemplate` file data.
    public func `import`(from data: Data) throws -> Template {
        var imported = try JSONDecoder().decode(Template.self, from: data)
        
        // Run migration chain on imported template
        let current = imported.schemaVersion
        for version in current..<Template.currentSchemaVersion {
            if let migration = migrationChain[version] {
                migration(&imported)
                imported.schemaVersion = version + 1
            }
        }
        
        // Regenerate ID to avoid collisions with existing templates
        imported.id = UUID()
        imported.createdAt = Date()
        imported.isDefault = false
        
        // Handle duplicate name
        if templates.contains(where: { $0.name == imported.name }) {
            imported.name = uniqueName(from: imported.name + " (imported)")
        }
        
        try save(imported)
        return imported
    }
    
    // MARK: - Private
    
    private func persist() {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        guard let data = try? JSONEncoder().encode(templates) else { return }
        defaults.set(data, forKey: templatesKey)
        defaults.set(Template.currentSchemaVersion, forKey: versionKey)
    }
    
    private func saveToDefaults(_ templates: [Template]) {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data = try? JSONEncoder().encode(templates) else { return }
        defaults.set(data, forKey: templatesKey)
    }
    
    private func clearOtherDefaults(except templateID: UUID) {
        for i in templates.indices where templates[i].id != templateID {
            templates[i].isDefault = false
        }
    }
    
    private func uniqueName(from base: String) -> String {
        var candidate = base
        var counter = 2
        while templates.contains(where: { $0.name == candidate }) {
            candidate = "\(base) \(counter)"
            counter += 1
        }
        return candidate
    }
}

public enum TemplateStoreError: LocalizedError {
    case emptyName
    case duplicateName(String)
    case notFound
    
    public var errorDescription: String? {
        switch self {
        case .emptyName:
            return "Template name cannot be empty."
        case .duplicateName(let name):
            return "A template named \"\(name)\" already exists. Please choose a different name."
        case .notFound:
            return "Template not found."
        }
    }
}
```

### Pattern 3: Default Template Auto-Apply on Import

**What:** Each ViewModel calls `TemplateStore.shared.defaultTemplate` after media import completes. If a default template exists and the user hasn't modified the config yet (tracked by a `hasUserModifiedConfig` flag), auto-apply the template config.

**When to use:** `WatermarkViewModel.handleSelection()`, `ShareExtensionViewModel.loadSharedMedia()`, `PhotosExtensionViewModel.startEditing()` — after media setup completes.

**Example:**
```swift
// Source: Modification to WatermarkViewModel.swift — added method

/// Auto-applies the default template config on new media import.
/// Only fires once per import — subsequent user changes are preserved.
func applyDefaultTemplateIfNeeded() {
    guard let defaultTemplate = TemplateStore.shared.defaultTemplate else { return }
    config = defaultTemplate.config
    // config.didSet triggers AppGroupConfigSync.save(config) automatically
}
```

### Anti-Patterns to Avoid

- **Storing thumbnail PNGs in the JSON template array:** ImageWatermarkInput.pngData can be multi-MB. Embedding it in the JSON array would balloon the serialized blob past UserDefaults' practical limit (~1MB before iOS throttles). Store thumbnails as separate PNG files in caches.
- **App Group UserDefaults for high-frequency writes:** UserDefaults is not a database — it syncs to disk periodically. High-frequency writes (e.g., saving every keystroke) cause unnecessary I/O. Debounce template saves.
- **Assuming single-target access:** Extensions and main app can read/write simultaneously. Use atomic reads (load whole array → mutate → write whole array) rather than in-place mutations.
- **Decoding templates without version check:** Always check `schemaVersion` and run migration chain before using decoded data. A template saved by v2.0 should survive v2.1 schema additions.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Template data persistence | Custom file format / SQLite | `UserDefaults(suiteName:)` with `Codable` JSON array | Already proven in this codebase (AppGroupConfigSync). Templates <50 items — relational DB is overkill. UserDefaults handles atomicity and app group sharing out of the box. |
| Schema migration tracking | Ad-hoc version checks scattered across code | Centralized `MigrationChain` registry in `TemplateStore` | Single registry means all migrations run in one place, in order. New fields added without touching old code. |
| Preview thumbnail rendering | Custom CIImage pipeline | `WatermarkEngine.shared` (existing) with downsized output | Engine already handles all watermark types (text, image, signature, white frame). Reuse, don't duplicate. |
| Template file format | Custom binary format or plist | Codable JSON with `.watermarktemplate` UTI | JSON is human-readable, debuggable, and the Codable implementation already exists for `WatermarkConfiguration`. |
| Cross-target state sync | NotificationCenter / Darwin notifications | App Group `UserDefaults` (already used) | Extensions may not be running when main app writes. UserDefaults is the standard iOS mechanism for shared preferences across app+extensions. |
| Name uniqueness enforcement | Manual loop in each caller | `TemplateStore.save()` validates before writing | Centralize validation to prevent race conditions and duplicate logic |

**Key insight:** The existing `WatermarkConfiguration` Codable model already captures 100% of the watermark state. A template just adds a name and default flag. Don't reinvent serialization — wrap it.

## Runtime State Inventory

> Include this section for rename/refactor/migration phases only. Omit entirely for greenfield phases.

**This phase is greenfield (additive feature, not a rename/refactor). Runtime State Inventory is skipped.**

## Common Pitfalls

### Pitfall 1: Schema Versioning Retrofitting

**What goes wrong:** Phase 12 ships without a `schemaVersion` field in `Template`. Phase 13 adds a new field (e.g., `tags: [String]`). Existing templates without the field crash on decode because `JSONDecoder` can't find the key for a non-optional property. Fixing requires manual data migration on users' devices.

**Why it happens:** Developers add fields assuming Codable is backwards-compatible. It's not — non-optional new fields break decoding of old data.

**How to avoid:** Ship `schemaVersion: 1` in the first Template struct. Add a `MigrationChain` registry in `TemplateStore` on Day 0. Every future field addition registers a migration function. New fields should use `decodeIfPresent` with sensible defaults OR be Optional.

**Warning signs:** "I'll add versioning later" — the exact thought that creates the 3-5× retrofitting cost documented in STATE.md.

### Pitfall 2: Template Name Uniqueness Across Targets

**What goes wrong:** User saves template "Instagram" in the main app. User imports a template file with the same name via the share extension. No uniqueness check runs, resulting in duplicates with identical display names.

**Why it happens:** Each target instantiates its own `TemplateStore` instance (though shared via `shared` singleton). Without centralized validation in `save()`, duplicates slip through.

**How to avoid:** `TemplateStore.save()` checks for duplicate names before writing. `TemplateStore.import()` auto-appends " (imported)" suffix on collision. All CRUD goes through `TemplateStore`, never through direct array mutation.

**Warning signs:** Direct `templates.append()` calls outside of `TemplateStore`.

### Pitfall 3: Preview Thumbnail Memory Pressure

**What goes wrong:** `TemplateListView` renders all 20+ template previews simultaneously using full `CIContext.createCGImage` at screen resolution. Memory spikes, scrolling janks.

**Why it happens:** Previews are generated eagerly and held in memory without caching or lazy loading.

**How to avoid:** Generate thumbnails lazily (`.task` modifier on each row). Cache the 48×48pt output as a PNG file in caches directory. Use `CIContext.createCGImage` with a tiny render target (48×48 logical pixels × screen scale). On next list display, load from cache — only regenerate if template config changed (track with a hash or `previewIdentifier` pattern already used in the app). Only cache in-memory for visible rows.

**Warning signs:** "I'll just render it at full resolution and scale down with `.resizable()`" — this renders the full photo pipeline per thumbnail.

### Pitfall 4: UserDefaults Size Limits with Image Data

**What goes wrong:** Templates containing image watermark layers (logos) store the full `ImageWatermarkInput.pngData` (could be 2-10MB) in the UserDefaults JSON blob. iOS throttles or truncates UserDefaults values above ~1MB.

**Why it happens:** `WatermarkConfiguration` includes `ImageWatermarkInput.pngData` directly. When this is serialized as part of a Template JSON array, the total blob can exceed UserDefaults limits.

**How to avoid:** The existing `strippingImageData()` / `rehydrateImageData()` pattern in `WatermarkConfiguration` already handles this for `PHAdjustmentData`. For templates, store image data separately in App Group container files (keyed by template ID + layer index) and reference them via a file path or UUID in the template config. OR accept the size limitation as a known constraint (image watermarks in templates work but limit total template count). The simpler approach: store the full config as-is for v2.0 — if a user has 5 templates with 2MB logos each, they'll get ~10MB, which exceeds UserDefaults limits. Flag this as a known v2.1 hardening item.

**For Phase 12:** Apply the stripping pattern to templates — strip image data before storing in UserDefaults, rehydrate on load. Store full image data in App Group shared container files at `Library/Application Support/template_images/<templateID>/layer_<index>.png`.

### Pitfall 5: Default Template Fighting Between Targets

**What goes wrong:** Main app sets template A as default. Share extension opens and sets template B as default (via user action or auto-save). Both targets overwrite each other's default flag due to stale reads.

**Why it happens:** Each target reads the template store at init time, then mutates its local copy. If both targets are "live" simultaneously (rare but possible — extension overlay on iPad), one's write clobbers the other's.

**How to avoid:** Always read fresh from UserDefaults before mutating (read-modify-write). `TemplateStore` is a `@MainActor` singleton but separate processes read independently. This is a fundamental limitation of file-based storage — acceptable for a utility app where simultaneous template edits across targets are extremely rare. Document as known limitation.

**Warning signs:** "I'll cache the template array and only write on save" — reads become stale.

## Code Examples

### Save Template Flow (ControlsView + ContentView integration)

```swift
// Source: Modified ControlsView.swift — add Save Template button
// Inside ControlsView body, after the LayerListView and before the exportOptionsDisclosure:

// Save Template button
Button {
    viewModel.showSaveTemplateAlert = true
} label: {
    HStack(spacing: 8) {
        Image(systemName: "square.and.arrow.down.on.square")
        Text("Save Template")
    }
    .frame(maxWidth: .infinity)
    .frame(height: 44)
}
.buttonStyle(.bordered)
.tint(.accentColor)
```

```swift
// Source: Modified WatermarkConfigurable protocol — add template properties
// Added to WatermarkConfigurable:
var showSaveTemplateAlert: Bool { get set }
var showTemplateList: Bool { get set }
var templateSaveName: String { get set }
func saveCurrentAsTemplate(name: String) throws
func applyTemplate(_ template: Template)
```

### Template List Sheet (ContentView integration)

```swift
// Source: Modified ContentView.swift — add sheet modifier
.sheet(isPresented: $viewModel.showTemplateList) {
    NavigationStack {
        TemplateListView(viewModel: viewModel)
    }
}
```

### Preview Thumbnail Rendering

```swift
// Source: NEW — TemplatePreviewThumbnail.swift
import SwiftUI
import WatermarkCore
import CoreImage

/// Renders a 48×48pt watermark preview for a template applied to current media.
struct TemplatePreviewThumbnail: View {
    let template: Template
    let sourceURL: URL?  // nil = no media loaded
    @State private var thumbnail: UIImage?
    @State private var isLoading = false
    
    private let engine = WatermarkEngine.shared
    private let store = TemplateStore.shared
    
    var body: some View {
        Group {
            if let thumbnail = thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else if isLoading {
                ProgressView()
                    .frame(width: 48, height: 48)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 6))
            } else {
                // Placeholder
                Image(systemName: "doc.text")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
                    .frame(width: 48, height: 48)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .task {
            await generateThumbnail()
        }
    }
    
    private func generateThumbnail() async {
        // Check cache first
        if let cached = store.loadThumbnail(for: template.id),
           let image = UIImage(data: cached) {
            thumbnail = image
            return
        }
        
        guard let sourceURL = sourceURL else { return }
        isLoading = true
        defer { isLoading = false }
        
        // Render at 48×48 logical pixels (× scale for actual render)
        let scale = await UIScreen.main.scale
        let renderSize = CGSize(width: 48 * scale, height: 48 * scale)
        
        // Use engine with a small render target
        // For simplicity, process full then downsample thumbnail
        if let result = try? await engine.process(sourceURL: sourceURL, config: template.config),
           let url = result.url,
           let data = try? Data(contentsOf: url),
           let source = CGImageSourceCreateWithData(data as CFData, nil) {
            let options = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: renderSize.width
            ] as CFDictionary
            if let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) {
                let image = UIImage(cgImage: cgImage)
                thumbnail = image
                // Cache for next time
                if let pngData = image.pngData() {
                    store.saveThumbnail(pngData, for: template.id)
                }
            }
        }
    }
}
```

### `.watermarktemplate` UTI Registration

```xml
<!-- Source: Add to App/Info.plist, ShareExtension/Info.plist, PhotoEditExtension/Info.plist -->
<key>UTExportedTypeDeclarations</key>
<array>
    <dict>
        <key>UTTypeIdentifier</key>
        <string>com.watermark.app.template</string>
        <key>UTTypeDescription</key>
        <string>Watermark Template</string>
        <key>UTTypeConformsTo</key>
        <array>
            <string>public.json</string>
        </array>
        <key>UTTypeTagSpecification</key>
        <dict>
            <key>public.filename-extension</key>
            <array>
                <string>watermarktemplate</string>
            </array>
            <key>public.mime-type</key>
            <array>
                <string>application/json</string>
            </array>
        </dict>
    </dict>
</array>
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Single `WatermarkConfiguration` in App Group | Same config + `[Template]` array in App Group | Phase 12 (new) | Additive — existing config sync unchanged |
| No template concept | Full template CRUD with schema versioning | Phase 12 (new) | Greenfield — no migration needed |
| `AppGroupConfigSync` — single config | `TemplateStore` — array of configs with metadata | Phase 12 (new) | Both coexist; ConfigSync still saves active config |
| Manual Codable (no version field) | `Template` includes `schemaVersion` with `MigrationChain` | Phase 12 (new) | Forward-looking — version field costs nothing today, saves weeks later |

**Deprecated/outdated:**
- Nothing deprecated. Templates are strictly additive.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | UserDefaults(suiteName: "group.com.watermark.app") can store a JSON array of 50 templates (each ~1-5KB of config + ~200 bytes metadata) without hitting iOS throttling limits (~1MB total). Image watermark PNG data stripped. | Standard Stack | If templates routinely contain large image watermarks and many templates are saved, may need file-based storage or the stripping pattern. Medium risk — mitigated by the stripping recommendation. |
| A2 | `FileManager.default.cachesDirectory` is accessible from all 3 targets within the App Group. Caches in the app container may not be directly accessible to extensions. | Architecture Patterns — Preview Thumbnails | If extensions can't read the main app's caches directory, thumbnails cached by the main app won't be visible in extensions. Extensions would need to generate their own thumbnails or use the App Group shared container. MEDIUM risk — needs validation. |
| A3 | `TemplateStore` as a `@MainActor` singleton works correctly when the main app and an extension both instantiate `TemplateStore.shared` in separate processes. UserDefaults is process-safe for atomic read/write. | Architecture Patterns | UserDefaults across processes has well-documented edge cases with frequent writes. LOW risk — template saves are infrequent (user-initiated), not rapid-fire. |
| A4 | The `.watermarktemplate` UTI registered in Info.plist is sufficient for `.fileImporter` filtering in the main app and for Safari/Files "Open In" recognition. | File Format — UTI Registration | If UTI is not properly declared in all 3 Info.plist files, import may accept any JSON file instead of only `.watermarktemplate` files. LOW risk — UTI declarations are well-understood. |
| A5 | `CGImageSourceCreateThumbnailAtIndex` with `kCGImageSourceThumbnailMaxPixelSize: 48*scale` produces acceptable quality previews for the template list without running the full watermark pipeline. | Preview Thumbnails | If the thumbnail API doesn't preserve the watermark rendering quality, the full engine may need to be called for each preview, impacting performance. LOW risk — the engine is GPU-accelerated and 48×48 is tiny. |

## Open Questions (RESOLVED)

1. **Should preview thumbnails use the full watermark engine (accurate) or a fast approximate render (quick)?**
   - What we know: The UI-SPEC says to use `CIContext.createCGImage` at 48×48pt. The full engine handles all watermark types correctly. A simplified render would need to duplicate text/image/signature/whiteframe logic.
   - What's unclear: Whether `WatermarkEngine.process()` is fast enough for a 48×48 render target (it likely is — the engine is GPU-accelerated and 48×48 is trivial pixel count).
   - Recommendation: Use the full engine for correctness. If performance profiling shows >100ms per thumbnail, fall back to the CGImageSource thumbnail API on the output (which is what the code example above does). Start simple, profile, optimize only if needed.

2. **Should ImageWatermarkInput.pngData be stripped from templates stored in UserDefaults?**
   - What we know: `WatermarkConfiguration.strippingImageData()` already exists for `PHAdjustmentData`. Applying the same pattern to templates would prevent UserDefaults size issues. However, it adds complexity (rehydration logic, separate file storage).
   - What's unclear: Whether users will actually save templates with logo watermarks frequently enough to hit size limits. The app's core use case is text watermarks + white frame.
   - Recommendation: Apply the stripping pattern from Day 1. It's already written and tested (see `WatermarkConfiguration.strippingImageData()` + `rehydrateImageData()`). Reuse these methods. Store full image data in App Group container files. The cost is low, the benefit is preventing a hard-to-debug data corruption issue.

3. **Should `TemplateStore` be `@Observable` (iOS 17+) or `ObservableObject` (iOS 13+)?**
   - What we know: The project targets iOS 18 and uses `@Observable` macros in all existing ViewModels (`WatermarkViewModel`, `ShareExtensionViewModel`, `PhotosExtensionViewModel`).
   - What's unclear: `TemplateStore` is a singleton used across views. `@Observable` with `@MainActor` works for single-owner scenarios but `ObservableObject` with `@Published` is more traditional for shared singleton stores.
   - Recommendation: Use `@Observable @MainActor` to match the existing codebase pattern. All existing ViewModels use this pattern. Consistency over novelty.

## Environment Availability

> Phase 12 has no external tool/service dependencies beyond what the existing app already requires (Xcode 18, iOS 18 SDK). All new code uses Apple system frameworks that ship with the SDK.

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Xcode 18 | All development | ✓ | 18.x (project constraint) | — |
| iOS 18 SDK | All frameworks | ✓ | Bundled with Xcode | — |
| App Group: `group.com.watermark.app` | TemplateStore, AppGroupConfigSync | ✓ | Configured in 2/3 entitlements | Main app needs `.entitlements` file (currently missing — see note below) |

**Missing dependencies with no fallback:**
- **Main app `.entitlements` file:** The ShareExtension and PhotoEditExtension both have `.entitlements` files with App Group `group.com.watermark.app`. The main app target does NOT have an `.entitlements` file. For `TemplateStore` to read/write App Group UserDefaults from the main app, the main app must also have an entitlements file declaring `com.apple.security.application-groups` with `group.com.watermark.app`. Without this, the main app's `UserDefaults(suiteName:)` calls will fail silently. **This is a blocking issue — must be resolved in Wave 0 before any template code runs.**

**Missing dependencies with fallback:**
- None — all other dependencies are available.

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | No | N/A — no user accounts |
| V3 Session Management | No | N/A — no sessions |
| V4 Access Control | No | N/A — single-user, on-device only |
| V5 Input Validation | Yes | Template name: max 50 chars, non-empty, no duplicates. Import file: validate JSON schema, check `schemaVersion` ≤ current, reject on decode failure. Export: no validation needed (we control the output). |
| V6 Cryptography | No | N/A — no cryptographic operations |

### Known Threat Patterns for iOS App Group + UserDefaults Template Storage

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Imported `.watermarktemplate` file contains maliciously crafted JSON (e.g., extreme nesting, massive arrays, invalid CGColor components causing crash) | Denial of Service | `JSONDecoder` has built-in nesting depth limits. Validate after decode: check `schemaVersion` is within bounds, `name` ≤ 50 chars, `config.watermarks.count` ≤ 20. Wrap decode in `try?` — on failure, reject import with user-facing error. |
| Template file claims `isDefault: true` on import — imported template becomes default without user consent | Elevation of Privilege | `TemplateStore.import()` always sets `isDefault = false` regardless of what the file contains. The user must explicitly set default via context menu. |
| Malicious template file contains extremely large `ImageWatermarkInput.pngData` (100MB+) causing memory exhaustion on decode | Denial of Service | Apply the stripping pattern on import: decode the full config, then strip image data before storing in UserDefaults. Store image data separately with size validation (reject >50MB PNGs). |
| User deletes a template, but thumbnail cache file persists — disk accumulation over time | Information Disclosure (low severity) | `TemplateStore.delete()` cleans up the associated thumbnail cache file. Periodically clean orphaned thumbnails on store init (files without matching template IDs). |

## Sources

### Primary (HIGH confidence)
- Codebase scan (`Packages/WatermarkCore/`, `App/`, `ShareExtension/`, `PhotoEditExtension/`) — verified all existing patterns:
  - `WatermarkConfiguration.swift` — Codable model with enum-based discriminated union (`WatermarkLayer`)
  - `AppGroupConfigSync.swift` — UserDefaults(suiteName:) pattern for App Group sharing
  - `WatermarkViewModel.swift` — `@Observable @MainActor` + `WatermarkConfigurable` protocol + `didSet` config sync
  - `ShareExtensionViewModel.swift` / `PhotosExtensionViewModel.swift` — same pattern, different input sources
  - `ControlsView.swift` — generic over `WatermarkConfigurable`, VStack layout pattern
  - `ContentView.swift` — `.sheet`, `.alert`, `.fileImporter` modifier patterns
  - `WatermarkConfigurable.swift` — protocol with default implementations
  - `TempFileManager.swift` — UUID-based temp file pattern, caches directory usage
  - `.entitlements` files — App Group `group.com.watermark.app` configured in extensions but NOT main app
  - `Info.plist` files — existing UTI declarations for image/video types
- Apple Developer Documentation: `UserDefaults.init(suiteName:)`, `Codable`, `JSONEncoder`/`JSONDecoder`, `UTType`, `PHAdjustmentData`, `App Groups entitlement`
- UI-SPEC.md (`.planning/phases/12-template-management/12-UI-SPEC.md`) — approved design contract

### Secondary (MEDIUM confidence)
- Apple Developer Documentation — `CGImageSourceCreateThumbnailAtIndex` with `kCGImageSourceThumbnailMaxPixelSize` — thumbnail generation for preview
- Apple Developer Documentation — `UTExportedTypeDeclarations` in Info.plist for custom UTI registration
- SWIFT.org — Codable migration patterns (encode/decode with version fields)

### Tertiary (LOW confidence)
- Training data knowledge of iOS UserDefaults size limits (~1MB practical limit) — confirmed by multiple Stack Overflow posts but not tested on this specific iOS version [ASSUMED]

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all libraries are Apple system frameworks already used in the project. No third-party dependencies.
- Architecture: HIGH — the existing codebase establishes clear patterns (App Group UserDefaults, @Observable @MainActor ViewModels, Codable models, WatermarkConfigurable protocol). The Template system follows these exact patterns.
- Pitfalls: HIGH — pitfalls are derived from (a) existing codebase patterns (PHAdjustmentData size handling already solved with stripping/rehydration), (b) stated project constraints (schema versioning is non-negotiable per STATE.md), and (c) well-known iOS platform constraints (UserDefaults size limits, cross-process consistency).

**Research date:** 2026-06-19
**Valid until:** 2026-07-19 (30 days — ecosystem is stable, no new iOS SDK expected within this window)

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| TMPL-01 | User can save current watermark configuration as a named, reusable template | `TemplateStore.save()` + `Template` model. Save button in `ControlsView`. Name input via `.alert` with text field. Config serialized via existing `WatermarkConfiguration` Codable. Schema version `1` on first save. |
| TMPL-02 | User can browse saved templates in a list and apply one with a single tap | `TemplateListView` with `ForEach` over `TemplateStore.shared.templates`. Tap row → `viewModel.applyTemplate(template)` → sets `viewModel.config = template.config`. Sheet dismiss on apply. 48×48pt preview thumbnails per TMPL-06. |
| TMPL-03 | User can manage templates — rename, duplicate, and swipe-to-delete | Context menu on each `TemplateRowView`: Rename (alert with text field), Duplicate (call `TemplateStore.shared.duplicate()`), Delete (swipe action + confirmation alert). Swipe-to-delete using `.onDelete` or custom swipe actions. |
| TMPL-04 | User can mark template as default; auto-applies on import across all 3 targets | `Template.isDefault: Bool`. `TemplateStore.setDefault(id:)` clears other defaults. Each ViewModel's media import path calls `TemplateStore.shared.defaultTemplate` and auto-applies if config not user-modified. |
| TMPL-05 | User can export template as `.watermarktemplate` file and import via share sheet or Files picker | Export: `TemplateStore.exportData()` → JSON → temp file → `ShareLink`. Import: `.fileImporter` filtered to `.watermarktemplate` UTI → `TemplateStore.import(from:)` → validate schema version → insert. UTI declared in all 3 `Info.plist` files. |
| TMPL-06 | User can see a preview thumbnail of each template applied to current media while browsing | `TemplatePreviewThumbnail` — renders 48×48pt watermark preview via `WatermarkEngine.shared` or `CGImageSourceCreateThumbnailAtIndex`. Cached as PNG in caches directory. Placeholder shown when no media loaded. ProgressView during render. |
