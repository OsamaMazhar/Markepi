# Phase 1: Core Engine & Photo Pipeline - Context

**Gathered:** 2026-06-17
**Status:** Ready for planning

## Phase Boundary

This phase delivers a shared Swift Package (WatermarkCore) containing the photo watermarking engine. The engine renders text and image watermarks at 8 configurable positions, applies white borders with device metadata text, and outputs the result with full HDR, EXIF, and color profile preservation. The engine is testable end-to-end without any UI — it exposes a programmatic API consumed by all subsequent phases (main app, share extension, Photos extension).

**In scope:** Text watermark rendering, image/logo watermark compositing, 8-position placement, white frame + device metadata overlay, HDR gain map preservation, EXIF/metadata passthrough, format-aware output

**Out of scope:** Video processing (Phase 3), any UI (Phase 2), share sheet integration (Phase 2-3), Photos extension (Phase 4)

## Implementation Decisions

### Watermark Composition
- **D-01:** The engine composes watermarks as an ordered layer stack (text and image overlays can be arranged in any order, then composited onto the base image)
- **D-02:** Text watermarks use SF system fonts in v1. Custom font import is deferred to v2 (CUST-01 group)
- **D-03:** Image/logo watermarks accept PNG format with alpha/transparency support. SVG and HEIC watermark images deferred.

### White Frame Design
- **D-04:** White frame is a uniform border on all 4 sides of the image — not a bottom-only strip
- **D-05:** Frame width is proportional to the image (3-5% of the shorter dimension)
- **D-06:** Metadata text is rendered centered on the bottom portion of the white frame

### Metadata Content
- **D-07:** Primary text line reads "Taken by: [Device Model]" where device model is sourced from EXIF metadata when available, falling back to `UIDevice.current.model`
- **D-08:** v1 supports a single "Taken by:" metadata line. Additional metadata lines (camera date, GPS location, lens/camera specs) are deferred to v2 (CUST-04 group)

### Output Format
- **D-09:** Engine preserves the source image format for output (HEIC in → HEIC out, JPEG in → JPEG out) unless the watermark requires a format change (e.g., transparency mandates PNG/HEIC)
- **D-10:** Core supported formats: HEIC, JPEG, PNG. ProRAW and TIFF are deferred to v2.

### Claude's Discretion
- Core Image filter chain architecture (CIFilter graph composition, shared CIContext reuse strategy)
- Watermark position coordinate math (normalized vs pixel coordinates, aspect ratio handling)
- CGImageSource → CGImageDestination metadata extraction and re-application approach
- HDR gain map extraction via `kCGImageAuxiliaryDataTypeHDRGainMap` and re-attachment

## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project Foundation
- `.planning/PROJECT.md` — Project context, core value, constraints, out-of-scope boundaries
- `.planning/config.json` — Granularity (coarse), parallelization, workflow preferences

### Requirements
- `.planning/REQUIREMENTS.md` — v1 requirements WMRK-01 through WMRK-03, FRME-01 through FRME-02, QUAL-01 through QUAL-03

### Research
- `.planning/research/STACK.md` — Technology stack: Swift 6, Core Image, ImageIO, CGImageDestination, CIContext, HDR gain map APIs
- `.planning/research/ARCHITECTURE.md` — MVVM + @Observable pattern, shared Swift Package (WatermarkCore), Core Image filter graph approach, rendering pipeline data flow
- `.planning/research/PITFALLS.md` — Critical pitfalls: HDR gain map destruction (pitfall #1), metadata stripping via UIImage conversion (pitfall #3), CIImage coordinate system vs EXIF orientation (pitfall #4), color profile loss (pitfall #5)
- `.planning/research/SUMMARY.md` §Phase 1 — Foundation recommendation: pure logic models, renderers, position calculator; testable in isolation, no UI

### Phase Tracking
- `.planning/ROADMAP.md` Phase 1 — Goal, requirements, success criteria
- `.planning/STATE.md` — Current position and blockers

## Existing Code Insights

### Reusable Assets
- None — greenfield project. All engine code is written from scratch.

### Established Patterns
- N/A — this is the first phase. Sets conventions for the WatermarkCore Swift Package API that all subsequent phases (Phases 2-4) will consume.

### Integration Points
- The WatermarkCore Swift Package is linked by: main app target (Phase 2), share extension target (Phase 3), Photos edit extension target (Phase 4)
- Engine API signature must be stable — all phases depend on it
- Output is written to temp files for Phase 2's share sheet to consume (no camera roll save)

## Specific Ideas

- Watermark positions defined as enum with 8 cases: topLeft, topCenter, topRight, middleLeft, center, middleRight, bottomLeft, bottomCenter, bottomRight (center = 9th implicit position, or map center → one of the 8)
- "Taken by:" frame aesthetic should match the Instagram/TikTok trend — clean, minimal, white border like iPhone screenshots with attribution text
- User explicitly specified 8 positions in the idea document — support exactly 8 preset positions (corners × 4 + edge centers × 4), with center as an additional implicit position

## Deferred Ideas

- Custom font import for text watermarks → defer to v2 (CUST-01)
- SVG/HEIC watermark image support → defer to v2
- Additional metadata frame lines (date, GPS, camera specs) → defer to v2 (CUST-04)
- ProRAW and TIFF output format support → defer to v2
- Rotation control for watermarks → defer to Phase 2 or v2 (CUST-02)
- Template/preset saving → defer to v2 (CUST-01)

---
*Phase: 1-Core Engine & Photo Pipeline*
*Context gathered: 2026-06-17*
