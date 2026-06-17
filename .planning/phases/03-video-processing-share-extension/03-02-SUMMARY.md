---
phase: 03-video-processing-share-extension
plan: 02
subsystem: video-processing
tags: [avfoundation, calayer, avvideocomposition, hdr, hevc, core-animation]

# Dependency graph
requires:
  - phase: 01-core-engine-photo-pipeline
    provides: [WatermarkConfiguration, WatermarkLayer, PositionCalculator, CIContextProvider, TempFileManager, PipelineError, ProcessingResult]
  - phase: 01-core-engine-photo-pipeline
    provides: [TextWatermarkRenderer, ImageWatermarkRenderer, WhiteFrameRenderer]
provides:
  - "AVFoundation video watermarking pipeline: load→compose→CALayer overlay→export→validate"
  - "VideoProcessor.process(sourceURL:config:) → (outputURL, ExportValidationResult)"
  - "VideoLayerBuilder.buildLayers(config:videoSize:) → (parentLayer, videoLayer) for AVVideoCompositionCoreAnimationTool"
  - "VideoFrameExtractor.extract(from:at:maxPixelSize:) → CGImage for static video previews"
  - "ExportValidator.validate(outputURL:sourceAsset:wasHDR:) → ExportValidationResult"
  - "WatermarkEngine.processVideo(sourceURL:config:) → ProcessingResult"
  - "PipelineError video-specific cases (videoTrackNotFound, videoExportFailed, etc.)"
  - "ProcessingResult.videoValidation: ExportValidationResult?"
  - "WatermarkEngine.MediaType enum + mediaType(for:) static utility"
affects: [03-03-video-in-share-extension, 04-photos-edit-extension]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Static struct + static method pattern for processing utilities (VideoProcessor, VideoLayerBuilder, VideoFrameExtractor, ExportValidator)"
    - "AVVideoCompositionCoreAnimationTool with CALayer hierarchy for watermark overlays (D-01)"
    - "CIImage → CGImage rasterization via CIContextProvider.shared for CALayer.contents"
    - "CALayer y-axis flip: CALayer top-left origin ← CIImage bottom-left origin"
    - "HDR detection via CMFormatDescription transfer function inspection"
    - "Audio passthrough via individual track insertion into AVMutableComposition (D-11)"
    - "Source format matching via determineCompatibleFileTypes + AVFileType(sourceUTI) (D-04)"

key-files:
  created:
    - "Packages/WatermarkCore/Sources/WatermarkCore/Processing/VideoProcessor.swift - AVFoundation pipeline orchestrator (298 lines)"
    - "Packages/WatermarkCore/Sources/WatermarkCore/Processing/VideoLayerBuilder.swift - CALayer hierarchy builder from WatermarkConfiguration (169 lines)"
    - "Packages/WatermarkCore/Sources/WatermarkCore/Processing/VideoFrameExtractor.swift - AVAssetImageGenerator static frame extraction (75 lines)"
    - "Packages/WatermarkCore/Sources/WatermarkCore/Processing/ExportValidator.swift - Post-export HDR/audio validation (91 lines)"
  modified:
    - "Packages/WatermarkCore/Sources/WatermarkCore/Engine/WatermarkEngine.swift - Added processVideo(), MediaType, mediaType(for:)"
    - "Packages/WatermarkCore/Sources/WatermarkCore/Engine/PipelineError.swift - Added 9 video-specific error cases"
    - "Packages/WatermarkCore/Sources/WatermarkCore/Models/ProcessingResult.swift - Added videoValidation field"

key-decisions:
  - "HDR detection via CMFormatDescription transfer function inspection (HLG/2084) instead of AVAssetTrack.hasMediaCharacteristic API (unavailable in Swift 6 async load)"
  - "CALayer.colorspace not set on iOS (unavailable) — HDR fidelity maintained through AVVideoComposition color properties and RGBAh pixel format"
  - "determineCompatibleFileTypes bridged via withCheckedContinuation (completion-handler API, no native async)"
  - "ExportValidator implemented inline in Task 1 for compilation (complete implementation, not skeleton) — Task 2 added VideoFrameExtractor"
  - "Video-specific PipelineError cases added in Task 1 (Rule 3 — blocking compilation) rather than deferred to Task 3"

patterns-established:
  - "Video processing: public struct with static process() method following ImageLoader/FormatDetector precedent"
  - "CALayer building: PositionCalculator reused for coordinate math, CIImage→CGImage via CIContextProvider.shared, y-axis flip for CALayer coordinates"
  - "Export validation: read-only AVAsset metadata inspection, structured result with warnings array"

requirements-completed: [QUAL-04]

# Metrics
duration: 8min
completed: 2026-06-17
---

# Phase 3 Plan 2: Video Watermarking Engine Summary

**AVFoundation CALayer overlay pipeline: VideoProcessor loads, composes, watermarks via AVVideoCompositionCoreAnimationTool, exports with HDR preservation and audio passthrough, validates post-export quality**

## Performance

- **Duration:** 8 min
- **Started:** 2026-06-17T20:00:37Z
- **Completed:** 2026-06-17T20:08:33Z
- **Tasks:** 3/3
- **Files created:** 4 / modified: 3

## Accomplishments

- Full AVFoundation video watermarking pipeline: load AVAsset → build AVMutableComposition with video + all audio tracks → CALayer overlay via AVVideoCompositionCoreAnimationTool → export with source format matching → post-export HDR/audio validation
- CALayer hierarchy mirroring all photo watermark layer types: text, image/logo, white frame with all 9 positions via shared PositionCalculator
- HDR preservation: detection via format description transfer function inspection, AVVideoComposition color properties (BT.2020 primaries, HLG/PQ transfer), RGBAh pixel format
- Audio passthrough: all source audio tracks inserted individually into composition, no mixdown (D-11)
- Source format matching via determineCompatibleFileTypes + AVFileType compatibility check (D-04)
- WatermarkEngine.processVideo() entry point with ProcessingResult.videoValidation surfacing HDR/audio warnings to callers
- MediaType detection utility for photo/video branching in future extension code
- 9 video-specific PipelineError cases with human-readable error descriptions

## Task Commits

Each task was committed atomically:

1. **Task 1: VideoProcessor + VideoLayerBuilder** - `5cd197c` (feat)
2. **Task 2: VideoFrameExtractor + ExportValidator** - `22970ad` (feat)
3. **Task 3: Wire into WatermarkEngine + PipelineError + ProcessingResult** - `1c117d4` (feat)

## Files Created/Modified

- `Packages/WatermarkCore/Sources/WatermarkCore/Processing/VideoProcessor.swift` — AVFoundation pipeline orchestrator (load→compose→CALayer overlay→export→validate)
- `Packages/WatermarkCore/Sources/WatermarkCore/Processing/VideoLayerBuilder.swift` — CALayer hierarchy builder: text, image, white frame layers with PositionCalculator coordinate math
- `Packages/WatermarkCore/Sources/WatermarkCore/Processing/VideoFrameExtractor.swift` — AVAssetImageGenerator async frame extraction with orientation correction (D-03)
- `Packages/WatermarkCore/Sources/WatermarkCore/Processing/ExportValidator.swift` — Post-export HDR metadata + audio track count validation (D-12)
- `Packages/WatermarkCore/Sources/WatermarkCore/Engine/WatermarkEngine.swift` — Added `processVideo()`, `MediaType` enum, `mediaType(for:)` utility
- `Packages/WatermarkCore/Sources/WatermarkCore/Engine/PipelineError.swift` — Added 9 video-specific error cases with Equatable conformance
- `Packages/WatermarkCore/Sources/WatermarkCore/Models/ProcessingResult.swift` — Added `videoValidation: ExportValidator.ExportValidationResult?` field

## Decisions Made

- HDR detection via `CMFormatDescriptionGetExtensions` transfer function key inspection (`HLG`/`2084` substrings) instead of `AVAssetTrack.hasMediaCharacteristic(.containsHDRVideo)` which had API compatibility issues in Swift 6 async loading
- `determineCompatibleFileTypes` bridged from completion handler to async via `withCheckedContinuation` (no native async API)
- CALayer HDR color space not set on iOS (`colorspace` property unavailable) — fidelity maintained through AVVideoComposition color properties + `.RGBAh` pixel format
- `ExportValidator` implemented as complete module in Task 1 rather than skeleton — needed for VideoProcessor compilation (Task 1 depends on it)
- Video-specific `PipelineError` cases added in Task 1 (Rule 3 auto-fix for blocking compilation) rather than deferred to Task 3

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Added PipelineError video cases early (Task 1 instead of Task 3)**
- **Found during:** Task 1 (VideoProcessor compilation)
- **Issue:** VideoProcessor references `PipelineError.videoTrackNotFound` etc. but these error cases were scheduled for Task 3. Build blocked.
- **Fix:** Added all 9 video-specific error cases to `PipelineError` enum immediately, including custom `Equatable` conformance for `videoExportFailed(Error?)` (Error? not Equatable)
- **Files modified:** `Packages/WatermarkCore/Sources/WatermarkCore/Engine/PipelineError.swift`
- **Committed in:** `5cd197c` (Task 1 commit)

**2. [Rule 3 - Blocking] Created ExportValidator in Task 1 instead of Task 2 for compilation**
- **Found during:** Task 1 (VideoProcessor step 7 calls ExportValidator.validate())
- **Issue:** ExportValidator referenced in VideoProcessor but scheduled for Task 2. Build blocked.
- **Fix:** Implemented full ExportValidator module (struct, ExportValidationResult, validate() method) in Task 1. Task 2 added VideoFrameExtractor and verified ExportValidator.
- **Files modified:** `Packages/WatermarkCore/Sources/WatermarkCore/Processing/ExportValidator.swift`
- **Committed in:** `5cd197c` (Task 1 commit, as complete implementation — not skeleton)

**3. [Rule 3 - Blocking] Fixed AVFoundation API incompatibilities**
- **Found during:** Task 1 (initial build)
- **Issue:** Multiple API mismatches: (a) `AVAssetTrack.load(.hasMediaCharacteristic, with:)` not available in Swift 6, (b) `AVAssetExportSession.determineCompatibleFileTypes()` is completion-handler based, not async, (c) `CALayer.colorspace` unavailable on iOS
- **Fix:** (a) HDR detection via `CMFormatDescriptionGetExtensions` transfer function inspection, (b) bridged `determineCompatibleFileTypes` with `withCheckedContinuation`, (c) removed CALayer.colorspace on iOS (commented with rationale)
- **Files modified:** `Packages/WatermarkCore/Sources/WatermarkCore/Processing/VideoProcessor.swift`
- **Committed in:** `5cd197c`

---

**Total deviations:** 3 auto-fixed (all Rule 3 blocking)
**Impact on plan:** All auto-fixes were necessary for compilation and API correctness. No architectural changes. Task ordering was adjusted (errors + validator created earlier) but final deliverables match plan.

## Issues Encountered

- `AVAssetTrack.hasMediaCharacteristic(.containsHDRVideo)` async API unavailable in Swift 6 — worked around with format description transfer function inspection
- `AVAssetExportSession.determineCompatibleFileTypes()` uses completion handler — bridged to async with `withCheckedContinuation`
- `CALayer.colorspace` unavailable on iOS — documented rationale for HDR fidelity via alternative mechanisms

## Next Phase Readiness

- Video watermarking engine is ready for Plan 03-03 (Video in Share Extension): VideoProcessor can be called from any context, VideoFrameExtractor provides static preview frames, ExportValidator surfaces quality warnings
- No blockers for Plan 03-01 integration — WatermarkEngine.shared.processVideo() is a clean actor-isolated entry point
- Test infrastructure is in place (all 103 existing tests pass, no regressions)

---

*Phase: 03-video-processing-share-extension*
*Completed: 2026-06-17*
