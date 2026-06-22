---
phase: 17-inspector-bottom-sheet-shell
plan: 01
subsystem: ui
tags: [swiftui, share-button, extraction, design-system, state-machine]

# Dependency graph
requires: []
provides:
  - "Standalone ShareActionButton component in WatermarkCore/DesignSystem/ with all 6 rendering states"
  - "ControlsView wired to ShareActionButton as drop-in replacement, shareButton computed property removed"
affects: [17-02-pinned-action-bar, 17-03-detent-sheet]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Generic ViewModel constraint pattern: <ViewModel: WatermarkConfigurable & Observable> for DesignSystem components"
    - "SwiftUI view extraction pattern: verbatim code-move from container view to standalone component"
    - "State machine pattern: 6-case switch (idle/rendering/renderingVideo/batchProcessing/done/error) with protocol-driven ViewModel interaction"

key-files:
  created:
    - Packages/WatermarkCore/Sources/WatermarkCore/DesignSystem/ShareActionButton.swift
    - Packages/WatermarkCore/Tests/WatermarkCoreTests/ShareActionButtonTests.swift
    - Packages/WatermarkCore/Tests/WatermarkCoreTests/TestHelpers/MockRenderingViewModel.swift
  modified:
    - Packages/WatermarkCore/Sources/WatermarkCore/UI/ControlsView.swift

key-decisions:
  - "Extracted Share button rendering state machine verbatim from ControlsView:239-358 — code move, not rewrite"
  - "Replaced isBatchMode references with viewModel.hasMultiplePhotos (protocol property) for placement-agnostic correctness"
  - "Created MockRenderingViewModel spy for testing — conforms to WatermarkConfigurable & Observable with call counters"

patterns-established:
  - "Pattern 1: DesignSystem component extraction — verbatim code-move from container view; private helpers for complex switch cases; @State viewModel + @Environment accessibility"
  - "Pattern 2: TDD for SwiftUI view extraction — RED (mock + tests referencing non-existent type) → GREEN (create component) → skip REFACTOR (verbatim extraction)"

requirements-completed:
  - LYT-03

# Test tracking (auto-populated by executor)
tests_added: 2
tests_modified: 0

# Metrics
duration: ~15min
completed: 2026-06-22
---

# Phase 17 Plan 01: ShareActionButton Extraction Summary

**Standalone ShareActionButton extracted from ControlsView into WatermarkCore/DesignSystem/, preserving all 6 rendering states and protocol surface, with ControlsView wired as drop-in replacement.**

## Performance

- **Duration:** ~15 min
- **Started:** 2026-06-22T10:30:00Z
- **Completed:** 2026-06-22T08:44:39Z
- **Tasks:** 2
- **Files modified:** 4 (1 created production, 1 modified production, 2 created test)

## Accomplishments

- Extracted Share button rendering state machine (120 lines) from ControlsView into standalone `ShareActionButton` component in `WatermarkCore/DesignSystem/`
- Preserved all 6 rendering states with verbatim button copy, icons, animations, and protocol method calls
- Replaced `isBatchMode` references with `viewModel.hasMultiplePhotos` for placement-agnostic correctness (D-08)
- Created mock ViewModel (`MockRenderingViewModel`) with spy callbacks for testing protocol interactions
- ControlsView now uses `ShareActionButton(viewModel: viewModel)` — `shareButton` computed property removed, shell-agnostic mandate (D-14) preserved

## Task Commits

Each task was committed atomically:

1. **Task 1: Extract ShareActionButton (TDD)** - `104e90a` (test: RED), `765a758` (feat: GREEN)
2. **Task 2: Wire ControlsView, remove shareButton** - `ef5ae89` (feat)

## Files Created/Modified

- `Packages/WatermarkCore/Sources/WatermarkCore/DesignSystem/ShareActionButton.swift` — Standalone Share button component, generic over `WatermarkConfigurable & Observable`, 6-state rendering machine with video/batch helper methods
- `Packages/WatermarkCore/Sources/WatermarkCore/UI/ControlsView.swift` — `shareButton` computed property removed (lines 239-358), replaced with inline `ShareActionButton(viewModel: viewModel)` in Output section
- `Packages/WatermarkCore/Tests/WatermarkCoreTests/ShareActionButtonTests.swift` — 12 tests covering constructor, body evaluation for all 6 states, and protocol interaction (spy-based)
- `Packages/WatermarkCore/Tests/WatermarkCoreTests/TestHelpers/MockRenderingViewModel.swift` — Spy mock conforming to `WatermarkConfigurable & Observable`, tracks `renderAndPrepareShareCallCount`, `presentShareSheetCallCount`, `cancelProcessingCallCount`

## Decisions Made

- Code-move extraction (not rewrite) — the shareButton computed property was extracted verbatim with `isBatchMode` → `viewModel.hasMultiplePhotos` as the only code change
- TDD approach: RED phase committed mock ViewModel + test file referencing `ShareActionButton` before the component existed; GREEN phase created the component

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered

- Pre-existing macOS build errors (`glassEffect(_:in:)` only available in macOS 26.0) in DesignSystem files prevent `swift test` from compiling via SPM. iOS xcodebuild succeeds. These errors are out of scope for this plan (pre-existing, not caused by extraction) and logged to deferred-items.md.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- `ShareActionButton` is ready for Phase 17-02 (pinned action bar) and Phase 17-03 (detent sheet)
- ControlsView is shell-agnostic and ready for placement inside the InspectorSheetView
- Mock ViewModel available for downstream testing of pinned bar and sheet components

---
*Phase: 17-inspector-bottom-sheet-shell*
*Completed: 2026-06-22*
