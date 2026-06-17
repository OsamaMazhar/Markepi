# Phase 2: Main App (Photo Watermark & Share) - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-17
**Phase:** 2-Main App (Photo Watermark & Share)
**Areas discussed:** Preview Rendering, Multi-Select, Temp File Lifecycle, UI Layout, Empty State, Share Flow, Error Handling, Picker Trigger, Render Progress, Photo Navigation, Config Persistence, Logo Picker, Text Input, Scale Control, Clear Watermark, Photo Loading, Accessibility, Multi-Photo Cancel

---

## Preview Rendering

| Option | Description | Selected |
|--------|-------------|----------|
| Low-res engine render on every change | Debounced 0.3-0.5s, real pipeline, true WYSIWYG | ✓ |
| SwiftUI overlay mock | Place watermark as SwiftUI views overlaid on photo | |
| Hybrid: mock for text, render for images | Text as SwiftUI overlays, images trigger engine render | |
| Full engine render, coarse debounce | Real pipeline, debounce 1s, sluggish on sliders | |

**User's choice:** Low-res engine render on every change
**Notes:** True WYSIWYG representation is the priority. Debounce keeps it responsive.

---

## Multi-Select

| Option | Description | Selected |
|--------|-------------|----------|
| Single photo only | PhotosPicker maxSelectionCount=1 | |
| Multi-select, sequential flow | Pick N photos, config each individually with navigation | ✓ |

**User's choice:** Multi-select, sequential flow
**Notes:** Each photo gets individually configured and shared. Not batch with templates (v2).

---

## Temp File Lifecycle

| Option | Description | Selected |
|--------|-------------|----------|
| Cleanup on next render | Temp file persists until next render | |
| Cleanup after share sheet dismisses | Deleted immediately on share dismiss | ✓ |
| Manual only | Accumulate, iOS cleans on pressure | |

**User's choice:** Cleanup after share sheet dismisses
**Notes:** Minimum disk usage. Re-share requires fresh render.

---

## UI Layout

| Option | Description | Selected |
|--------|-------------|----------|
| Bottom sheet over preview | Config in .sheet overlay, drag to dismiss | |
| Split: preview top, controls bottom | Fixed 60/40 split, always visible | ✓ |
| Full-screen editor with toolbar | Preview full screen, toolbar toggles panels | |

**User's choice:** Split layout — preview top (60%), controls bottom (40%)
**Notes:** No sheet gesture conflicts, always visible.

---

## Empty State

| Option | Description | Selected |
|--------|-------------|----------|
| PhotosPicker triggers immediately | Auto-opens picker on first launch | ✓ |
| Branded placeholder with CTA | Logo + "Select a photo" button | |
| Empty preview canvas | Blank preview area with "+ Add Photo" button | |

**User's choice:** PhotosPicker opens immediately
**Notes:** Minimum friction. Direct to picker.

---

## Share Flow

| Option | Description | Selected |
|--------|-------------|----------|
| Auto-open share sheet after render | One tap: Share → render → share sheet opens | |
| Show rendered result, tap to share | Two tap: Share → render → show → confirm → share sheet | ✓ |

**User's choice:** Two-tap with confirmation
**Notes:** Gives user a chance to verify before sharing. Extra tap is intentional.

---

## Error Handling

| Option | Description | Selected |
|--------|-------------|----------|
| Alert dialog | UIAlertController modal with OK dismiss | ✓ |
| Inline error banner | Red banner at top, dismissable | |
| Toast / snackbar | Brief overlay, auto-dismisses | |

**User's choice:** Alert dialog
**Notes:** Standard iOS pattern, blocks interaction until acknowledged.

---

## Picker Trigger

| Option | Description | Selected |
|--------|-------------|----------|
| Top toolbar button | "+" icon in navigation bar | |
| Floating button over empty preview | Large "+" when no photo loaded | |
| Both: toolbar + empty state card | Toolbar always + card in empty state | |
| Center of UI | Large prominent button centered in view | ✓ |

**User's choice:** Center of the UI
**Notes:** Always prominent and accessible.

---

## Render Progress

| Option | Description | Selected |
|--------|-------------|----------|
| Full-screen spinner overlay | ProgressView over entire preview, blocks interaction | |
| Share button shows spinner | Button itself becomes ProgressView, UI stays interactive | ✓ |

**User's choice:** Share button shows spinner
**Notes:** Less intrusive, rest of UI remains interactive.

---

## Photo Navigation

| Option | Description | Selected |
|--------|-------------|----------|
| Prev/next arrow buttons | Chevrons flanking preview or in toolbar | |
| Swipe to navigate | Swipe left/right on preview | |
| Thumbnail strip below preview | Horizontal scrollable thumbnails, tap to jump | ✓ |

**User's choice:** Thumbnail strip below preview
**Notes:** Best for 5+ photos. Tap to jump to any.

---

## Config Persistence

| Option | Description | Selected |
|--------|-------------|----------|
| Reset on new photo | Each photo starts fresh | |
| Persist across photos in session | Config stays until user clears | ✓ |

**User's choice:** Persist across photos in same session
**Notes:** Great for applying same watermark to many photos.

---

## Logo Picker

| Option | Description | Selected |
|--------|-------------|----------|
| PhotosPicker (second instance) | Pick from photo library only | |
| File picker (UTType.image) | Document picker, Files/iCloud access | |
| Both — user chooses source | "From Photos" or "From Files" choice | ✓ |

**User's choice:** Both sources
**Notes:** Maximum flexibility. Extra tap is acceptable trade-off.

---

## Text Input

| Option | Description | Selected |
|--------|-------------|----------|
| Single-line TextField | Simple, auto-trims | |
| Multi-line TextField | Allows line breaks for multi-line watermarks | ✓ |

**User's choice:** Multi-line TextField
**Notes:** More flexible, supports creative watermark text layouts.

---

## Scale Control

| Option | Description | Selected |
|--------|-------------|----------|
| Slider with percentage label | Slider 1-90% with value display | |
| Stepper with presets | Preset buttons (5%, 10%, 20%) + stepper | |
| Pinch-to-resize on preview | Direct manipulation, pinch on preview | ✓ |

**User's choice:** Pinch-to-resize on preview
**Notes:** Most intuitive. Needs MagnifyGesture implementation with clamp at 0.01-0.90.

---

## Clear Watermark

| Option | Description | Selected |
|--------|-------------|----------|
| Per-layer swipe-to-delete | Swipe action on each layer row | |
| X button per layer | Small X button on each layer row | ✓ |
| Reset All button only | Single button clears everything | |

**User's choice:** X button per layer
**Notes:** Explicit control, no gesture discovery needed.

---

## Photo Loading

| Option | Description | Selected |
|--------|-------------|----------|
| Load full-res immediately | Load full image right after picking | |
| Thumbnail first, then full-res | Low-res thumbnail for responsiveness, async full-res | ✓ |

**User's choice:** Thumbnail first, then full-res
**Notes:** Responsive feel on first load. Full-res loads async in background.

---

## Accessibility

| Option | Description | Selected |
|--------|-------------|----------|
| Slider fallback in controls | Scale slider always visible as backup | |
| Stepper with ±5% increments | Accessibility-specific stepper | ✓ |
| No separate control | Pinch-to-resize only | |

**User's choice:** Stepper with ±5% increments
**Notes:** VoiceOver and assistive touch compatible.

---

## Multi-Photo Cancel

| Option | Description | Selected |
|--------|-------------|----------|
| Cancel with confirmation | Alert, returns to picker mode | ✓ |
| No cancel — commit to finish | Must finish or force-quit | |

**User's choice:** Cancel with confirmation
**Notes:** "Discard changes to remaining photos?" alert.

---

## Claude's Discretion

No areas were deferred to the agent — all decisions were user-directed.

## Deferred Ideas

None — discussion stayed within phase scope.
