# Phase 5: Extended Engine (ProRAW, EXIF Tokens, Multi-Layer) - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.

**Date:** 2026-06-18
**Phase:** 5-Extended Engine (ProRAW, EXIF Tokens, Multi-Layer)
**Areas discussed:** ProRAW DNG path, EXIF token syntax, EXIF token fallback, Multi-layer compositing, Multi-layer data model

---

## ProRAW DNG Path

| Option | Description | Selected |
|--------|-------------|----------|
| RAW Bayer data | Process full 48MP RAW data from DNG, preserve DNG metadata | ✓ |
| Embedded JPEG preview | Process lower-res JPEG preview for performance | |

**User's choice:** [auto] RAW Bayer data at full 48MP with HDR gain map preservation.
**Notes:** Memory profiling required with Instruments. Use tiled rendering if needed.

---

## EXIF Token Syntax

| Option | Description | Selected |
|--------|-------------|----------|
| `{camera_model}` style | Curly-brace delimited, snake_case | ✓ |
| `{{camera_model}}` style | Double curly braces | |
| `$camera_model` style | Dollar-sign prefix | |

**User's choice:** [auto] `{camera_model}` format matching REQUIREMENTS.md EXIF-01 spec.
**Notes:** Exact keys: camera_model, lens, aperture, focal_length, shutter_speed, iso, date, gps.

---

## EXIF Token Fallback

| Option | Description | Selected |
|--------|-------------|----------|
| "--" placeholder | Double em dash when EXIF field missing | ✓ |
| Empty string | Silent removal of unresolved token | |
| "(Unknown)" | Explicit "Unknown" text | |

**User's choice:** [auto] "--" placeholder. Never empty — user must know token didn't resolve.

---

## Multi-Layer Compositing

| Option | Description | Selected |
|--------|-------------|----------|
| Fixed order: text→image→frame | Deterministic back-to-front order | ✓ |
| User-reorderable | Drag-and-drop layer reordering | |
| Configurable order via enum | Preset ordering schemes | |

**User's choice:** [auto] Fixed order (text watermarks → image watermarks → white frame). User-reorderable deferred to v2 CUST-02.

---

## Multi-Layer Data Model

| Option | Description | Selected |
|--------|-------------|----------|
| Reuse [WatermarkLayer] array | Allow both .text and .image in same array | ✓ |
| New MultiLayerConfig type | Separate model for multi-layer state | |
| Pick-one with stacking | Keep single-layer, add "stacking" flag | |

**User's choice:** [auto] Reuse existing `[WatermarkLayer]` — remove any single-layer assumption.

---

## Claude's Discretion

- ProRAW CIImage loading options and rendering configuration
- EXIF token parser implementation (regex-based vs dedicated parser struct)
- Token substitution integration into TextWatermarkRenderer and WhiteFrameRenderer
- GPS coordinate extraction and formatting
- DNG metadata write path
- Memory profiling strategy for 48MP pipeline
- FormatDetector extension for DNG UTI
- Test coverage for token types, ProRAW round-trip, multi-layer combinations

## Deferred Ideas

- User-reorderable layer order → v2 CUST-02
- Additional token types (flash, white balance, exposure bias) → v2 CUST-04
- Custom token format strings → v2 CUST-03
- ProRAW→HEIC/JPEG tone-mapped export → Phase 6 EXPT-03
