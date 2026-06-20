---
phase: 12-template-management
plan: 05
subsystem: templates
tags: [swiftui, swift, uti, plist, extension-viewmodel, default-template, auto-apply]

# Dependency graph
requires:
  - phase: 12-01
    provides: TemplateStore with defaultTemplate
  - phase: 12-02
    provides: WatermarkConfigurable protocol with showSaveTemplateAlert/showTemplateList
provides:
  - Default template auto-apply on share extension import (photo + video)
  - Default template auto-apply on Photos edit extension fresh edit (guards re-edit)
  - .watermarktemplate UTI registration in all three targets (system file recognition)
affects: [batch-auto-apply, template-import-flow]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Conditional auto-apply: guard input.adjustmentData == nil before applying default template in Photos extension"
    - "UTExportedTypeDeclarations pattern for custom file type registration in Info.plist"

key-files:
  created: []
  modified:
    - ShareExtension/ShareExtensionViewModel.swift
    - PhotoEditExtension/PhotosExtensionViewModel.swift
    - App/Info.plist
    - ShareExtension/Info.plist
    - PhotoEditExtension/Info.plist

key-decisions:
  - "Default template auto-apply runs AFTER preview generation so the preview reflects the template"
  - "Photos extension guards against overwriting re-edit config by checking input.adjustmentData == nil"
  - "UTI registered as public.json conforming with .watermarktemplate extension across all three targets"

patterns-established:
  - "Extension ViewModels don't show template UI (showSaveTemplateAlert/showTemplateList always false) but conform to protocol for ControlsView compatibility"
  - "defaultTemplate auto-apply is idempotent — if no default template set, config remains unchanged"

requirements-completed:
  - TMPL-04
  - TMPL-05

# Metrics
duration: 2min
completed: 2026-06-19
---

# Phase 12 Plan 05: Extension Template Auto-Apply & UTI Registration Summary

**Default template auto-applied on extension import + .watermarktemplate UTI registered in all three Info.plist files**

## Performance

- **Duration:** 2 min
- **Started:** 2026-06-19T19:53:00Z
- **Completed:** 2026-06-19T19:55:57Z
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments

- ShareExtensionViewModel auto-applies default template on both photo and video import, right after preview generation
- PhotosExtensionViewModel conditionally auto-applies default template only on fresh edits (adjustmentData == nil); re-edits preserve saved config
- All three targets (App, ShareExtension, PhotoEditExtension) now expose .watermarktemplate file type via UTExportedTypeDeclarations
- App/Info.plist additionally registers the template in CFBundleDocumentTypes for Files app "Open In" support

## Task Commits

Each task was committed atomically:

1. **Task 1: Add template protocol conformance and auto-apply to extension ViewModels** - `0d7ae11` (feat)
2. **Task 2: Register .watermarktemplate UTI in all three Info.plist files** - `57920b2` (feat)

## Files Created/Modified

- `ShareExtension/ShareExtensionViewModel.swift` - Added auto-apply default template in loadPhotoFromProvider (line 273) and loadVideoFromProvider (line 320)
- `PhotoEditExtension/PhotosExtensionViewModel.swift` - Added conditional auto-apply in startEditing (lines 185-188), guarded by input.adjustmentData == nil
- `App/Info.plist` - Added UTExportedTypeDeclarations dict + Watermark Template CFBundleDocumentTypes entry
- `ShareExtension/Info.plist` - Added UTExportedTypeDeclarations dict with com.watermark.app.template
- `PhotoEditExtension/Info.plist` - Added UTExportedTypeDeclarations dict with com.watermark.app.template

## Decisions Made

None - followed plan as specified. Protocol conformance properties (showSaveTemplateAlert, showTemplateList) were already present from plan 12-03; only the auto-apply logic and UTI registration were needed.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- TMPL-04 (default auto-apply) and TMPL-05 (UTI registration) are now satisfied
- Ready for plan 12-04 (TemplateDetailView) — templates can now be auto-applied on import and files recognized by the system

---
## Self-Check: PASSED

- All 5 key files exist on disk
- Both task commits (0d7ae11, 57920b2) found in git log

---

*Phase: 12-template-management*
*Completed: 2026-06-19*
