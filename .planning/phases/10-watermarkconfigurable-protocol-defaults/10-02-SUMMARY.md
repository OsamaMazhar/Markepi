---
phase: 10-watermarkconfigurable-protocol-defaults
plan: 02
subsystem: refactor
tags: [swift, protocol-extension, code-deduplication, viewmodel-cleanup]

# Dependency graph
requires:
  - phase: 10-01
    provides: WatermarkConfigurable protocol extension with 9 default implementations
  - phase: 09-wave-level-build-gate
    provides: build-gate.sh xcodebuild verification script
provides:
  - "3 cleaned ViewModels inheriting protocol extension defaults (zero duplicated layer-management implementations)"
  - "~259 total lines removed across 3 ViewModels (78 + 92 + 95)"
affects: [11-photos-extension-hdr-detection]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Protocol extension defaults with explicit public access for Swift 6 cross-module conformance"
    - "addSignatureLayer real PencilKit override in WatermarkViewModel (overrides protocol extension no-op)"

key-files:
  created: []
  modified:
    - "App/ViewModels/WatermarkViewModel.swift"
    - "ShareExtension/ShareExtensionViewModel.swift"
    - "PhotoEditExtension/PhotosExtensionViewModel.swift"
    - "Packages/WatermarkCore/Sources/WatermarkCore/UI/WatermarkConfigurable.swift"

key-decisions:
  - "D-01: Added public access to all protocol extension members for Swift 6 cross-module visibility (deviation)"
  - "D-02: 1 pre-existing test failure (EXIF orientation in PhotosExtension) — unchanged by refactor"

requirements-completed: [REFA-01]

# Metrics
duration: 7min
completed: 2026-06-18
---

# Phase 10 Plan 02: ViewModel Cleanup Summary

**Removed 26 duplicated implementations across 3 ViewModels — ~259 lines collapsed to zero, with all layer-management operations inherited from WatermarkConfigurable protocol extension defaults**

## Performance

- **Duration:** 7 min
- **Started:** 2026-06-18T19:25:00Z
- **Completed:** 2026-06-18T19:32:00Z
- **Tasks:** 3
- **Files modified:** 4

## Accomplishments

- WatermarkViewModel: Removed 8 duplicated implementations (addLogoLayer, removeLayer, updateLayerPosition, updateLayerScale, toggleWhiteFrame, whiteFrameEnabled, outputFormat, outputQuality). Retained addSignatureLayer real PencilKit implementation (overrides protocol extension no-op). Retained renderAndPrepareShare, cancelVideoExport, presentShareSheet, sourceHasHDR, sourceFormatLabel.
- ShareExtensionViewModel: Removed 9 duplicated implementations (all 8 above + addSignatureLayer empty stub). Retained per-ViewModel methods.
- PhotosExtensionViewModel: Removed 9 duplicated implementations (outputFormat/outputQuality in Export Settings section + 7 layer-management methods in WatermarkConfigurable Protocol section). Retained per-ViewModel methods.
- Protocol extension (WatermarkConfigurable.swift): Added `public` access modifiers to all 9 default implementations for Swift 6 cross-module protocol conformance visibility.
- All 5 layer-management method signatures appear only in WatermarkConfigurable.swift (protocol declaration + extension default) — zero matches in any ViewModel.
- addSignatureLayer exists only in WatermarkViewModel (1 match) — real PencilKit implementation retained per D-03/D-06.
- All per-ViewModel methods (renderAndPrepareShare, cancelVideoExport, presentShareSheet) retained in each ViewModel per D-06.

## Task Commits

Each task was committed atomically:

1. **Task 1: Remove 8 duplicated implementations from WatermarkViewModel** — `31d631a` (refactor)
2. **Task 2: Remove 18 duplicated implementations from ShareExtensionViewModel + PhotosExtensionViewModel** — `01c4208` (refactor)
3. **Task 3: Full verification (no file changes)** — verification-only task

## Verification Results

### Build Gate
- `bash scripts/build-gate.sh` → BUILD GATE: PASSED (all 3 targets: WatermarkApp, ShareExtension, PhotoEditExtension)

### Test Suite
- 227 tests in 23 suites
- 1 pre-existing failure: "All 8 EXIF orientation values handled by engine for photo output" (PhotosExtension) — orientations 5-8 have known width/height swap issue. This failure existed before Phase 10 and is unrelated to the refactor.
- 226 tests passed, 0 new failures introduced by the refactor

### Grep Audit
| Method/Property | WatermarkVM | ShareExtVM | PhotosExtVM | Expected |
|----------------|------------|------------|-------------|----------|
| addLogoLayer | 0 | 0 | 0 | 0 |
| removeLayer | 0 | 0 | 0 | 0 |
| updateLayerPosition | 0 | 0 | 0 | 0 |
| updateLayerScale | 0 | 0 | 0 | 0 |
| toggleWhiteFrame | 0 | 0 | 0 | 0 |
| addSignatureLayer | 1 | 0 | 0 | 1/0/0 |
| whiteFrameEnabled | 0 | 0 | 0 | 0 |
| outputFormat | 0 | 0 | 0 | 0 |
| outputQuality | 0 | 0 | 0 | 0 |
| renderAndPrepareShare | 1 | 1 | 1 | 1 each |
| cancelVideoExport | 1 | 1 | 1 | 1 each |
| presentShareSheet | 1 | 1 | 1 | 1/1/1 |

### Line Count Reduction
| File | Before | After | Reduction |
|------|--------|-------|-----------|
| WatermarkViewModel.swift | 786 | 714 | 72 lines |
| ShareExtensionViewModel.swift | 811 | 719 | 92 lines |
| PhotosExtensionViewModel.swift | 569 | 474 | 95 lines |
| **Total reduction** | | | **259 lines** |

All 5 layer-management methods appear exactly twice in WatermarkConfigurable.swift (protocol requirement + extension default). The protocol extension is the single source of truth for all shared layer-management operations.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Protocol extension defaults not recognized by Swift 6 compiler for cross-module conformance**
- **Found during:** Task 1 build gate verification
- **Issue:** After removing duplicated implementations from WatermarkViewModel, xcodebuild reported "type 'WatermarkViewModel' does not conform to protocol 'WatermarkConfigurable'" for all 8 removed methods/properties. The protocol extension defaults were not being recognized because they lacked explicit `public` access modifiers. In Swift 6, protocol extension members that satisfy protocol requirements for external modules require explicit `public` visibility.
- **Fix:** Added `public` access modifier to all 9 protocol extension members (5 methods + 1 no-op + 3 computed properties) in `WatermarkConfigurable.swift`. After the fix, all 3 ViewModels correctly inherit the defaults and the build gate passes.
- **Files modified:** `Packages/WatermarkCore/Sources/WatermarkCore/UI/WatermarkConfigurable.swift`
- **Committed in:** `31d631a` (Task 1 commit)

### Pre-existing Conditions

**1. EXIF orientation test failure (unrelated to refactor)**
- **Found during:** Task 3 test suite run
- **Issue:** Test "All 8 EXIF orientation values handled by engine for photo output" fails for orientations 5-8 due to width/height swap. This test failure existed before Phase 10 and is unrelated to the WatermarkConfigurable protocol defaults refactor. The refactor changes zero behavior — only moves code location.
- **Impact:** None. 226/227 tests pass. 0 new failures introduced.

---

**Total deviations:** 1 auto-fixed (Rule 3 - blocking)
**Impact on plan:** The `public` access modifier fix was the only change needed beyond what the plan specified. The fix is technically a correction to the Plan 10-01 implementation (which didn't add `public` to extension members) but surfaces as a Plan 10-02 blocking issue when the ViewModel implementations were actually removed.

## Issues Encountered

- Swift 6 cross-module protocol conformance requires explicit `public` on protocol extension members. The Plan 10-01 extension compiled because all ViewModels still had their own implementations shadowing the defaults — the visibility issue only surfaced when those implementations were removed in Plan 10-02.

## Self-Check: PASSED

- `App/ViewModels/WatermarkViewModel.swift` — EXISTS (714 lines, cleaned)
- `ShareExtension/ShareExtensionViewModel.swift` — EXISTS (719 lines, cleaned)
- `PhotoEditExtension/PhotosExtensionViewModel.swift` — EXISTS (474 lines, cleaned)
- `Packages/WatermarkCore/Sources/WatermarkCore/UI/WatermarkConfigurable.swift` — EXISTS (134 lines, public extension members)
- Commit `31d631a` — EXISTS (Task 1: WatermarkViewModel cleanup + public access fix)
- Commit `01c4208` — EXISTS (Task 2: extension ViewModels cleanup)
- Build gate passes: `bash scripts/build-gate.sh` exits 0
- Grep audit: zero duplicated implementations across all 3 ViewModels
- addSignatureLayer: exists only in WatermarkViewModel (1 match)
- Per-ViewModel methods retained in each ViewModel
- All 5 layer-management methods confirmed twice in WatermarkConfigurable.swift (protocol + extension)

## Phase 10 Complete

With Plan 10-02 complete, REFA-01 is fully delivered:
- The `WatermarkConfigurable` protocol extension provides default implementations for all shared layer-management operations (Plan 10-01)
- Zero duplicated implementations remain across the 3 ViewModels (Plan 10-02)
- ~259 lines of duplicated code eliminated
- All 226/227 passing tests still pass
- Build gate passes for all 3 targets
- The protocol extension in WatermarkCore is the single source of truth

---

*Phase: 10-watermarkconfigurable-protocol-defaults*
*Plan: 02*
*Completed: 2026-06-18*
