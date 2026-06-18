---
phase: 07-additional-inputs-system-integration-v2
plan: 02
subsystem: media-processing
tags: [live-photo, PHLivePhotoEditingContext, PhotosPicker, WatermarkEngine, SwiftUI]

# Dependency graph
requires:
  - phase: 07-01
    provides: "Signature watermarks, PKDrawing integration, multi-layer rendering"
provides:
  - "LivePhotoProcessor — two-phase Live Photo watermarking via existing engine pipeline"
  - "PipelineError.livePhotoUnsupported — typed error for unsupported Live Photo formats"
  - "WatermarkEngine.MediaType.livePhoto + processLivePhoto() — Live Photo processing entry point"
  - "detectLivePhotoPairs() — PhotosPickerItem pairing by base identifier"
  - "ProcessingResult.livePhotoVideoURL — Live Photo pair output data"
  - "PhotoItem.videoSourceURL + mediaType — Live Photo-aware model"
  - "renderAndShareLivePhoto() — fallback to still-only watermarking on failure"
affects: [photo-edit-extension]

# Tech tracking
tech-stack:
  added: [Photos (framework import for LivePhotoProcessor)]
  patterns:
    - "Two-phase Live Photo processing: watermark still via process() + video via processVideo()"
    - "PhotosPickerItem.itemIdentifier suffix parsing for Live Photo pair detection"
    - "Graceful fallback pattern: processLivePhoto → still-only watermarking with user alert"

key-files:
  created:
    - "Packages/WatermarkCore/Sources/WatermarkCore/Processing/LivePhotoProcessor.swift"
    - "Packages/WatermarkCore/Tests/WatermarkCoreTests/LivePhotoProcessorTests.swift"
  modified:
    - "Packages/WatermarkCore/Sources/WatermarkCore/Engine/PipelineError.swift"
    - "Packages/WatermarkCore/Sources/WatermarkCore/Engine/WatermarkEngine.swift"
    - "Packages/WatermarkCore/Sources/WatermarkCore/Models/ProcessingResult.swift"
    - "App/Models/PhotoItem.swift"
    - "App/ViewModels/WatermarkViewModel.swift"

key-decisions:
  - "Two-phase approach (process + processVideo) over PHLivePhotoEditingContext.frameProcessor: PhotosPicker returns raw URLs, not PHContentEditingInput. frameProcessor will be used in Photo Edit Extension follow-up."
  - "LivePhotoProcessor uses static method pattern matching VideoProcessor for consistency"
  - "Fallback to still-only watermarking on Live Photo processing failure with user alert (Pitfall 2 mitigation)"

patterns-established:
  - "PhotosPickerItem.itemIdentifier parsing: strip /public.* suffix to extract shared base ID for Live Photo pair detection"
  - "Graceful degradation: Live Photo failure → still-only watermark + user alert (not silent failure)"

requirements-completed:
  - LIVE-01
  - LIVE-02

# Metrics
duration: 2min
completed: 2026-06-18
---

# Phase 07 Plan 02: Live Photo Processing Summary

**Live Photo watermarking via two-phase engine pipeline with PhotosPicker pair detection, graceful fallback, and typed error handling**

## Performance

- **Duration:** 2 min
- **Started:** 2026-06-18T11:30:35Z
- **Completed:** 2026-06-18T11:32:24Z
- **Tasks:** 2
- **Files modified:** 7 total (2 created, 5 modified)
- **Changes:** +512 / -9 lines

## Accomplishments
- LivePhotoProcessor.swift wraps existing photo + video pipelines into coordinated Live Photo pair processing
- PipelineError.livePhotoUnsupported with generic error message (mitigates T-07-05 information disclosure)
- detectLivePhotoPairs() groups PhotosPickerItems by shared base identifier, creating single PhotoItem per pair
- renderAndShareLivePhoto() with Pitfall 2 fallback: on failure, watermarks only the still image and alerts user
- 10 unit tests covering error handling, ProcessingResult extension, MediaType, and pipeline smoke tests

## Task Commits

Each task was committed atomically:

1. **Task 1: LivePhotoProcessor + PipelineError + WatermarkEngine extension** - `cc6a8ce` (feat)
2. **Task 2: ViewModel Live Photo pairing detection + handleSelection extension + UI flow** - `9f9ebe8` (feat)

## Files Created/Modified
- `Packages/WatermarkCore/Sources/WatermarkCore/Processing/LivePhotoProcessor.swift` — Two-phase Live Photo processing struct with static process() method
- `Packages/WatermarkCore/Tests/WatermarkCoreTests/LivePhotoProcessorTests.swift` — 10 unit tests for error handling, result types, MediaType, and E2E
- `Packages/WatermarkCore/Sources/WatermarkCore/Engine/PipelineError.swift` — Added livePhotoUnsupported case with error description and _isEqual entry
- `Packages/WatermarkCore/Sources/WatermarkCore/Engine/WatermarkEngine.swift` — Added MediaType.livePhoto, processLivePhoto() method, @available annotation
- `Packages/WatermarkCore/Sources/WatermarkCore/Models/ProcessingResult.swift` — Added livePhotoVideoURL: URL? field for Live Photo pair data
- `App/Models/PhotoItem.swift` — Added videoSourceURL: URL? and mediaType: WatermarkEngine.MediaType properties
- `App/ViewModels/WatermarkViewModel.swift` — Added detectLivePhotoPairs(), updated handleSelection(), renderAndShareLivePhoto(), loadSourceForComparison()

## Decisions Made
- **Two-phase approach over PHLivePhotoEditingContext:** PhotosPicker returns raw URLs, not PHContentEditingInput. The frameProcessor API will be used in the Photo Edit Extension follow-up. For the main app flow, watermarking each component individually via the existing pipelines and returning a paired result is correct and pragmatic.
- **LivePhotoProcessor mirrors VideoProcessor's static method pattern** for consistency across the processing module.
- **Graceful fallback on failure** (Pitfall 2): if processLivePhoto fails, the still image is watermarked alone and the user sees an alert explaining the animation couldn't be preserved.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] Added @available annotation to processLivePhoto()**
- **Found during:** Task 2 build verification
- **Issue:** WatermarkEngine.processLivePhoto() calls LivePhotoProcessor.process() which is annotated with @available(iOS 18, macOS 15, *). Without the matching annotation on the caller, compilation would fail.
- **Fix:** Added @available(iOS 18, macOS 15, *) to processLivePhoto() method signature
- **Files modified:** Packages/WatermarkCore/Sources/WatermarkCore/Engine/WatermarkEngine.swift
- **Committed in:** 9f9ebe8 (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (1 missing critical)
**Impact on plan:** Single annotation gap — necessary for compilation correctness. No scope creep.

## Issues Encountered
- Pre-existing test failures in PhotosExtensionTests (orientation normalization, 14 issues) — out of scope, not caused by plan changes

## Threat Flags

None — all threat model mitigations (T-07-04, T-07-05, T-07-06) are implemented:
- T-07-04 (DoS): Fallback to still-only watermarking on Live Photo processing failure with user alert
- T-07-05 (Info Disclosure): PipelineError.livePhotoUnsupported returns generic message
- T-07-06 (Tampering): detectLivePhotoPairs uses guard clauses; malformed identifiers result in individual item treatment

## User Setup Required

None — no external service configuration required.

## Next Plan Readiness
Ready for Plan 07-03. Live Photo processing is complete — both still and video components are watermarked through the existing engine pipeline, with Live Photo pairing detected automatically in the PhotosPicker import flow.

---
*Phase: 07-additional-inputs-system-integration-v2*
*Completed: 2026-06-18*

## Self-Check: PASSED
- All 7 files verified on disk
- Both commits (cc6a8ce, 9f9ebe8) verified in git log
- No modifications to STATE.md or ROADMAP.md
- All 10 LivePhotoProcessorTests pass
- WatermarkCore package builds successfully
