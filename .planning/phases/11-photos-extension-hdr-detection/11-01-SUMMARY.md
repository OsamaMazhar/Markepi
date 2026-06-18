---
phase: 11-photos-extension-hdr-detection
plan: 01
subsystem: photos-extension
tags: [hdr, cgimagesource, avfoundation, uti, swift, swiftui, photos]

# Dependency graph
requires:
  - phase: 10-watermarkconfigurable-protocol-defaults
    provides: "Refactored PhotosExtensionViewModel with protocol defaults and WatermarkConfigurable conformance"
provides:
  - "PhotosExtensionViewModel populates sourceHasHDR from PHContentEditingInput (HEIC photos → true, HDR videos → true)"
  - "PhotosExtensionViewModel populates sourceFormatLabel from PHContentEditingInput (HEIC/JPEG/PNG/TIFF photos, MOV/MP4/M4V videos)"
  - "HDR→JPEG warning alert now fires in Photos extension (ControlsView already wired)"
  - "Match Source format label shows correctly in Photos extension ControlsView"
affects: [photos-extension, hdr-detection, controls-view]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Eager synchronous source detection in PHContentEditingController.startEditing via CGImageSourceCreateWithURL (photo) and AVAssetTrack.hasMediaCharacteristic(.containsHDRVideo) (video)"
    - "CGImageSource URL-based header read (not Data-based full file read) for memory efficiency with large ProRAW files"
    - "Synchronous AVAsset.tracks(withMediaType:) API for lightweight detection in synchronous startEditing method"

key-files:
  created: []
  modified:
    - "PhotoEditExtension/PhotosExtensionViewModel.swift — Added detectSourceProperties(), detectPhotoProperties(), detectVideoProperties() called from startEditing"
    - "Packages/WatermarkCore/Tests/WatermarkCoreTests/PhotosExtensionTests.swift — Added 6 detection pattern tests (Tests 16–21)"

key-decisions:
  - "Used CGImageSourceCreateWithURL (not Data(contentsOf:)) for photo UTI detection — reads only ~4KB file header, not full pixel data"
  - "Used synchronous AVAsset.tracks(withMediaType:) (deprecated but functional) because startEditing is synchronous"
  - "Kept detection inline in PhotosExtensionViewModel (did not extract to WatermarkCore per D-09 scope boundary)"
  - "Used same UTI heuristic as WatermarkViewModel and ShareExtensionViewModel (public.heic → HDR capable)"

patterns-established:
  - "Eager HDR + format detection in PHContentEditingController flow — detection runs after isLoadingMedia=false, before preview generation"
  - "4-way UTI-to-label mapping for photos: public.heic→HEIC, public.jpeg→JPEG, public.png→PNG, public.tiff→TIFF"
  - "3-way ext-to-label mapping for videos: mov→MOV, mp4→MP4, m4v→M4V"

requirements-completed:
  - PHDR-01

# Metrics
duration: 4m 55s
completed: 2026-06-18
---

# Phase 11 Plan 01: Photos Extension HDR Detection Summary

**PhotosExtensionViewModel now populates sourceHasHDR and sourceFormatLabel from PHContentEditingInput, enabling the HDR→JPEG warning alert and Match Source format label in the Photos extension's ControlsView**

## Performance

- **Duration:** 4m 55s
- **Started:** 2026-06-18T17:50:17Z
- **Completed:** 2026-06-18T17:55:12Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- PhotosExtensionViewModel now detects HDR from HEIC photos via CGImageSourceCreateWithURL UTI heuristic (consistent with WatermarkViewModel and ShareExtensionViewModel)
- PhotosExtensionViewModel now detects HDR from videos via AVAssetTrack.hasMediaCharacteristic(.containsHDRVideo)
- sourceFormatLabel populated for HEIC, JPEG, PNG, TIFF photos and MOV, MP4, M4V videos
- Detection runs eagerly in startEditing after isLoadingMedia=false, before preview generation — ensuring ControlsView has data before user interaction
- The HDR→JPEG warning alert (already wired in ControlsView) now fires correctly when HEIC HDR source is loaded and JPEG output selected

## Task Commits

Each task was committed atomically:

1. **Task 1 (RED): Detection pattern tests** — `49395c3` (test) — 6 tests for CGImageSource URL UTI detection, format label mapping, HDR heuristic, video format mapping, and nil-UTI guard
2. **Task 1 (GREEN): Detection implementation** — `dec1523` (feat) — Added detectSourceProperties(), detectPhotoProperties(), detectVideoProperties() to PhotosExtensionViewModel
3. **Task 2: Verification only** — No file changes (verification confirmed build gate, test suite, and grep assertions all pass)

_REFACTOR phase not needed — implementation was clean on first pass._

## Files Created/Modified
- `PhotoEditExtension/PhotosExtensionViewModel.swift` — Added 76 lines: detectSourceProperties() call in startEditing + 3 private detection methods
- `Packages/WatermarkCore/Tests/WatermarkCoreTests/PhotosExtensionTests.swift` — Added 6 detection pattern tests (Tests 16–21, ~144 lines)

## Decisions Made
- Used CGImageSourceCreateWithURL (not Data(contentsOf:)) for photo UTI detection — reads only ~4KB file header, avoiding 75MB memory cost for large ProRAW files
- Used synchronous AVAsset.tracks(withMediaType:) (deprecated in iOS 16) — appropriate for lightweight detection in synchronous startEditing method; deprecation is advisory, not breaking
- Kept detection inline in PhotosExtensionViewModel — extraction to WatermarkCore deferred per D-09 (bonus, not required)
- Used same UTI heuristic as WatermarkViewModel and ShareExtensionViewModel (public.heic → HDR capable) — preserves consistency across all 3 targets

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed incorrect test expectation for CGImageSourceCreateWithURL on text files**
- **Found during:** Task 1 (RED phase) — Test 20
- **Issue:** Test expected `CGImageSourceCreateWithURL` to return nil for text files, but on this platform it returns a valid CGImageSource (with nil UTI from `CGImageSourceGetType`)
- **Fix:** Changed test to verify `CGImageSourceGetType` returns nil for non-image files (the actual guard condition used in implementation)
- **Files modified:** Packages/WatermarkCore/Tests/WatermarkCoreTests/PhotosExtensionTests.swift
- **Verification:** All 6 new tests pass after fix
- **Committed in:** 49395c3 (Task 1 RED commit, included with other test additions)

---

**Total deviations:** 1 auto-fixed (Rule 1 - Bug)
**Impact on plan:** Minor test correction. The implementation guard (`guard let source = ... let uti = ... else { return }`) handles both nil-source and nil-UTI conditions correctly regardless of platform behavior.

## Issues Encountered
- CGImageSourceCreateWithURL behavior varies by platform for non-image files — handled via nil-UTI guard (not nil-source guard)
- Deprecation warnings for `tracks(withMediaType:)` and `hasMediaCharacteristic` (expected — plan acknowledges these are deprecated but functional for synchronous detection)

## Verification Results

### Layer 1 — Build Gate: PASSED
`bash scripts/build-gate.sh` → BUILD GATE: PASSED (all 3 targets: WatermarkApp, ShareExtension, PhotoEditExtension)

### Layer 2 — Test Suite: PASSED (0 new failures)
233 tests in 23 suites, 14 pre-existing issues (all prior to Phase 11):
- 8 issues: EXIF orientation test (pre-existing, known width/height swap for orientations 5-8)
- 6 issues: SKIP/RED tests for missing test assets (HEIC, video) and UIKit-unavailable platform
- **0 new failures introduced by Phase 11 changes**

### Layer 3 — Grep Audit: ALL ACs PASS
| AC | Assertion | Expected | Actual | Status |
|----|-----------|----------|--------|--------|
| AC-01 | sourceHasHDR = assignments | ≥2 | 2 | ✓ |
| AC-02 | sourceFormatLabel = assignments | ≥2 | 9 | ✓ |
| AC-03 | CGImageSourceCreateWithURL | ≥1 | 3 | ✓ |
| AC-04 | containsHDRVideo | ≥1 | 3 | ✓ |
| AC-05 | "public.heic" | ≥1 | 2 | ✓ |
| AC-06 | Data(contentsOf:) in detection | 0 | 0 | ✓ |
| AC-07 | tracks(withMediaType: | ≥1 | 3 | ✓ |
| AC-08 | isLoadingMedia = false | 1 | 1 | ✓ |
| AC-09 | Detection after isLoadingMedia, before preview | ✓ | ✓ | ✓ |
| AC-10 | extractColorProperties | 0 | 0 | ✓ |
| AC-11 | CGImageSourceCopyAuxiliaryDataInfoAtIndex | 0 | 0 | ✓ |

## Threat Flags

None — no new threat surfaces introduced. All detection APIs are read-only metadata inspections operating on system-provided inputs within the iOS sandbox. The plan's threat model (T-11-01 through T-11-04) was assessed as accept — no mitigations needed.

## Known Stubs

None — all properties (sourceHasHDR, sourceFormatLabel) are now populated from the actual PHContentEditingInput asset. No placeholder values or TODO markers.

## User Setup Required

None — no external service configuration required. All changes are code-only within the existing Xcode project.

## Next Phase Readiness
- Phase 11 complete — all 4 success criteria met
- Photos extension now has full HDR detection parity with Main App and Share Extension
- HDR→JPEG warning and Match Source format label are fully functional in the Photos extension
- Ready for milestone v1.1 closure

---
*Phase: 11-photos-extension-hdr-detection*
*Completed: 2026-06-18*
