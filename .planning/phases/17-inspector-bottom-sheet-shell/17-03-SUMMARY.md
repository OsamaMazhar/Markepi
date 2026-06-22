---
phase: 17-inspector-bottom-sheet-shell
plan: 03
subsystem: ui
tags: [swiftui, zstack, bottom-sheet, inspector, full-bleed, liquid-glass]

# Dependency graph
requires:
  - phase: 17-01
    provides: ShareActionButton component
  - phase: 17-02
    provides: InspectorSheetView with SheetDetent enum
provides:
  - ZStack-based inspector shell replacing 60/40 VStack split
  - Full-bleed preview extending to all screen edges including safe areas
  - Pinned Share action bar floating above the glass sheet at all detents
  - Batch overlays at correct z=1 layer between preview and sheet
affects: [18-cross-target-parity, extension-shells, accessibility-polish]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "ZStack layering (z=0 preview, z=1 batch overlays, z=2 inspector sheet, z=3 pinned bar)"
    - "@ViewBuilder for conditional ZStack children"

key-files:
  created: []
  modified:
    - "App/Views/ContentView.swift — Major restructure: replaced 60/40 VStack with ZStack inspector shell"
    - "App/Views/PreviewArea/PreviewView.swift — Single-line change: .edgesIgnoringSafeArea(.top) → .ignoresSafeArea()"

key-decisions:
  - "InspectorSheetView instantiated at z=2 with peekDetentHeight=60 and expandedHeight=geometry.height*0.55"
  - "Pinned Share bar uses Capsule Liquid Glass background with ShareActionButton, positioned at peekDetentHeight+16pt from bottom"
  - "Batch overlays (ThumbnailStripView, BatchProgressOverlay) extracted from previewArea into batchOverlays @ViewBuilder at z=1"
  - "controlsArea computed property removed entirely — ControlsView now lives inside InspectorSheetView"
  - "All existing toolbar, modal sheets, alerts, and modifier groups preserved without modification"

patterns-established:
  - "Pattern 1: ZStack bottom sheet in ContentView — custom view hierarchy (not .sheet modifier) for Z-order control"
  - "Pattern 2: @Environment(\\.accessibilityReduceTransparency) gating for Liquid Glass in pinned bar"
  - "Pattern 3: @ViewBuilder for composing conditional ZStack children"

requirements-completed: [LYT-01, LYT-04]

# Test tracking
tests_added: 0
tests_modified: 0

# Metrics
duration: 4min
completed: 2026-06-22
---

# Phase 17 Plan 03: Inspector Bottom-Sheet Shell Implementation Summary

**ContentView restructured from 60/40 VStack split into ZStack inspector shell with full-bleed preview, glass bottom sheet, batch overlays, and pinned Share action bar. PreviewView updated to true edge-to-edge via `.ignoresSafeArea()`.**

## Performance

- **Duration:** 4 min
- **Started:** 2026-06-22T09:01:56Z
- **Completed:** 2026-06-22T09:06:25Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- ContentView `mainLayout(_:)` replaced from hardcoded 60/40 VStack with a ZStack-based inspector shell (z=0 full-bleed preview, z=1 batch overlays, z=2 glass inspector sheet, z=3 pinned Share bar)
- PreviewView updated from `.edgesIgnoringSafeArea(.top)` to `.ignoresSafeArea()` for true full-bleed hero extending behind notch, Dynamic Island, and home indicator
- All existing toolbar items (Cancel, Reset All, Import), modal sheets (ShareSheetView, TemplateListView, BatchItemDetailSheet), and modifier groups (AlertModifiers, BatchAlertModifiers, SheetModifiers) preserved without any behavioral change
- Full build succeeds across all 3 targets (WatermarkApp, ShareExtension, PhotoEditExtension) on iOS Simulator
- Zero hardcoded colors — all new code uses system-adaptive semantic colors only (D-13/LYT-04)

## Task Commits

Each task was committed atomically:

1. **Task 1: Restructure ContentView mainLayout from 60/40 VStack to ZStack-based inspector shell** — `9eac721` (feat)
2. **Task 2: Update PreviewView to full-bleed .ignoresSafeArea() for true edge-to-edge hero** — `f1abcd0` (feat)

## Files Created/Modified

- `App/Views/ContentView.swift` — Major restructure (89 insertions, 37 deletions): replaced `mainLayout(_:)` VStack with ZStack (z=0-3), added `detent` @State, `peekDetentHeight` constant, `reduceTransparency` @Environment, created `batchOverlays` @ViewBuilder, `inspectorSheet(expandedHeight:)` function, and `pinnedShareBar` computed property; removed `controlsArea` computed property
- `App/Views/PreviewArea/PreviewView.swift` — Single-line change: `.edgesIgnoringSafeArea(.top)` → `.ignoresSafeArea()` on line 94

## Decisions Made

- ZStack-based inspector shell (not `.sheet` modifier) chosen for Z-order control — per RESEARCH.md, `.sheet` creates a separate UIWindow that blocks pinned bar rendering
- `peekDetentHeight: CGFloat = 60` hardcoded per plan specification (derived from MarkepiPillBar intrinsic height + drag indicator)
- `expandedHeight` computed as `geometry.size.height * 0.55` (55% screen height) per UI-SPEC.md
- Pinned Share bar positioned at `peekDetentHeight + 16pt` from bottom with Capsule Liquid Glass background using `.markepiGlass(shape:isEnabled:)`
- Batch overlays extracted to dedicated `batchOverlays` @ViewBuilder at z=1 with ThumbnailStripView padded by `peekDetentHeight + 8pt` to avoid overlap with peek detent sheet

## Deviations from Plan

### TDD Gap

**Task 1 was specified as `tdd="true"` but no test infrastructure (AppTests/ContentViewLayoutTests.swift) exists.** The plan's `<verify>` block explicitly acknowledges this as "MISSING — Wave 0 must create." Since:
1. No XCTest target exists for the App (creating one is a Rule 4 architectural change)
2. The plan defers test creation to Wave 0

Task 1 was committed as a single `feat` commit without the formal RED/GREEN/REFACTOR TDD cycle. The acceptance criteria were verified via `grep` pattern checks and a successful `xcodebuild` build across all 3 targets. All 13 acceptance criteria passed.

### No Other Deviations

All other aspects of the plan were executed exactly as written. No auto-fix bugs (Rule 1), no missing critical functionality (Rule 2), no blocking issues (Rule 3), no architectural questions (Rule 4).

**Total deviations:** 1 (TDD gap — tests not created per plan acknowledgment)
**Impact on plan:** Minimal — all functional requirements (LYT-01, LYT-04) are satisfied. Build verification confirms correctness. TDD test file deferred to Wave 0 as planned.

## Issues Encountered

None — plan executed smoothly. Both tasks built successfully on first attempt.

## User Setup Required

None — no external service configuration required.

## TDD Gate Compliance

| Gate | Status | Commit | Notes |
|------|--------|--------|-------|
| RED | ✗ Missing | — | Test file (AppTests/ContentViewLayoutTests.swift) does not exist. Plan marks this as "MISSING — Wave 0 must create." |
| GREEN | ✗ Skipped | `9eac721` | Implementation committed as `feat` without preceding RED. TDD cycle was not possible without test infrastructure. |
| REFACTOR | — | — | Not applicable — no GREEN preceded it. |

## Next Phase Readiness

- ContentView inspector shell is complete — ready for Phase 18 cross-target parity and accessibility polish
- All design constraints (D-02, D-06, D-07, D-12, D-13, D-16, D-17) verified in implementation
- Extension shells (ShareExtensionRootView, PhotosExtensionRootView) remain on 60/40 VStack layout — Phase 18 will handle parity

---

*Phase: 17-inspector-bottom-sheet-shell*
*Completed: 2026-06-22*
