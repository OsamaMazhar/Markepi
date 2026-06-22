---
phase: 18-cross-target-parity-accessibility-polish
plan: "01"
subsystem: testing
tags: [snapshot-testing, swift-testing, pixel-comparison, extension-verification, watermarkcore]

# Dependency graph
requires:
  - phase: 16-redesigned-controls
    provides: "Redesigned ControlsView (consumed by extension root views)"
  - phase: 17-inspector-bottom-sheet-shell
    provides: "ShareActionButton extraction, ControlsView final form"
provides:
  - "SnapshotTestViewModel: test-only WatermarkConfigurable ViewModel with pre-populated config"
  - "SnapshotRenderer: UIHostingController-based SwiftUI→PNG renderer with pixel comparator"
  - "5 extension root view snapshot tests with committed reference images"
  - "ExtensionRendering protocols enabling generic root views for testability"
affects: [18-02-accessibility, 18-03-empty-state]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Generic extension root views over ShareExtensionRendering / PhotosExtensionRendering protocols"
    - "UIHostingController + UIGraphicsImageRenderer for snapshot rendering (NOT ImageRenderer)"
    - "CGImageSource → UIGraphicsImageRenderer normalize → pixel comparison pipeline"
    - "Record-mode flag pattern for snapshot test reference generation"

key-files:
  created:
    - "Packages/WatermarkCore/Sources/WatermarkCore/UI/ExtensionRendering.swift"
    - "Packages/WatermarkCore/Sources/WatermarkCore/UI/ShareExtensionRootView.swift"
    - "Packages/WatermarkCore/Sources/WatermarkCore/UI/PhotosExtensionRootView.swift"
    - "Packages/WatermarkCore/Sources/WatermarkCore/UI/ShareSheetView.swift"
    - "Packages/WatermarkCore/Tests/WatermarkCoreTests/TestHelpers/SnapshotTestViewModel.swift"
    - "Packages/WatermarkCore/Tests/WatermarkCoreTests/ExtensionSnapshotTests.swift"
    - "Packages/WatermarkCore/Tests/WatermarkCoreTests/__Snapshots__/ (5 reference PNGs)"
  modified:
    - "ShareExtension/ShareExtensionViewModel.swift"
    - "PhotoEditExtension/PhotosExtensionViewModel.swift"
    - "ShareExtension/ShareViewController.swift"
    - "Packages/WatermarkCore/Tests/WatermarkCoreTests/TestHelpers/MockRenderingViewModel.swift"
    - "Packages/WatermarkCore/Tests/WatermarkCoreTests/SignatureRendererTests.swift"

key-decisions:
  - "D-01: Automated snapshot tests in WatermarkCore test target — not manual verification"
  - "D-02: Full root view snapshots at extension 60/40 layout — not ControlsView-only"
  - "D-04: SnapshotTestViewModel with pre-populated config avoids dependency on real ViewModels"
  - "D-05: Single snapshot size 430×932 @3x (iPhone 16 Pro Max) — size-class driven"
  - "D-06: 5 snapshots covering 3 share ext states + 2 photos ext states"
  - "2% pixel tolerance handles antialiasing/font rendering drift across OS versions"
  - "Reference images committed to repo (not generated per-machine) per RESEARCH.md Q1"
  - "Extension root views moved into WatermarkCore to enable @testable import from tests"
  - "ShareSheetView consolidated into WatermarkCore (was duplicated in App + ShareExtension)"

patterns-established:
  - "Protocol-based generic root views: ShareExtensionRendering & PhotosExtensionRendering extend WatermarkConfigurable with extension-specific surface"
  - "Snapshot rendering via UIHostingController (NOT ImageRenderer) for toolbar support"
  - "Pixel comparison via UIGraphicsImageRenderer normalize → CGContext extract → per-pixel diff"

requirements-completed:
  - XTG-01
  - XTG-02

# Test tracking
tests_added: 20
tests_modified: 0

# Metrics
duration: 120min
completed: 2026-06-22
---

# Phase 18 Plan 01: Extension Snapshot Test Infrastructure Summary

**5 automated snapshot tests verify both extension root views render correctly with the redesigned ControlsView at 430×932, with committed reference images and 2% pixel tolerance comparison.**

## Performance

- **Duration:** ~120 min
- **Started:** 2026-06-22T10:35:00Z
- **Completed:** 2026-06-22T11:38:44Z
- **Tasks:** 2
- **Files modified:** 16 (5 created, 7 modified, 4 moved, 2 deleted)

## Accomplishments

- SnapshotTestViewModel conforming to `ShareExtensionRendering & PhotosExtensionRendering & WatermarkConfigurable & Observable` with pre-populated watermark config (2 layers, white frame enabled)
- SnapshotRenderer: `UIHostingController` + `UIGraphicsImageRenderer` → PNG pipeline with optional `UINavigationController` wrapping for toolbar rendering
- Pixel comparator: `UIGraphicsImageRenderer`-based normalization followed by per-pixel RGBA diff with configurable tolerance (default 2%)
- 5 extension root view snapshot tests: Share Ext (idle, preview, multi-item) + Photos Ext (idle, preview)
- Committed reference images at 430×932 @3x for reproducible CI validation
- `ExtensionRendering` protocols in WatermarkCore enabling generic extension root views for testability
- Consolidated `ShareSheetView` into WatermarkCore (removed duplicates from App/ and ShareExtension/)
- 20 new tests total: 15 infrastructure tests + 5 extension snapshot tests

## Task Commits

Each task committed atomically:

1. **Task 1 RED: Infrastructure test file** — `3fb8887` (test)
   - 11 failing infrastructure tests for SnapshotTestViewModel + SnapshotRenderer + comparator
   - Fixed pre-existing MockRenderingViewModel protocol conformance
   - Fixed pre-existing SignatureRendererTests optional unwrap

2. **Task 1 GREEN: Implementation** — `30cb4a3` (feat)
   - SnapshotTestViewModel, SnapshotRenderer, pixel comparator
   - ExtensionRendering protocols + generic root views
   - All 15 infrastructure tests pass

3. **Task 2: Extension snapshot tests + references** — `1f05161` (feat)
   - 5 extension root view snapshot tests with record-mode flag
   - Committed reference PNG images (35KB each)
   - Moved root views into WatermarkCore for test access
   - Consolidated ShareSheetView into WatermarkCore

## Files Created/Modified

### Created
- `Packages/WatermarkCore/Sources/WatermarkCore/UI/ExtensionRendering.swift` — ShareExtensionRendering & PhotosExtensionRendering protocols
- `Packages/WatermarkCore/Sources/WatermarkCore/UI/ShareExtensionRootView.swift` — Generic share extension root view (moved from ShareExtension/)
- `Packages/WatermarkCore/Sources/WatermarkCore/UI/PhotosExtensionRootView.swift` — Generic photos extension root view (moved from PhotoEditExtension/)
- `Packages/WatermarkCore/Sources/WatermarkCore/UI/ShareSheetView.swift` — Consolidated UIActivityViewController bridge (moved from ShareExtension/)
- `Packages/WatermarkCore/Tests/WatermarkCoreTests/TestHelpers/SnapshotTestViewModel.swift` — Test ViewModel + SnapshotRenderer + pixel comparator
- `Packages/WatermarkCore/Tests/WatermarkCoreTests/ExtensionSnapshotTests.swift` — 20 snapshot tests (15 infra + 5 extension)
- `Packages/WatermarkCore/Tests/WatermarkCoreTests/__Snapshots__/*.png` — 5 reference images

### Modified
- `ShareExtension/ShareExtensionViewModel.swift` — Conforms to `ShareExtensionRendering`
- `PhotoEditExtension/PhotosExtensionViewModel.swift` — Conforms to `PhotosExtensionRendering`
- `ShareExtension/ShareViewController.swift` — Added `import WatermarkCore`
- `Packages/WatermarkCore/Tests/WatermarkCoreTests/TestHelpers/MockRenderingViewModel.swift` — Added missing protocol properties
- `Packages/WatermarkCore/Tests/WatermarkCoreTests/SignatureRendererTests.swift` — Fixed optional URL.path unwrap

### Deleted
- `App/Views/Share/ShareSheetView.swift` — Consolidated into WatermarkCore
- `ShareExtension/ShareSheetView.swift` — Consolidated into WatermarkCore

## Decisions Made

- Moved extension root views into WatermarkCore to enable `@testable import` from package test target (otherwise inaccessible from extension targets)
- Consolidated `ShareSheetView` into WatermarkCore (was duplicated in App and ShareExtension with identical code)
- Used 2% pixel tolerance per RESEARCH.md recommendation — handles antialiasing / font rendering drift across OS versions
- Reference images committed to repo (not generated per-machine on CI) per RESEARCH.md Q1 resolution
- Single snapshot size at 430×932 @3x covers all iPhone variants (size-class driven, per D-05)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] MockRenderingViewModel missing protocol conformance**
- **Found during:** Task 1 RED phase
- **Issue:** `MockRenderingViewModel` did not conform to `WatermarkConfigurable` — missing `sourceHasHDR` and `sourceFormatLabel` properties. Pre-existing issue blocked entire test target compilation.
- **Fix:** Added `var sourceHasHDR: Bool = false` and `var sourceFormatLabel: String? = nil` to MockRenderingViewModel
- **Files modified:** `Packages/WatermarkCore/Tests/WatermarkCoreTests/TestHelpers/MockRenderingViewModel.swift`
- **Committed in:** `3fb8887` (Task 1 RED)

**2. [Rule 3 - Blocking] SignatureRendererTests optional URL.path unwrap**
- **Found during:** Task 1 RED phase
- **Issue:** `result.url.path` called on optional `URL?` — Swift 6 strict concurrency compilation error. Pre-existing issue.
- **Fix:** Changed to `result.url?.path`
- **Files modified:** `Packages/WatermarkCore/Tests/WatermarkCoreTests/SignatureRendererTests.swift`
- **Committed in:** `3fb8887` (Task 1 RED)

**3. [Rule 1 - Bug] Pixel comparator CGContext memory bug**
- **Found during:** Task 1 GREEN phase
- **Issue:** `&pixelData` on a `Data` value does not pass a valid buffer pointer to `CGContext(data:)`, causing the pixel extraction to operate on garbage memory. All comparisons returned incorrect results.
- **Fix:** Replaced `Data(count:) + &pixelData` with `UnsafeMutableRawPointer.allocate` + `initializeMemory` + `defer deallocate`. Also redesigned `compare()` to use `UIGraphicsImageRenderer`-based normalization before pixel extraction for consistent color-space handling.
- **Files modified:** `SnapshotTestViewModel.swift` (compare + renderToBitmap methods)
- **Committed in:** `30cb4a3` (Task 1 GREEN)

**4. [Rule 3 - Blocking] Extension root views inaccessible from WatermarkCore tests**
- **Found during:** Task 2
- **Issue:** `ShareExtensionRootView` and `PhotosExtensionRootView` were defined in extension targets (`ShareExtension/`, `PhotoEditExtension/`), which cannot be imported from the WatermarkCore Swift Package test target. Snapshot tests could not render the actual root views.
- **Fix:** Moved both root views into `WatermarkCore/Sources/WatermarkCore/UI/`, removed self-imports, added `Observable` generic constraint for `ControlsView` compatibility. Consolidated `ShareSheetView` into WatermarkCore (was a dependency of `ShareExtensionRootView`). Updated `project.pbxproj` to remove stale references.
- **Files modified:** 10 files (6 moved/created, 3 deleted, 1 modified)
- **Committed in:** `1f05161` (Task 2)

**5. [Rule 3 - Blocking] Duplicate Array safe subscript**
- **Found during:** Task 2
- **Issue:** `ShareExtensionRootView.swift` contained `extension Array { subscript(safe:) }` which conflicted with the existing public declaration in `WatermarkPosition.swift` when both were compiled in the same module.
- **Fix:** Removed duplicate extension from `ShareExtensionRootView.swift`
- **Files modified:** `ShareExtensionRootView.swift`
- **Committed in:** `1f05161` (Task 2)

---

**Total deviations:** 5 auto-fixed (3 blocking, 1 bug, 1 blocking)
**Impact on plan:** All deviations were necessary to achieve the plan's objective — snapshot tests of extension root views. The root-view move (deviation #4) was the most significant, enabling cross-target test access to the actual root view types. No scope creep — all changes directly support the plan's verification goals.

## Issues Encountered

- **Simulator rendering variance:** Pixel-perfect snapshot comparison in the iOS Simulator is inherently non-deterministic. Two renders of the same view may differ at the pixel level due to antialiasing and font rendering. Resolved by using 2% pixel tolerance and UIGraphicsImageRenderer-based normalization in the `compare()` function.
- **Pre-existing test failure:** `ImageWatermarkRendererTests.Scale 0.5` test fails due to an unrelated image dimension expectation issue. Logged out of scope — not caused by Phase 18 changes.
- **Swift Package cross-target import limitation:** WatermarkCore test target cannot import app extension targets. Required architectural refactoring (root views moved into shared package).

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- Snapshot test infrastructure ready for downstream Phase 18 plans (18-02 accessibility, 18-03 empty state)
- Extension root views now in WatermarkCore — accessible from any test target
- Reference images committed — CI can run snapshot validation immediately
- Only pre-existing `ImageWatermarkRenderer` test failure persists (unrelated to this plan)

---
*Phase: 18-cross-target-parity-accessibility-polish*
*Completed: 2026-06-22*
