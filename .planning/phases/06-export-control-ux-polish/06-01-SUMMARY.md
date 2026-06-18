---
phase: 06-export-control-ux-polish
plan: 01
subsystem: export-control
tags: [swift, swiftui, core-image, imageio, codable, tiff, heic, jpeg, png, hdr]

# Dependency graph
requires:
  - phase: 05-proraw-exif-multi-layer
    provides: WatermarkConfiguration with outputFormat, WatermarkEngine pipeline, ControlsView layout
provides:
  - OutputFormat.tiff case with UTI/isLossless computed properties
  - WatermarkConfiguration.outputQuality property with backward-compatible Codable
  - ImageWriter destinationUTI + quality parameters
  - Engine-level format resolution from config
  - Export Options DisclosureGroup UI with format picker + quality slider
  - HDR→JPEG loss warning dialog
affects:
  - 06-02-comparison-view (ControlsView layout changed)
  - 06-03-video-export-ux (ControlsView layout changed)
  - 07-live-photos-signature (format pipeline extended)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "OutputFormat.uti: nil for .preserveSource, UTI string for explicit formats — enables nil-coalescing in engine for source fallback"
    - "OutputFormat.isLossless: computed Bool for UI-driven slider disabled state"
    - "Quality merged into combinedMetadata dict BEFORE CGImageDestinationAddImage (Pitfall 5: single properties dict pattern)"
    - "HDR source detection via CGImageSourceGetType UTI heuristic (format-based, not gain-map-based)"

key-files:
  created:
    - Packages/WatermarkCore/Tests/WatermarkCoreTests/OutputFormatTests.swift
    - Packages/WatermarkCore/Tests/WatermarkCoreTests/ImageWriterFormatTests.swift
  modified:
    - Packages/WatermarkCore/Sources/WatermarkCore/Models/WatermarkConfiguration.swift
    - Packages/WatermarkCore/Sources/WatermarkCore/Input/FormatDetector.swift
    - Packages/WatermarkCore/Sources/WatermarkCore/UI/WatermarkConfigurable.swift
    - Packages/WatermarkCore/Sources/WatermarkCore/Output/ImageWriter.swift
    - Packages/WatermarkCore/Sources/WatermarkCore/Engine/WatermarkEngine.swift
    - Packages/WatermarkCore/Sources/WatermarkCore/UI/ControlsView.swift
    - Packages/WatermarkCore/Tests/WatermarkCoreTests/FormatDetectorTests.swift
    - Packages/WatermarkCore/Tests/WatermarkCoreTests/ImageWriterTests.swift
    - App/ViewModels/WatermarkViewModel.swift
    - ShareExtension/ShareExtensionViewModel.swift

key-decisions:
  - "Output format resolution: config.outputFormat.uti ?? loaded.sourceUTI — nil on .preserveSource means 'use source UTI'"
  - "TIFF support as photo-only output format with isLossless=true and public.tiff UTI per CGImageDestination"
  - "Quality value merged into same combinedMetadata dictionary as metadata (not a separate call) per Pitfall 5"
  - "HDR source detection is format-heuristic (HEIC UTI check), not full gain-map inspection — advisory dialog is sufficient for MVP"
  - "Video format override explicitly excluded (processVideo unchanged) — only photo path receives format/quality control"

patterns-established:
  - "Config-driven format override: engine resolves destinationUTI from config, passes to ImageWriter + TempFileManager + ProcessingResult"
  - "Lossless format detection drives UI: isLossless computed property controls slider disabled state and percentage label styling"
  - "Backward-compatible Codable: decodeIfPresent for new outputQuality key with default 1.0 when missing"

requirements-completed: [EXPT-01, EXPT-02, EXPT-03]

# Metrics
duration: 10min
completed: 2026-06-18
---

# Phase 6 Plan 1: Export Control & UX Polish Summary

**OutputFormat.tiff, quality slider, format picker UI, and HDR→JPEG loss warning — full export control pipeline from config model through engine to UI**

## Performance

- **Duration:** 10 min
- **Started:** 2026-06-18T09:09:20Z
- **Completed:** 2026-06-18T09:19:20Z
- **Tasks:** 3
- **Files modified:** 12

## Accomplishments
- OutputFormat enum extended with `.tiff` case (full Codable, UTI resolution, isLossless detection)
- WatermarkConfiguration carries `outputQuality` Float with backward-compatible Codable (defaults to 1.0)
- ImageWriter accepts `destinationUTI` and `quality` parameters; quality merged per Pitfall 5 compliance
- Engine resolves output format from config before ImageWriter and TempFileManager calls
- Export Options DisclosureGroup with format picker (5 options), quality slider (60–100%), and HDR→JPEG warning dialog

## Task Commits

Each task was committed atomically:

1. **Task 1: Model Layer (TDD)** — `5be8ab9` (RED), `cbaeacf` (GREEN)
2. **Task 2: Engine & ImageWriter (TDD)** — `157d984` (RED), `67880fd` (GREEN)
3. **Task 3: Export Options UI** — `266b7f5` (feat)

## Files Created/Modified
- `Packages/WatermarkCore/Sources/WatermarkCore/Models/WatermarkConfiguration.swift` — OutputFormat.tiff, .uti, .isLossless, outputQuality, explicit Codable
- `Packages/WatermarkCore/Sources/WatermarkCore/Input/FormatDetector.swift` — public.tiff support (detection + UTI + file extension)
- `Packages/WatermarkCore/Sources/WatermarkCore/UI/WatermarkConfigurable.swift` — outputFormat, outputQuality, sourceHasHDR, sourceFormatLabel protocol requirements
- `Packages/WatermarkCore/Sources/WatermarkCore/Output/ImageWriter.swift` — destinationUTI + quality parameters, quality in combinedMetadata
- `Packages/WatermarkCore/Sources/WatermarkCore/Engine/WatermarkEngine.swift` — format resolution from config, passes destinationUTI + quality
- `Packages/WatermarkCore/Sources/WatermarkCore/UI/ControlsView.swift` — Export Options DisclosureGroup with format picker, quality slider, HDR warning
- `App/ViewModels/WatermarkViewModel.swift` — outputFormat/outputQuality/sourceHasHDR/sourceFormatLabel conformance + HDR detection
- `ShareExtension/ShareExtensionViewModel.swift` — same protocol conformance + HDR detection
- `Packages/WatermarkCore/Tests/WatermarkCoreTests/OutputFormatTests.swift` — 17 tests for model layer (created)
- `Packages/WatermarkCore/Tests/WatermarkCoreTests/ImageWriterFormatTests.swift` — 9 tests for format resolution (created)
- `Packages/WatermarkCore/Tests/WatermarkCoreTests/FormatDetectorTests.swift` — TIFF detection test added
- `Packages/WatermarkCore/Tests/WatermarkCoreTests/ImageWriterTests.swift` — parameter rename updates

## Decisions Made
- Output format resolution uses nil-coalescing: `config.outputFormat.uti ?? loaded.sourceUTI` — `.preserveSource` returns nil for `.uti`, triggering source UTI fallback
- Quality merged into the same `combinedMetadata` dictionary passed to `CGImageDestinationAddImage` — avoids Pitfall 5 (separate properties dict would overwrite metadata)
- HDR source detection is a format-based heuristic (HEIC UTI check via CGImageSourceGetType) — sufficient for advisory dialog; full gain-map inspection deferred
- Video format override explicitly excluded from this plan — `processVideo` path unchanged per D-04

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered
None

## Next Phase Readiness
- Export control pipeline (format + quality) fully wired from model through engine to UI
- Ready for Plan 06-02 (Before/After Comparison) which shares ControlsView layout
- EXPT-01 (format selection), EXPT-02 (quality control), EXPT-03 (format preservation with HDR) — all satisfied

---
*Phase: 06-export-control-ux-polish*
*Completed: 2026-06-18*
