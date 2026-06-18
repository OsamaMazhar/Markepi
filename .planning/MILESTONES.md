# Milestones

## v1.0 MVP (Shipped: 2026-06-18)

**Phases completed:** 7 phases, 20 plans, 44 tasks

**Key accomplishments:**

- Built the WatermarkCore Swift Package with a working actor-based watermark engine that renders SF system font text watermarks at 9 preset positions while preserving all EXIF metadata, HDR gain maps, and source format through a CGImageSource → Core Image filter graph → CGImageDestination pipeline — zero third-party dependencies, 55 automated tests, compiles targeting iOS 18/Swift 6.
- Extended the WatermarkCore engine with PNG image/logo watermark support via ImageWatermarkRenderer (CIImage(data:) → CGAffineTransform scale → CIFilter.colorMatrix opacity), wired into the engine's buildFilterGraph with configurable padding, completing all 9-position coverage with verified mixed text+image multi-layer compositing — 23 new tests, zero regressions, WMRK-02 and WMRK-03 complete.
- Extended the WatermarkCore engine with white frame border rendering and "Taken by: [Device Model]" metadata text overlay. The white frame is composited below all watermark layers in a single processing pass, completing the Phase 1 engine's full feature set (text watermarks, image watermarks, white frames). UIGraphicsImageRenderer with .extended range ensures HDR compatibility. CTLineDraw on macOS enables cross-platform testing. 103 tests pass across 13 suites — zero regressions.
- iOS 18 SwiftUI app with PhotosPicker import, text watermark controls, real-time debounced preview, and share-without-saving via UIActivityViewController
- Extended main app with logo/image watermark support, white frame toggle, per-layer management, pinch-to-resize gesture, accessibility, and animations
- One-liner:
- AVFoundation CALayer overlay pipeline: VideoProcessor loads, composes, watermarks via AVVideoCompositionCoreAnimationTool, exports with HDR preservation and audio passthrough, validates post-export quality
- Video NSItemProvider loading with static frame preview, HDR fallback warnings, multi-item sequential processing, and shared controls refactoring — extending the share extension to full photo+video watermarking
- One-liner:
- Video watermarking from Photos edit menu with HDR preservation; PHAdjustmentData image stripping for size safety; 15 automated tests; 17-case manual QA checklist
- One-liner:
- One-liner:
- One-liner:
- 1. [Rule 3 - Blocking] Enum breaking change required 50+ call site updates
- OutputFormat.tiff, quality slider, format picker UI, and HDR→JPEG loss warning — full export control pipeline from config model through engine to UI
- Long-press comparison toggle in PreviewView with "Original" label overlay, light impact haptic, and simultaneous pinch-to-scale gesture composition — working for both photos and videos via cached source images.
- Real-time video export progress bar with percentage/ETA, cancelable export with config preservation, and background completion notification using iOS 18 AVFoundation APIs
- PencilKit-based signature capture with CGColor Codable model, CIImage rendering via colorMatrix, full UIViewRepresentable canvas, and WatermarkLayer .signature enum integration across all 3 targets
- Live Photo watermarking via two-phase engine pipeline with PhotosPicker pair detection, graceful fallback, and typed error handling
- Phase:

---
