---
gsd_state_version: 1.0
milestone: v2.1
milestone_name: UI Redesign
status: executing
stopped_at: Phase 17 context gathered
last_updated: "2026-06-22T07:02:01.713Z"
last_activity: 2026-06-21 -- Phase 16 execution started
progress:
  total_phases: 4
  completed_phases: 2
  total_plans: 5
  completed_plans: 5
  percent: 50
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-06-21)

**Core value:** Add a watermark and share it instantly — without ever cluttering the camera roll.
**Current focus:** Phase 16 — redesigned-controls

## Current Position

Phase: 16 (redesigned-controls) — EXECUTING
Plan: 1 of 2
Plans: 3 of 3
Status: Executing Phase 16
Last activity: 2026-06-21 -- Phase 16 execution started

Progress: [███░░░░░░░] 1/4 phases

### v2.1 Phase Map

| Phase | Goal | Requirements |
|-------|------|--------------|
| 15. Visual Design System & Shared Primitives | Shared Liquid Glass chrome, section cards, button language, scroll-edge | VIS-01, VIS-02, VIS-03, VIS-04 ✓ |
| 16. Redesigned Controls | Rebuild every ControlsView control on the new design system | CTL-01..CTL-08 |
| 17. Inspector Bottom-Sheet Shell | Full-bleed hero + detent control sheet + pinned action bar | LYT-01, LYT-02, LYT-03, LYT-04 |
| 18. Cross-Target Parity & Accessibility Polish | Extension parity + a11y + empty state | XTG-01, XTG-02, UXQ-01, UXQ-02, UXQ-03, UXQ-04 |

## Performance Metrics

**Velocity:**

- Total plans completed (all milestones): 26
- v2.1 plans completed: 0

**By Phase (v2.1):**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 15. Visual Design System & Shared Primitives | 0/TBD | — | — |
| 16. Redesigned Controls | 0/TBD | — | — |
| 17. Inspector Bottom-Sheet Shell | 0/TBD | — | — |
| 18. Cross-Target Parity & Accessibility Polish | 0/TBD | — | — |

*Updated after each plan completion*

## Accumulated Context

### Decisions

- [v2.1 roadmap]: Phases 15-18 ordered by dependency: Design System (15) → Controls (16) → App Shell (17) → Cross-Target + A11y (18). Shared visual primitives ship first because every control and shell consumes them. Controls are rebuilt on those primitives before the app shell rearranges them into the bottom sheet. Cross-target parity and accessibility verification run last, after the redesigned ControlsView is final.
- [v2.1 roadmap]: Risk is concentrated in the shared `ControlsView` (consumed by App, ShareExtension, PhotoEditExtension). The redesign flows through WatermarkCore to all three; XTG-01/02 in Phase 18 explicitly verify the extensions still render and function.
- [v2.1 roadmap]: Pure presentation-layer milestone. WatermarkEngine, WatermarkConfigurable protocol surface, ViewModels' public behavior, and the data/config model are frozen. Every requirement is an observable look-and-feel change.
- [v2.1 roadmap]: Layout decision — inspector bottom-sheet: full-bleed photo hero + resizable detent sheet (peek + expanded) + pinned Share action bar. Adaptive light/dark (NOT permanent dark). iOS 26 Liquid Glass on the chrome layer with graceful fallback on the iOS 18 floor.

### Pending Todos

None yet.

### Blockers/Concerns

- **Phase 15**: Liquid Glass APIs are iOS 26+. The iOS 18 deployment floor requires graceful fallback (`if #available` paths) so chrome never renders broken/blank on older OS. Establish the fallback strategy in the design-system primitives before downstream phases depend on them.
- **Phase 16/18**: The redesigned `ControlsView` lives in WatermarkCore and is consumed by all 3 targets. Any layout assumption that only holds in the main app's bottom-sheet shell can break the extension hosts (ShareExtensionRootView, PhotosExtensionRootView). Keep ControlsView shell-agnostic.

## Deferred Items

| Category | Item | Status | Deferred At |
|----------|------|--------|-------------|
| v2.2+ | Drag-to-position watermark on preview (VIS-05) | Deferred — beyond 9 presets; future milestone | 2026-06-21 |
| v2.2+ | Glass-morph transitions via glassEffectID (VIS-06) | Deferred — polish beyond v2.1 scope | 2026-06-21 |
| v2.1+ | Template folders/categories | Deferred — premature at v2.0 | 2026-06-19 |
| v2.1+ | Template version history/undo | Deferred — overwrite-on-save sufficient for utility app | 2026-06-19 |
| v2.1+ | Batch "smart auto-position" (Vision framework) | Deferred — latency per photo kills throughput | 2026-06-19 |
| v2.1+ | Batch preview — spot check before full batch | Deferred — per-item override provides equivalent value | 2026-06-19 |

## Session Continuity

Last session: 2026-06-22T07:02:01.704Z
Stopped at: Phase 17 context gathered
Resume file: .planning/phases/17-inspector-bottom-sheet-shell/17-CONTEXT.md
