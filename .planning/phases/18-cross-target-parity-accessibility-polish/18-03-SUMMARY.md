---
phase: 18-cross-target-parity-accessibility-polish
plan: "03"
subsystem: ui
tags: [swiftui, accessibility, design-system, empty-state, dynamic-type, reduce-motion]

# Dependency graph
requires:
  - phase: 15-visual-design-system-shared-primitives
    provides: "MarkepiGlassModifier, MarkepiTypography, MarkepiButtonStyle — design primitives consumed by EmptyStateView"
  - phase: 17-inspector-bottom-sheet-shell
    provides: "InspectorSheetView, ShareActionButton — sheet/bar hidden when empty state shown"
provides:
  - "EmptyStateView shared component in WatermarkCore/DesignSystem"
  - "Empty state integration in ContentView with sheet/bar hiding"
  - "Dynamic Type-responsive expanded sheet height (55% → 70% at .xxLarge)"
  - "Reduce Motion gates on preview animation and batch overlay transition"
  - "Extension idle state replacement with EmptyStateView (Share + Photos)"
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Shared design system component pattern (EmptyStateView → consumed by app + both extensions)"
    - "Environment-driven accessibility gating (@Environment variables for ReduceMotion, ReduceTransparency, DynamicTypeSize)"
    - "Optional closure parameter pattern for conditional CTA rendering (onChoosePhoto: (() -> Void)?)"
    - "sourceURL == nil guard pattern for distinguishing true idle from transient loading in extensions"

key-files:
  created:
    - "Packages/WatermarkCore/Sources/WatermarkCore/DesignSystem/EmptyStateView.swift"
  modified:
    - "App/Views/ContentView.swift"
    - "App/Views/PreviewArea/PreviewView.swift"
    - "ShareExtension/ShareExtensionRootView.swift"
    - "PhotoEditExtension/PhotosExtensionRootView.swift"

key-decisions:
  - "EmptyStateView CTA renders conditionally via optional onChoosePhoto closure — main app passes closure, extensions pass nil"
  - "Empty state gated on currentPhoto == nil AND renderingState != .rendering to prevent flash during batch processing"
  - "Expanded sheet height threshold at DynamicTypeSize >= .xxLarge (~135% base) — balances screen real estate with usability"
  - "sourceURL == nil check in extensions distinguishes true idle from transient loading to prevent EmptyStateView flash"
  - "PreviewView renders Color.clear as fallback (not EmptyStateView) — empty state is a ContentView-level concern"

patterns-established:
  - "Shared design system component consumed by all 3 targets via WatermarkCore import"

requirements-completed: [UXQ-01, UXQ-03, UXQ-04]

# Test tracking
tests_added: 0
tests_modified: 0

# Metrics
duration: 5 min
completed: 2026-06-22
---

# Phase 18 Plan 03: Empty State Redesign & Accessibility Polish Summary

**Shared EmptyStateView component integrated across all 3 targets with Dynamic Type sheet scaling and Reduce Motion gating on preview/batch animations, replacing old pill-button and extension idle states.**

## Performance

- **Duration:** 5 min
- **Started:** 2026-06-22T10:30:20Z
- **Completed:** 2026-06-22T10:35:23Z
- **Tasks:** 3
- **Files modified:** 5 (1 created, 4 modified)

## Accomplishments

- Created shared `EmptyStateView` design system component with glass circle, SF Symbol, headline/body text, and conditional CTA button
- Integrated empty state into ContentView — when no photo loaded, sheet and Share bar are hidden; reappear when media loads
- Implemented Dynamic Type-responsive expanded sheet height (55% default, 70% at `.xxLarge` and above)
- Added Reduce Motion gates on preview rendering state animation and batch progress overlay transition
- Removed deprecated `pickerButton` ("Add Photos" ultraThinMaterial pill) from PreviewView
- Replaced extension idle states with `EmptyStateView(onChoosePhoto: nil)` in both Share and Photos extensions, with `sourceURL == nil` guard to prevent flash during loading

## Task Commits

Each task was committed atomically:

1. **Task 1: EmptyStateView Shared Component** — `394f163` (feat)
2. **Task 2: ContentView Integration** — `fccde2d` (feat)
3. **Task 3: Extension Idle State Replacement** — `6ebac25` (feat)

**Plan metadata:** (pending — summary commit below)

## Files Created/Modified

- `Packages/WatermarkCore/Sources/WatermarkCore/DesignSystem/EmptyStateView.swift` — New shared empty state component (76 lines). Glass circle with SF Symbol, Markepi typography, conditional CTA button, Reduce Transparency gate, VoiceOver grouping.
- `App/Views/ContentView.swift` — Added `@Environment(dynamicTypeSize)` and `@Environment(accessibilityReduceMotion)`. Restructured `mainLayout` with empty state branch. Dynamic Type sheet height scaling. Reduce Motion gates on preview animation and batch overlay transition.
- `App/Views/PreviewArea/PreviewView.swift` — Removed `pickerButton` computed property and its usage. Fallback branch now renders `Color.clear` — empty state handled at ContentView level.
- `ShareExtension/ShareExtensionRootView.swift` — Idle branch changed from VStack with photo icon to `EmptyStateView(onChoosePhoto: nil)` when `sourceURL == nil`. Preserved "Preparing photo..." loading state.
- `PhotoEditExtension/PhotosExtensionRootView.swift` — Same pattern: `EmptyStateView(onChoosePhoto: nil)` idle state with `sourceURL == nil` guard.

## Decisions Made

- **Optional `onChoosePhoto` closure** — Enables one component for all 3 targets. Main app passes a closure; extensions pass `nil`. Cleaner than a `showCTA: Bool` parameter because the closure itself carries the intent.
- **Empty state gate: `currentPhoto == nil AND renderingState != .rendering`** — Prevents the empty state from flashing during batch processing when photo data briefly shows nil between items. The `.rendering` check keeps the inspector shell during active work.
- **Dynamic Type threshold at `.xxLarge` (~135% base)** — This is the point where standard controls start wrapping/clipping. 70% height gives enough room for large type without overwhelming the preview area.
- **sourceURL guard in extensions** — Distinguishes "truly idle" (no media loaded) from "loading in progress" (sourceURL set but preview not yet generated). Prevents EmptyStateView flash between media selection and preview generation.

## Deviations from Plan

None — plan executed exactly as written.

### Pre-existing Issue (Out of Scope)

The full `build-gate.sh` fails due to `ControlsView.swift` compilation errors (missing `label` parameter on `ControlSection` calls). This is from concurrently executing Plan 18-02 which modifies ControlsView.swift. Per the scope boundary: logged, not fixed. Individual target builds (`WatermarkCore` scheme, `WatermarkApp` scheme with `iPhone 17 Pro` simulator) all pass cleanly.

## Issues Encountered

- **Build gate pre-existing failure:** `build-gate.sh` fails on ControlsView.swift due to concurrent 18-02 work in progress. Verified all 18-03 changes compile via direct `xcodebuild -scheme WatermarkApp build` which succeeds. The build gate will pass once 18-02 completes its ControlsView.swift fixes.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

Ready for manual QA verification of empty state UI, Dynamic Type sheet scaling, and Reduce Motion behavior. All code changes compile and pass automated build checks. The verifier agent should confirm:
- Cold launch empty state renders correctly (Task 1 UAT)
- Dynamic Type at 200% shows expanded sheet (Task 2 UAT)
- Reduce Motion gates work as expected (Task 2 UAT)
- Extension idle states show EmptyStateView without CTA (Task 3 UAT)

---

*Phase: 18-cross-target-parity-accessibility-polish*
*Completed: 2026-06-22*
