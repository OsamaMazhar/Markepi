# Roadmap: Watermark

## Milestones

- ✅ **v1.0 MVP** — Phases 1-7 (shipped 2026-06-18)
- ✅ **v1.1 Tech Debt Hardening** — Phases 8-11 (shipped 2026-06-18)
- ✅ **v2.0 Batch, Templates & Process** — Phases 12-14 (shipped 2026-06-19)
- 🚧 **v2.1 UI Redesign** — Phases 15-18 (in progress)

## Phases

### v2.1 UI Redesign (Phases 15-18)

- [ ] **Phase 15: Visual Design System & Shared Primitives** - Liquid Glass chrome, grouped inset section cards, one consistent button language, and scroll-edge legibility — the shared visual foundation every control and shell consumes.
- [ ] **Phase 16: Redesigned Controls** - Every control inside the shared `ControlsView` rebuilt on the new design system: visual 9-position picker, cleaner text/scale/logo/signature/white-frame/layer-list rows, native Menus for export, and the template button in the new button language.
- [ ] **Phase 17: Inspector Bottom-Sheet Shell** - The main app shell becomes a full-bleed photo hero with a resizable detent control sheet and a pinned Share action bar, rendering correctly in light and dark.
- [ ] **Phase 18: Cross-Target Parity & Accessibility Polish** - The redesigned `ControlsView` verified in both extensions, Dynamic Type / VoiceOver / Reduce Motion+Transparency honored, and the empty state redesigned.

## Phase Details

### Phase 15: Visual Design System & Shared Primitives
**Goal**: Establish the shared visual language — Liquid Glass chrome, grouped inset section cards, a single button language, and scroll-edge legibility — so every downstream control and shell renders consistently.
**Depends on**: Nothing (first phase of v2.1; builds on shipped v1.0/v1.1/v2.0 codebase)
**Requirements**: VIS-01, VIS-02, VIS-03, VIS-04
**Success Criteria** (what must be TRUE):
  1. Navigation and control chrome (toolbar, floating buttons, sheet surface) render with iOS 26 Liquid Glass on iOS 26 devices and fall back gracefully (no broken/blank chrome) on the iOS 18 deployment floor
  2. Controls within `ControlsView` are grouped into inset section cards with a clear typographic hierarchy instead of a flat stack of equal-weight section titles
  3. Primary, secondary, and destructive actions share one consistent button language (one shape/weight/tint vocabulary) wherever they appear
  4. Content scrolling beneath the chrome stays legible via scroll-edge effects (no text colliding illegibly with floating controls)
**Plans**: 3 plans in 3 waves
Plans:
- [ ] 15-01-PLAN.md — Foundation Primitives (directory scaffold, View.modify utility, MarkepiGlassModifier, MarkepiTypography)
- [ ] 15-02-PLAN.md — Interaction Primitives (MarkepiButtonStyle, MarkepiPillBar, MarkepiScrollEdgeProtection)
- [ ] 15-03-PLAN.md — Preview Catalog + Cross-Target Verification
**UI hint**: yes

### Phase 16: Redesigned Controls
**Goal**: Rebuild every control hosted by the shared `ControlsView` on the new design system so each watermark feature is presented clearly and consistently, with no change to underlying behavior.
**Depends on**: Phase 15
**Requirements**: CTL-01, CTL-02, CTL-03, CTL-04, CTL-05, CTL-06, CTL-07, CTL-08
**Success Criteria** (what must be TRUE):
  1. A visual 9-position picker shows watermark placement glanceably, replacing the TL/TC/TR text grid, and still drives the same 9 placement values
  2. The text watermark field, scale control (with live value readout), logo picker, and signature picker present clean fields and consistent add / preview / remove affordances
  3. White Frame appears as an integrated grouped row, the layer list shows clear active-layer selection plus remove controls, and Export Options use native Menus/pickers
  4. The Save-as-Template action conforms to the new button language, and all existing control behaviors (positions, scale, layers, export, HDR→JPEG warning) function unchanged
**Plans**: TBD
**UI hint**: yes

### Phase 17: Inspector Bottom-Sheet Shell
**Goal**: Replace the main app's hardcoded 60/40 split with a full-bleed photo hero and a resizable detent control sheet plus a pinned Share action bar, working in both appearances.
**Depends on**: Phase 16
**Requirements**: LYT-01, LYT-02, LYT-03, LYT-04
**Success Criteria** (what must be TRUE):
  1. The photo/video preview fills the screen as a full-bleed hero behind the controls
  2. Controls live in a resizable bottom sheet with a peek detent and an expanded detent that the user can drag between
  3. The primary action (Share / Watermark All) stays reachable at all times via a pinned action bar regardless of sheet detent
  4. The entire shell renders correctly in both system light and dark appearance
**Plans**: TBD
**UI hint**: yes

### Phase 18: Cross-Target Parity & Accessibility Polish
**Goal**: Verify the redesigned shared `ControlsView` works in both extensions and finish the accessibility and empty-state polish that makes the redesign production-ready.
**Depends on**: Phase 17
**Requirements**: XTG-01, XTG-02, UXQ-01, UXQ-02, UXQ-03, UXQ-04
**Success Criteria** (what must be TRUE):
  1. The redesigned `ControlsView` renders and functions correctly in the Share Extension and the Photos Edit Extension (controls usable, share/render works end-to-end)
  2. Dynamic Type scales redesigned controls up to 200% with no truncation or overlap
  3. VoiceOver labels and hints are preserved or improved relative to the pre-redesign UI, and Reduce Motion / Reduce Transparency settings are respected
  4. The empty state (no photo loaded) is redesigned to match the new visual system
**Plans**: TBD
**UI hint**: yes

## Progress

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 15. Visual Design System & Shared Primitives | 0/3 | Not started | - |
| 16. Redesigned Controls | 0/TBD | Not started | - |
| 17. Inspector Bottom-Sheet Shell | 0/TBD | Not started | - |
| 18. Cross-Target Parity & Accessibility Polish | 0/TBD | Not started | - |

---

<details>
<summary>✅ v2.0 Batch, Templates & Process (Phases 12-14) — SHIPPED 2026-06-19</summary>

- [x] Phase 12: Template Management (5/5 plans) — completed 2026-06-19
- [x] Phase 13: Batch Processing (3/3 plans) — completed 2026-06-19
- [x] Phase 14: Process Hardening (2/2 plans) — completed 2026-06-19

See `.planning/milestones/v2.0-ROADMAP.md` for full phase details.

</details>

<details>
<summary>✅ v1.0 MVP (Phases 1-7) — SHIPPED 2026-06-18</summary>

- [x] Phase 1: Core Engine & Photo Pipeline (3/3 plans) — completed 2026-06-17
- [x] Phase 2: Main App (Photo Watermark & Share) (2/2 plans) — completed 2026-06-17
- [x] Phase 3: Video Processing & Share Extension (3/3 plans) — completed 2026-06-17
- [x] Phase 4: Photos Edit Extension & Polish (2/2 plans) — completed 2026-06-18
- [x] Phase 5: Extended Engine (ProRAW, EXIF, Multi-Layer) (4/4 plans) — completed 2026-06-18
- [x] Phase 6: Export Control & UX Polish (3/3 plans) — completed 2026-06-18
- [x] Phase 7: Additional Inputs & System Integration (v2) (3/3 plans) — completed 2026-06-18

See `.planning/milestones/v1.0-ROADMAP.md` for full phase details.

</details>

<details>
<summary>✅ v1.1 Tech Debt Hardening (Phases 8-11) — SHIPPED 2026-06-18</summary>

- [x] Phase 8: Traceability Reconciliation & Recurrence Guard (2/2 plans) — completed 2026-06-18
- [x] Phase 9: Wave-Level Build Gate (1/1 plan) — completed 2026-06-18
- [x] Phase 10: WatermarkConfigurable Protocol Defaults (2/2 plans) — completed 2026-06-18
- [x] Phase 11: Photos Extension HDR Detection (1/1 plan) — completed 2026-06-18

See `.planning/milestones/v1.1-ROADMAP.md` for full phase details.

</details>
