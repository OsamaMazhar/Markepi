---
phase: 16-redesigned-controls
plan: 02
subsystem: ui
tags: [swiftui, markepi, design-system, controls, typography, buttons]

# Dependency graph
requires:
  - phase: 15-visual-design-system-and-shared-primitives
    provides: MarkepiTypography, MarkepiButtonStyle, MarkepiGlassModifier design system primitives
provides:
  - All 6 sub-view files restyled on Markepi design system (inset grouped row pattern, semantic typography, capsule buttons)
affects: [16-redesigned-controls, controls-view, inspector-bottom-sheet-shell]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Inset grouped row pattern with glass-backed VStack container + section header"
    - "MarkepiTypography semantic font styles (.sectionHeader, .controlLabel, .value, .metadata)"
    - "MarkepiButtonStyle capsule buttons with D-10 role mapping (.primary/.destructive)"
    - "D-11 label conventions: primary=icon+text, destructive=text-only or icon-only"
    - "Active-layer highlight: Color.accentColor.opacity(0.08) background on selected row"

key-files:
  created: []
  modified:
    - Packages/WatermarkCore/Sources/WatermarkCore/UI/TextWatermarkInputView.swift
    - Packages/WatermarkCore/Sources/WatermarkCore/UI/ScaleStepperView.swift
    - Packages/WatermarkCore/Sources/WatermarkCore/UI/WhiteFrameToggleView.swift
    - Packages/WatermarkCore/Sources/WatermarkCore/UI/LogoPickerView.swift
    - Packages/WatermarkCore/Sources/WatermarkCore/UI/SignatureCaptureView.swift
    - Packages/WatermarkCore/Sources/WatermarkCore/UI/LayerListView.swift

key-decisions:
  - "Removed separatorColor from TextWatermarkInputView (glass backing replaces border)"
  - "ScaleStepperView simplified to single HStack row (container glass handled by parent ControlsView)"
  - "LayerListView remove buttons changed from .foregroundStyle(.red) to .buttonStyle(.markepiDestructive()) — icon-only per D-11"
  - "#else stub Close button changed from .bordered to .markepiSecondary() for consistency"

patterns-established:
  - "Pattern 1: Glass-backed inset grouped row — VStack(spacing: 0) { sectionHeader + container(.markepiGlass) }"
  - "Pattern 2: Semantic typography — .markepiTypography(.controlLabel) for labels, .value for readouts, .metadata for subtitles"
  - "Pattern 3: D-10 button role mapping — add/edit = .primary (icon+text), remove = .destructive (text-only or icon-only)"
  - "Pattern 4: Active-layer highlight — Color.accentColor.opacity(0.08) background + .accentColor icon tint"

requirements-completed: [CTL-02, CTL-03, CTL-04, CTL-05, CTL-06]

# Test tracking (auto-populated by executor)
tests_added: 0
tests_modified: 0

# Metrics
duration: 3min
completed: 2026-06-21
---

# Phase 16 Plan 02: Sub-View Restyle Summary

**All 6 sub-view files (TextWatermarkInputView, ScaleStepperView, WhiteFrameToggleView, LogoPickerView, SignatureCaptureView, LayerListView) restyled onto the Phase 15 Markepi design system — inset grouped row pattern, semantic typography, and capsule button styles — with zero behavior changes to ViewModel bindings or data flow.**

## Performance

- **Duration:** 3 min
- **Started:** 2026-06-21T19:25:07Z
- **Completed:** 2026-06-21T19:28:54Z
- **Tasks:** 2
- **Files modified:** 6

## Accomplishments
- All 6 sub-view files now use MarkepiTypography (.sectionHeader, .controlLabel, .value, .metadata) instead of raw `.font()` calls
- All buttons use MarkepiButtonStyle (.markepiPrimary() for add/edit, .markepiDestructive() for remove) instead of `.buttonStyle(.bordered)` and `.foregroundStyle(.red/.blue)`
- Glass-backed inset grouped row containers (`.markepiGlass()`) on files that own their section (TextWatermarkInputView, LogoPickerView, SignatureCaptureView, LayerListView)
- Active-layer visual highlight (accentColor.opacity(0.08) + icon tint) added to LayerListView
- All existing accessibility labels preserved; all ViewModel bindings and protocol calls untouched

## Task Commits

Each task was committed atomically:

1. **Task 1: Restyle TextWatermarkInputView, ScaleStepperView, and WhiteFrameToggleView** - `f95b666` (feat)
2. **Task 2: Restyle LogoPickerView, SignatureCaptureView, and LayerListView** - `c48be8e` (feat)

## Files Created/Modified
- `Packages/WatermarkCore/Sources/WatermarkCore/UI/TextWatermarkInputView.swift` - Glass-backed inset grouped row with .markepiTypography(.sectionHeader/.controlLabel) + .markepiGlass()
- `Packages/WatermarkCore/Sources/WatermarkCore/UI/ScaleStepperView.swift` - Single HStack row with .markepiTypography(.controlLabel/.value) live percentage readout
- `Packages/WatermarkCore/Sources/WatermarkCore/UI/WhiteFrameToggleView.swift` - Compact toggle row with .markepiTypography(.controlLabel/.metadata)
- `Packages/WatermarkCore/Sources/WatermarkCore/UI/LogoPickerView.swift` - Glass-backed section with .markepiPrimary() add, .markepiDestructive() remove
- `Packages/WatermarkCore/Sources/WatermarkCore/UI/SignatureCaptureView.swift` - Glass-backed section with .markepiPrimary() add/edit, .markepiDestructive() remove; #else stub updated
- `Packages/WatermarkCore/Sources/WatermarkCore/UI/LayerListView.swift` - Glass-backed section with active-layer highlight, icon-only destructive remove, layerTypeName/layerSubtitle helpers

## Decisions Made
- Removed `separatorColor` computed property from TextWatermarkInputView (glass backing replaces the border)
- ScaleStepperView simplified to single HStack row — parent ControlsView provides the section container
- LayerListView remove button uses icon-only destructive (red X, no text label) per D-11

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed `ShapeStyle.accentColor` type error in ternary expression**
- **Found during:** Task 2 (LayerListView)
- **Issue:** `.foregroundStyle(viewModel.activeLayerIndex == index ? .accentColor : .secondary)` failed to compile — `ShapeStyle` has no member `accentColor` in ternary context
- **Fix:** Changed to explicit `Color.accentColor` and `Color.secondary`
- **Files modified:** `LayerListView.swift`
- **Verification:** Build gate passed after fix
- **Committed in:** `c48be8e` (Task 2 commit)

**2. [Rule 1 - Bug] Removed non-existent `.labelStyle(.iconAndText)`**
- **Found during:** Task 2 (SignatureCaptureView)
- **Issue:** `.labelStyle(.iconAndText)` doesn't exist in SwiftUI — `Label` already defaults to showing icon+text
- **Fix:** Removed the `.labelStyle(.iconAndText)` modifier
- **Files modified:** `SignatureCaptureView.swift`
- **Verification:** Build gate passed after fix
- **Committed in:** `c48be8e` (Task 2 commit)

**3. [Rule 2 - Missing Critical] Updated `#else` stub Close button from `.bordered` to `.markepiSecondary()`**
- **Found during:** Plan-level verification (Task 2)
- **Issue:** The non-UIKit stub's "Close" button still used `.buttonStyle(.bordered)`, violating the zero-`.bordered` success criterion
- **Fix:** Changed to `.buttonStyle(.markepiSecondary())` — "Close" is a secondary/dismiss action per D-10
- **Files modified:** `SignatureCaptureView.swift` (#else branch)
- **Verification:** Build gate passed; zero `.bordered` across all 6 files
- **Committed in:** `c48be8e` (Task 2 commit, amended)

---

**Total deviations:** 3 auto-fixed (2 bugs, 1 missing critical)
**Impact on plan:** All auto-fixes necessary for compilation correctness and consistency with design system. No scope creep.

## Issues Encountered
None — all issues were handled as auto-fix deviations above.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- All 6 sub-view files are now Markepi-styled and ready for integration into ControlsView's three pill-bar sections (CTL-01 already shipped in Plan 01)
- CTL-07 (ControlsView assembly wiring) and CTL-08 (PreviewView restyle) remain for Phase 16 completion
- Ready for Plan 03 (if applicable) or Phase 17 inspector bottom-sheet shell

---
## Self-Check: PASSED

- SUMMARY.md exists on disk ✓
- VERIFICATION.md exists on disk ✓
- Commit f95b666 found in git log ✓
- Commit c48be8e found in git log ✓
- `scripts/sync-requirements.sh` exited 0 (CTL-02 through CTL-06 marked complete) ✓

---
*Phase: 16-redesigned-controls*
*Completed: 2026-06-21*
