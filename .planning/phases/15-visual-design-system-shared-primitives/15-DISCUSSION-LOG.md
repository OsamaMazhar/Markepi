# Phase 15: Visual Design System & Shared Primitives - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-21
**Phase:** 15-Visual Design System & Shared Primitives
**Areas discussed:** Liquid Glass surface area, Section structure, Button language vocabulary, Typographic hierarchy, Scroll-edge effects, Shared primitive packaging

---

## Liquid Glass surface area

| Option | Description | Selected |
|--------|-------------|----------|
| Toolbar + floating buttons + sheet surface | The 3 chrome surfaces visible in every target. Minimal risk. | |
| Toolbar only | Most conservative, least visual impact. | |
| Everything semi-transparent | More depth but may clash with readability. | |

**User's choice:** "Everything MUST adopt iOS 26 Liquid Glass" (freeform — emphatic, no exceptions)

| Option | Description | Selected |
|--------|-------------|----------|
| Material hierarchy | ultaThinMaterial for toolbar/buttons, regularMaterial for sheet surfaces. | ✓ |
| Single material (regular) | One material everywhere. | |
| Opaque backgrounds | Flat surfaces, no translucency. | |

**User's choice:** Material hierarchy (Recommended)

**Notes:** Coherent "glass lite" look on iOS 18. Won't look identical to iOS 26 but won't look broken.

| Option | Description | Selected |
|--------|-------------|----------|
| System-adaptive tint | Auto follows system appearance — cooler light, warmer dark. | ✓ |
| Fixed cool tint | Consistent brand look but harsh in dark mode. | |
| Defer to Phase 17 | Decide later. | |

**User's choice:** System-adaptive tint (Recommended)

| Option | Description | Selected |
|--------|-------------|----------|
| Glass on cards only, controls opaque | Content reads as content on glass. | ✓ |
| Glass on input fields only | Lighter touch, depth on input areas. | |

**User's choice:** Glass on cards only, controls opaque (Recommended)

**Notes:** Keeps text legible and controls clearly interactive. Glass is surface-level, not element-level.

---

## Section structure

| Option | Description | Selected |
|--------|-------------|----------|
| Semantic groups — 3 cards | Watermark, Appearance, Output in inset cards. | |
| One card per control (7+ cards) | Minimal grouping, maximal noise. | |
| Minimal — 2 cards | Watermark controls + output/config. | |

**User's choice:** Rejected the card concept entirely. Instead: pill bar with 3 swipable sections. "Instead of a card how about we do sections like the pill bar. We can set horizontally each detail in the card and then can swipe left or right or tap the pill to go to next?" (freeform)

| Option | Description | Selected |
|--------|-------------|----------|
| Vertical scroll within each section | Multiple controls per pill, natural for many controls. | ✓ |
| Fit-to-size, no internal scroll | Tighter layouts, no nested scroll. | |

**User's choice:** Vertical scroll within each section (Recommended)

| Option | Description | Selected |
|--------|-------------|----------|
| Native segmented picker | System conventions, auto-adapts to glass. | ✓ |
| Custom glass pills | Custom, matches "everything is glass." | |
| Standard segmented picker | Reliable, well-tested, no glass. | |

**User's choice:** Native segmented picker (Recommended)

| Option | Description | Selected |
|--------|-------------|----------|
| Inset grouped rows | Settings-style rows within each pill. | ✓ |
| Plain list with separators | Lighter, less visual weight. | |
| Nested cards | Original card idea shifted inside pill. | |

**User's choice:** Inset grouped rows (Recommended)

| Option | Description | Selected |
|--------|-------------|----------|
| 3 balanced pills | Watermark (text, position, scale) / Style (logo, signature, white frame, layer list) / Output (export options, save template) | ✓ |
| Content-heavy 1st pill | All watermark controls in one pill, fewer controls in others. | |

**User's choice:** 3 balanced pills (Recommended)

| Option | Description | Selected |
|--------|-------------|----------|
| Text only | Clean, scannable, accessible. | ✓ |
| Icons only | SF Symbols, compact but less explicit. | |
| Icon + text, graceful fallback | Both where space permits. | |

**User's choice:** Text only (Recommended)

**User's choice (Share button):** "the share button must be an icon overlayed on top or top right above the image so the user can export asap" (freeform)

**Notes:** Save-as-Template goes in the Output section. Share button is an icon overlay on preview — Phase 15 defines its visual style; Phase 17 confirms placement.

---

## Button language vocabulary

| Option | Description | Selected |
|--------|-------------|----------|
| Pill / capsule | iOS 26 standard, looks native on glass. | ✓ |
| Rounded rectangle (~10pt) | Traditional, familiar. | |
| Capsule for primary, rounded for secondary | Visual distinction between levels. | |

**User's choice:** Pill / capsule (Recommended)

| Option | Description | Selected |
|--------|-------------|----------|
| Standard iOS convention | accentColor primary, gray secondary, red destructive. | ✓ |
| Blue primary, accent secondary | Distinct from accentColor. | |
| Accent-color-everything | Simplest palette. | |

**User's choice:** Standard iOS convention (Recommended)

| Option | Description | Selected |
|--------|-------------|----------|
| Custom ButtonStyle | Simple, works with existing Button API. | ✓ |
| Wrapper view | More control, diverges from SwiftUI conventions. | |
| ViewModifier | Intermediate approach. | |

**User's choice:** Custom ButtonStyle (Recommended)

| Option | Description | Selected |
|--------|-------------|----------|
| Context-dependent | icon+text primary, icon-only overlay, text-only destructive. | ✓ |
| Always icon+text | Uniform, accessible, wordy. | |

**User's choice:** Context-dependent (Recommended)

---

## Typographic hierarchy

| Option | Description | Selected |
|--------|-------------|----------|
| Standard iOS 26 scale | title3.semibold headers, body labels, monospaced values, caption metadata. | ✓ |
| Compressed scale | Lighter, less imposing. | |
| Expanded scale | Heavier, more emphasis. | |

**User's choice:** Standard iOS 26 scale (Recommended)

| Option | Description | Selected |
|--------|-------------|----------|
| System default | Safest, most readable. | ✓ |
| Rounded for headers/labels | Softer glass-era feel. | |
| Rounded everywhere | Consistent soft look. | |

**User's choice:** System default (Recommended)

| Option | Description | Selected |
|--------|-------------|----------|
| ViewModifier | .markepiTypography(.sectionHeader) — simple, hard to deviate. | ✓ |
| Font extension enum | More idiomatic. | |
| Documentation only | No code primitive. | |

**User's choice:** ViewModifier (Recommended)

| Option | Description | Selected |
|--------|-------------|----------|
| Uncapped | Let standard font styles scale with Dynamic Type. | ✓ |
| Capped at specific sizes | Prevents extreme breakage but limits accessibility. | |

**User's choice:** Uncapped, layout handles scaling (Recommended)

---

## Scroll-edge effects

| Option | Description | Selected |
|--------|-------------|----------|
| Glass backing + clip disabled | Native iOS 26 pattern. | ✓ |
| Gradient mask overlay | Clean, no blur needed. | |
| Row-level scrollTransition | Dynamic per-row animation. | |
| No edge effect | Clip only — simplest. | |

**User's choice:** Glass backing on pill bar + clip disabled (Recommended)

| Option | Description | Selected |
|--------|-------------|----------|
| Material fallback is sufficient | ultraThinMaterial provides same obscuring effect. | ✓ |
| Gradient mask as fallback | Two code paths. | |
| No edge effect on iOS 18 | Less polish. | |

**User's choice:** Material fallback is sufficient (Recommended)

| Option | Description | Selected |
|--------|-------------|----------|
| Top edge only | No colliding element at bottom. | ✓ |
| Both top and bottom | Symmetry, pure polish. | |

**User's choice:** Top edge only (Recommended)

| Option | Description | Selected |
|--------|-------------|----------|
| Yes — reusable modifier | Applied to any scroll view. | ✓ |
| No — inline only | Not worth abstraction. | |

**User's choice:** Yes — reusable modifier (Recommended)

---

## Shared primitive packaging

| Option | Description | Selected |
|--------|-------------|----------|
| New DesignSystem/ folder | Clear separation from existing UI/ folder. | ✓ |
| Inline in existing UI/ folder | Simpler structure. | |
| New SPM module | Fully separate compilation unit, overkill. | |

**User's choice:** New DesignSystem/ folder (Recommended)

| Option | Description | Selected |
|--------|-------------|----------|
| Public — usable by all targets | Consumed directly by extension roots and ContentView. | ✓ |
| Internal to WatermarkCore | Only consumed by other WatermarkCore views. | |

**User's choice:** Public — usable by all targets (Recommended)

| Option | Description | Selected |
|--------|-------------|----------|
| Watermark/Markepi prefix | Clear ownership, no collision risk. Naming updated per app rename to Markepi. | ✓ |
| DesignSystem enum namespace | Modern, reads cleanly. | |
| No prefix/namespace | Simpler but collision-prone. | |

**User's choice:** Markepi prefix (updated from Watermark per app rename)

**Notes:** User directed: "we are going to change the name of this app to Markepi, so make sure to use that prefix."

| Option | Description | Selected |
|--------|-------------|----------|
| Yes — include preview catalog | All primitives rendered side-by-side. | ✓ |
| No — per-file previews only | Less centralized. | |

**User's choice:** Yes — include preview catalog (Recommended)

---

## Agent's Discretion

- Specific iOS 26 API calls (`GlassEffect`, `glassMaterial`, etc.) — research during planning
- Exact ViewModifier signatures and parameter defaults — planner derives from above
- `#if available(iOS 26, *)` fallback structure — standard pattern

## Deferred Ideas

- **Full app rename (Watermark → Markepi):** Bundle IDs, package names, folder structure, existing source files. Project-level change beyond Phase 15.
- **Share button placement on preview:** Phase 17's bottom-sheet shell confirms exact position and sizing.
- **Drag-to-position watermark (VIS-05):** v2.2+ per REQUIREMENTS.md.
- **Glass-morph transitions (VIS-06):** v2.2+ per REQUIREMENTS.md.
