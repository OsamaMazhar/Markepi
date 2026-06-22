# Phase 17: Inspector Bottom-Sheet Shell - Context

**Gathered:** 2026-06-22
**Status:** Ready for planning

<domain>
## Phase Boundary

Replace the main app's hardcoded 60/40 split (ContentView.swift) with a full-bleed photo hero and a resizable detent bottom sheet housing ControlsView, plus a standalone glass floating pill with the Share button pinned above the sheet. Works in both light and dark appearances.

**This is the main app shell only.** The ShareExtension and PhotosExtension shells are untouched — they keep their current 60/40 layout. ControlsView remains shell-agnostic (Phase 16 mandate). WatermarkEngine, ViewModels, and WatermarkConfigurable protocol are frozen.

**Requirements:** LYT-01 (full-bleed hero), LYT-02 (resizable detent sheet), LYT-03 (pinned action bar), LYT-04 (light + dark appearance)
</domain>

<decisions>
## Implementation Decisions

### Detent Strategy (LYT-02)
- **D-01:** Two detents: **peek** (pill bar only — user sees Watermark/Style/Output labels, no control content) and **expanded** (`.medium` — approximately half screen height, following the professional photo-editing app convention seen in Apple Photos, Lightroom, Darkroom).
- **D-02:** The sheet **overlays** the full-bleed preview — the preview stays edge-to-edge behind the glass sheet. No push/resize of the preview area.
- **D-03:** **Background interaction enabled** — user can tap/drag the preview image behind the sheet (e.g., pan a zoomed photo) even with the sheet visible. Use `.presentationBackgroundInteraction` (iOS 26) or equivalent.
- **D-04:** The sheet is **not dismissible** — always shows at least the peek (pill bar). The inspector is permanent chrome, not a temporary modal. Cannot be dragged off-screen.

### Share Button Extraction (LYT-03)
- **D-05:** The Share button state machine (idle → rendering → done → error) is **extracted from ControlsView into a standalone component** (e.g., `MarkepiShareButton` or `ShareActionButton`) living in WatermarkCore/DesignSystem/. This component is the single source of truth consumed by: (a) the main app's pinned action bar, (b) ControlsView's Output section, (c) the extension shells via ControlsView.
- **D-06:** The pinned action bar is a **Liquid Glass floating pill** centered at the bottom of the preview area, above the sheet. It floats independently from the sheet — always visible regardless of detent.
- **D-07:** The pinned bar contains **the Share button only** — no batch controls, no import button. Batch cancel/reset stay in the NavigationStack toolbar.
- **D-08:** The extracted component preserves the full rendering state machine: `.idle` ("Share"/"Watermark All"), `.rendering` (spinner), `.renderingVideo` (progress bar + cancel), `.batchProcessing` (progress + stop), `.done` ("Ready to Share"), `.error` ("Retry"). Calls `viewModel.renderAndPrepareShare()` / `viewModel.presentShareSheet()` via `WatermarkConfigurable` protocol.

### Sheet Chrome & Styling (LYT-04)
- **D-09:** The sheet surface is **full Liquid Glass** across its entire body — preview image is visible through the sheet. Uses `.markepiGlass()` from Phase 15. On iOS 18, falls back to `.regularMaterial` per the existing glass modifier.
- **D-10:** **Standard iOS drag indicator** shown at the top of the sheet — a small horizontal capsule signaling draggability.
- **D-11:** **Standard iOS sheet corners** — default rounded top corners, square bottom.
- **D-12:** The preview gets **no visual treatment** (no dimming, no blur, no scale) as the sheet expands. It stays full-bleed and unmodified at all detents.
- **D-13:** The shell renders correctly in both system light and dark appearance — all colors are system-adaptive (`.primary`, `.secondary`, `.accentColor`) per the Phase 15 design system. No hardcoded colors.

### ControlsView-in-Sheet Integration
- **D-14:** ControlsView is placed inside the sheet **completely unchanged** — pill bar, scroll, scroll-edge protection, all 3 pill sections. Phase 16's shell-agnostic mandate is strictly preserved. The sheet wraps ControlsView as its content.
- **D-15:** **Native nested scroll** — no custom gesture coordination. iOS handles the nesting: inner ControlsView scroll scrolls content first; sheet resize gesture activates only at scroll boundaries (top of content).
- **D-16:** Batch toolbar items (Cancel, Reset All) stay in the **NavigationStack toolbar** at the top of the screen — not in the sheet or pinned bar.
- **D-17:** Batch overlays (ThumbnailStripView, BatchProgressOverlay) remain **above the sheet on the preview area** — they float at the Z level between the preview and the sheet/pinned-bar layers.

### Agent's Discretion
- Exact API choice for bottom sheet presentation: `.sheet` with `.presentationDetents` vs custom implementation. `.presentationDetents([.height(pillBarHeight), .medium])` is the standard approach and should suffice.
- The `pillBarHeight` constant for the peek detent — derived from MarkepiPillBar's intrinsic height.
- The extracted Share button component's exact interface — generic over `WatermarkConfigurable & Observable`, renders the rendering-state-driven button. Planner derives the signature.
- How the pinned floating pill is positioned — likely a `.overlay(alignment: .bottom)` or `safeAreaInset(edge: .bottom)` on the preview area.
- iOS 18 fallback for any iOS 26-specific sheet APIs — follow the established `if #available(iOS 26, *)` pattern from Phase 15.
</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project-Level
- `.planning/PROJECT.md` — Core value, constraints, v2.1 milestone context, key decisions
- `.planning/REQUIREMENTS.md` — LYT-01 through LYT-04 (what Phase 17 must deliver), v2.1 scope note (presentation-only)
- `.planning/ROADMAP.md` § Phase 17 — Goal, success criteria, depends on Phase 16
- `.planning/STATE.md` — v2.1 phase map, risk re: shared ControlsView, layout decision

### Upstream Phases (deliverables consumed here)
- `.planning/phases/15-visual-design-system-shared-primitives/15-CONTEXT.md` — All design decisions: Liquid Glass, pill bar, button vocabulary, typography, scroll-edge (D-01 through D-23)
- `.planning/phases/16-redesigned-controls/16-CONTEXT.md` — ControlsView rebuild decisions: pill bar sections (D-04/D-05), position Menu (D-01), button roles (D-09/D-10), scroll-edge (D-12), shell-agnostic mandate

### Design System Primitives (to consume)
- `Packages/WatermarkCore/Sources/WatermarkCore/DesignSystem/GlassEffect/MarkepiGlassModifier.swift` — `.markepiGlass()` for sheet surface and pinned bar
- `Packages/WatermarkCore/Sources/WatermarkCore/DesignSystem/ButtonStyles/MarkepiButtonStyle.swift` — `.markepiPrimary()`, `.markepiSecondary()`, `.markepiDestructive()` for Share button states
- `Packages/WatermarkCore/Sources/WatermarkCore/DesignSystem/Typography/MarkepiTypography.swift` — Semantic typography for any new labels
- `Packages/WatermarkCore/Sources/WatermarkCore/DesignSystem/MarkepiPillBar.swift` — Pill bar consumed inside sheet
- `Packages/WatermarkCore/Sources/WatermarkCore/DesignSystem/ScrollEdge/MarkepiScrollEdgeProtection.swift` — Scroll-edge protection in sheet
- `Packages/WatermarkCore/Sources/WatermarkCore/DesignSystem/MarkepiUtilities.swift` — `.modify {}` conditional helper

### Source Files (being modified or referenced)
- `App/Views/ContentView.swift` — **Primary target for Phase 17** — entire file restructured (current 60/40 split at lines 69-78, previewArea lines 127-171, controlsArea lines 175-177, sheet modifiers lines 267-283)
- `App/Views/PreviewArea/PreviewView.swift` — Already uses `.edgesIgnoringSafeArea(.top)` at line 94; may need adjustment
- `Packages/WatermarkCore/Sources/WatermarkCore/UI/ControlsView.swift` — Share button extraction target (lines 239-358), consumed unchanged inside sheet
- `Packages/WatermarkCore/Sources/WatermarkCore/UI/WatermarkConfigurable.swift` — Protocol surface for Share button (`renderAndPrepareShare`, `presentShareSheet`, `cancelProcessing`)
- `App/ViewModels/WatermarkViewModel.swift` — ViewModel backing (rendering state, share flow, batch); NOT modified but referenced
- `App/Views/Batch/BatchProgressOverlay.swift` — Batch overlay repositioned above sheet
- `App/Views/Navigation/ThumbnailStripView.swift` — Thumbnail strip repositioned above sheet

### Extension Shells (NOT modified — reference only)
- `ShareExtension/ShareExtensionRootView.swift` — Keeps current 60/40; Phase 17 does not touch
- `PhotoEditExtension/PhotosExtensionRootView.swift` — Keeps current 60/40; Phase 17 does not touch
</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`MarkepiGlassModifier`** — Already built, ready for sheet surface and pinned bar. iOS 26 Liquid Glass with `.ultraThinMaterial` fallback on iOS 18.
- **`MarkepiButtonStyle` (.primary, .secondary, .destructive)** — The extracted Share button uses these for its rendering state variants.
- **`MarkepiPillBar`** — Already built with matched-geometry animation, `ControlsSection` enum, glass backing. Lives unchanged inside ControlsView.
- **`MarkepiScrollEdgeProtection`** — Already applied inside ControlsView. No changes needed.
- **`WatermarkConfigurable` protocol** — Frozen. The extracted Share button calls `renderAndPrepareShare()`, `presentShareSheet()`, `cancelProcessing()` through this protocol.
- **`RenderingState` enum** — Already defined in ProcessingResult.swift (idle/rendering/renderingVideo/batchProcessing/done/error). The extracted Share button uses this as its state driver.
- **`PreviewView`** — Already uses `.edgesIgnoringSafeArea(.top)`. Ready for full-bleed.

### Established Patterns
- **Generic over `WatermarkConfigurable & Observable`** — All UI views, including the new Share button component, are generic over the ViewModel.
- **Shared code in WatermarkCore** — The extracted Share button component lives in WatermarkCore/DesignSystem/, consumed by all targets.
- **`if #available(iOS 26, *)`** — Pattern from Phase 15 for Liquid Glass fallback. The sheet's glass surface follows the same pattern.
- **60/40 split is hardcoded** — Every root view (ContentView, ShareExtensionRootView, PhotosExtensionRootView) uses identical `GeometryReader → VStack(60%/40%)`. Phase 17 replaces this in ContentView only.

### Integration Points
- `ContentView.swift:69-78` — The `mainLayout(_:)` with `VStack(spacing: 0) { previewArea (60%) + separator + controlsArea (40%) }` — this entire block is replaced by the full-bleed + sheet layout.
- `ContentView.swift:175-177` — `controlsArea` hosts `ControlsView(viewModel: viewModel)`. In the new layout, ControlsView moves inside the sheet.
- `ContentView.swift:267-283` — Existing `.sheet` modifiers for ShareSheetView, TemplateListView, BatchItemDetailSheet. These coexist with the new bottom sheet — they are separate modal presentations.
- `ControlsView.swift:239-358` — The `shareButton` computed property with the rendering state switch. This is the extraction target for the standalone component.
- `WatermarkViewModel.swift:327-529` — `renderAndPrepareShare()` and `presentShareSheet()` implementations. The extracted Share button calls these unchanged.
- `BatchProgressOverlay.swift` and `ThumbnailStripView.swift` — Currently positioned inside `previewArea` ZStack. Reposition above the sheet in the new layout.

### No Existing Sheet/Detent API Usage
- Zero `.presentationDetents` usage anywhere in the codebase.
- Zero `.presentationBackgroundInteraction` usage.
- `.sheet` is used only for modal presentations (share sheet, template list, batch detail) — not for persistent bottom sheets.
- This is greenfield for the app — no migration or compatibility concerns.
</code_context>

<specifics>
## Specific Ideas

- **Professional photo-editing app convention** — The detent and glass choices follow the pattern used by Apple Photos, Lightroom, and Darkroom: full-bleed preview hero, glass bottom sheet at ~half height, always-visible primary action. User explicitly deferred to "the best professional style" for detent heights and 2026 Liquid Glass conventions.
- **ControlsView stays shell-agnostic at all costs** — Phase 16's mandate is absolute. The sheet wraps ControlsView without modifying it. The pill bar stays inside ControlsView. The scroll-edge protection stays. This means the sheet is a pure container — it provides the glass surface, detents, and drag affordance, nothing more.
- **Share button extraction is the key architectural move** — Rather than moving ControlsView's Output section, extracting the Share button into a standalone component solves the pinned-bar problem cleanly: main app hosts it in the floating pill, ControlsView hosts it inline, extensions get it through ControlsView. One component, three placements.
- **No preview treatment means simpler animations** — User explicitly rejected dimming, blur, or scale on the preview as the sheet moves. This keeps the animation model simple: just the sheet translating up/down, with glass overlay.
</specifics>

<deferred>
## Deferred Ideas

- **Drag-to-position watermark (VIS-05):** Deferred to v2.2+ per REQUIREMENTS.md.
- **Glass-morph transitions (VIS-06):** Deferred to v2.2+ per REQUIREMENTS.md.
- **Extension shell redesign:** The ShareExtension and PhotosExtension keep their current 60/40 layout. Redesigning them with bottom sheets is a future phase if needed.

None — discussion stayed within phase scope.
</deferred>

---

*Phase: 17-Inspector Bottom-Sheet Shell*
*Context gathered: 2026-06-22*
