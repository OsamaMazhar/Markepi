# Phase 15: Visual Design System & Shared Primitives - Context

**Gathered:** 2026-06-21
**Status:** Ready for planning

<domain>
## Phase Boundary

Establish the shared visual language primitives — Liquid Glass chrome, pill-bar section navigation, consistent button vocabulary, typographic hierarchy, and scroll-edge legibility — as reusable `Markepi*` components in a new `WatermarkCore/DesignSystem/` folder. Every downstream control (Phase 16) and shell (Phase 17) consumes these primitives.

**This is presentation-layer only.** `WatermarkEngine`, `WatermarkConfigurable` protocol, ViewModels, and the data/config model are frozen. All 3 targets (App, ShareExtension, PhotoEditExtension) consume the primitives via the shared WatermarkCore package.
</domain>

<decisions>
## Implementation Decisions

### Liquid Glass Surface Area
- **D-01:** Every UI surface adopts iOS 26 Liquid Glass — toolbar, sheet surface, floating buttons, section pill bar, inset rows. Glass is applied to cards/surfaces; individual control elements inside cards remain opaque for legibility.
- **D-02:** iOS 18 fallback uses a material hierarchy: `.ultraThinMaterial` for toolbar/buttons, `.regularMaterial` for sheet/row surfaces. No dual-renderer code path — `if #available(iOS 26, *)` gate with `GlassEffect` or `.glassMaterial` on iOS 26, falling back to the material hierarchy.
- **D-03:** Glass tint is system-adaptive (cool tones in light mode, warm in dark). No fixed/custom tint.

### Section Structure (Pill Bar)
- **D-04:** The flat `VStack(spacing: 20)` of 8+ controls is replaced by a **pill bar** at the top of the controls area — a native `.pickerStyle(.segmented)` with 3 text-only pills: **Watermark** | **Style** | **Output**. User swipes left/right or taps a pill to switch sections.
- **D-05:** Each pill section scrolls vertically. Within each pill, controls appear as **inset grouped rows** (iOS Settings-style).
- **D-06:** Control allocation: **Watermark** = text input + position picker + scale stepper. **Style** = logo picker + signature capture + white frame toggle + layer list. **Output** = export options + save-as-template.
- **D-07:** Share button is an icon overlay on the preview image (top-right corner) — always reachable. The *styling* of this button is Phase 15; the *placement* on the preview is confirmed in Phase 17.
- **D-08:** Save-as-Template action lives inside the Output section, styled with the new button vocabulary.

### Button Language Vocabulary
- **D-09:** All buttons use **pill/capsule shape**.
- **D-10:** Tint vocabulary follows standard iOS convention: **primary** = `accentColor`, **secondary** = gray, **destructive** = red.
- **D-11:** Delivered as a **custom `ButtonStyle`** (e.g., `.buttonStyle(.markepiPrimary)`, `.buttonStyle(.markepiSecondary)`, `.buttonStyle(.markepiDestructive)`) with built-in glass treatment on iOS 26 and material fallback on iOS 18.
- **D-12:** Label convention is context-dependent: icon+text for primary actions, icon-only for the overlay Share button, text-only for destructive/inline buttons.

### Typographic Hierarchy
- **D-13:** Standard iOS 26 typographic scale delivered via a `ViewModifier` (e.g., `.markepiTypography(.sectionHeader)`, `.markepiTypography(.body)`, `.markepiTypography(.caption)`):
  - `.sectionHeader` = `title3.semibold`
  - `.controlLabel` = `body`
  - `.value` = `body.monospacedDigit`
  - `.metadata` = `caption`
  - Pill bar labels = `headline.weight(.medium)`
- **D-14:** System default font (San Francisco). No rounded variant.
- **D-15:** Dynamic Type is **uncapped** — layout handles scaling up to accessibility sizes. The `MarkepiTypography` modifier uses standard font styles that respect the user's Dynamic Type setting.

### Scroll-Edge Effects
- **D-16:** Top scroll-edge uses **glass backing on the pill bar** combined with `.scrollClipDisabled()` so content renders beneath the pill bar and is blurred by the glass backing. This is the native iOS 26 pattern.
- **D-17:** iOS 18 fallback uses `.ultraThinMaterial` on the pill bar — the material itself provides the obscuring effect without needing a separate gradient or mask. No dual code path for the edge effect.
- **D-18:** Bottom edge has no scroll effect — only the top edge needs protection since the pill bar is the colliding element.
- **D-19:** Delivered as a reusable `ViewModifier` (e.g., `.markepiScrollEdgeProtection`) applicable to any scroll view with a glass/material header.

### Shared Primitive Packaging
- **D-20:** All primitives live in a new `WatermarkCore/Sources/WatermarkCore/DesignSystem/` folder with subdirectories: `ButtonStyles/`, `Typography/`, `GlassEffect/`, `ScrollEdge/`.
- **D-21:** All primitives are `public` — directly usable by all 3 targets, not just internal to WatermarkCore.
- **D-22:** Naming convention uses `Markepi` prefix: `MarkepiButtonRole`, `MarkepiTypography`, `MarkepiGlassModifier`, `MarkepiScrollEdgeProtection`.
- **D-23:** Includes a `PreviewCatalog.swift` rendering all primitives side-by-side in Xcode Previews for design iteration without building to device.

### Agent's Discretion
- Which specific iOS 26 API calls (`GlassEffect`, `glassMaterial`, etc.) to use — research during planning.
- Exact ViewModifier signatures and parameter defaults — planner derives from the decisions above.
- `#if available(iOS 26, *)` fallback structure — standard pattern, planner implements.
</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project-Level
- `.planning/PROJECT.md` — Core value, constraints, key decisions, v2.1 milestone context
- `.planning/REQUIREMENTS.md` — VIS-01 through VIS-04 (what Phase 15 must deliver), v2.1 scope note (presentation-only)
- `.planning/ROADMAP.md` § Phase 15 — Goal, success criteria, dependency chain (Phase 15 → 16 → 17 → 18)
- `.planning/STATE.md` — v2.1 phase map, blocker re: iOS 18 fallback strategy, risk re: shared ControlsView

### Requirements Locked
- `.planning/REQUIREMENTS.md` §§ Layout & Shell (LYT), Visual System (VIS), Redesigned Controls (CTL), Cross-Target Parity (XTG), Polish & Accessibility (UXQ)

### Source Files (Current Code)
- `Packages/WatermarkCore/Sources/WatermarkCore/UI/ControlsView.swift:1-280` — The shared control view being redesigned; current flat VStack pattern
- `Packages/WatermarkCore/Sources/WatermarkCore/UI/WatermarkConfigurable.swift` — Protocol surface (frozen, do not modify)
- `App/Views/ContentView.swift:1-332` — Main app shell (60/40 split to be replaced in Phase 17)
- `ShareExtension/ShareExtensionRootView.swift:1-222` — Share extension root (60/40 split, consumes ControlsView)
- `PhotoEditExtension/PhotosExtensionRootView.swift:1-161` — Photos extension root (60/40 split, consumes ControlsView)

### Design System Destination
- `Packages/WatermarkCore/Sources/WatermarkCore/DesignSystem/` — Target directory for all new primitives (create in Phase 15)
</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `WatermarkConfigurable` protocol — All ViewModels conform to this. The design system primitives do NOT touch it, but ControlsView (Phase 16) rebuilds on top of both.
- `AsyncButton` (`App/Views/Common/AsyncButton.swift`) — Existing async-safe button wrapper. May be refactored to use the new `MarkepiButtonRole` ButtonStyle.
- Existing `.ultraThinMaterial` usage in `ContentView.swift:165` — The only material usage in the codebase. Provides a reference for the iOS 18 fallback implementation.

### Established Patterns
- **Generic Views over `WatermarkConfigurable & Observable`** — All control views are generic over the ViewModel. Design system primitives (ButtonStyle, ViewModifier) should remain ViewModel-agnostic.
- **Shared code lives in WatermarkCore** — The package is the single source of truth for all 3 targets. New `DesignSystem/` folder follows this pattern.
- **60/40 split with separator** — The current shell layout is hardcoded in all 3 root views. Phase 15 does NOT change this; Phase 17 does.

### Integration Points
- `ControlsView.swift:34` — The body `ScrollView > VStack(spacing: 20)` is the insertion point for the pill bar structure in Phase 16.
- `ContentView.swift:175-176` — `controlsArea` hosts `ControlsView`. Design system primitives are consumed here indirectly.
- `ShareExtensionRootView.swift:146` and `PhotosExtensionRootView.swift:133` — Both host `ControlsView` identically. No per-target modifications needed for primitives.
- `WatermarkCore/Sources/WatermarkCore/UI/` — Existing directory. Do NOT place DesignSystem files here; use the new `DesignSystem/` folder alongside it.
</code_context>

<specifics>
## Specific Ideas

- **"Everything MUST adopt iOS 26 Liquid Glass"** — User was emphatic. Every glass-able surface gets glass on iOS 26, no exceptions.
- **Pill bar over cards** — User explicitly rejected inset section cards in favor of a swipable pill bar. The pill bar uses native segmented picker, not custom.
- **Share button on preview** — Icon overlay, top-right corner, always reachable. Styling here (Phase 15), placement confirmed in Phase 17.
- **Markepi rename** — App is being renamed from Watermark to Markepi. New code uses `Markepi` prefix. Full project rename (bundle IDs, package names, existing files) is deferred.
</specifics>

<deferred>
## Deferred Ideas

- **Full app rename (Watermark → Markepi):** Bundle IDs, package names, folder structure, all existing source files. Project-level change beyond Phase 15 scope. Track for roadmap backlog.
- **Share button placement on preview:** The exact layout (top-right corner, sizing, hit target, animation) is Phase 17's bottom-sheet shell. Phase 15 only defines the button's visual style.
- **Drag-to-position watermark (VIS-05):** Deferred to v2.2+ per REQUIREMENTS.md.
- **Glass-morph transitions (VIS-06):** Deferred to v2.2+ per REQUIREMENTS.md.
</deferred>

---

*Phase: 15-Visual Design System & Shared Primitives*
*Context gathered: 2026-06-21*
