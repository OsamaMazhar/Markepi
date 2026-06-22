# Phase 17: Inspector Bottom-Sheet Shell - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-22
**Phase:** 17-inspector-bottom-sheet-shell
**Areas discussed:** Detent Strategy, Share Button Extraction, Sheet Chrome & Styling, ControlsView-in-Sheet Integration

---

## Detent Strategy

| Option | Description | Selected |
|--------|-------------|----------|
| Pill bar only | Peek = just the pill bar (3 segment labels). User drags up to see controls. | ✓ |
| Pill bar + Watermark section | Peek = pill bar + first section visible (~medium height). | |
| Custom: pill bar + first ~2 rows | Peek shows pill bar plus the first 1-2 control rows of Watermark section. | |

**User's choice:** Pill bar only
**Notes:** Minimal and clean peek state.

---

| Option | Description | Selected |
|--------|-------------|----------|
| .medium (~half screen) | Sheet expands to ~50%. Shows 1-2 pill sections. | ✓ (agent inference) |
| .large (full height) | Sheet fills the screen (below status bar). | |
| Custom fraction (~60-65%) | Shows most controls with preview peeking above. | |

**User's choice:** "Follow the best professional style" — agent inferred `.medium` based on Apple Photos, Lightroom, Darkroom conventions.
**Notes:** Professional photo-editing apps all use ~half-screen bottom controls with the preview remaining the dominant visual element.

---

| Option | Description | Selected |
|--------|-------------|----------|
| Overlay (preview stays full-bleed) | Sheet slides up over the preview image. Preview remains edge-to-edge behind the glass sheet. | ✓ (agent inference) |
| Push (preview resizes) | Preview area shrinks as the sheet expands, maintaining the full image visible above the sheet. | |
| Overlay with parallax | Sheet overlays the preview, but the preview image gently shifts up as the sheet expands. | |

**User's choice:** "Use technique what most advanced professional apps of 2026 use" — agent inferred overlay with Liquid Glass, full-bleed preview stays beneath.
**Notes:** iOS 26 Liquid Glass sheet over full-bleed preview is the 2026 professional standard.

---

| Option | Description | Selected |
|--------|-------------|----------|
| Background interaction enabled | User can tap/drag the preview image behind the sheet even with the sheet visible. | ✓ |
| No background interaction | Sheet captures all touches. User must dismiss to peek to interact with the preview. | |
| Background interaction only in peek | Peek state allows background interaction; expanded state captures touches. | |

**User's choice:** Background interaction enabled
**Notes:** Professional photo editors allow interacting with the preview behind the sheet.

---

| Option | Description | Selected |
|--------|-------------|----------|
| Always show peek (no dismiss) | Sheet always visible at pill-bar height. Cannot be dragged off-screen. | ✓ |
| Dismissible (drag below peek hides sheet) | User can drag the sheet completely off-screen for a distraction-free full-screen preview. | |

**User's choice:** Always show peek (no dismiss)
**Notes:** The inspector is permanent layout, not a temporary modal.

---

## Share Button Extraction

| Option | Description | Selected |
|--------|-------------|----------|
| Above the sheet (standalone bar) | A separate glass bar sits between the preview and the sheet, always visible. | ✓ |
| Pinned at top of sheet | The action bar is part of the sheet — pinned at the top, above the pill bar. | |
| Integrated into pill bar | The Share button becomes a 4th segment in the pill bar or a right-aligned element within it. | |

**User's choice:** Above the sheet (standalone bar)
**Notes:** Clean separation from the sheet.

---

| Option | Description | Selected |
|--------|-------------|----------|
| Extract Share button as standalone component | Pull the share button state machine out of ControlsView into a new shared component. One source of truth. | ✓ |
| Duplicate in pinned bar (keep inside ControlsView too) | ControlsView keeps its Share button unchanged. The main app duplicates the button logic in the pinned bar. | |
| Remove from ControlsView, add to pinned bar only | The Share button lives only in the pinned action bar. | |

**User's choice:** Extract Share button as standalone component
**Notes:** One component consumed by main app's pinned bar, ControlsView (for all targets), and extensions.

---

| Option | Description | Selected |
|--------|-------------|----------|
| Share button only | Bar contains just the primary action button (Share / Watermark All / Ready to Share / Retry). Minimal, focused. | ✓ |
| Share + batch controls | Bar shows Share button plus contextual batch actions (Cancel, Reset All) when in batch mode. | |
| Share + import button | Share button on the right, plus an "Add Photos" button on the left. | |

**User's choice:** Share button only
**Notes:** Batch controls stay in NavigationStack toolbar.

---

| Option | Description | Selected |
|--------|-------------|----------|
| Liquid Glass floating pill | A floating glass capsule centered at the bottom of the preview area, above the sheet. | ✓ |
| Full-width glass bar | A full-width glass bar spanning the bottom of the preview, edge-to-edge. | |
| Glass overlay on preview | The Share button is a glass capsule overlaid directly on the preview image (bottom-center or top-right). | |

**User's choice:** Liquid Glass floating pill
**Notes:** Centered, floating, independent from the sheet.

---

## Sheet Chrome & Styling

| Option | Description | Selected |
|--------|-------------|----------|
| Full Liquid Glass | The entire sheet surface is Liquid Glass. Preview image is visible through the sheet. Controls sit on glass. | ✓ |
| Glass pill bar + opaque sheet body | Only the pill bar at the top of the sheet is glass. The scrollable body below is opaque. | |
| Matte material (iOS 18 fallback style) | Use .regularMaterial or .ultraThinMaterial throughout. No Liquid Glass even on iOS 26. | |

**User's choice:** Full Liquid Glass
**Notes:** The professional 2026 look. MarkepiGlassModifier handles both iOS 26 and iOS 18 fallback.

---

| Option | Description | Selected |
|--------|-------------|----------|
| Show drag indicator | Standard iOS pattern — a small horizontal capsule at the top of the sheet. | ✓ |
| Hide drag indicator | No visible drag indicator. The pill bar itself serves as the visual affordance. | |

**User's choice:** Show drag indicator
**Notes:** Standard iOS sheet pattern. Familiar to users.

---

| Option | Description | Selected |
|--------|-------------|----------|
| Standard iOS sheet corners | The default top corners iOS gives to sheets — rounded top corners, square bottom. | ✓ |
| Continuous rounded rectangle | Fully rounded top corners with continuous corner style. | |

**User's choice:** Standard iOS sheet corners
**Notes:** Default behavior, zero custom work.

---

| Option | Description | Selected |
|--------|-------------|----------|
| No treatment — preview stays as-is | The preview remains full-bleed, unmodified. The glass sheet overlays it and that's the only interaction. | ✓ |
| Gentle dimming | Preview subtly darkens as the sheet expands — like a very light overlay. | |
| Subtle scale-down | Preview image gets a slight parallax/scale effect — shrinks ~5% as the sheet expands. | |

**User's choice:** No treatment — preview stays as-is
**Notes:** Simple animation model: just the sheet moving up/down.

---

## ControlsView-in-Sheet Integration

| Option | Description | Selected |
|--------|-------------|----------|
| Pill bar stays inside ControlsView (unchanged) | ControlsView remains exactly as-is. The sheet wraps ControlsView as a child. | ✓ (agent inference) |
| Pill bar extracted as sheet header | Move the pill bar out of ControlsView — it becomes part of the sheet's own chrome. | |
| Pill bar kept but restructured | ControlsView keeps the pill bar, but the scroll-edge protection is rethought for the sheet context. | |

**User's choice:** "Design the approach to be simple, user intuitive and professional and modern" — agent inferred pill bar stays inside ControlsView unchanged.
**Notes:** Phase 16's shell-agnostic mandate preserved. iOS natively handles nested scroll views — simplest and most professional approach.

---

| Option | Description | Selected |
|--------|-------------|----------|
| Native nested scroll (no custom work) | Let iOS handle it. Inner content scrolls first; sheet resize only at scroll boundaries. | ✓ |
| Disable internal scroll in ControlsView | ControlsView becomes a fixed-height content area — no internal scrolling. | |

**User's choice:** Native nested scroll (no custom work)
**Notes:** Zero custom gesture coordination. Standard UIKit/SwiftUI nested scroll behavior.

---

| Option | Description | Selected |
|--------|-------------|----------|
| Move to navigation toolbar (top of screen) | Keep batch Cancel/Reset in the NavigationStack toolbar at the top. | ✓ |
| Integrate into the pinned action bar | When in batch mode, the floating pill bar shows cancel/reset alongside the Share button. | |
| Move into the sheet (ControlsView) | Add batch controls as a row inside ControlsView. | |

**User's choice:** Move to navigation toolbar (top of screen)
**Notes:** Batch controls are contextual and belong in standard toolbar positions.

---

| Option | Description | Selected |
|--------|-------------|----------|
| Above the sheet, on the preview | Thumbnail strip sits above the pinned action bar in the preview area. Batch progress overlay covers the full preview. | ✓ |
| Inside the sheet | Move the thumbnail strip into the sheet. Batch progress shows within the sheet. | |
| Thumbnail strip above sheet, progress as overlay | Thumbnail strip floats above the sheet on the preview. Batch progress overlay covers the entire screen. | |

**User's choice:** Above the sheet, on the preview
**Notes:** Overlays are preview-level, not sheet-level. Consistent with current approach.

---

## Agent's Discretion

- Exact API choice for bottom sheet presentation: `.sheet` with `.presentationDetents` vs custom implementation.
- The `pillBarHeight` constant for the peek detent.
- The extracted Share button component's exact interface (generic over `WatermarkConfigurable & Observable`).
- Pinned floating pill positioning (likely `.overlay(alignment: .bottom)` or `safeAreaInset(edge: .bottom)`).
- iOS 18 fallback for any iOS 26-specific sheet APIs.

## Deferred Ideas

- Drag-to-position watermark (VIS-05): Deferred to v2.2+ per REQUIREMENTS.md.
- Glass-morph transitions (VIS-06): Deferred to v2.2+ per REQUIREMENTS.md.
- Extension shell redesign: ShareExtension and PhotosExtension keep current 60/40 layout.
