---
phase: 12-template-management
plan: 03
subsystem: ui
tags: [swiftui, templates, preview, caching, context-menu, import-export]

# Dependency graph
requires:
  - phase: 12-template-management
    provides: "Template model, TemplateStore CRUD, WatermarkConfigurable.applyTemplate(), WatermarkEngine.process()"
provides:
  - "TemplateListView — scrollable template library sheet with CRUD context menus"
  - "TemplateRowView — reusable row with preview thumbnail, name, date, default badge"
  - "TemplatePreviewThumbnail — lazy 48x48pt watermark preview with PNG caching"
affects:
  - 12-04 (ContentView wiring — sheet modifier for TemplateListView)
  - 12-05 (end-to-end UAT verification)
  - Phase 13 (batch processing may reuse template list UI)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Generic view pattern: `TemplateListView<ViewModel: WatermarkConfigurable & Observable>: View` matching ControlsView"
    - "Lazy async thumbnail: `.task` + `CGImageSourceCreateThumbnailAtIndex` + `TemplateStore` cache"
    - "Export-to-share pattern: `TemplateStore.exportData()` → temp `.watermarktemplate` file → `ShareSheetView`"

key-files:
  created:
    - App/Views/Templates/TemplateRowView.swift
    - App/Views/Templates/TemplatePreviewThumbnail.swift
    - App/Views/Templates/TemplateListView.swift
  modified:
    - App/ViewModels/WatermarkViewModel.swift (added protocol conformance)
    - PhotoEditExtension/PhotosExtensionViewModel.swift (added protocol conformance)
    - ShareExtension/ShareExtensionViewModel.swift (added protocol conformance)

key-decisions:
  - "TemplateListView accepts optional sourceURL parameter for preview thumbnails — ContentView wires it in Plan 04"
  - "Export flow serializes via TemplateStore.exportData() which strips isDefault, writes to temp file, presents ShareSheetView"
  - ".fileImporter uses UTType(filenameExtension: 'watermarktemplate') with compactMap fallback for safety"

patterns-established:
  - "Three-state preview thumbnail: cached → Image, loading → ProgressView, idle → SF Symbol placeholder"

requirements-completed:
  - TMPL-02
  - TMPL-03
  - TMPL-05
  - TMPL-06

# Metrics
duration: 6min
completed: 2026-06-19
---

# Phase 12 Plan 03: Template List UI Summary

**Complete template library UI — TemplateRowView, TemplatePreviewThumbnail with 48x48pt lazy caching, and TemplateListView sheet with full CRUD context menus, swipe-to-delete, import, and export**

## Performance

- **Duration:** 6 min
- **Started:** 2026-06-19T19:47:00Z
- **Completed:** 2026-06-19T19:53:46Z
- **Tasks:** 3 (+1 auto-fix)
- **Files created:** 3 (new views)
- **Files modified:** 3 (protocol conformance)

## Accomplishments

- Built three new SwiftUI views forming the complete template library UI
- TemplateRowView: HStack row with 48x48pt thumbnail, name, creation date, and star badge for default templates
- TemplatePreviewThumbnail: lazy 48x48pt watermark preview rendered via `WatermarkEngine.process()`, downsized via `CGImageSourceCreateThumbnailAtIndex`, cached as PNG in `TemplateStore`
- TemplateListView: generic sheet (`WatermarkConfigurable & Observable`) with scrollable `List`, 6-item context menu (Apply, Rename, Duplicate, Set/Remove Default, Export, Delete), swipe-to-delete with confirmation, `.fileImporter` for `.watermarktemplate` files, export via `ShareSheetView`, and `ContentUnavailableView` empty state
- Fixed missing `showSaveTemplateAlert` and `showTemplateList` protocol conformance in all three ViewModels (WatermarkViewModel, ShareExtensionViewModel, PhotosExtensionViewModel)

## Task Commits

Each task was committed atomically:

1. **Task 1: Create TemplateRowView** - `2517ce2` (feat)
2. **Task 2: Create TemplatePreviewThumbnail** - `4d0275d` (feat)
3. **Task 3: Create TemplateListView** - `698f98f` (feat)
4. **Fix: Protocol conformance in ViewModels** - `f8e59bf` (fix)

## Files Created/Modified

**Created:**
- `App/Views/Templates/TemplateRowView.swift` — Single template row with preview thumbnail, name, date, and default star badge
- `App/Views/Templates/TemplatePreviewThumbnail.swift` — Lazy 48x48pt watermark preview renderer with PNG caching via TemplateStore
- `App/Views/Templates/TemplateListView.swift` — Full template list sheet with context menus, import/export, swipe-to-delete, and empty state

**Modified (auto-fix):**
- `App/ViewModels/WatermarkViewModel.swift` — Added `showSaveTemplateAlert` and `showTemplateList` properties
- `PhotoEditExtension/PhotosExtensionViewModel.swift` — Added `showSaveTemplateAlert` and `showTemplateList` properties
- `ShareExtension/ShareExtensionViewModel.swift` — Added `showSaveTemplateAlert` and `showTemplateList` properties

## Decisions Made

- **sourceURL parameter**: TemplateListView accepts an optional `sourceURL` parameter for preview thumbnails. ContentView will wire this from `viewModel.currentPhoto?.sourceURL` in Plan 04.
- **Export flow**: Serializes via `TemplateStore.exportData()` (strips `isDefault`) → temp `.watermarktemplate` file → `ShareSheetView` with cleanup on dismiss.
- **Import flow**: `.fileImporter` filtered to `UTType(filenameExtension: "watermarktemplate")` → `TemplateStore.import()` with error alert on failure.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Added missing `showSaveTemplateAlert` and `showTemplateList` protocol properties to all three ViewModels**
- **Found during:** Build gate verification after Task 3
- **Issue:** `WatermarkConfigurable` protocol added `showSaveTemplateAlert` and `showTemplateList` properties in Plan 12-01, but `WatermarkViewModel`, `ShareExtensionViewModel`, and `PhotosExtensionViewModel` were not updated with conforming declarations. xcodebuild failed with "type does not conform to protocol" errors.
- **Fix:** Added `var showSaveTemplateAlert: Bool = false` and `var showTemplateList: Bool = false` to all three ViewModels, each under a `// MARK: - Template Management (Phase 12)` section.
- **Files modified:** `App/ViewModels/WatermarkViewModel.swift`, `PhotoEditExtension/PhotosExtensionViewModel.swift`, `ShareExtension/ShareExtensionViewModel.swift`
- **Verification:** `bash scripts/build-gate.sh` → BUILD SUCCEEDED across all 3 targets
- **Committed in:** `f8e59bf`

---

**Total deviations:** 1 auto-fixed (Rule 3 - blocking)
**Impact on plan:** Minor — protocol conformance missing from prior plan. All three ViewModels now build successfully. No scope creep.

## Issues Encountered

None — all tasks completed as planned with one auto-fixed protocol conformance issue.

## Next Phase Readiness

- All three template UI views are built and compile across all targets
- TemplateListView is ready for Plan 04 wiring — needs `.sheet(isPresented: $viewModel.showTemplateList)` in `ContentView` with a `NavigationStack` wrapper
- TemplateRowView and TemplatePreviewThumbnail are ready for use in Plan 05 UAT verification
- Known stub: `sourceURL` parameter defaults to `nil` — Plan 04 will pass `viewModel.currentPhoto?.sourceURL` for live preview thumbnails

---
*Phase: 12-template-management*
*Completed: 2026-06-19*
