---
phase: 05-extended-engine-proraw-exif-tokens-multi-layer
plan: 04
subsystem: WatermarkCore Engine
tags: [multi-layer, compositing, opacity, visibility, ProRAW, DNG-metadata]
requires: [05-02, 05-03]
provides:
  - WatermarkLayer.opacity (per-layer compositing alpha)
  - WatermarkLayer.isVisible (per-layer visibility toggle)
  - D-12 compositing order enforcement (text → image → frame)
  - ProRAW dngMetadata passthrough via engine → ImageWriter
affects:
  - WatermarkConfiguration.WatermarkLayer
  - WatermarkEngine.process() / buildFilterGraph()
  - VideoLayerBuilder
tech-stack:
  added: []
  patterns:
    - CIFilter.colorMatrix aVector for per-layer opacity modulation
    - CISourceOverCompositing with D-12 frame-on-top layering
    - decodeIfPresent for backward-compatible Codable defaults
key-files:
  created:
    - Packages/WatermarkCore/Tests/WatermarkCoreTests/MultiLayerCompositingTests.swift
  modified:
    - Packages/WatermarkCore/Sources/WatermarkCore/Models/WatermarkConfiguration.swift
    - Packages/WatermarkCore/Sources/WatermarkCore/Engine/WatermarkEngine.swift
    - Packages/WatermarkCore/Sources/WatermarkCore/Processing/VideoLayerBuilder.swift
    - Packages/WatermarkCore/Sources/WatermarkCore/UI/LayerListView.swift
    - Packages/WatermarkCore/Sources/WatermarkCore/UI/TextWatermarkInputView.swift
    - Packages/WatermarkCore/Tests/WatermarkCoreTests/WatermarkEngineTests.swift
    - Packages/WatermarkCore/Tests/WatermarkCoreTests/PhotosExtensionTests.swift
decisions:
  - "Per-layer opacity via CIFilter.colorMatrix.aVector — separate from per-element opacity (text rendering alpha, PNG pixel alpha)"
  - "D-12 compositing order: text (bottom) → image (middle) → white frame (outermost/top) enforced in buildFilterGraph"
  - "Backward-compatible Codable: decodeIfPresent with defaults (opacity: 1.0, isVisible: true) for old JSON payloads"
  - "Per-layer visibility guard skips hidden layers before any rendering work (MULT-02)"
metrics:
  duration_seconds: 373
  completed_date: "2026-06-18T08:42:15Z"
---

# Phase 05 Plan 04: Multi-Layer Compositing + Engine Integration Summary

Integrated all Phase 5 capabilities into a unified multi-layer compositing pipeline: D-12 compositing order enforcement, per-layer visibility and opacity controls (MULT-02), ProRAW dngMetadata passthrough wiring, and resolution of all breaking compilation changes from Plans 05-02 and 05-03.

## Tasks Completed

| Task | Name | Type | Commit | Files |
|------|------|------|--------|-------|
| 1 | WatermarkLayer Model Update — Per-Layer Opacity and Visibility | auto | `1e133fe` | WatermarkConfiguration.swift, WatermarkEngine.swift, VideoLayerBuilder.swift, LayerListView.swift, TextWatermarkInputView.swift, PhotosExtensionTests.swift, WatermarkEngineTests.swift |
| 2 | buildFilterGraph Multi-Layer Enforcement + Engine ProRAW Wiring | auto | included in `1e133fe` | WatermarkEngine.swift |
| 3 | Multi-Layer Compositing Tests | auto (tdd) | `3b78797` | MultiLayerCompositingTests.swift |

## What Changed

### WatermarkLayer Model (Task 1)
- Added `opacity: CGFloat` and `isVisible: Bool` associated values to both `.text` and `.image` enum cases
- New computed properties `opacity` (0.0–1.0, default 1.0) and `isVisible` (default true)
- Codable backward-compatible: `decodeIfPresent` with defaults for old JSON payloads
- `strippingImageData()` and `rehydrateImageData()` updated to preserve new fields through transform
- All 50+ callers (tests, UI, engine, video builder) updated with defaults `opacity: 1.0, isVisible: true`

### Engine Integration (Task 2)
- **D-12 compositing order**: watermark layers composited first (text → image, bottom to top), THEN white frame composited on top as outermost layer
- **Per-layer visibility (MULT-02)**: `guard watermark.isVisible else { continue }` skips hidden layers before any rendering
- **Per-layer opacity (MULT-02)**: `CIFilter.colorMatrix.aVector` modulates alpha channel for layers with `opacity < 1.0`
- **ProRAW dngMetadata passthrough**: `loaded.dngMetadata` passed through to `ImageWriter.write(dngMetadata:)` — DNG metadata preserved end-to-end
- Removed old frame-before-watermarks compositing block

### Tests (Task 3)
- 8 tests in `MultiLayerCompositingTests.swift`:
  - Text + image + frame all enabled (MULT-01)
  - Hidden layer skip (MULT-02)
  - Per-layer opacity: translucent text (0.3), opaque image (1.0)
  - D-12 frame-on-top compositing order
  - Multiple text layers at different positions
  - All layers visible with default opacity
  - Backward compatibility: single text layer
  - ProRAW DNG metadata passthrough wiring

## Verification Results

```
✓ swift build — passes (0 compilation errors)
✓ MultiLayerCompositingTests — 8/8 pass
✓ WatermarkEngineTests — all pass (including combinedAllFeatures)
✓ WhiteFrameRendererTests — all pass (frame order change compatible)
✓ TextWatermarkRendererTests — all pass (overload integration OK)
✓ EXIFTokenParserTests — all pass (token integration OK)
✓ ProRAWTests — all pass (spike + detection)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  85 tests in 6 suites — all pass
```

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Enum breaking change required 50+ call site updates**
- **Found during:** Task 1
- **Issue:** Adding two new associated values to `WatermarkLayer` broke every `.text(...)` and `.image(...)` construction site across the codebase
- **Fix:** Used sed to add default `opacity: 1.0, isVisible: true` to all constructor calls in test files; manually updated pattern matches in engine, video builder, and UI files
- **Files modified:** 7 files total (WatermarkConfiguration.swift, WatermarkEngine.swift, VideoLayerBuilder.swift, LayerListView.swift, TextWatermarkInputView.swift, PhotosExtensionTests.swift, WatermarkEngineTests.swift)

### Notes

- Tasks 1 and 2 were committed together since WatermarkEngine.swift contained both the model-call updates (Task 1 dependency) and the engine logic changes (Task 2). The combined commit `1e133fe` covers both tasks' changes.
- TDD Task 3 tests passed immediately because the implementation already existed from Tasks 1-2. The RED → GREEN cycle was effectively split across the plan's task structure.
- The `frameWithTextWatermark` engine test continues to pass after the D-12 frame-on-top order change because the white frame has a transparent center — watermarks visible through the inner area are expected behavior.

## Known Stubs

None. All features are fully wired:
- Per-layer opacity is applied via `CIFilter.colorMatrix` in `buildFilterGraph()`
- Per-layer visibility is gated via `guard watermark.isVisible else { continue }`
- DNG metadata flows through `loaded.dngMetadata` → `ImageWriter.write(dngMetadata:)`
- D-12 compositing order enforced with frame composited after watermark layers

## Threat Flags

None. Threat model items T-05-09 (opacity tampering), T-05-10 (DoS via many layers), and T-05-11 (DNG metadata passthrough) are addressed by design:
- CIFilter.colorMatrix iOS GPU pipeline clamps internally (T-05-09)
- Linear layer cost, bounded by config size (T-05-10)
- DNG metadata is technical RAW data, no PII, passthrough only (T-05-11)

## Self-Check: PASSED

- [x] All created files exist: `MultiLayerCompositingTests.swift` confirmed
- [x] Commit `1e133fe` exists: `feat(05-04): add per-layer opacity and visibility to WatermarkLayer enum`
- [x] Commit `3b78797` exists: `test(05-04): add multi-layer compositing tests`
- [x] All verification criteria met: 85 tests pass, 0 compilation errors
