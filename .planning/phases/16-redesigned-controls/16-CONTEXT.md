# Phase 16: Redesigned Controls - Context

**Gathered:** 2026-06-21
**Status:** Ready for planning

<domain>
## Phase Boundary

Rebuild every control hosted by the shared `ControlsView` on the Phase 15 Markepi design system primitives — visual 9-position picker, redesigned text/scale/logo/signature/white-frame/layer-list rows, native Menus for export options, and the template button in the new button language. Zero behavior changes — all 8 CTL requirements are pure reskinning of existing functionality.

`ControlsView` is shared across all 3 targets (App, ShareExtension, PhotoEditExtension) via WatermarkCore. The redesign must stay shell-agnostic — ControlsView must not assume it's inside a bottom sheet (Phase 17) or any particular host layout.
</domain>

<decisions>
## Implementation Decisions

### 9-Position Picker (CTL-01)
- **D-01:** The current `PositionGridView` 3x3 grid of text-labeled buttons is replaced by a single button showing the currently selected position name (e.g., "Center") with a disclosure arrow.
- **D-02:** Tapping the button presents a Menu listing all 9 position names as plain text items. No directional icons, no thumbnails, no image rendering. Items show position names only.
- **D-03:** The underlying 9 `WatermarkPosition` values and `updateLayerPosition(at:position:)` behavior are unchanged — this is UI-only.

### Section Grouping (Pill Bar)
- **D-04:** Controls are grouped into the 3 `MarkepiPillBar` sections as defined in Phase 15's D-06, confirmed here:
  - **Watermark**: Text watermark input + Position picker (D-01) + Scale stepper
  - **Style**: Logo picker + Signature capture + White Frame toggle + Layer list
  - **Output**: Export Options + Save as Template
- **D-05:** The `ControlsSection` enum in `MarkepiPillBar.swift` is the source of truth for pill bar segment identity. ControlsView body uses `ControlsSection` to switch between the 3 content areas.

### Row Presentation
- **D-06:** Inside each pill section, controls are presented as iOS Settings-style inset grouped rows with `.markepiGlass()` backing on the section container. Clean, minimal, professional — Lightroom/Adobe-style control panel aesthetic.
- **D-07:** Current `DisclosureGroup("Export Options")` is replaced by a plain tap-to-open row that presents a `Menu` with format options, plus a separate quality row. No inline expand/collapse.
- **D-08:** Section headers use `MarkepiTypography.sectionHeader`. Control labels use `.controlLabel`. Values use `.value` (monospacedDigit for numbers). Metadata uses `.metadata`. No raw `.font()` calls.

### MarkepiButtonStyle Application (CTL-08)
- **D-09:** All buttons in ControlsView must use `MarkepiButtonStyle` or the convenience `.markepiPrimary()`, `.markepiSecondary()`, `.markepiDestructive()` modifiers. No `.bordered`, `.borderedProminent`, or raw `.tint()` calls.
- **D-10:** Button role mapping:
  - `.primary` — Share / Watermark All (rendering idle), Ready to Share (done state), Add Logo, Add Signature, Edit Signature
  - `.secondary` — Cancel (during rendering), Retry (error state), Save as Template
  - `.destructive` — Remove Logo, Remove Signature, Remove Layer (red X)
- **D-11:** Label conventions follow Phase 15 D-12:
  - Primary (`.primary`) = icon + text (SF Symbol + label)
  - Secondary (`.secondary`) = text-only or icon + text per context
  - Destructive (`.destructive`) = text-only
  - Layer remove = icon-only (red X)

### Scroll & Surface
- **D-12:** Each pill section scrolls vertically within its pill view. The pill bar sits above the scroll area with `.markepiScrollEdgeProtection()` ensuring content blurs beneath the glass-backed pill bar.
- **D-13:** The pill bar itself gets `.markepiGlass()` — content scrolling beneath is blurred by the glass backing. This is purely additive; `MarkepiPillBar` already has glass backing from Phase 15.

### Agent's Discretion
- Exact layout metrics (padding, spacing, corner radii, separator placement) within the inset grouped rows — follow iOS HIG grouped list conventions.
- The Menu presentation style for the position picker and export format — use native `.menu` picker style.
- Transition between the 3 pill sections — `MarkepiPillBar` already handles the matched-geometry sliding indicator; ControlsView only needs to switch content via `ControlsSection`.
- How to handle the "Ready to Share" state transitioned from the primary button — keep the existing `RenderingState` enum driving the button state machine; only restyle the button look, not the state logic.
</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project-Level
- `.planning/PROJECT.md` — Core value, constraints, v2.1 milestone context
- `.planning/REQUIREMENTS.md` — CTL-01 through CTL-08 (what Phase 16 must deliver)
- `.planning/ROADMAP.md` § Phase 16 — Goal, success criteria, depends on Phase 15
- `.planning/STATE.md` — v2.1 phase map, blocker re: ControlsView staying shell-agnostic

### Upstream Phase (Phase 15 — deliverables consumed here)
- `.planning/phases/15-visual-design-system-shared-primitives/15-CONTEXT.md` — All design decisions this phase builds upon (Liquid Glass, pill bar, button vocabulary, typography, scroll-edge)
- `.planning/phases/15-visual-design-system-shared-primitives/15-01-SUMMARY.md` — Foundation primitives delivered
- `.planning/phases/15-visual-design-system-shared-primitives/15-02-SUMMARY.md` — Interaction primitives delivered
- `.planning/phases/15-visual-design-system-shared-primitives/15-03-SUMMARY.md` — Preview catalog + cross-target verification

### Design System Source (primitives to consume)
- `Packages/WatermarkCore/Sources/WatermarkCore/DesignSystem/MarkepiPillBar.swift` — Pill bar with ControlsSection enum (D-04, D-05)
- `Packages/WatermarkCore/Sources/WatermarkCore/DesignSystem/ButtonStyles/MarkepiButtonStyle.swift` — Button roles and convenience modifiers (D-09, D-10, D-11)
- `Packages/WatermarkCore/Sources/WatermarkCore/DesignSystem/Typography/MarkepiTypography.swift` — Semantic typography styles (D-08)
- `Packages/WatermarkCore/Sources/WatermarkCore/DesignSystem/GlassEffect/MarkepiGlassModifier.swift` — Liquid Glass + material fallback (D-06, D-13)
- `Packages/WatermarkCore/Sources/WatermarkCore/DesignSystem/ScrollEdge/MarkepiScrollEdgeProtection.swift` — Scroll edge blur (D-12)
- `Packages/WatermarkCore/Sources/WatermarkCore/DesignSystem/MarkepiUtilities.swift` — `.modify()` conditional helper

### Current Source Files (being redesigned)
- `Packages/WatermarkCore/Sources/WatermarkCore/UI/ControlsView.swift` — The shared control view being rebuilt (~280 lines, 10 flat sections)
- `Packages/WatermarkCore/Sources/WatermarkCore/UI/WatermarkConfigurable.swift` — Protocol surface (frozen — do not modify)
- `App/ViewModels/WatermarkViewModel.swift` — Main app ViewModel (consumed by ControlsView, not modified)
- `ShareExtension/ShareExtensionRootView.swift` — Share extension host (consumes ControlsView at line ~146)
- `PhotoEditExtension/PhotosExtensionRootView.swift` — Photos extension host (consumes ControlsView at line ~134)

### Sub-views (being restyled)
- `Packages/WatermarkCore/Sources/WatermarkCore/UI/TextWatermarkInputView.swift`
- `Packages/WatermarkCore/Sources/WatermarkCore/UI/PositionGridView.swift` (replaced by Menu in D-01)
- `Packages/WatermarkCore/Sources/WatermarkCore/UI/ScaleStepperView.swift`
- `Packages/WatermarkCore/Sources/WatermarkCore/UI/LogoPickerView.swift`
- `Packages/WatermarkCore/Sources/WatermarkCore/UI/SignatureCaptureView.swift`
- `Packages/WatermarkCore/Sources/WatermarkCore/UI/WhiteFrameToggleView.swift`
- `Packages/WatermarkCore/Sources/WatermarkCore/UI/LayerListView.swift`
</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`MarkepiPillBar` with `ControlsSection` enum** — Already built, ready to drop into ControlsView. ControlsView switches content by `ControlsSection` value. Pill bar handles the glass backing, matched-geometry indicator, and tap/swipe.
- **`MarkepiButtonStyle` (.primary, .secondary, .destructive)** — Add `.markepiPrimary()`, `.markepiSecondary()`, `.markepiDestructive()` to existing buttons. Replace all `.buttonStyle(.borderedProminent)` and `.buttonStyle(.bordered)`.
- **`MarkepiTypography` (.sectionHeader, .controlLabel, .value, .metadata)** — Replace all raw `.font(.title3.weight(.semibold))` calls.
- **`MarkepiGlassModifier`** — Apply `.markepiGlass()` to section containers and the pill bar backing.
- **`MarkepiScrollEdgeProtection`** — Wrap the scroll area with `.markepiScrollEdgeProtection(header: pillBar)`.

### Established Patterns
- **Generic over `WatermarkConfigurable & Observable`** — ControlsView is generic. All sub-views receive the ViewModel as `@State var viewModel` (direct mutation via `@Bindable`). Do not change this pattern.
- **Shared code in WatermarkCore** — The package is consumed by all 3 targets. All redesign work lives in WatermarkCore.
- **RenderingState state machine** — The share button cycles through `.idle → .rendering → .done → .error` states. Only restyle the button for each state; do not touch the state machine logic.

### Integration Points
- `ControlsView.swift:34` — Current `ScrollView > VStack(spacing: 20)` is the insertion point for pill bar + section content.
- `ContentView.swift:176` — `controlsArea` hosts ControlsView. No changes needed here for Phase 16.
- `ShareExtensionRootView.swift:146` and `PhotosExtensionRootView.swift:133` — Both host ControlsView identically. The redesign must work in both without target-specific code.
</code_context>

<specifics>
## Specific Ideas

- **Position picker is a Menu, not a grid** — User explicitly rejected the grid pattern in favor of a button + dropdown menu. This is a significant divergence from the current `PositionGridView`.
- **Lightroom/Adobe-style clean rows** — User wants the professional photo-editing-app feel: minimal, clean, inset grouped rows with glass backing. No heavy chrome, no card borders.
- **Export Options → plain row** — User wants DisclosureGroup replaced with a tap-to-open Menu row, keeping the Output section visually consistent.
- **Button language must be uniform** — Every button in ControlsView must use the Markepi vocabulary. No exceptions for "quick" or "temporary" buttons.
</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.
</deferred>

---

*Phase: 16-Redesigned Controls*
*Context gathered: 2026-06-21*
