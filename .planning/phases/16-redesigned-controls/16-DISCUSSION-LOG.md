# Phase 16: Redesigned Controls - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-21
**Phase:** 16-redesigned-controls
**Areas discussed:** 9-position picker, Section grouping, Row presentation, Button language

---

## 9-Position Picker

| Option | Description | Selected |
|--------|-------------|----------|
| Grid of 9 mini photo previews | Each cell shows a tiny preview of the loaded photo with a watermark dot at that position | |
| Grid with position icons | Each cell shows a directional icon pointing to the relevant corner/center | |
| Grid with position names | Each cell shows "Top Left", "Center", etc. — more readable than TL/TC | |
| Button + dropdown menu | Button showing current position → taps to open a Menu listing all 9 positions | ✓ |

**User's choice:** "Instead of a grid, use a button that opens a dropdown menu"
**Notes:** User explicitly rejected the grid pattern. This diverges from the current `PositionGridView` 3x3 grid and from Phase 15's unstated assumption of a grid-based picker. The button + Menu approach is simpler and requires no image rendering.

### Menu Items (follow-up)

| Option | Description | Selected |
|--------|-------------|----------|
| Position name + directional icon | "Top Left" with arrow icon | |
| Position name only | Clean text list | ✓ |
| agent's discretion | Let the agent choose | |

**User's choice:** Position name only — plain text menu items, no icons.

---

## Section Grouping

| Option | Description | Selected |
|--------|-------------|----------|
| Keep Phase 15 allocation as-is | Watermark = text+position+scale, Style = logo+sig+white frame+layers, Output = export+template | ✓ |
| Adjust grouping | User specifies what to move | |

**User's choice:** Keep as-is. No adjustments to the Phase 15 D-06 allocation.

---

## Row Presentation

| Option | Description | Selected |
|--------|-------------|----------|
| iOS Settings-style inset rows | Inset grouped list with glass backing | ✓ (implicit) |
| Labeled fields with spacing | Current VStack feel but with Markepi headers | |

**User's choice:** "Whatever is the best solution that is often employed in apps like Lightroom or Adobe — simple, professional, and modern"
**Notes:** User wants the photo-editing-app control panel aesthetic. Inset grouped rows with glass backing is the iOS-native equivalent of Lightroom's clean control panels. This maps to option 1 (inset rows).

### Export Options (follow-up)

| Option | Description | Selected |
|--------|-------------|----------|
| Keep DisclosureGroup | Inline expand/collapse for format + quality | |
| Plain row → Menu/Picker | Tap opens Menu for format, separate quality row | ✓ |

**User's choice:** Plain row → Menu/Picker. Replace DisclosureGroup.

---

## Button Language

### Primary Action Button

| Option | Description | Selected |
|--------|-------------|----------|
| Primary (accent capsule) | Visually dominant — standard iOS convention | ✓ |
| Secondary (gray capsule) | Less prominent | |

**User's choice:** Primary (Recommended) — Share/Watermark All gets accent-colored capsule.

### Remaining Button Roles

| Option | Description | Selected |
|--------|-------------|----------|
| Cancel/Retry/Template=Sec, Add=Primary, Remove=Destructive | Standard Apple HIG mapping | ✓ |
| All Secondary except Remove=Destructive | Simpler vocabulary | |

**User's choice:** Cancel/Retry/Template = Secondary, Add = Primary, Remove = Destructive.

### Button Labels

| Option | Description | Selected |
|--------|-------------|----------|
| Follow D-12 as-is | Primary=icon+text, Secondary=text-or-icon+text, Destructive=text-only, Remove=icon-only | ✓ |
| Adjust the convention | User specifies different convention | |

**User's choice:** Follow D-12 as-is.

---

## Agent's Discretion

- Exact layout metrics (padding, spacing, corner radii, separator placement) within inset grouped rows
- Menu presentation style for position picker and export format
- Transition between pill sections (MarkepiPillBar handles indicator; ControlsView switches content)

## Deferred Ideas

None — discussion stayed within phase scope.
