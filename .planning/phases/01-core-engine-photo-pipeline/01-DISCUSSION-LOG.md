# Phase 1: Core Engine & Photo Pipeline — Discussion Log

**Generated:** 2026-06-17
**Mode:** auto
**Decision count:** 10

## Areas Discussed

### 1. Watermark Composition
**Q:** How should the engine compose multiple overlay elements (text + image + frame)?
**Auto-selected:** Ordered layer stack — text and image overlays arranged in any order, composited onto base image.

**Q:** What font support for text watermarks?
**Auto-selected:** System fonts (San Francisco) only in v1. Custom fonts deferred to v2.

**Q:** What watermark image formats?
**Auto-selected:** PNG with alpha/transparency. SVG/HEIC deferred.

### 2. White Frame Design
**Q:** Full border or bottom-only?
**Auto-selected:** Uniform border on all 4 sides.

**Q:** Fixed width or proportional?
**Auto-selected:** Proportional — 3-5% of shorter image dimension.

**Q:** Metadata text placement?
**Auto-selected:** Centered on bottom portion of white frame.

### 3. Metadata Content
**Q:** What info appears in the "Taken by:" frame?
**Auto-selected:** "Taken by: [Device Model]" sourced from EXIF metadata, fallback to UIDevice.current.model.

**Q:** Multiple metadata lines?
**Auto-selected:** Single "Taken by:" line in v1. Date, GPS, lens info deferred to v2.

### 4. Output Format
**Q:** Output format strategy?
**Auto-selected:** Preserve source format (HEIC→HEIC, JPEG→JPEG). Format change only when required (transparency).

**Q:** Supported formats?
**Auto-selected:** HEIC, JPEG, PNG core. ProRAW and TIFF deferred to v2.

## Deferred Ideas
- Custom font import → v2 (CUST-01)
- SVG/HEIC watermark images → v2
- Additional metadata lines (date, GPS, lens) → v2 (CUST-04)
- ProRAW/TIFF output support → v2
- Rotation control → v2 (CUST-02)
- Template/preset saving → v2 (CUST-01)
