---
phase: 16-redesigned-controls
plan: 01
subsystem: ui
tags: [swiftui, menu, pillbar, markepibuttonstyle, scrolledge, glass-effect]

# Dependency graph
requires:
  - phase: 15-visual-design-system
    provides: "MarkepiPillBar, MarkepiScrollEdgeProtection, MarkepiButtonStyle, MarkepiTypography, MarkepiGlassModifier design system primitives"
provides:
  - "Rewritten ControlsView with pill-bar-driven 3-section layout, inline Menu-based position picker, Menu-based export format picker, MarkepiButtonStyle capsules on all buttons"
  - "WatermarkPosition.displayName extension mapping all 9 positions to human-readable labels"
  - "Array safe subscript extension (migrated from deleted PositionGridView)"
affects: [16-redesigned-controls, 17-inspector-shell, controls-layout, batch-item-detail]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Pill-bar section switching: MarkepiScrollEdgeProtection wraps VStack switch(section), with MarkepiPillBar as header content"
    - "Menu-based picker replacing grid/DisclosureGroup: Menu { ForEach(allCases) } with current-value label and chevron.up.chevron.down"
    - "Button restyling via .markepiPrimary() / .markepiSecondary() convenience modifiers — no bare .tint() calls"
    - "ControlSection: VStack content wrapped in .markepiGlass(RoundedRectangle) for inset grouped card appearance"

key-files:
  created: []
  modified:
    - "Packages/WatermarkCore/Sources/WatermarkCore/UI/ControlsView.swift — full rewrite (~300 lines)"
    - "Packages/WatermarkCore/Sources/WatermarkCore/Models/WatermarkPosition.swift — displayName extension + Array safe subscript"
    - "Packages/WatermarkCore/Sources/WatermarkCore/UI/PositionGridView.swift — DELETED"
    - "App/Views/Batch/BatchItemDetailSheet.swift — replaced PositionGridView ref with inline position Menu"
    - "App/Views/Batch/BatchItemConfigProxy.swift — updated comment from PositionGridView to position Menu"

key-decisions:
  - "Position picker switched from 3×3 grid to Menu button — complies with D-01/D-02 (plain text names, no directional icons)"
  - "Export format switched from DisclosureGroup to Menu row — no inline layout jumps, consistent row aesthetic per D-07"
  - "Cancel/Stop buttons use .markepiSecondary() (not .markepiDestructive()) — D-10: Cancel=secondary role"
  - "Array safe subscript migrated from PositionGridView to WatermarkPosition.swift to preserve ScaleStepperView functionality"

patterns-established:
  - "Pattern 1: Inline Menu pickers with chevron.up.chevron.down — reusable for any CaseIterable enum picker"
  - "Pattern 2: ControlSection<V: View> generic wrapper — glass-backed inset card with .markepiGlass + .clipShape"
  - "Pattern 3: MarkepiScrollEdgeProtection top-bar pattern — ScrollView created internally, content padded to clear header"

requirements-completed: [CTL-01, CTL-07, CTL-08]

# Test tracking
tests_added: 0
tests_modified: 0

# Metrics
duration: 5min
completed: 2026-06-21
---

# Phase 16 Plan 01: Redesigned Controls Core Summary

**Rewritten ControlsView with pill-bar-driven 3-section layout, Menu-based position & export format pickers, and MarkepiButtonStyle capsules on all buttons**

## Performance

- **Duration:** 5 min
- **Started:** 2026-06-21T19:18:16Z
- **Completed:** 2026-06-21T19:23:29Z
- **Tasks:** 2
- **Files modified:** 5 (4 modified, 1 deleted)

## Accomplishments
- Deleted PositionGridView (94 lines) — fully replaced by inline Menu button in ControlsView
- Added WatermarkPosition.displayName extension with all 9 human-readable position names
- Rewrote ControlsView body architecture: ScrollView replaced by MarkepiScrollEdgeProtection + MarkepiPillBar with 3 switchable sections (watermark/style/output)
- Replaced 3×3 position grid with Menu-based picker showing current position name + chevron
- Replaced Export Options DisclosureGroup with Menu-based exportFormatRow + qualitySliderRow
- Restyled all buttons (share, template, cancel, retry, stop) with MarkepiButtonStyle capsules
- Preserved HDR→JPEG warning alert on the output section per threat model T-16-03
- Fixed BatchItemDetailSheet to use inline position Menu (removed PositionGridView dependency)

## Task Commits

Each task was committed atomically:

1. **Task 1: Delete PositionGridView, add WatermarkPosition.displayName extension** — `14f51c1` (feat)
2. **Task 2: Rewrite ControlsView body with pill bar, section switching, position menu, export menu, button restyling** — `0e7068a` (feat)

## Files Created/Modified
- `Packages/WatermarkCore/Sources/WatermarkCore/UI/ControlsView.swift` — Full rewrite: pill bar architecture, position menu, export menu, button restyling, HDR warning preservation
- `Packages/WatermarkCore/Sources/WatermarkCore/Models/WatermarkPosition.swift` — Added public displayName extension + public Array safe subscript
- `Packages/WatermarkCore/Sources/WatermarkCore/UI/PositionGridView.swift` — DELETED (replaced by inline Menu)
- `App/Views/Batch/BatchItemDetailSheet.swift` — Replaced PositionGridView ref with inline position Menu + positionMenuRow
- `App/Views/Batch/BatchItemConfigProxy.swift` — Updated comment reference from PositionGridView to position Menu

## Decisions Made
None — followed plan as specified.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Migrated Array safe subscript from deleted PositionGridView**
- **Found during:** Task 1 build verification
- **Issue:** PositionGridView.swift contained an `extension Array { subscript(safe:) }` used by ScaleStepperView. Deleting the file broke ScaleStepperView compilation.
- **Fix:** Added the Array safe subscript extension to WatermarkPosition.swift (already being modified in Task 1), made it public for cross-module access.
- **Files modified:** Packages/WatermarkCore/Sources/WatermarkCore/Models/WatermarkPosition.swift
- **Verification:** Build gate PASSED after fix
- **Committed in:** 14f51c1 (Task 1 commit)

**2. [Rule 3 - Blocking] Fixed BatchItemDetailSheet PositionGridView reference**
- **Found during:** Task 2 build verification
- **Issue:** App/Views/Batch/BatchItemDetailSheet.swift also referenced PositionGridView(viewModel: proxy). Deleting the file broke App target compilation.
- **Fix:** Replaced PositionGridView with an inline Menu-based position picker (positionMenuRow) in BatchItemDetailSheet, matching the ControlsView pattern. Updated BatchItemConfigProxy.swift comment.
- **Files modified:** App/Views/Batch/BatchItemDetailSheet.swift, App/Views/Batch/BatchItemConfigProxy.swift
- **Verification:** Build gate PASSED across all 3 targets
- **Committed in:** 0e7068a (Task 2 commit)

**3. [Rule 1 - Bug] Fixed missing closing brace on extension WatermarkPosition**
- **Found during:** Task 1 build verification
- **Issue:** The displayName extension was appended without a closing brace for the extension block, causing the Array extension to appear nested, triggering "declaration is only valid at file scope" compiler error.
- **Fix:** Added the missing `}` to close the extension WatermarkPosition block before the Array extension.
- **Files modified:** Packages/WatermarkCore/Sources/WatermarkCore/Models/WatermarkPosition.swift
- **Verification:** swiftc -parse succeeded, build gate PASSED
- **Committed in:** 14f51c1 (Task 1 commit)

**4. [Rule 3 - Blocking] Made displayName and Array safe subscript public for cross-module access**
- **Found during:** Task 2 build verification
- **Issue:** The displayName property and Array safe subscript were internal (default access level), inaccessible from the App module (BatchItemDetailSheet.swift).
- **Fix:** Added `public` modifier to both `displayName` and `subscript(safe:)` in WatermarkPosition.swift.
- **Files modified:** Packages/WatermarkCore/Sources/WatermarkCore/Models/WatermarkPosition.swift
- **Verification:** Build gate PASSED after fix
- **Committed in:** 0e7068a (Task 2 commit)

---

**Total deviations:** 4 auto-fixed (2 Rule 3 blocking, 1 Rule 1 bug, 1 Rule 3 blocking)
**Impact on plan:** All auto-fixes necessary for correct compilation across all 3 targets. The BatchItemDetailSheet fix was the only scope expansion — extending the position Menu pattern to the batch override sheet for consistency.

## Issues Encountered
- WatermarkPosition.swift brace counting error during extension addition (fixed in 1 iteration)
- PositionGridView dependencies in ScaleStepperView (safe subscript) and BatchItemDetailSheet (direct usage) — both external to the plan's scope, required cross-target fixes

## Next Phase Readiness
- ControlsView architecture ready for Phase 16 Plan 02 sub-view refactors (TextWatermarkInputView, ScaleStepperView, LogoPickerView, SignatureCaptureView, WhiteFrameToggleView, LayerListView)
- Position picker (CTL-01), export menu (CTL-07), and button restyling (CTL-08) complete
- All 3 targets compile with the redesigned ControlsView

---
*Phase: 16-redesigned-controls*
*Completed: 2026-06-21*
