# Milestones

## v2.1 UI Redesign (Shipped: 2026-06-22)

**Phases completed:** 4 phases, 11 plans, 25 tasks

**Key accomplishments:**

- Foundation design system layer: Liquid Glass modifier with iOS 18 material fallback, semantic typography system with uncapped Dynamic Type, and conditional-modifier utility extension — all public in WatermarkCore/DesignSystem/
- Three SwiftUI primitives consuming the glass/typography foundation — capsule button style with three semantic roles, 3-section pill bar with matched-geometry sliding indicator, and scroll-edge protection via glass-backed header
- PreviewCatalog.swift rendering all 6 design system primitives side-by-side in Xcode Previews, with build-gate confirming cross-target compilation across App, ShareExtension, and PhotoEditExtension
- Rewritten ControlsView with pill-bar-driven 3-section layout, Menu-based position & export format pickers, and MarkepiButtonStyle capsules on all buttons
- All 6 sub-view files (TextWatermarkInputView, ScaleStepperView, WhiteFrameToggleView, LogoPickerView, SignatureCaptureView, LayerListView) restyled onto the Phase 15 Markepi design system — inset grouped row pattern, semantic typography, and capsule button styles — with zero behavior changes to ViewModel bindings or data flow.
- Standalone ShareActionButton extracted from ControlsView into WatermarkCore/DesignSystem/, preserving all 6 rendering states and protocol surface, with ControlsView wired as drop-in replacement.
- Custom ZStack-compatible bottom sheet container with drag-to-resize detent snapping, Liquid Glass surface, and native nested scroll via indicator-only DragGesture
- ContentView restructured from 60/40 VStack split into ZStack inspector shell with full-bleed preview, glass bottom sheet, batch overlays, and pinned Share action bar. PreviewView updated to true edge-to-edge via `.ignoresSafeArea()`.
- 5 automated snapshot tests verify both extension root views render correctly with the redesigned ControlsView at 430×932, with committed reference images and 2% pixel tolerance comparison.
- VoiceOver labels on pill bar segments with .isSelected trait, ControlSection container group labels, and Reduce Motion gating on pill bar matched-geometry animation
- Shared EmptyStateView component integrated across all 3 targets with Dynamic Type sheet scaling and Reduce Motion gating on preview/batch animations, replacing old pill-button and extension idle states.

---

## v1.1 Tech Debt Hardening (Shipped: 2026-06-19)

**Phases completed:** 4 phases, 6 plans, 15 tasks

**Key accomplishments:**

- Reconciled v1.0 REQUIREMENTS.md traceability — 15 checkbox flips, 15 traceability table updates, 7 requirements reclassified v2→v1, with Reconciliation Note documenting MILESTONE-AUDIT.md evidence
- Repo-local bash guard script with gsd-tools delegation, self-contained fixture test, and AGENTS.md documentation — prevents v1.0 traceability drift from recurring by making REQUIREMENTS.md checkbox sync a reproducible, verifiable post-plan step that fails noisily on mismatch.
- xcodebuild wave-level build gate with self-contained fixture test, replacing file-existence self-checks as source of truth for build pass/fail — directly addressing the v1.0 retrospective's root cause where pre-existing build errors compounded undetected across Phases 5–6.
- Protocol extension with 9 default implementations (5 method + 1 no-op + 3 computed properties) collapses ~186 lines of duplicated ViewModel code into a single source of truth in WatermarkCore
- Removed 26 duplicated implementations across 3 ViewModels — ~259 lines collapsed to zero, with all layer-management operations inherited from WatermarkConfigurable protocol extension defaults
- PhotosExtensionViewModel now populates sourceHasHDR and sourceFormatLabel from PHContentEditingInput, enabling the HDR→JPEG warning alert and Match Source format label in the Photos extension's ControlsView

---

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
