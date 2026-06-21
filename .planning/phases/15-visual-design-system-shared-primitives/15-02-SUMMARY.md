---
phase: 15-visual-design-system-shared-primitives
plan: 02
subsystem: ui
tags: [swiftui, buttonstyle, pillbar, scrolledge, glass-effect, design-system]

# Dependency graph
requires:
  - phase: 15-01
    provides: MarkepiGlassModifier (.markepiGlass), MarkepiTypography (.markepiTypography), MarkepiUtilities (.modify)
provides:
  - MarkepiButtonRole enum (primary/secondary/destructive)
  - MarkepiButtonStyle ButtonStyle (configuration-driven, capsule glass treatment)
  - ControlsSection enum (watermark/style/output)
  - MarkepiPillBar view (custom HStack + matchedGeometryEffect sliding indicator)
  - MarkepiScrollEdgeProtection<Header> ViewModifier (ZStack + scrollClipDisabled + glass header)
  - View.scrollEdgeProtection(headerContent:) View extension
affects:
  - Phase 16 (ControlsView redesign — all buttons switch to MarkepiButtonStyle, flat VStack becomes pill-bar-grouped sections)
  - Phase 17 (Inspector bottom-sheet shell — scroll view uses .markepiScrollEdgeProtection)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Configuration-driven ButtonStyle: MarkepiButtonStyle renders configuration.label; caller provides content via standard Button { } label: { }"
    - "matchedGeometryEffect pill bar: custom HStack per-segment Buttons with per-instance @Namespace for the sliding indicator"
    - "scrollClipDisabled glass header: ZStack with scroll content in back + glass header in front; header glass naturally blurs underlying content"
    - "Reduce Transparency respect: @Environment(\.accessibilityReduceTransparency) disables glass backgrounds across all primitives"

key-files:
  created:
    - Packages/WatermarkCore/Sources/WatermarkCore/DesignSystem/ButtonStyles/MarkepiButtonStyle.swift
    - Packages/WatermarkCore/Sources/WatermarkCore/DesignSystem/MarkepiPillBar.swift
    - Packages/WatermarkCore/Sources/WatermarkCore/DesignSystem/ScrollEdge/MarkepiScrollEdgeProtection.swift
  modified: []

key-decisions:
  - "Configuration-driven ButtonStyle (option 2 from RESEARCH.md): Style takes only role, renders configuration.label — standard SwiftUI idiom avoiding unused label closure"
  - "Custom HStack pill bar over PickerStyle.segmented: native segmented picker has no API for per-segment glass-effect styling"
  - "Per-instance @Namespace for matchedGeometryEffect: each MarkepiPillBar declares @Namespace private var pillNamespace, preventing ID collision when multiple pill bars exist"
  - "No separate .blur() on ScrollEdgeProtection: the .ultraThinMaterial/.glassEffect background on the header naturally blurs scrolling content"

requirements-completed: [VIS-02, VIS-03, VIS-04]

# Test tracking (auto-populated by executor)
tests_added: 0
tests_modified: 0

# Metrics
duration: 3min
completed: 2026-06-21
---

# Phase 15 Plan 02: Interaction Primitives Summary

**Three SwiftUI primitives consuming the glass/typography foundation — capsule button style with three semantic roles, 3-section pill bar with matched-geometry sliding indicator, and scroll-edge protection via glass-backed header**

## Performance

- **Duration:** 3 min
- **Started:** 2026-06-21T13:45:58Z
- **Completed:** 2026-06-21T13:49:53Z
- **Tasks:** 3
- **Files modified:** 6 (3 created, 2 .gitkeep removals, 1 VERIFICATION.md)

## Accomplishments
- `MarkepiButtonStyle` with three semantic roles (primary/secondary/destructive), capsule shape, glass treatment, and pressed-state animation — replacing `.borderedProminent`/`.bordered`/inline `.tint()` across the app
- `MarkepiPillBar` 3-section navigation (Watermark | Style | Output) with glass backing and matched-geometry sliding indicator — ready to replace the flat VStack in ControlsView
- `MarkepiScrollEdgeProtection` ViewModifier with ZStack + scrollClipDisabled + glass header — blurs scrolling content without a separate blur gradient

## Task Commits

1. **Task 1: Create MarkepiButtonStyle.swift** — `1725d4f` (feat)
2. **Task 2: Create MarkepiPillBar.swift** — `2dc7f08` (feat)
3. **Task 3: Create MarkepiScrollEdgeProtection.swift** — `513a5c9` (feat)

**Plan metadata:** Pending (will be committed alongside SUMMARY.md)

## Files Created/Modified
- `Packages/WatermarkCore/Sources/WatermarkCore/DesignSystem/ButtonStyles/MarkepiButtonStyle.swift` — Unified button language: `MarkepiButtonRole` enum + `MarkepiButtonStyle` ButtonStyle + 3 convenience extensions
- `Packages/WatermarkCore/Sources/WatermarkCore/DesignSystem/MarkepiPillBar.swift` — 3-section pill bar: `ControlsSection` enum + `MarkepiPillBar` view with matchedGeometryEffect
- `Packages/WatermarkCore/Sources/WatermarkCore/DesignSystem/ScrollEdge/MarkepiScrollEdgeProtection.swift` — Scroll-edge protection: `MarkepiScrollEdgeProtection<Header>` ViewModifier + `.markepiScrollEdgeProtection()` extension
- `Packages/WatermarkCore/Sources/WatermarkCore/DesignSystem/ButtonStyles/.gitkeep` — Removed (replaced by `.swift` file)
- `Packages/WatermarkCore/Sources/WatermarkCore/DesignSystem/ScrollEdge/.gitkeep` — Removed (replaced by `.swift` file)

## Decisions Made
- **Configuration-driven ButtonStyle:** Style renders `configuration.label` — caller controls content via standard `Button { } label: { }` pattern (RESEARCH.md recommendation option 2)
- **Custom HStack over PickerStyle.segmented:** Native segmented picker has no API for per-segment glass-effect backgrounds
- **Per-instance @Namespace:** Each `MarkepiPillBar` owns its `@Namespace private var pillNamespace` — prevents `matchedGeometryEffect` ID collision per Pitfall 3
- **Material-as-blur:** No separate `.blur()` modifier on scroll-edge protection; the `.ultraThinMaterial`/`.glassEffect` background on the header naturally provides the obscuring effect

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered

None.

## Verification

- **xcodebuild:** `BUILD SUCCEEDED` — all 3 new files compile cleanly with no `#available(iOS 26, *)` or `matchedGeometryEffect` warnings
- **Acceptance criteria:** All 6 criteria across 3 tasks pass (verified via automated grep checks)

## Next Phase Readiness

All three interaction primitives are ready for Phase 16 consumption:
- `ControlsView.swift` can switch all buttons to `.buttonStyle(.markepiPrimary())` / `.markepiSecondary()` / `.markepiDestructive()`
- The flat `VStack` becomes pill-bar-grouped sections via `MarkepiPillBar(selection: $section)`
- The scroll view wraps in `.markepiScrollEdgeProtection { MarkepiPillBar(...) }` for edge blur

---

*Phase: 15-visual-design-system-shared-primitives*
*Completed: 2026-06-21*
