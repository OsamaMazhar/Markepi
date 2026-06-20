---
phase: 12-template-management
plan: 01
subsystem: data
tags: [codable, userdefaults, app-group, schema-versioning, swift]
requires: []
provides:
  - Template Codable model with schema versioning (Template.swift)
  - TemplateStore CRUD singleton with migration chain (TemplateStore.swift)
  - App Group entitlements for main app target (App.entitlements)
affects: [12-template-management, 13-batch-processing]

tech-stack:
  added: []
  patterns:
    - "Codable with decodeIfPresent defaults for forward-compatible schema evolution"
    - "@Observable @MainActor singleton store pattern (matching WatermarkViewModel)"
    - "App Group UserDefaults(suiteName:) persistence (matching AppGroupConfigSync)"
    - "MigrationChain dictionary registry for versioned template upgrades"
    - "os_log(.error, \"[TemplateStore] ...\") error logging pattern"

key-files:
  created:
    - Packages/WatermarkCore/Sources/WatermarkCore/Models/Template.swift
    - Packages/WatermarkCore/Sources/WatermarkCore/Storage/TemplateStore.swift
    - App/App.entitlements
  modified: []

key-decisions:
  - "Used @Observable @MainActor (not ObservableObject) for TemplateStore to match existing WatermarkViewModel pattern"
  - "Inlined MigrationChain registry into TemplateStore.swift rather than a separate file — pattern from RESEARCH.md recommendation"
  - "TemplateStore.import() validates schema ≤ current, name ≤ 50 chars, watermarks.count ≤ 20 per T-12-01"
  - "App.entitlements is byte-identical to ShareExtension.entitlements — same XML structure, single App Group key"

patterns-established:
  - "Template model with schemaVersion and decodeIfPresent defaults"
  - "TemplateStore singleton with migration chain registry"
  - "App Group UserDefaults template persistence under key com.watermark.app.templates"
  - "Thumbnail caching in cachesDirectory/template_thumbnails/ with orphan cleanup"

requirements-completed:
  - TMPL-01
  - TMPL-02
  - TMPL-03
  - TMPL-04
  - TMPL-05
  - TMPL-06

duration: 2 min
completed: 2026-06-19
---

# Phase 12 Plan 01: Template Data Layer Summary

**Versioned Codable Template model, full-CRUD TemplateStore with migration chain and App Group persistence, and main app App Group entitlements**

## Performance

- **Duration:** 2 min
- **Started:** 2026-06-19T19:42:04Z
- **Completed:** 2026-06-19T19:43:59Z
- **Tasks:** 3
- **Files modified:** 0 (3 new files created)

## Accomplishments

- Created `Template.swift` — a versioned Codable model wrapping `WatermarkConfiguration` with metadata (name, default flag, creation date) and `schemaVersion` field for forward-compatible migration. Follows `WatermarkConfiguration.swift` Codable patterns exactly with `decodeIfPresent` defaults.
- Created `TemplateStore.swift` — a 420-line `@Observable @MainActor` singleton managing `[Template]` in App Group UserDefaults with full CRUD, migration chain, thumbnail caching, export/import with validation, and `TemplateStoreError` enum.
- Created `App.entitlements` — byte-identical to `ShareExtension.entitlements`, declaring `com.apple.security.application-groups` with `group.com.watermark.app`, unblocking main app access to shared template storage.
- All threat model mitigations implemented: T-12-01 (import validation), T-12-02 (import isDefault=false), T-12-03 (500KB size limit), T-12-04 (thumbnail orphan cleanup on init + delete).

## Task Commits

Each task was committed atomically:

1. **Task 1: Create Template.swift** - `cb8773b` (feat)
2. **Task 2: Create TemplateStore.swift** - `e3a992c` (feat)
3. **Task 3: Create App.entitlements** - `0896f5c` (feat)

## Files Created

- `Packages/WatermarkCore/Sources/WatermarkCore/Models/Template.swift` (84 lines) — Codable model with 6 fields, schema versioning, decodeIfPresent defaults
- `Packages/WatermarkCore/Sources/WatermarkCore/Storage/TemplateStore.swift` (420 lines) — CRUD singleton with migration chain, thumbnail caching, export/import, TemplateStoreError
- `App/App.entitlements` (9 lines) — App Group entitlement for main app target, byte-identical to ShareExtension.entitlements

## Decisions Made

- **@Observable @MainActor over ObservableObject:** Chose `@Observable` to match the existing `WatermarkViewModel` pattern in the codebase. Properties are automatically observed by SwiftUI — no `@Published` needed (nor compatible with `@Observable` in Swift 6).
- **MigrationChain inlined:** Kept the migration chain dictionary inside `TemplateStore.swift` rather than a separate `MigrationChain.swift` file, per RESEARCH.md recommendation that the registry is too thin to justify its own file.
- **Threat mitigations baked into implementation:** All T-12-01 through T-12-04 mitigations are in the code (not deferred). import() validates schema, name length, and layer count; forces `isDefault = false`; `persist()` rejects blobs over 500KB; `delete()` and `init()` both clean up thumbnail orphans.

## Deviations from Plan

None — plan executed exactly as written. Minor technical adjustment: used `@Observable` without `@Published` (mutually exclusive in Swift 6) since `@Observable` provides native property observation matching the plan's intent.

## Issues Encountered

None. All tasks compiled cleanly with the expected patterns.

## User Setup Required

**External services require manual configuration.** See below:

- **Xcode project settings:** The `App.entitlements` file must be referenced in the WatermarkApp target's **Code Signing Entitlements** build setting. Without this, `UserDefaults(suiteName: "group.com.watermark.app")` will silently return `nil` in the main app. Steps:
  1. Open `Watermark.xcodeproj` in Xcode
  2. Select the **WatermarkApp** target → Build Settings
  3. Search for "Code Signing Entitlements"
  4. Set the value to `App/App.entitlements`

## Next Phase Readiness

Plan 12-01 establishes the data foundation for all subsequent Phase 12 plans:
- Template model and TemplateStore are ready for 12-02 (Template list UI + save alert)
- App Group entitlements unblock cross-target template access
- Schema versioning (currentSchemaVersion=1, MigrationChain registry) ships on Day 0

---

*Phase: 12-template-management*
*Completed: 2026-06-19*
