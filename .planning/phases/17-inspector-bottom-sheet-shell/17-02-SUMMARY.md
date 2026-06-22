---
phase: 17-inspector-bottom-sheet-shell
plan: 02
subsystem: ui
tags: [swiftui, bottom-sheet, drag-gesture, liquid-glass, ios]

# Dependency graph
requires: []
provides:
  - InspectorSheetView component with SheetDetent enum, drag-to-resize gesture, and glass surface
  - SheetDetent enum (peek/expanded) for ContentView's ZStack-based detent management
affects: [ContentView, 17-03-PLAN]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Custom ZStack bottom sheet pattern (not .sheet modifier) for Z-order control of pinned elements"
    - "DragGesture on indicator-only for native nested scroll (D-15)"
    - "Midpoint-threshold detent snap with spring animation gated on Reduce Motion"
    - "Liquid Glass via .markepiGlass(shape:isEnabled:) with Reduce Transparency gating"

key-files:
  created:
    - Packages/WatermarkCore/Sources/WatermarkCore/UI/InspectorSheetView.swift
    - Packages/WatermarkCore/Tests/WatermarkCoreTests/InspectorSheetViewTests.swift
  modified:
    - Packages/WatermarkCore/Sources/WatermarkCore/DesignSystem/GlassEffect/MarkepiGlassModifier.swift
    - Packages/WatermarkCore/Sources/WatermarkCore/DesignSystem/ScrollEdge/MarkepiScrollEdgeProtection.swift

key-decisions:
  - "Custom ZStack bottom sheet (not .sheet modifier) for full Z-order control — pinned Share bar must render above sheet"
  - "DragGesture on indicator capsule only — architectural separation from ControlsView ScrollView (D-15)"
  - "Midpoint threshold ((peekHeight + expandedHeight) / 2) for detent snap per standard iOS convention"
  - "No withAnimation in .onEnded — .animation(.spring(...), value: detent) modifier on VStack handles snap automatically (Pitfall 3)"
  - "Simplified direct-translation approach: dragOffset = -translation.height, no lastDragPosition accumulator"
  - "macOS 26 availability guard added alongside iOS 26 in MarkepiGlassModifier and MarkepiScrollEdgeProtection"

patterns-established:
  - "InspectorSheetView: generic ViewModel constraint pattern matching ControlsView (WatermarkConfigurable & Observable)"
  - "Glass surface application: UnevenRoundedRectangle clip + background + .markepiGlass() with accessibility gating"

requirements-completed:
  - LYT-02

# Test tracking
tests_added: 1
tests_modified: 0

# Metrics
duration: 7 min
completed: 2026-06-22
---

# Phase 17 Plan 02: InspectorSheetView Bottom Sheet Component Summary

**Custom ZStack-compatible bottom sheet container with drag-to-resize detent snapping, Liquid Glass surface, and native nested scroll via indicator-only DragGesture**

## Performance

- **Duration:** 7 min
- **Started:** 2026-06-22T08:47:40Z
- **Completed:** 2026-06-22T08:55:09Z
- **Tasks:** 2
- **Files modified:** 4 (2 created, 2 modified)

## Accomplishments
- `InspectorSheetView<ViewModel>` component — a generic, reusable bottom sheet container that hosts ControlsView unchanged
- `SheetDetent` enum with `.peek` and `.expanded` cases for two-detent configuration
- Drag gesture on indicator capsule with midpoint-threshold detent snap and spring animation
- Liquid Glass surface via `.markepiGlass()` with `UnevenRoundedRectangle` (20pt top, 0pt bottom corners)
- Sheet never collapses below peek height (D-04: not dismissible)
- Nested scroll preserved via architectural separation — DragGesture on indicator only, ControlsView ScrollView unimpeded (D-15)
- VoiceOver accessibility label and hint on drag indicator
- Spring animation gated on Reduce Motion, glass gated on Reduce Transparency

## Task Commits

Each task was committed atomically (TDD: RED → GREEN):

1. **Task 1 RED: Failing tests for InspectorSheetView** — `795a4ed` (test)
2. **Task 1 GREEN: InspectorSheetView implementation** — `649968f` (feat)
3. **Task 2 GREEN: Drag gesture + expanded height** — `ccab4b8` (feat)

**Plan metadata:** (pending)

_Note: Task 2 combined test update and implementation in one commit — the RED failure was transient (existing tests broke on expandedHeight param addition), and the fix was atomic. See TDD Gate Compliance below._

## Files Created/Modified
- `Packages/WatermarkCore/Sources/WatermarkCore/UI/InspectorSheetView.swift` — SheetDetent enum + InspectorSheetView struct with drag gesture, glass surface, and detent snap (created)
- `Packages/WatermarkCore/Tests/WatermarkCoreTests/InspectorSheetViewTests.swift` — 7 tests across 2 suites: SheetDetent enum cases + Equatable, InspectorSheetView init parameters (created)
- `Packages/WatermarkCore/Sources/WatermarkCore/DesignSystem/GlassEffect/MarkepiGlassModifier.swift` — Added `macOS 26` to `#available` guard alongside `iOS 26` (modified — Rule 3 fix)
- `Packages/WatermarkCore/Sources/WatermarkCore/DesignSystem/ScrollEdge/MarkepiScrollEdgeProtection.swift` — Added `macOS 26` to `#available` guard alongside `iOS 26` (modified — Rule 3 fix)

## Decisions Made
- Custom ZStack bottom sheet (not `.sheet` modifier) for full Z-order control — pinned Share bar must render above sheet per D-06
- DragGesture on indicator capsule only — architectural separation from ControlsView ScrollView (D-15)
- Midpoint threshold `(peekHeight + expandedHeight) / 2` for detent snap per standard iOS convention
- No `withAnimation` in `.onEnded` — `.animation(.spring(...), value: detent)` modifier on VStack handles snap automatically (Pitfall 3)
- Simplified direct-translation approach: `dragOffset = -translation.height`, no `lastDragPosition` accumulator
- macOS 26 availability guard added alongside iOS 26 in `MarkepiGlassModifier` and `MarkepiScrollEdgeProtection`

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] macOS 26 availability guard missing in glass modifiers**
- **Found during:** Task 1 RED phase (swift test compilation)
- **Issue:** `MarkepiGlassModifier.swift` and `MarkepiScrollEdgeProtection.swift` used `if #available(iOS 26, *)` but Package.swift specifies `macOS(.v15)` minimum. `glassEffect(_:in:)` is only available in macOS 26 — compilation failed on macOS target.
- **Fix:** Added `macOS 26` to both `#available` guards: `if #available(iOS 26, macOS 26, *)`.
- **Files modified:** `MarkepiGlassModifier.swift` (line 40), `MarkepiScrollEdgeProtection.swift` (line 68)
- **Verification:** `swift build` exits 0, all 245 tests pass
- **Committed in:** `795a4ed` (RED phase — included with test file as it blocked all compilation)

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** Essential fix for macOS target compilation. No scope creep.

## TDD Gate Compliance

**Plan type: `execute` with `tdd="true"` tasks.** Each task follows RED → GREEN.

| Task | RED Commit | GREEN Commit | Status |
|------|-----------|-------------|--------|
| Task 1 | `795a4ed` (test) | `649968f` (feat) | Pass |
| Task 2 | — (transient) | `ccab4b8` (feat) | ⚠️ Combined |

**Task 2 note:** The RED phase was a transient compilation failure — the test file was updated to add `expandedHeight` parameter tests, which failed because `expandedHeight` wasn't in the init. The fix was atomic (test update + implementation in one commit `ccab4b8`). The test DID fail before the implementation was written, but commits were combined.

## Issues Encountered
- `xcodebuild -scheme WatermarkCore test` not configured for test action — used `swift test` from package directory instead (consistent with existing test patterns in the project)
- macOS 26 availability gate blocked `swift test` compilation — Rule 3 fix applied to both glass modifier files

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness
- `InspectorSheetView` is ready for consumption by `ContentView` in plan 17-03
- Sheet component is generic over `WatermarkConfigurable & Observable` — compatible with `WatermarkViewModel`
- Peek height constant (60pt) and expanded height ratio (0.55) are parameterized — parent controls sizing
- All 245 existing tests + 7 new tests pass with zero regressions

---
*Phase: 17-inspector-bottom-sheet-shell*
*Completed: 2026-06-22*
