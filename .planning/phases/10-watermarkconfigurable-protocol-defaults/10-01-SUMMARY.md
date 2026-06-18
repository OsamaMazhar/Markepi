---
phase: 10-watermarkconfigurable-protocol-defaults
plan: 01
subsystem: refactor
tags: [swift, protocol-extension, code-deduplication, watermark-core]

# Dependency graph
requires:
  - phase: 09-wave-level-build-gate
    provides: build-gate.sh xcodebuild verification script
provides:
  - Protocol extension with 9 default implementations for WatermarkConfigurable (5 layer-management methods + 1 no-op + 3 computed properties)
  - errorMessage and showError protocol requirements for addLogoLayer error surfacing
  - Build gate updated with CODE_SIGNING_ALLOWED=NO for CI compatibility
affects: [10-02-viewmodel-cleanup]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Protocol extension defaults on @MainActor AnyObject-constrained protocol"
    - "Direct self.config mutation in protocol extensions (D-04)"
    - "3-case switch-reconstruct pattern for WatermarkLayer enum mutation (D-05)"
    - "Computed property passthrough defaults for { get set } protocol requirements"

key-files:
  created: []
  modified:
    - "Packages/WatermarkCore/Sources/WatermarkCore/UI/WatermarkConfigurable.swift"
    - "scripts/build-gate.sh"

key-decisions:
  - "D-01: Added errorMessage/showError to protocol for addLogoLayer validation surfacing"
  - "D-02: Included whiteFrameEnabled, outputFormat, outputQuality computed property defaults in extension"
  - "D-03: addSignatureLayer default no-op eliminates extension ViewModel stubs"
  - "D-04: Protocol extension methods mutate self.config directly (AnyObject reference semantics)"
  - "D-05: 3-case switch for layer reconstruction instead of WatermarkLayer with(position:)/with(scale:) helpers"

patterns-established:
  - "Pattern 1: Protocol extension defaults for shared ViewModel behavior — single source of truth for ~186 lines of duplicated code"
  - "Pattern 2: Computed property passthrough defaults — get/set wrappers around config in protocol extension"
  - "Pattern 3: Error surfacing via protocol properties — errorMessage/showError set by default impl, bound by SwiftUI alert"

requirements-completed: [REFA-01]

# Metrics
duration: 5min
completed: 2026-06-18
---

# Phase 10 Plan 01: WatermarkConfigurable Protocol Defaults Summary

**Protocol extension with 9 default implementations (5 method + 1 no-op + 3 computed properties) collapses ~186 lines of duplicated ViewModel code into a single source of truth in WatermarkCore**

## Performance

- **Duration:** 5 min
- **Started:** 2026-06-18T19:20:00Z
- **Completed:** 2026-06-18T19:25:20Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Added `errorMessage: String? { get set }` and `showError: Bool { get set }` to the `WatermarkConfigurable` protocol (D-01)
- Protocol extension provides 9 default implementations: `addLogoLayer`, `addSignatureLayer` (no-op), `removeLayer`, `updateLayerPosition`, `updateLayerScale`, `toggleWhiteFrame`, `whiteFrameEnabled`, `outputFormat`, `outputQuality`
- Build gate passes for all 3 targets (WatermarkApp + ShareExtension + PhotoEditExtension) with protocol extension compiling cleanly in Swift 6
- Fixed build gate script with `CODE_SIGNING_ALLOWED=NO` for CI environments without development team

## Task Commits

Each task was committed atomically:

1. **Task 1: Add error properties to protocol + implement all 8 protocol extension defaults** - `553dff3` (feat)
2. **Task 2: Final build gate verification and extension validation** - `816d993` (fix)

## Files Created/Modified
- `Packages/WatermarkCore/Sources/WatermarkCore/UI/WatermarkConfigurable.swift` - Protocol declaration (47→47 lines with error properties) + protocol extension (lines 49-134, 86 lines of default implementations)
- `scripts/build-gate.sh` - Added `CODE_SIGNING_ALLOWED=NO` for CI compatibility

## Extension Defaults Summary

| # | Default | Type | Lines | Description |
|---|---------|------|-------|-------------|
| 1 | `addLogoLayer(pngData:)` | Method | 14 | PNG validation + layer append. Sets errorMessage/showError on failure |
| 2 | `addSignatureLayer(...)` | Method (no-op) | 3 | Empty body — WatermarkViewModel overrides with real PencilKit impl |
| 3 | `removeLayer(at:)` | Method | 7 | Guard bounds, remove, adjust activeLayerIndex |
| 4 | `updateLayerPosition(at:position:)` | Method | 12 | 3-case switch reconstructing layer with new position |
| 5 | `updateLayerScale(at:scale:)` | Method | 13 | Clamp 0.01–0.90, 3-case switch reconstructing layer with new scale |
| 6 | `toggleWhiteFrame()` | Method | 6 | Toggle config.whiteFrame between nil and WhiteFrameConfig(isEnabled: true) |
| 7 | `whiteFrameEnabled` | Computed property | 3 | Getter-only: `config.whiteFrame?.isEnabled ?? false` |
| 8 | `outputFormat` | Computed property | 4 | Get/set passthrough to `config.outputFormat` |
| 9 | `outputQuality` | Computed property | 4 | Get/set passthrough to `config.outputQuality` |

## Decisions Made

All implementation decisions followed the CONTEXT.md D-01 through D-05 specifications exactly:
- D-01: Error properties added to protocol for `addLogoLayer` validation surfacing
- D-02: Computed property defaults included in extension alongside layer-management methods
- D-03: `addSignatureLayer` default no-op eliminates 2 extension ViewModel stubs
- D-04: Direct mutation of `self.config` and `self.activeLayerIndex` — no `@discardableResult`
- D-05: 3-case switch-reconstruct pattern preserved; no `with(position:)`/`with(scale:)` helpers added to WatermarkLayer

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Build gate failed due to missing code signing configuration**
- **Found during:** Task 2 (build gate verification)
- **Issue:** `scripts/build-gate.sh` exited with error: "Signing for 'WatermarkApp' requires a development team." No development team was configured in the Xcode project.
- **Fix:** Added `CODE_SIGNING_ALLOWED=NO` to the xcodebuild invocation in `scripts/build-gate.sh`. This allows compilation verification to proceed without code signing, which is the build gate's actual purpose.
- **Files modified:** `scripts/build-gate.sh`
- **Verification:** `bash scripts/build-gate.sh` exits 0 and prints "BUILD GATE: PASSED"
- **Committed in:** `816d993` (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (Rule 3 - blocking)
**Impact on plan:** The build gate fix is environment-specific (no development team configured). The protocol extension compiled cleanly on the first attempt — zero code changes were needed after the initial write.

## Issues Encountered
- Pre-existing code signing configuration missing in Xcode project — resolved by adding `CODE_SIGNING_ALLOWED=NO` to build gate. This does not affect code compilation verification.

## User Setup Required
None — no external service configuration required.

## Self-Check: PASSED
- `Packages/WatermarkCore/Sources/WatermarkCore/UI/WatermarkConfigurable.swift` — EXISTS (134 lines)
- `scripts/build-gate.sh` — EXISTS (updated with CODE_SIGNING_ALLOWED=NO)
- Commit `553dff3` — EXISTS (git log confirms)
- Commit `816d993` — EXISTS (git log confirms)
- Build gate passes: `bash scripts/build-gate.sh` exits 0
- All 14 acceptance criteria from Task 1 verified
- All 4 validation checks from Task 2 verified

## Next Phase Readiness
- Protocol extension is ready for ViewModel cleanup in Plan 10-02
- All 3 conforming ViewModels (WatermarkViewModel, ShareExtensionViewModel, PhotosExtensionViewModel) have their own implementations that currently shadow the defaults — no behavioral change yet
- Plan 10-02 will remove the ~186 lines of duplicated implementations and let all ViewModels inherit from the protocol extension

---
*Phase: 10-watermarkconfigurable-protocol-defaults*
*Completed: 2026-06-18*
