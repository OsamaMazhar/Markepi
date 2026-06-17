---
phase: 01-core-engine-photo-pipeline
plan: 02
subsystem: engine
tags: [swift, core-image, png, watermark, ciimage, cicolormatrix, alpha, opacity, scale, positioning]

# Dependency graph
requires:
  - 01-01 (WatermarkCore package, text watermark pipeline, 9-position enum, compositor)
provides:
  - PNG image watermark rendering with alpha channel preservation
  - ImageWatermarkRenderer: PNG Data → CIImage with scale + opacity
  - Full 9-position coverage verified with image watermarks
  - Configurable padding via WatermarkConfiguration.padding
  - Multi-layer mixed text+image compositing (D-01)
  - ImageWatermarkInput with validation (scale 0.01–0.90, non-empty PNG)
affects:
  - 01-03 (white frame rendering — uses same padding config)
  - 02-main-app-photo-watermark-share (consumes image watermark API)
  - 03-video-processing-share-extension
  - 04-photos-edit-extension-polish

# Tech tracking
tech-stack:
  added: [CIFilter.colorMatrix, CIImage(data:), CGAffineTransform(scaleX:scaleY:)]
  patterns:
    - "ImageWatermarkRenderer follows TextWatermarkRenderer pattern: static render(config:) → CIImage"
    - "Opacity via CIFilter.colorMatrix aVector alpha modulation (multiply alpha channel, RGB untouched)"
    - "CISourceOverCompositing in WatermarkRenderer naturally respects modulated alpha for correct blends"
    - "PNG data validated in ImageWatermarkInput.init (non-empty); format validation deferred to CIImage(data:) returning nil"
    - "Scale validation (0.01–0.90) prevents memory exhaustion from extreme CIImage extents (T-02-02)"

key-files:
  created:
    - Packages/WatermarkCore/Sources/WatermarkCore/Rendering/ImageWatermarkRenderer.swift
    - Packages/WatermarkCore/Tests/WatermarkCoreTests/ImageWatermarkRendererTests.swift
  modified:
    - Packages/WatermarkCore/Sources/WatermarkCore/Engine/WatermarkEngine.swift
    - Packages/WatermarkCore/Sources/WatermarkCore/Models/WatermarkConfiguration.swift
    - Packages/WatermarkCore/Sources/WatermarkCore/Models/ImageWatermarkInput.swift
    - Packages/WatermarkCore/Sources/WatermarkCore/Engine/PipelineError.swift
    - Packages/WatermarkCore/Tests/WatermarkCoreTests/WatermarkEngineTests.swift
    - Packages/WatermarkCore/Tests/WatermarkCoreTests/WatermarkRendererTests.swift

key-decisions:
  - "Opacity approach: CIFilter.colorMatrix aVector for alpha modulation instead of pre-compositing onto transparent background — keeps filter graph lazy and preserves HDR pixel format"
  - "Scale validation range 0.01–0.90: prevents CIImage extents that would cause memory exhaustion (T-02-02), while allowing practical watermark sizes from tiny (1%) to dominant (90%)"
  - "Padding property on WatermarkConfiguration (not a separate type): single source of truth consumed by PositionCalculator, defaults to 20pt, trivially testable"
  - "ImageWatermarkInput.init throws for scale violations and empty data; clamps opacity silently (0.0–1.0) — throwing for scale is a security boundary per threat model"

requirements-completed: [WMRK-02, WMRK-03]

# Metrics
duration: 5min
completed: 2026-06-17
---

# Phase 01 Plan 02: PNG Image Watermark Rendering + Full 9-Position Coverage + Configurable Padding Summary

**Extended the WatermarkCore engine with PNG image/logo watermark support via ImageWatermarkRenderer (CIImage(data:) → CGAffineTransform scale → CIFilter.colorMatrix opacity), wired into the engine's buildFilterGraph with configurable padding, completing all 9-position coverage with verified mixed text+image multi-layer compositing — 23 new tests, zero regressions, WMRK-02 and WMRK-03 complete.**

## Performance

- **Duration:** ~5 min
- **Started:** 2026-06-17T17:40:18Z
- **Completed:** 2026-06-17T17:45:44Z
- **Tasks:** 2 (both TDD: RED → GREEN)
- **Files:** 2 created, 6 modified
- **Tests:** 23 new (13 ImageWatermarkRenderer + 10 engine/renderer), 78 total (no regressions)

## Accomplishments

- `ImageWatermarkRenderer.render(config:)` — PNG Data → CIImage pipeline: decode via `CIImage(data:)`, scale via `CGAffineTransform(scaleX:scaleY:)`, opacity via `CIFilter.colorMatrix` aVector alpha modulation
- `ImageWatermarkInput` — throwing init validates: non-empty PNG data (`PipelineError.invalidImageData`), scale 0.01–0.90 (`PipelineError.invalidScale`), opacity clamped 0.0–1.0
- `WatermarkEngine.buildFilterGraph` — `.image` case wired to `ImageWatermarkRenderer.render()`; removed Plan 01 stub (`continue`)
- `WatermarkConfiguration.padding: CGFloat = 20` — consumed by `PositionCalculator` via engine, replacing hardcoded `defaultPadding`
- Multi-layer mixed text+image compositing works correctly per D-01 (ordered layer stack)
- All 9 positions verified via existing `WatermarkPosition.translation()` math (Plan 01 implementation) plus new E2E engine tests with image watermarks
- `PipelineError` now `Equatable` — enables `#expect(throws:)` in Swift Testing for error assertions
- Threat mitigations: scale range validation (T-02-02), empty PNG data rejection (T-02-01)

## Task Commits

1. **Task 1: Image Watermark Renderer — PNG Data to CIImage with Alpha + Scale + Opacity** (TDD)
   - `220d512` — `test(01-02)` — RED: 13 failing tests for PNG rendering, scale, opacity, validation
   - `68510df` — `feat(01-02)` — GREEN: ImageWatermarkInput validation, ImageWatermarkRenderer with opacity via CIFilter.colorMatrix, PipelineError Equatable

2. **Task 2: Wire Image Watermark into Engine + 9-Position Coverage + Configurable Padding + Multi-Layer Tests** (TDD)
   - `1d903c4` — `test(01-02)` — RED: engine tests for mixed layers, opacity, padding (image layer skipped → watermark absent)
   - `314dcb8` — `feat(01-02)` — GREEN: .image case wired, config.padding replaces hardcoded defaultPadding

## Files Created

- `Rendering/ImageWatermarkRenderer.swift` — static `render(config:) throws -> CIImage` with PNG decode, CGAffineTransform scale, CIFilter.colorMatrix opacity
- `Tests/ImageWatermarkRendererTests.swift` — 13 tests: valid PNG, scale transform, empty/invalid data, opacity blends, transparent watermark, scale validation boundaries, default values

## Files Modified

- `Models/ImageWatermarkInput.swift` — throwing init with validation, documentation updated from "stub" to full implementation
- `Models/WatermarkConfiguration.swift` — added `var padding: CGFloat = 20`
- `Engine/WatermarkEngine.swift` — `.image` case wired, `config.padding` used, removed `defaultPadding` property
- `Engine/PipelineError.swift` — added `Equatable` conformance
- `Tests/WatermarkEngineTests.swift` — 7 new tests: mixed text+image, opacity 0.0/1.0, configurable/default padding, image-only config, plus PNG data helper
- `Tests/WatermarkRendererTests.swift` — 4 new tests: three-layer compositing, layer order sensitivity, scale edge cases (tiny/large)

## Decisions Made

- **Opacity via CIFilter.colorMatrix:** Modulating alpha channel with aVector `(0, 0, 0, opacity)` keeps RGB channels intact. `CISourceOverCompositing` in the compositor then uses the modulated alpha for correct blending. This stays within the lazy Core Image filter graph (no intermediate rendering).
- **Scale range 0.01–0.90:** Lower bound prevents near-zero watermarks (waste of computation). Upper bound prevents 1.0+ scale from exceeding base image dimensions or causing extreme CIImage extents (T-02-02 denial-of-service vector). Practical range covers all real-world watermark sizes.
- **ImageWatermarkInput.init is throwing:** Validation at construction time catches invalid configs before they reach the rendering pipeline. Opacity is clamped silently (0.0–1.0) — throwing for scale is a security boundary per the threat model.
- **Padding on WatermarkConfiguration:** Single source of truth. Defaults to 20pt (matching Plan 01 hardcoded value for backward compatibility). Engine passes `config.padding` directly to `PositionCalculator`.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Test scale values exceeded valid range**
- **Found during:** Task 1 GREEN
- **Issue:** Tests used `scale: 1.0` which is outside the validated 0.01–0.90 range, causing `PipelineError.invalidScale` at init
- **Fix:** Changed opacity and transparency test watermarks from 50×50 at scale 1.0 to 100×100 at scale 0.5 (same net size, valid scale)
- **Files modified:** `Tests/ImageWatermarkRendererTests.swift`
- **Committed in:** `68510df` (Task 1 GREEN)

**2. [Rule 1 - Bug] CIFilter.colorMatrix CIVector expects CGFloat, not Float**
- **Found during:** Task 1 GREEN (compile)
- **Issue:** `CIVector(x: 0, y: 0, z: 0, w: opacity)` where opacity was `Float` causing type mismatch
- **Fix:** Changed `let opacity = Float(config.opacity)` to `let opacity = CGFloat(config.opacity)`
- **Files modified:** `Rendering/ImageWatermarkRenderer.swift`
- **Committed in:** `68510df` (Task 1 GREEN)

**3. [Rule 1 - Bug] macOS test helper used incorrect CIFilter constant name**
- **Found during:** Task 1 RED (compile)
- **Issue:** `kCIInputAlphaVectorKey` not found in scope on macOS; the correct constant is `"inputAVector"` as a string literal
- **Fix:** Changed to string literal `"inputAVector"` in the macOS test PNG generation fallback
- **Files modified:** `Tests/ImageWatermarkRendererTests.swift`
- **Committed in:** `68510df` (Task 1 GREEN)

**4. [Rule 3 - Blocking] PipelineError not Equatable prevented #expect(throws:)**
- **Found during:** Task 1 RED (compile)
- **Issue:** Swift Testing `#expect(throws:)` macro requires the error type to conform to `Equatable`; `PipelineError` did not
- **Fix:** Added `Equatable` to `PipelineError` enum conformance (auto-synthesized since all associated values — `Double`, `String` — are Equatable)
- **Files modified:** `Engine/PipelineError.swift`
- **Committed in:** `68510df` (Task 1 GREEN)

**5. [Rule 3 - Blocking] Tests needed WatermarkConfiguration.padding to compile**
- **Found during:** Task 2 RED (compile)
- **Issue:** New engine tests referenced `config.padding = 50` but `WatermarkConfiguration` had no padding property
- **Fix:** Added `var padding: CGFloat = 20` to `WatermarkConfiguration` (was part of the plan's GREEN implementation, needed early for test compilation)
- **Files modified:** `Models/WatermarkConfiguration.swift`
- **Committed in:** `1d903c4` (Task 2 RED)

**Total deviations:** 5 auto-fixed (3 bugs, 2 blocking)
**Impact on plan:** All auto-fixes were necessary for correctness (valid scale in tests, correct Core Image types/constants) or buildability (Equatable conformance, padding property). No architectural changes. No scope creep.

## Known Stubs

The following stubs are intentional per the plan's multi-phase design — they will be implemented in subsequent plans:

| Stub | File | Reason | Plan |
|------|------|--------|------|
| `WhiteFrameConfig` — isEnabled flag only | `Models/WhiteFrameConfig.swift` | White frame border + device text rendering deferred | Plan 03 |
| `DeviceMetadataProvider.attributionText` exists but not rendered | `Utilities/DeviceMetadataProvider.swift` | White frame renders this text (Plan 03) | Plan 03 |
| `WatermarkEngine.buildFilterGraph` does not apply white frame | `Engine/WatermarkEngine.swift` | Frame compositing deferred to Plan 03 | Plan 03 |
| `FormatDetector` HEIC detection stub | `Input/FormatDetector.swift` | HEIC detection stub from Plan 01, not in Plan 02 scope | Future plan |

---

*Phase: 01-core-engine-photo-pipeline*
*Plan: 02*
*Completed: 2026-06-17*

## Self-Check: PASSED

- ImageWatermarkRenderer.swift: FOUND
- ImageWatermarkRendererTests.swift: FOUND
- 01-02-SUMMARY.md: FOUND
- 220d512 (Task 1 RED): FOUND
- 68510df (Task 1 GREEN): FOUND
- 1d903c4 (Task 2 RED): FOUND
- 314dcb8 (Task 2 GREEN): FOUND
