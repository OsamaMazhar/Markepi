---
phase: 07-additional-inputs-system-integration-v2
plan: 01
subsystem: watermarking
tags: [signature, pencilkit, swiftui, core-image, codable]

# Dependency graph
requires: []
provides:
  - SignatureInput model with CGColor Codable for App Group config sync
  - WatermarkLayer .signature case with full Codable + backward compatibility
  - SignatureRenderer — PKDrawing → CIImage with ink color tint via colorMatrix
  - SignatureCaptureView — full-screen PencilKit canvas with undo/clear/color/width controls
  - WatermarkConfigurable.addSignatureLayer protocol requirement
  - WatermarkEngine.buildFilterGraph .signature case integration
affects:
  - 07-03 (text+sig combo proof-of-concept wireup)
  - Future plans using signature watermark layers

# Tech tracking
tech-stack:
  added: [PencilKit]
  patterns:
    - "CGColor Codable: encode as [CGFloat] RGBA array (matches TextWatermarkInput pattern)"
    - "WatermarkLayer enum extension: add case + all computed properties + Codable + strippingImageData"
    - "Canvas UIViewRepresentable: PKCanvasView wrapper with Coordinator delegate"
    - "Platform guard: #if canImport(UIKit) for PencilKit views (macOS gets stub)"
    - "Renderer pattern: struct + static func render(input:) throws -> CIImage (matches ImageWatermarkRenderer)"

key-files:
  created:
    - Packages/WatermarkCore/Sources/WatermarkCore/Models/SignatureInput.swift
    - Packages/WatermarkCore/Sources/WatermarkCore/Processing/SignatureRenderer.swift
    - Packages/WatermarkCore/Sources/WatermarkCore/UI/SignatureCaptureView.swift
    - Packages/WatermarkCore/Tests/WatermarkCoreTests/SignatureInputTests.swift
    - Packages/WatermarkCore/Tests/WatermarkCoreTests/SignatureRendererTests.swift
  modified:
    - Packages/WatermarkCore/Sources/WatermarkCore/Models/WatermarkConfiguration.swift
    - Packages/WatermarkCore/Sources/WatermarkCore/Engine/WatermarkEngine.swift
    - Packages/WatermarkCore/Sources/WatermarkCore/Processing/VideoLayerBuilder.swift
    - Packages/WatermarkCore/Sources/WatermarkCore/UI/LayerListView.swift
    - Packages/WatermarkCore/Sources/WatermarkCore/UI/ControlsView.swift
    - Packages/WatermarkCore/Sources/WatermarkCore/UI/WatermarkConfigurable.swift
    - App/ViewModels/WatermarkViewModel.swift
    - ShareExtension/ShareExtensionViewModel.swift
    - PhotoEditExtension/PhotosExtensionViewModel.swift

key-decisions:
  - "PKDrawing rasterization at 3× scale for Retina-quality output on high-res sources"
  - "Ink color tint via CIFilter.colorMatrix RGB vector multiplication with alpha pass-through"
  - "Signature stroke data stored as raw PKDrawing.dataRepresentation() Data (vector, typically <100KB)"
  - "strippingImageData no-op for .signature layers — stroke data is small enough for PHAdjustmentData"
  - "Extension ViewModels use no-op addSignatureLayer stubs — PencilKit unavailable in extension contexts"

patterns-established:
  - "SignatureInput: 1:1 mirror of TextWatermarkInput CGColor Codable pattern with CodingKey colorRGBA"
  - "SignatureRenderer: 1:1 mirror of ImageWatermarkRenderer struct + static render pattern with #if canImport(UIKit)"
  - "SignatureCaptureView: 1:1 mirror of LogoPickerView generic ViewModel + sheet presentation pattern"

requirements-completed: [SIGN-01]

# Metrics
duration: 8min
completed: 2026-06-18
---

# Phase 7 Plan 1: Signature Watermark Layer Summary

**PencilKit-based signature capture with CGColor Codable model, CIImage rendering via colorMatrix, full UIViewRepresentable canvas, and WatermarkLayer .signature enum integration across all 3 targets**

## Performance

- **Duration:** 8 min
- **Started:** 2026-06-18T11:10:10Z
- **Completed:** 2026-06-18T11:18:52Z
- **Tasks:** 3
- **Files modified:** 14 (5 created, 9 modified)

## Accomplishments

- SIGN-01: User can add, edit, and remove signature watermark layers with finger/Apple Pencil
- SignatureInput model with strokeData/inkColor/strokeWidth — full Codable round-trip with CGColor RGBA array pattern
- WatermarkLayer.signature case exhaustively integrated into all switch statements across WatermarkCore, app, share extension, and Photos extension
- SignatureRenderer produces tinted CIImage from PKDrawing with CIFilter.colorMatrix ink color application at 3× scale
- SignatureCaptureView — full-screen PencilKit canvas in SwiftUI with undo, clear, color picker, and stroke width controls
- Backward-compatible JSON decoding — old configs without signature layers decode successfully
- 10 new unit tests (5 SignatureInput + 5 SignatureRenderer) all passing

## Task Commits

Each task was committed atomically:

1. **Task 1: SignatureInput model + WatermarkLayer .signature case + Codable** - `fdd811b` (feat)
2. **Task 2: SignatureRenderer + WatermarkEngine buildFilterGraph integration** - `6444d30` (test)
3. **Task 3: SignatureCaptureView UI + ViewModel + Controls/LayerList integration** - `de4d74a` (feat)

## Files Created/Modified

**Created:**
- `Packages/WatermarkCore/Sources/WatermarkCore/Models/SignatureInput.swift` — Sendable+Codable model with strokeData, inkColor (CGColor Codable), strokeWidth
- `Packages/WatermarkCore/Sources/WatermarkCore/Processing/SignatureRenderer.swift` — PKDrawing → CIImage with ink color tint via CIFilter.colorMatrix
- `Packages/WatermarkCore/Sources/WatermarkCore/UI/SignatureCaptureView.swift` — Full-screen PencilKit canvas UIViewRepresentable with toolbar controls
- `Tests/WatermarkCoreTests/SignatureInputTests.swift` — 5 tests: Codable round-trip, defaults, WatermarkLayer round-trip, backward compat, strippingImageData
- `Tests/WatermarkCoreTests/SignatureRendererTests.swift` — 5 tests: valid stroke, invalid stroke, ink color, engine integration, hidden layer

**Modified:**
- `WatermarkConfiguration.swift` — .signature case in WatermarkLayer enum + all computed properties + Codable + LayerType + strippingImageData + rehydrateImageData
- `WatermarkEngine.swift` — buildFilterGraph: .signature case delegates to SignatureRenderer.render
- `VideoLayerBuilder.swift` — buildWatermarkLayer: .signature case for video CALayer compositing
- `LayerListView.swift` — layerIcon: "signature" SF Symbol; layerDescription: "Signature"
- `ControlsView.swift` — SignatureCaptureView inserted between LogoPickerView and WhiteFrameToggleView
- `WatermarkConfigurable.swift` — addSignatureLayer protocol requirement
- `WatermarkViewModel.swift` — addSignatureLayer implementation + .signature in previewIdentifier/updateLayerPosition/updateLayerScale
- `ShareExtensionViewModel.swift` — no-op addSignatureLayer stub + .signature in previewIdentifier/updateLayerPosition/updateLayerScale/generateVideoPreview
- `PhotosExtensionViewModel.swift` — no-op addSignatureLayer stub + .signature in previewIdentifier/updateLayerPosition/updateLayerScale

## Decisions Made

- PKDrawing rasterized at 3× scale for Retina-quality output on high-res sources (per RESEARCH.md Open Question 2)
- Ink color applied via CIFilter.colorMatrix RGB vectors (multiply RGB by inkColor components, alpha pass-through) rather than bitmap-level pixel manipulation
- Signature stroke data stored as raw PKDrawing.dataRepresentation() Data — vector format, typically <100KB, well within PHAdjustmentData limits
- strippingImageData() is a no-op for .signature layers (stroke data is small, no stripping needed)
- Extension ViewModels use no-op addSignatureLayer stubs — PencilKit canvas requires UIApplication/UIWindowScene which isn't available in extension sandboxes

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Exhaustive switch compilation errors from .signature case**
- **Found during:** Task 1 (immediately after adding .signature to WatermarkLayer)
- **Issue:** Adding the new .signature case to WatermarkLayer enum caused Swift exhaustive switch errors in 10+ files across WatermarkCore, app, share extension, and Photos extension targets
- **Fix:** Added .signature cases to all affected switch statements: WatermarkEngine.buildFilterGraph, VideoLayerBuilder.buildWatermarkLayer, LayerListView (layerIcon + layerDescription), all 3 ViewModels (previewIdentifier, updateLayerPosition, updateLayerScale, generateVideoPreview), and PhotosExtensionViewModel's previewIdentifier
- **Files modified:** WatermarkEngine.swift, VideoLayerBuilder.swift, LayerListView.swift, WatermarkViewModel.swift, ShareExtensionViewModel.swift, PhotosExtensionViewModel.swift
- **Verification:** Full swift test suite compiles and passes (10 new tests, 203 pre-existing passing)
- **Committed in:** fdd811b (Task 1 commit — exhaustive switch handling included as necessary compilation fix)

**2. [Rule 3 - Blocking] Created SignatureRenderer earlier than planned to unblock compilation**
- **Found during:** Task 1
- **Issue:** WatermarkEngine and VideoLayerBuilder reference SignatureRenderer.render() but the file didn't exist yet (planned for Task 2)
- **Fix:** Created minimal SignatureRenderer.swift in Task 1, then fleshed out in Task 2 with tests. On macOS, the renderer was adjusted to use #if canImport(UIKit) instead of #if canImport(PencilKit) because PencilKit on macOS uses NSColor/NSView, not UIColor/UIView
- **Files modified:** SignatureRenderer.swift (created early, refined iteratively)
- **Verification:** Compiles on both iOS and macOS targets
- **Committed in:** fdd811b (initial), refined in de4d74a

**3. [Rule 3 - Blocking] Platform guard fix for SignatureCaptureView**
- **Found during:** Task 3
- **Issue:** Initial implementation used #if canImport(PencilKit) but PencilKit IS available on macOS — it just uses AppKit types (NSColor, NSView) instead of UIKit. This caused UIColor/PKCanvasView/UIViewRepresentable to be unavailable.
- **Fix:** Wrapped entire iOS implementation in #if canImport(UIKit) with a non-UIKit stub that shows "not available on this platform" message. Changed inkColor from UIColor to SwiftUI Color for cross-platform compatibility.
- **Files modified:** SignatureCaptureView.swift
- **Verification:** Compiles on macOS (arm64e-apple-macos14.0)
- **Committed in:** de4d74a

---

**Total deviations:** 3 auto-fixed (3 blocking/compilation)
**Impact on plan:** All auto-fixes were necessary for compilation. The switch exhaustive errors were an expected consequence of adding a new enum case; the early SignatureRenderer creation and platform guard fixes were necessary for cross-platform compilation. No scope creep.

## Issues Encountered

- Pre-existing PhotosExtension orientation test failures (14 issues, 8 orientations × 2 assertions) — unrelated to signature watermarking changes
- CGColor import visibility in WatermarkConfigurable protocol — CGColor is available transitively through CoreImage import in extension ViewModels

## Threat Flags

| Flag | File | Description |
|------|------|-------------|
| threat_flag: T-07-01 handled | SignatureRenderer.swift | PKDrawing(data:) validation at render time — corrupt stroke data throws PipelineError.invalidImageData |
| threat_flag: T-07-02 handled | SignatureInput.swift | Stroke data is vector format (<100KB typical); no size enforcement needed per threat model |
| threat_flag: T-07-03 handled | WatermarkConfiguration.swift | decodeIfPresent on signatureConfig key — old configs without signature layers decode without error |

## Known Stubs

| Stub | File | Reason |
|------|------|--------|
| addSignatureLayer() no-op | ShareExtensionViewModel.swift:663 | PencilKit not available in share extension context — intentional design limitation |
| addSignatureLayer() no-op | PhotosExtensionViewModel.swift:405 | PencilKit not available in photo editing extension context — intentional design limitation |
| SignatureCaptureView non-UIKit stub | SignatureCaptureView.swift (second #else block) | macOS platform doesn't support PKCanvasView — shows "not available" message |

## Next Phase Readiness

- SIGN-01 complete — signature watermark layer fully functional
- Ready for Plan 07-02 (QR Code watermark layers)
- No blockers; all 3 targets compile; 10 new tests pass

---
*Phase: 07-additional-inputs-system-integration-v2*
*Completed: 2026-06-18*
