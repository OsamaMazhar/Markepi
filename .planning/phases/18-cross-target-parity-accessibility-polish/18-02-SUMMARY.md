---
phase: 18-cross-target-parity-accessibility-polish
plan: "02"
subsystem: a11y
tags: [voiceover, accessibility, reduce-motion, swiftui]

# Dependency graph
requires:
  - phase: 17-inspector-bottom-sheet-shell
    provides: "MarkepiPillBar, ControlSection, InspectorSheetView reduceMotion gate"
  - phase: 16-redesigned-controls
    provides: "Redesigned ControlsView with pill bar sections and glass containers"
  - phase: 15-visual-design-system-shared-primitives
    provides: "MarkepiGlassModifier, MarkepiTypography, MarkepiButtonStyle"
provides:
  - "VoiceOver labels on pill bar segments (Watermark/Style/Output controls) with .isSelected trait"
  - "VoiceOver group labels on ControlSection glass containers (Text and position, Export options, Template controls)"
  - "Reduce Motion gating on pill bar matched-geometry sliding indicator"
  - "Reduce Motion environment on BatchProgressOverlay for Plan 18-03 call site gating"
affects: [18-03, accessibility, cross-target]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "SwiftUI .accessibilityElement(children: .contain) for custom container VoiceOver grouping"
    - "SwiftUI .accessibilityAddTraits(.isButton, .isSelected) for segmented control accessibility"
    - "withAnimation(reduceMotion ? nil : .spring(...)) for instant state change when Reduce Motion enabled"

key-files:
  created: []
  modified:
    - "Packages/WatermarkCore/Sources/WatermarkCore/DesignSystem/MarkepiPillBar.swift"
    - "Packages/WatermarkCore/Sources/WatermarkCore/UI/ControlsView.swift"
    - "App/Views/Batch/BatchProgressOverlay.swift"

key-decisions:
  - "D-13: Pill bar segments labeled 'Watermark controls', 'Style controls', 'Output controls' with .isSelected trait on active segment"
  - "D-14: Pill bar withAnimation gated on reduceMotion; InspectorSheetView and ShareActionButton verified already gated (Phase 17)"
  - "D-11: Accessibility audit — ContentView .animation(.easeInOut) line 163 and .transition(.opacity) line 194 documented for Plan 18-03"

patterns-established:
  - "Pill bar VoiceOver pattern: .accessibilityElement(children: .contain) on HStack container + per-segment .accessibilityLabel/.accessibilityHint/.accessibilityAddTraits"
  - "ControlSection VoiceOver pattern: label: String init parameter → .accessibilityElement(children: .contain) + .accessibilityLabel on VStack"
  - "Reduce Motion gating pattern: withAnimation(reduceMotion ? nil : .spring(...)) for nil = instant switch"

requirements-completed: [UXQ-01, UXQ-02, UXQ-03]

# Test tracking
tests_added: 0
tests_modified: 0

# Metrics
duration: 3 min 30 sec
completed: 2026-06-22
---

# Phase 18 Plan 02: Accessibility Polish — VoiceOver Labels and Reduce Motion Gating

**VoiceOver labels on pill bar segments with .isSelected trait, ControlSection container group labels, and Reduce Motion gating on pill bar matched-geometry animation**

## Performance

- **Duration:** 3 min 30 sec
- **Started:** 2026-06-22T10:30:29Z
- **Completed:** 2026-06-22T10:33:59Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments

- Pill bar segments now have VoiceOver labels ("Watermark controls", "Style controls", "Output controls") with `.isSelected` trait on the active segment and hints ("Shows watermark settings", etc.)
- ControlSection glass containers now have descriptive VoiceOver group labels ("Text and position controls", "Export options", "Template controls") via a new `label: String` parameter
- Pill bar `withAnimation` gated on `reduceMotion` — when Reduce Motion is enabled, selection switches instantly without the spring sliding animation
- BatchProgressOverlay now declares `@Environment(\.accessibilityReduceMotion)` for Plan 18-03 call site transition gating
- InspectorSheetView and ShareActionButton reduceMotion gating verified (already implemented in Phase 17)
- ContentView ungated animation sites (`.animation(.easeInOut)` line 163, `.transition(.opacity)` line 194) documented for Plan 18-03

## Task Commits

1. **Task 1: VoiceOver Labels for Pill Bar Segments and ControlSection Containers** — `30b0388` (feat)
2. **Task 2: Reduce Motion Gating — Pill Bar Animation and Batch Overlay Transition** — `800afbf` (feat)

## Files Created/Modified

- `Packages/WatermarkCore/Sources/WatermarkCore/DesignSystem/MarkepiPillBar.swift` — Added `@Environment(\.accessibilityReduceMotion)`, `.accessibilityElement(children: .contain)` with group label on HStack, per-segment `.accessibilityLabel`/`.accessibilityHint`/`.accessibilityAddTraits`, and `withAnimation(reduceMotion ? nil : .spring(...))` gate
- `Packages/WatermarkCore/Sources/WatermarkCore/UI/ControlsView.swift` — ControlSection now has `label: String` parameter with custom `init`, `.accessibilityElement(children: .contain)` + `.accessibilityLabel(label)` on VStack, updated all 4 call sites
- `App/Views/Batch/BatchProgressOverlay.swift` — Added `@Environment(\.accessibilityReduceMotion)` declaration for Plan 18-03 usage

## Decisions Made

- ControlSection used a new `label: String` init parameter instead of a generic approach — callers pass descriptive labels at each instantiation site, keeping the struct generic over content while providing accessibility context
- Reduce Motion gating for ContentView's `.animation(.easeInOut)` and `.transition(.opacity)` deferred to Plan 18-03 (already touches ContentView.swift)
- InspectorSheetView and ShareActionButton reduceMotion gating verified as read-only audits — no code changes needed (Phase 17 implementation confirmed correct)

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered

- `xcodebuild test -scheme WatermarkCore` is not configured for the test action — used `xcodebuild build -scheme WatermarkApp` for build verification instead, which covers all 3 targets including WatermarkCore
- "iPhone 16 Pro" simulator not available in the environment — used "iPhone 17 Pro" which is the closest available simulator runtime

## User Setup Required

None — no external service configuration required.

## TDD Gate Compliance

Not applicable — this is a `type: execute` plan (accessibility labels and animation gating), not a `type: tdd` plan. No RED/GREEN/REFACTOR gate sequence required.

## Next Phase Readiness

- Accessibility labels and Reduce Motion gates are additive-only — all existing labels preserved unchanged
- ContentView `.transition(.opacity)` and `.animation(.easeInOut)` gating remains for Plan 18-03 (already documented in audit)
- Ready for Plan 18-03 to consume the `reduceMotion` environment on BatchProgressOverlay

## Known Stubs

None — all accessibility labels and animation gates are fully wired.

---

*Phase: 18-cross-target-parity-accessibility-polish*
*Completed: 2026-06-22*
