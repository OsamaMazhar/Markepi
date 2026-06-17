---
phase: 01-core-engine-photo-pipeline
plan: 01
subsystem: engine
tags: [swift, core-image, imageio, hdr, watermark, ciimage, cgimagesource, cgimagedestination]

# Dependency graph
requires: []
provides:
  - WatermarkCore Swift Package (iOS 18, Swift 6) with zero third-party dependencies
  - WatermarkEngine actor: process(url:config:) API for photo watermarking
  - Text watermark rendering via CIAttributedTextImageGenerator at 9 preset positions
  - CGImageSource → CGImageDestination pipeline with full metadata/HDR preservation
  - All model types: WatermarkConfiguration, WatermarkPosition, TextWatermarkInput, ImageWatermarkInput, WhiteFrameConfig, MediaMetadata, ProcessingResult, PipelineError
affects:
  - 01-core-engine-photo-pipeline (all subsequent plans)
  - 02-main-app-photo-watermark-share
  - 03-video-processing-share-extension
  - 04-photos-edit-extension-polish

# Tech tracking
tech-stack:
  added: [CoreImage, ImageIO, UniformTypeIdentifiers, UIKit(AppKit)]
  patterns:
    - "Pattern 1: CIFilter.sourceOverCompositing lazy filter graph — no intermediate pixel buffers"
    - "Pattern 2: CGImageSource metadata extraction BEFORE pixel ops → CGImageDestinationAddImage re-attachment"
    - "Pattern 3: Swift 6 actor-isolated WatermarkEngine owning shared CIContext (Pitfall 4)"
    - "Sendable safety: @unchecked Sendable on metadata dicts, String keys instead of CFString"
    - "Cross-platform: #if canImport(UIKit)/AppKit for font creation (macOS testing support)"

key-files:
  created:
    - Packages/WatermarkCore/Package.swift
    - Packages/WatermarkCore/Sources/WatermarkCore/Models/WatermarkPosition.swift
    - Packages/WatermarkCore/Sources/WatermarkCore/Models/WatermarkConfiguration.swift
    - Packages/WatermarkCore/Sources/WatermarkCore/Models/TextWatermarkInput.swift
    - Packages/WatermarkCore/Sources/WatermarkCore/Models/ImageWatermarkInput.swift
    - Packages/WatermarkCore/Sources/WatermarkCore/Models/WhiteFrameConfig.swift
    - Packages/WatermarkCore/Sources/WatermarkCore/Models/MediaMetadata.swift
    - Packages/WatermarkCore/Sources/WatermarkCore/Models/ProcessingResult.swift
    - Packages/WatermarkCore/Sources/WatermarkCore/Engine/PipelineError.swift
    - Packages/WatermarkCore/Sources/WatermarkCore/Engine/WatermarkEngine.swift
    - Packages/WatermarkCore/Sources/WatermarkCore/Input/ImageLoader.swift
    - Packages/WatermarkCore/Sources/WatermarkCore/Input/FormatDetector.swift
    - Packages/WatermarkCore/Sources/WatermarkCore/Rendering/PositionCalculator.swift
    - Packages/WatermarkCore/Sources/WatermarkCore/Rendering/WatermarkRenderer.swift
    - Packages/WatermarkCore/Sources/WatermarkCore/Rendering/TextWatermarkRenderer.swift
    - Packages/WatermarkCore/Sources/WatermarkCore/Rendering/OrientationNormalizer.swift
    - Packages/WatermarkCore/Sources/WatermarkCore/Output/ImageWriter.swift
    - Packages/WatermarkCore/Sources/WatermarkCore/Output/TempFileManager.swift
    - Packages/WatermarkCore/Sources/WatermarkCore/Utilities/CIContextProvider.swift
    - Packages/WatermarkCore/Sources/WatermarkCore/Utilities/DeviceMetadataProvider.swift
  modified: []

key-decisions:
  - "Swift 6 Sendable: used @unchecked Sendable for MediaMetadata (ImageIO dicts contain only value types but compiler can't verify)"
  - "Swift 6 Sendable: converted CFString dict keys to String keys for Sendable conformance, convert back at ImageIO boundary"
  - "Cross-platform: used #if canImport(UIKit)/AppKit for font access to support macOS testing with swift test"
  - "HDR fallback: CIImage(contentsOf:options:) with .auxiliaryHDRGainMap falls back to plain CIImage(contentsOf:) when HDR load fails (macOS SDR JPEGs)"
  - "macOS test platform: added .macOS(.v14) alongside .iOS(.v18) for UTType and expandToHDR availability during swift test"

patterns-established:
  - "Pattern 1: Core Image lazy filter graph — CISourceOverCompositing chain, no intermediate buffers, cropped to base extent"
  - "Pattern 2: CGImageSource metadata extraction BEFORE CIImage creation → CGImageDestinationAddImage with metadata dict → CGImageDestinationAddAuxiliaryDataInfo for HDR"
  - "Pattern 3: WatermarkEngine actor with shared CIContext (RGBAh + displayP3), buildFilterGraph for pure CIImage ops"
  - "TDD: RED (failing stub tests) → GREEN (implementation) for all three tasks; 55 tests total"

requirements-completed: [WMRK-01, QUAL-01, QUAL-02, QUAL-03]

# Metrics
duration: 8min
completed: 2026-06-17
---

# Phase 01 Plan 01: WatermarkCore Swift Package + Text Watermark Pipeline Summary

**Built the WatermarkCore Swift Package with a working actor-based watermark engine that renders SF system font text watermarks at 9 preset positions while preserving all EXIF metadata, HDR gain maps, and source format through a CGImageSource → Core Image filter graph → CGImageDestination pipeline — zero third-party dependencies, 55 automated tests, compiles targeting iOS 18/Swift 6.**

## Performance

- **Duration:** 8 min
- **Started:** 2026-06-17T17:29:39Z
- **Completed:** 2026-06-17T17:37:48Z
- **Tasks:** 3 (all TDD: RED → GREEN)
- **Files created:** 27 Swift files (20 source + 7 test)

## Accomplishments

- WatermarkCore Swift Package with iOS 18 platform, Swift 6 language mode, zero external dependencies
- `WatermarkEngine.process(url:config:)` actor API — full pipeline: load → normalize → render → write
- Text watermark rendering at 9 positions with configurable font size, color, and opacity via SF system fonts (D-02)
- CGImageSource → CGImageDestination pipeline preserves all EXIF/metadata (QUAL-01), HDR gain maps (QUAL-02), and source format (QUAL-03/D-09)
- CIFilter.sourceOverCompositing for GPU-accelerated multi-layer watermark compositing (Pattern 1, D-01)
- Security: file size ≤ 500MB, pixel count ≤ 100MP validation (T-01-01); UUID temp file names (T-01-04)
- 55 automated tests across 11 suites covering position math, format detection, I/O, text rendering, compositing, and E2E integration

## Task Commits

Each task was committed atomically (TDD: RED → GREEN):

1. **Task 1: Create WatermarkCore Swift Package + All Model Types + Position Enum**
   - `0115557` — `test(01-01)` — RED: failing position tests (57 issues)
   - `2a29fc1` — `feat(01-01)` — GREEN: WatermarkPosition.translation with CIImage bottom-left math, all model types

2. **Task 2: Build Input/Output Pipeline**
   - `80a02e7` — `test(01-01)` — RED: failing FormatDetector + ImageWriter tests (5 issues)
   - `59f0386` — `feat(01-01)` — GREEN: ImageLoader (metadata/HDR extraction), ImageWriter (CGImageDestination), FormatDetector, OrientationNormalizer, TempFileManager, CIContextProvider

3. **Task 3: Text Watermark Rendering + Layer Compositor + Engine Actor + E2E**
   - `e6a760c` — `test(01-01)` — RED: failing TextWatermarkRenderer + WatermarkEngine tests (8 issues)
   - `a8a0ecf` — `feat(01-01)` — GREEN: TextWatermarkRenderer (CIAttributedTextImageGenerator), WatermarkRenderer (CISourceOverCompositing), WatermarkEngine actor, DeviceMetadataProvider

## Files Created

### Package Manifest
- `Packages/WatermarkCore/Package.swift` — iOS 18 + macOS 14, Swift 6, single target WatermarkCore

### Models (8 files)
- `Models/WatermarkPosition.swift` — 9-case enum with CIImage bottom-left origin CGAffineTransform translation math
- `Models/WatermarkConfiguration.swift` — WatermarkLayer enum (.text/.image), ordered layer stack (D-01), OutputFormat
- `Models/TextWatermarkInput.swift` — text, fontSize, color (CGColor), opacity; SF system font defaults
- `Models/ImageWatermarkInput.swift` — pngData, scale, opacity; stub (full implementation Plan 02)
- `Models/WhiteFrameConfig.swift` — isEnabled flag; stub (full implementation Plan 03)
- `Models/MediaMetadata.swift` — metadata, gainMapAuxData, colorSpace, sourceUTI; @unchecked Sendable
- `Models/ProcessingResult.swift` — url/data output, outputUTI
- `Engine/PipelineError.swift` — 12 error cases with LocalizedError conformance

### Input (2 files)
- `Input/ImageLoader.swift` — CGImageSource metadata/HDR extraction, security validation, CIImage creation with HDR options + SDR fallback
- `Input/FormatDetector.swift` — CGImageSourceGetType → UTType for HEIC/JPEG/PNG (D-10)

### Rendering (4 files)
- `Rendering/PositionCalculator.swift` — delegates to WatermarkPosition.translation
- `Rendering/WatermarkRenderer.swift` — CIFilter.sourceOverCompositing per layer, crop to base extent (Pattern 1)
- `Rendering/TextWatermarkRenderer.swift` — NSAttributedString + CIAttributedTextImageGenerator (D-02)
- `Rendering/OrientationNormalizer.swift` — CIImage.oriented(.up) normalization (Pitfall 3)

### Output (2 files)
- `Output/ImageWriter.swift` — CGImageDestinationAddImage + CGImageDestinationAddAuxiliaryDataInfo (Pattern 2)
- `Output/TempFileManager.swift` — UUID filenames, cachesDirectory, cleanup (T-01-04)

### Utilities (2 files)
- `Utilities/CIContextProvider.swift` — shared CIContext with RGBAh + displayP3 (Pitfall 4)
- `Utilities/DeviceMetadataProvider.swift` — EXIF TIFF Model → LensModel → UIDevice fallback (D-07)

### Engine (1 file)
- `Engine/WatermarkEngine.swift` — actor: process(url:config:) pipeline (Pattern 3)

### Tests (7 files)
- `Tests/TestHelpers/TestImageFactory.swift` — programmatic test image creation
- `Tests/PositionCalculatorTests.swift` — 31 tests across landscape/portrait/square + edge cases
- `Tests/FormatDetectorTests.swift` — HEIC/JPEG/PNG detection
- `Tests/OrientationNormalizerTests.swift` — normalization idempotency, extent preservation
- `Tests/ImageWriterTests.swift` — metadata round-trip, pixel preservation, file output
- `Tests/TextWatermarkRendererTests.swift` — extent, font scaling, opacity
- `Tests/WatermarkRendererTests.swift` — single/multi-layer compositing, cropping, positioning
- `Tests/WatermarkEngineTests.swift` — 5 E2E tests: result, dimensions, format, structure, metadata

## Decisions Made

- **Swift 6 Sendable:** `MediaMetadata` uses `@unchecked Sendable` because ImageIO metadata dicts contain `Any` values (all value types in practice, but compiler can't verify). Dictionary keys converted from `CFString` to `String` for Sendable safety.
- **Cross-platform testing:** Added `#if canImport(UIKit)` blocks for `UIFont`/`UIColor` on iOS and `NSFont`/`NSColor` on macOS, enabling `swift test` to run on macOS for CI without Xcode.
- **HDR fallback:** `CIImage(contentsOf:options:)` with `.auxiliaryHDRGainMap: true` returns `nil` for SDR JPEGs on macOS. Added fallback to plain `CIImage(contentsOf:)` to maintain testability.
- **macOS platform:** Added `.macOS(.v14)` to Package.swift alongside `.iOS(.v18)` — required for `UTType`, `expandToHDR`, and `CIFormat.RGBAh` availability during macOS testing.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] CFString/Any not Sendable in Swift 6**
- **Found during:** Task 1 (Model type creation)
- **Issue:** `[CFString: Any]` dict and `CFString` sourceUTI prevented `Sendable` conformance on `MediaMetadata`
- **Fix:** Converted CFString dict keys to String keys at ImageIO boundary; used `@unchecked Sendable` with documentation that values are all value types
- **Files modified:** `Models/MediaMetadata.swift`
- **Verification:** `swift build` compiles without Sendable errors in Swift 6 language mode
- **Committed in:** `2a29fc1` (Task 1 GREEN)

**2. [Rule 1 - Bug] CIImage(contentsOf:options:) fails on macOS for SDR JPEGs**
- **Found during:** Task 3 (E2E tests)
- **Issue:** `CIImage(contentsOf: url, options: [.auxiliaryHDRGainMap: true, .expandToHDR: true])` returns `nil` for SDR JPEG test images on macOS
- **Fix:** Added fallback: try HDR-optioned load first, fall back to plain `CIImage(contentsOf:)` if nil
- **Files modified:** `Input/ImageLoader.swift`
- **Verification:** All 5 E2E tests pass on macOS
- **Committed in:** `a8a0ecf` (Task 3 GREEN)

**3. [Rule 1 - Bug] Test assertion incorrect for large-padding bottomRight**
- **Found during:** Task 1 (PositionCalculatorTests)
- **Issue:** Test expected `t.ty < 0` for bottomRight with padding=2000; bottomRight formula `y = padding` gives `2000` which is above the image (positive in CIImage coords)
- **Fix:** Changed assertion to `t.ty > baseExtent.height` (offscreen above)
- **Files modified:** `Tests/PositionCalculatorTests.swift`
- **Verification:** Test passes
- **Committed in:** `2a29fc1` (Task 1 GREEN)

**4. [Rule 3 - Blocking] UIKit not available on macOS during swift test**
- **Found during:** Task 3 (build)
- **Issue:** `import UIKit` fails when `swift test` runs on macOS
- **Fix:** Added `#if canImport(UIKit)`/`#elseif canImport(AppKit)` conditional compilation for `TextWatermarkRenderer` and `DeviceMetadataProvider`
- **Files modified:** `Rendering/TextWatermarkRenderer.swift`, `Utilities/DeviceMetadataProvider.swift`
- **Verification:** `swift build` succeeds, all tests pass on macOS
- **Committed in:** `e6a760c` (Task 3 RED) and refined in `a8a0ecf` (Task 3 GREEN)

**5. [Rule 3 - Blocking] CIContextOption.allowsLowPrecision incorrect, macOS version too low**
- **Found during:** Task 2 (build)
- **Issue:** `CIContextOption` has no member `allowLowPrecision` (should be `allowsLowPrecision`); `expandToHDR` requires macOS 14+
- **Fix:** Used dictionary-based `CIContext(options:)` init; bumped macOS platform from `.v11` to `.v14`
- **Files modified:** `Package.swift`, `Utilities/CIContextProvider.swift`
- **Verification:** Build and all tests pass
- **Committed in:** `59f0386` (Task 2 GREEN)

**6. [Rule 3 - Blocking] Enum pattern match expects 3 associated values**
- **Found during:** Task 3 (build)
- **Issue:** `WatermarkLayer.text` has 3 associated values `(TextWatermarkInput, position: WatermarkPosition, scale: CGFloat)` but switch matched as single tuple
- **Fix:** Changed pattern to `case .text(let textConfig, _, _)`
- **Files modified:** `Engine/WatermarkEngine.swift`
- **Verification:** Build succeeds
- **Committed in:** `a8a0ecf` (Task 3 GREEN)

**7. [Rule 3 - Blocking] UTType only available on macOS 11.0+**
- **Found during:** Task 2 (build)
- **Issue:** `UTType` requires macOS 11.0+ deployment target
- **Fix:** Added `@available(macOS 11.0, *)` to FormatDetector; later bumped platform to `.macOS(.v14)`
- **Files modified:** `Package.swift`, `Input/FormatDetector.swift`
- **Verification:** Build succeeds
- **Committed in:** `80a02e7` (Task 2 RED) and `59f0386` (Task 2 GREEN)

---

**Total deviations:** 7 auto-fixed (4 bugs, 3 blocking)
**Impact on plan:** All auto-fixes were necessary for correctness (Sendable conformance, HDR fallback, test assertion) or buildability (cross-platform imports, platform version). No architectural changes. No scope creep.

## Known Stubs

The following stubs are intentional per the plan's multi-plan phase design — they will be implemented in subsequent plans:

| Stub | File | Reason | Plan |
|------|------|--------|------|
| `ImageWatermarkInput` — no rendering | `Models/ImageWatermarkInput.swift` | Data model only; PNG-to-CIImage rendering deferred | Plan 02 |
| `WatermarkEngine.buildFilterGraph` skips `.image` case | `Engine/WatermarkEngine.swift` | Image watermark compositing not yet implemented | Plan 02 |
| `WhiteFrameConfig` — isEnabled flag only | `Models/WhiteFrameConfig.swift` | White frame border + device text rendering deferred | Plan 03 |
| `DeviceMetadataProvider.attributionText` exists but not rendered | `Utilities/DeviceMetadataProvider.swift` | White frame renders this text (Plan 03); method is testable now | Plan 03 |
| PositionCalculator padding hardcoded to 20 | `Engine/WatermarkEngine.swift` | Configurable padding deferred | Plan 02 |

## Issues Encountered

- Swift 6 strict concurrency checking is stricter than RESEARCH.md assumptions predicted — `CFString` and `Any` are not Sendable. Required `@unchecked Sendable` and String key conversion.
- macOS `swift test` uncovered platform differences: UIKit not importable, HDR CIImage options fail on SDR files, UTType requires explicit macOS deployment target.
- `CIAttributedTextImageGenerator` output had unexpected extent behavior — the `isInfinite` extent from `CIImage.empty()` worked for RED failure detection but required careful test design.

## Next Phase Readiness

- WatermarkCore Swift Package is ready for Plan 02 (PNG image watermark rendering) — all API contracts are stable
- Plan 02 can add image watermark rendering to `ImageWatermarkInput` and wire the `.image` case in `WatermarkEngine.buildFilterGraph`
- Plan 03 can implement `WhiteFrameConfig` fully and wire `DeviceMetadataProvider.attributionText` onto output
- Future plans (02-main-app, 03-share-extension, 04-photos-extension) can link WatermarkCore as a local Swift Package dependency via `Package.swift` path reference

---

*Phase: 01-core-engine-photo-pipeline*
*Plan: 01*
*Completed: 2026-06-17*
