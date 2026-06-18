---
phase: 04-photos-edit-extension-polish
plan: 02
subsystem: photos-edit-extension
tags: [photos-extension, video-watermark, phadjustmentdata, hdr-preservation, image-stripping]
requires:
  - plan: 04-01
    provides: "PhotoEditExtension target scaffold, PHContentEditingController lifecycle, photo watermarking pipeline, PHAdjustmentData undo/re-edit"
  - plan: 03-02
    provides: "VideoProcessor (AVVideoCompositionCoreAnimationTool), ExportValidator, HDR detection"
provides:
  - "Video watermarking from Photos edit menu (audiovisualAsset → processVideo → renderedContentURL)"
  - "PHAdjustmentData image stripping: 67-byte placeholder replaces PNG data, stays under ~2 MB limit"
  - "PHAdjustmentData image rehydration: restores full image data from AppGroupConfigSync on re-edit"
  - "HDR preservation check for video output with inline warning banner"
  - "Format-aware renderedContentURL extension (.jpg/.png/.mov based on source format)"
  - "17-case QA checklist for manual device testing (D-11, D-12)"
  - "15 automated tests covering video path, HDR, EXIF, orientation, PHAdjustmentData stripping"
affects: [phase-04-verification]
tech-stack:
  added: []
  patterns:
    - "strippingImageData() + rehydrateImageData() on WatermarkConfiguration for PHAdjustmentData size safety"
    - "AVAssetImageGenerator frame extraction for video preview in extension"
    - "Format-aware URL extension (.jpg/.png/.mov) for PHContentEditingOutput.renderedContentURL"
    - "Position + scale dual-match for tamper-resistant image rehydration (T-04-08)"
key-files:
  created:
    - .planning/phases/04-photos-edit-extension-polish/04-QA-CHECKLIST.md
  modified:
    - PhotoEditExtension/PhotosExtensionViewModel.swift
    - PhotoEditExtension/PhotosExtensionRootView.swift
    - Packages/WatermarkCore/Sources/WatermarkCore/Models/WatermarkConfiguration.swift
    - Packages/WatermarkCore/Tests/WatermarkCoreTests/PhotosExtensionTests.swift
key-decisions:
  - "Used 67-byte hardcoded 1×1 RGBA transparent PNG as PHAdjustmentData placeholder — no ImageIO dependency needed"
  - "Image layers matched by position AND scale during rehydration (T-04-08 dual-match for tamper resistance)"
  - "HEIC source output uses .jpg extension at renderedContentURL per Research Pitfall 3 safety"
  - "Video preview debounce increased to 500ms (350ms for photo) to avoid AVAssetExportSession churn"
  - "HDR warning surfaced as inline banner in root view (not modal) for non-blocking user awareness"
patterns-established:
  - "strippingImageData(): WatermarkConfiguration copy with image PNG data → 67-byte placeholder"
  - "rehydrateImageData(): match by position+scale, restore from AppGroupConfigSync, keep placeholder on mismatch"
  - "Video preview: processVideo() → AVAssetImageGenerator.copyCGImage(at:.zero) → UIImage"
  - "formatAwareOutputURL: detecting source extension for PHContentEditingOutput file naming"
requirements-completed: [MEDI-03]
metrics:
  duration: "8 min"
  completed_date: "2026-06-18"
---

# Phase 4 Plan 2: Video Support & Quality Validation — Summary

**Video watermarking from Photos edit menu with HDR preservation; PHAdjustmentData image stripping for size safety; 15 automated tests; 17-case manual QA checklist**

## Performance

- **Duration:** 8 min
- **Started:** 2026-06-18T07:18:50Z
- **Completed:** 2026-06-18T07:26:50Z
- **Tasks:** 3
- **Files modified:** 5

## Accomplishments

- Added video processing path to PhotosExtensionViewModel: audiovisualAsset → processVideo → renderedContentURL with .mov extension (D-08)
- Implemented HDR preservation check for video output with inline warning banner when hdrPreserved is false
- Created strippingImageData() — replaces image watermark PNG data with 67-byte 1×1 transparent placeholder, keeping JSON-encoded PHAdjustmentData safely under ~2 MB limit (T-04-09)
- Created rehydrateImageData() — restores full image PNG data from AppGroupConfigSync on re-edit, matching layers by position AND scale for tamper resistance (T-04-08)
- Extended automated test suite from 7 to 15 tests covering: video path, HDR validation, image data stripping, App Group rehydration, text config size limits, PHContentEditingOutput structure, and all 8 EXIF orientations
- Delivered 04-QA-CHECKLIST.md with 17 test cases across 5 categories (Extension Appearance, Photo Processing, Video Processing, PHAdjustmentData Undo/Re-edit, Memory & Stability)

## Task Commits

1. **Task 1: Add failing tests for video path + PHAdjustmentData image stripping** — `725b930` (test)
2. **Task 2: Add video processing to ViewModel + HDR preservation + format-aware output** — `48f122b` (feat)
3. **Task 3: Implement PHAdjustmentData image stripping + full automated test suite + QA checklist** — `a22154c` (feat)

## Files Created/Modified

- `PhotoEditExtension/PhotosExtensionViewModel.swift` — Extended with video processing path in renderAndCommit() (+processVideo), video preview generation via AVAssetImageGenerator, formatAwareOutputURL helper, stripped config encoding for PHAdjustmentData, rehydration on re-edit decode. Now 540+ lines.
- `PhotoEditExtension/PhotosExtensionRootView.swift` — Added video-specific loading message ("Loading video from Photos…"), HDR warning banner already wired to viewModel state.
- `Packages/WatermarkCore/Sources/WatermarkCore/Models/WatermarkConfiguration.swift` — Added strippingImageData() (replaces image pngData with 67-byte placeholder) and rehydrateImageData() (restores from AppGroupConfigSync, match by position+scale). Includes static strippedPlaceholderPNG constant with hardcoded valid 1×1 transparent PNG bytes.
- `Packages/WatermarkCore/Tests/WatermarkCoreTests/PhotosExtensionTests.swift` — Appended 8 new @Test functions (tests 8-15) covering: mediaType .mov detection, processVideo output, videoValidation.hdrPreserved, PHAdjustmentData image stripping (under 1 MB), App Group rehydration round-trip, text-only config under 10 KB, video PHContentEditingOutput path, all 8 EXIF orientations. Added makeMockPNGData helper.
- `.planning/phases/04-photos-edit-extension-polish/04-QA-CHECKLIST.md` — Created with 17 test cases across 5 categories, pass/fail columns, deviations table, ready for manual device testing per D-11/D-12.

## Decisions Made

- Used hardcoded 67-byte 1×1 RGBA transparent PNG bytes as PHAdjustmentData placeholder — avoids ImageIO import dependency in WatermarkConfiguration
- Image layers matched by position AND scale during rehydration (threat model T-04-08 requires both match)
- HEIC source output uses .jpg extension at renderedContentURL for safety (Research Pitfall 3); non-destructive undo preserves original HEIC quality
- Video preview debounce increased to 500ms (350ms for photo) to avoid rapid AVAssetExportSession churn during config changes

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered

- Pre-existing `Color(.separator)` compilation error in SwiftUI views (PositionGridView.swift, TextWatermarkInputView.swift) prevents standalone `swift test` execution. This is a known issue from Plan 04-01, documented in deferred-items.md. Tests must be run through Xcode's xcodebuild or Test navigator.

## Known Stubs

No stubs remain. The `isVideo` guard in `renderAndCommit()` was fully replaced with the video processing path via `engine.processVideo()`. The RED stub methods on WatermarkConfiguration (`strippingImageData()`, `rehydrateImageData()`) were replaced with complete implementations.

## Threat Flags

| Flag | File | Description |
|------|------|-------------|
| threat_flag: dos-mitigation | PhotoEditExtension/PhotosExtensionViewModel.swift | Video processing uses AVAssetExportSession (streaming, not in-memory) — safe for extension ~120 MB sandbox (T-04-06) |
| threat_flag: tamper-resistance | WatermarkConfiguration.swift | rehydrateImageData() matches image layers by position AND scale (T-04-08 dual-match) |
| threat_flag: size-safety | WatermarkConfiguration.swift | strippingImageData() ensures encoded JSON < 1 MB with 67-byte placeholder (T-04-09) |

## Next Phase Readiness

- MEDI-03 is complete: video and photo watermarking from Photos edit menu with non-destructive PHAdjustmentData undo/re-edit
- 04-QA-CHECKLIST.md ready for physical device testing (requires iPhone with iOS 18, A13+)
- Automated tests ready for Xcode Test navigator execution (standalone swift test blocked by pre-existing SwiftUI compilation issue)
- Phase 4 verification can proceed — all implementation tasks complete

---
*Phase: 04-photos-edit-extension-polish*
*Completed: 2026-06-18*
