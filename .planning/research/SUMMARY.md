# Project Research Summary

**Project:** iOS Photo/Video Watermarking App (Watermark)
**Domain:** iOS Photo/Video Watermarking & Instant Sharing
**Researched:** 2026-06-17
**Overall Confidence:** HIGH

## Executive Summary

This is an iOS utility app for watermarking photos and videos — but unlike every existing competitor on the App Store, it never forces the user to save a copy to the camera roll. The core workflow is: import media → apply watermark + device metadata frame → share directly via the iOS share sheet. The processed output lives in a temp file, gets handed to `UIActivityViewController`, and is cleaned up after sharing. No camera roll clutter. This "watermark and share without saving" workflow is a verified whitespace — no major competitor (Watermarkly, eZy Watermark, EXIFrame, OneLine, Canva) offers it.

The app is built entirely with Apple system frameworks — Swift 6, SwiftUI, Core Image, AVFoundation, and ImageIO — targeting iOS 18 minimum. There are zero third-party dependencies. A single shared Swift Package (`WatermarkCore`) contains all processing logic, models, and renderers, consumed by the main app, a Share Extension, and a Photos Edit Extension. This architecture eliminates code duplication while keeping extension targets lightweight (critical for the ~120 MB memory limit).

The three biggest risks are all media-processing concerns: (1) HDR gain map destruction — the most common silent quality regression in iOS photo apps, where the gain map auxiliary data that gives HDR photos their "pop" is discarded during the Core Image pipeline; (2) video HDR flattening to SDR during re-encoding — default AVFoundation settings assume SDR and will strip Dolby Vision/HLG metadata; and (3) share extension memory crashes — loading full-resolution images into memory within the extension's ~120 MB ceiling causes silent jetsam termination. All three are preventable if addressed during the processing pipeline design phase, not retrofitted later. Budget significantly more time for video processing than photo processing — video has more pitfalls and is inherently harder to validate.

## Key Findings

### Recommended Stack

A pure Apple-ecosystem stack with zero third-party dependencies. Every framework needed for photo/video watermarking, metadata preservation, and HDR handling is provided by the iOS 18 SDK. Third-party libraries would add unnecessary complexity to a privacy-focused, on-device-only app and typically strip metadata/HDR that this app must preserve.

**Core technologies:**
- **Swift 6 / SwiftUI / iOS 18 SDK** — Modern language with strict concurrency checking; `@Observable` for granular SwiftUI state; iOS 18 minimum covers >95% of active devices and eliminates legacy `ObservableObject` patterns
- **Core Image + CIContext** — GPU-accelerated filter graph for photo watermark compositing; lazy evaluation merges the entire filter chain into a single Metal shader; reuse a single `CIContext` instance — never create one per frame
- **AVFoundation (AVMutableComposition + AVAssetWriter)** — The only path for video watermarking with quality control; use `AVAssetWriter` (not `AVAssetExportSession`) for control over bitrate, color properties, and HDR metadata
- **ImageIO (CGImageSource → CGImageDestination)** — The only reliable metadata-preserving pipeline; `CGImage` and `UIImage` are pixel-only and strip EXIF, GPS, color profiles, and HDR gain maps
- **PhotosUI (PhotosPicker)** — Privacy-first media picker; no photo library permission needed; modern async `Transferable` integration
- **WatermarkCore (Local Swift Package)** — Shared processing engine consumed by all three targets (main app, share extension, photo edit extension); enforces single source of truth and keeps extensions thin
- **App Groups + UserDefaults(suiteName:)** — Cross-process communication between app and extensions via shared file container

### Expected Features

The watermark customization basics (text, logo, opacity, 8 positions, rotation, scale, real-time preview) are commodified — every competitor has them. They must work flawlessly but are not where this app wins. The differentiators are workflow innovations (share without save, 3 import methods, Photos edit extension) and quality guarantees (HDR preservation, metadata passthrough, on-device only).

**Must have (table stakes — MVP):**
- Text watermark overlay with font/size/color/opacity controls — baseline function, every competitor has it
- Image/logo watermark overlay — import transparent PNG from photo library, resize/rotate
- 8 preset watermark positions + drag-to-position — corners, edges, center
- Real-time preview — see result before sharing; proportional rendering matching output
- Photo import via in-app picker — PhotosPicker, supports HDR
- White frame + "Taken by: [Device]" metadata overlay — one-tap preset for the trending social media aesthetic
- Share without saving to camera roll — render in-memory, present share sheet immediately, temp file cleanup
- Preserve EXIF/metadata in output — copy all metadata from source to output
- Preserve HDR and original quality for photos — 10-bit pipeline, color profile passthrough, gain map retention

**Should have (competitive — ship fast post-launch):**
- Video watermarking — requires AVFoundation pipeline; same watermark engine, different renderer
- iOS Share Sheet import — receive photos/videos from other apps via share extension
- Rotation control for watermarks — simple gesture or slider
- Template/preset saving — save watermark configurations for reuse

**Defer (v2+):**
- Photos app edit extension — high engineering cost; trigger on confirmed power-user demand
- Batch processing (>1 media at a time) — complexity jumps for video batching due to memory management
- Additional device metadata frames — "Shot on iPhone," camera lens details, date/location stamps
- Custom frame styles — colored borders, gradients, multiple widths
- Any photo editing, cloud storage, account creation, or AI placement — explicitly anti-features that dilute the core value proposition

### Architecture Approach

Four-layer architecture with a shared Swift Package at its heart. The Presentation layer (SwiftUI views) is thin and declarative. The State/ViewModel layer uses `@Observable` for granular SwiftUI updates. The Processing Engine layer (in WatermarkCore) contains all media-specific logic — PhotoProcessor for the Core Image pipeline, VideoProcessor for the AVFoundation pipeline, and MetadataPreserver for EXIF/color profile passthrough. The Data layer manages temp files (with automatic cleanup) and App Group shared containers for cross-process communication.

**Major components:**
1. **WatermarkCore (Local Swift Package)** — Single source of truth for all models, renderers, processors, and storage utilities. Linked by all three targets. Enforces App-Extension-Safe API usage.
2. **ProcessingEngine** — Router that dispatches to PhotoProcessor or VideoProcessor based on media type. Owns async processing lifecycle with progress reporting and cancellation support.
3. **PhotoProcessor** — Constructs CIImage filter graph (watermark overlay → white frame → metadata text) with lazy evaluation. Uses shared `CIContext` for rendering. Writes via `CGImageDestination` with original metadata + HDR gain map re-attached.
4. **VideoProcessor** — Configures `AVAssetWriter` with explicit color properties matching the source (SDR or HDR). Uses `AVVideoComposition` with Core Image filter handler for frame-by-frame watermark compositing. Preserves audio track.
5. **Extension Shells** — Share Extension and Photo Edit Extension targets contain only entry-point view controllers, target-specific plist configuration, and thin SwiftUI hosting. All logic is in WatermarkCore. Extensions stay well under the 120 MB memory ceiling.
6. **AppGroupContainer + TempFileManager** — Shared file-based communication between app and extensions. Temp files in `cachesDirectory` are cleaned up automatically after sharing or on next launch.

### Critical Pitfalls

1. **HDR Gain Map Destruction** — `CIImage(contentsOf:)` loads only the base image by default. The HDR gain map auxiliary data that gives iPhone photos their dynamic range is silently discarded. Fix: load with `[.auxiliaryHDRGainMap: true]`, re-attach via `CGImageDestinationAddAuxiliaryDataInfo()` or `CIImageRepresentationOption.hdrGainMapImage` during write. Use 16-bit float pixel formats for rendering.

2. **EXIF/Metadata Stripping in Pixel Pipeline** — Every conversion step (PHAsset → CIImage → CGImage → output) strips metadata because `CGImage`/`CIImage` are pixel-only representations. Fix: extract metadata dictionary via `CGImageSourceCopyPropertiesAtIndex()` BEFORE any pixel manipulation, store separately, re-attach via `CGImageDestinationAddImage()` with the preserved properties dictionary during write.

3. **Video Re-Encoding Quality Degradation** — Default encoder settings assume SDR, Rec.601, and variable bitrate that dips too low on complex frames. Fix: use `AVAssetWriter` with explicit compression settings (bitrate ≥80% of source, HEVC profile), explicitly set color primaries/transfer function/YCbCr matrix matching source, and match source pixel format to avoid unnecessary color space conversions.

4. **Share Extension Memory Limit Crashes** — Extensions have a ~120 MB hard ceiling. Loading a 12MP photo as `UIImage` consumes ~48 MB; multiple copies (original + preview + processed) easily exceed the limit. Fix: never load shared media as `UIImage`; use `CGImageSource` with downsampling for previews; process one item at a time; use `NSExtensionActivationRule` with `MaxCount = 1`; test on physical devices only (Simulator has no memory limit).

5. **CIImage Coordinate System & Double-Rotation Bug** — `CIImage` ignores EXIF orientation and uses bottom-left origin (+Y up), conflicting with UIKit's top-left origin (+Y down). A watermark placed in "top-right" via UIKit coordinates appears in bottom-left of output. Fix: always normalize orientation before applying positional transforms using `oriented(forExifOrientation:)`; convert UIKit coordinates to CIImage space with Y-axis flip (`ciY = imageHeight - uiKitY - overlayHeight`).

## Implications for Roadmap

Based on research, the suggested phase structure follows the dependency graph from the architecture: foundation models/renderers first (everything depends on them), then processing pipelines (photo first — simpler, validates core differentiators), then UI (builds on working processing), then video (complex, separate pipeline), then extensions (depend on processing engine), then polish.

### Phase 1: WatermarkCore Foundation
**Rationale:** Everything depends on shared models and rendering functions. Build the pure-logic layer first — position calculation, watermark overlay construction, text generation, white frame rendering, temp file management, device metadata provider, and App Group container access. These are all synchronous, pure functions with zero UI dependencies, making them testable in isolation with Swift Testing.
**Delivers:** Shared Swift Package skeleton with all data models (`WatermarkConfiguration`, `MediaSource`, `ProcessingResult`), all renderers (`WatermarkOverlayFilter`, `TextOverlayGenerator`, `WhiteFrameGenerator`, `PositionCalculator`), storage utilities (`TempFileManager`, `AppGroupContainer`), and `DeviceMetadataProvider`.
**Addresses:** Foundation for all table-stakes features.
**Avoids:** Pitfalls 2 (metadata), 5 (coordinates), 9 (JPEG re-compression) — addressed by renderer design.
**Research flag:** LOW risk. Core Image filter chaining is well-documented, pure functions, highly testable. Skip research-phase — standard patterns.

### Phase 2: Photo Processing Pipeline
**Rationale:** Photo processing is the MVP delivery vehicle — it validates the core "watermark and share without saving" differentiator with lower complexity than video. Build `PhotoProcessor` (CIImage chain: load → watermark overlay → white frame → metadata text → render → write with metadata), `MetadataPreserver` (EXIF/GPS/color profile extraction and re-attachment), and `ProcessingEngine` (media type routing). Full HDR gain map handling must be integrated from the start.
**Delivers:** Complete photo processing pipeline: import HDR photo → apply watermark at any of 8 positions → render "Taken by: iPhone" frame → produce output with full EXIF + HDR gain map intact → write to temp file. Testable end-to-end without any UI.
**Uses:** Core Image, ImageIO, Photos framework.
**Implements:** PhotoProcessor, MetadataPreserver, ProcessingEngine.
**Avoids:** Pitfalls 1 (HDR gain map), 2 (EXIF stripping), 5 (coordinate system), 9 (JPEG re-compression). These MUST be verified with actual iPhone 12+ HDR photos before advancing.
**Research flag:** MEDIUM risk. HDR gain map preservation is the hardest part and needs offline investigation with sample HDR footage. **Needs `/gsd-plan-phase --research-phase 2`** during planning for HDR gain map pipeline validation.

### Phase 3: Main App UI
**Rationale:** Once the processing engine works end-to-end, build the SwiftUI interface that makes it usable. The main app has the most UI complexity (media picker, position grid, style selector, text input, preview area, share coordinator) and validates the full user experience before investing in extensions.
**Delivers:** Fully functional main app with PhotosPicker for import, 8-position grid + drag-to-position, text/image watermark configuration, opacity/size controls, real-time preview (downsampled for performance), and share button that triggers processing → presents `UIActivityViewController`.
**Addresses:** All 9 MVP features from FEATURES.md — delivers the complete "watermark and share" loop.
**Uses:** SwiftUI, PhotosPicker, `@Observable` ViewModels.
**Implements:** `MainAppView`, `MediaPickerView`, `PositionGridView`, `StylePickerView`, `PreviewView`, `ShareCoordinator`, `WatermarkViewModel`.
**Research flag:** LOW risk. SwiftUI picker/UI patterns are well-documented. Skip research-phase.

### Phase 4: Video Processing Pipeline
**Rationale:** Video processing is fundamentally different from photo processing — it requires AVFoundation, frame-by-frame compositing, audio track handling, and HDR color management. Budget significantly more time for this phase: video has 5 dedicated pitfalls (3, 7, 8, plus share extension memory and performance traps). This phase is separate from photo processing because it has different dependencies (AVAssetWriter, not CIImage chain) and higher complexity. Build after the photo pipeline validates the core concept.
**Delivers:** Video watermarking pipeline: import video → extract composition tracks → configure `AVVideoComposition` with Core Image handler for frame-by-frame watermark compositing → `AVAssetWriter` export with explicit color properties and bitrate control → temp file output. HDR video preservation (HLG/Dolby Vision). Audio track passthrough.
**Addresses:** Video watermarking (P2 feature), HDR video preservation (P2).
**Uses:** AVFoundation, Core Image (frame handler), Video Toolbox (via AVAssetWriter).
**Implements:** `VideoProcessor`, HDR detection and color property configuration.
**Avoids:** Pitfalls 3 (re-encoding quality), 7 (HDR flattening), 8 (audio drop), 4 (extension memory — video frames are massive).
**Research flag:** HIGH risk. HDR video preservation with custom compositions is poorly documented and has subtle platform-specific behavior. **Needs `/gsd-plan-phase --research-phase 4`** and possibly a Spike with sample Dolby Vision/HLG footage before committing to design.

### Phase 5: Share Extension
**Rationale:** The share extension provides the second import method — receiving media from other apps via the iOS share sheet. This is a key differentiator. The extension target must be thin (memory limit) and correctly handle `NSItemProvider` lifecycle. Build after the main app validates the UX pattern — the extension reuses the same watermark UI and processing engine.
**Delivers:** Share Extension target: receives photos/videos from share sheet → hosts SwiftUI watermark config view → processes via WatermarkCore engine → outputs temp file to App Group container → presents share sheet or opens main app.
**Addresses:** Share sheet import (P2 feature).
**Uses:** Share Extension framework, App Groups, NSItemProvider.
**Implements:** `ShareViewController` (UIViewController + UIHostingController), `ShareExtensionView` (SwiftUI), `NSExtensionActivationRule` configuration.
**Avoids:** Pitfall 4 (extension memory crash) — must use CGImageSource downsampling, never UIImage, one-at-a-time processing, physical device testing.
**Research flag:** LOW-MEDIUM risk. Share extension patterns are well-documented but memory limit behavior is device-specific. Needs physical device testing, not deep research.

### Phase 6: Photos Edit Extension
**Rationale:** The Photos edit extension is the third import method and a unique differentiator (no major watermark app offers this). It is the most complex extension to implement — `PHContentEditingController` has a strict lifecycle, orientation must be handled explicitly, and `PHAdjustmentData` size limits are undocumented. Defer this to post-launch unless power-user demand is confirmed early.
**Delivers:** Photos Edit Extension target: appears as editing option inside Apple Photos → receives `PHContentEditingInput` → presents watermark config UI → processes via WatermarkCore → returns `PHContentEditingOutput` with `PHAdjustmentData` for non-destructive editing.
**Addresses:** Photos app edit extension (P3 feature, deferred to v2+).
**Implements:** `PhotoEditViewController` (PHContentEditingController), `PhotoEditView` (SwiftUI), adjustment data serialization.
**Avoids:** Pitfalls 6 (PHContentEditingInput orientation), 10 (PHAdjustmentData size limit). Adjustment data must be a lightweight recipe (<1KB), never embedded assets.
**Research flag:** MEDIUM risk. PHContentEditingController lifecycle (cancelContentEditing, shouldShowCancelConfirmation) is well-documented but easy to miss. `PHAdjustmentData` size limit is undocumented — needs empirical testing. **Needs `/gsd-plan-phase --research-phase 6`** if this phase is committed.

### Phase 7: Polish & Quality Assurance
**Rationale:** After all processing pipelines and UI surfaces are built, comprehensive validation against every pitfall. This phase is non-negotiable — the "Looks Done But Isn't" checklist has 12 items that must pass before any release.
**Delivers:** HDR validation (photos + videos) with XDR display, metadata completeness verification via exiftool, orientation correctness across all 4 device orientations and aspect ratios, large-file stress testing (48MP ProRAW, 10min 4K60 video), physical device testing for extensions, format fidelity verification (HEIF→HEIF, JPEG→JPEG), performance profiling with Instruments (memory, GPU, export times).
**Uses:** exiftool, Instruments, physical test devices.
**Research flag:** LOW risk. QA patterns are standard. Skip research-phase — this is execution.

### Phase Ordering Rationale

- **Foundation first (Phase 1):** The dependency graph shows everything depends on WatermarkCore models and renderers. Building these first as pure, testable functions creates a solid base and enables parallel work in later phases.
- **Photo before video (Phase 2 before 4):** Photo processing is simpler, validates the core differentiator ("share without save") with lower risk, and most of the 10 pitfalls are photo-specific and must be solved in the photo pipeline anyway. Video adds HDR complexity and re-encoding quality concerns on top.
- **Processing before UI (Phases 1-2 before 3):** The processing engine should be testable end-to-end before any UI is built. This prevents the common anti-pattern of building UI that masks processing bugs.
- **Main app before extensions (Phase 3 before 5-6):** Extensions reuse the same WatermarkCore engine and similar UI. Build and validate the complete UX in the main app first, then port to the constrained extension environments.
- **Video is its own phase (Phase 4):** Video has 5 dedicated pitfalls, a fundamentally different rendering pipeline (AVFoundation vs Core Image), and needs AVAssetWriter configuration expertise. Isolating it prevents video complexity from delaying the photo MVP.
- **Extensions after core validation (Phases 5-6 after 2-3):** Extensions depend on a working processing engine and validated UX patterns. Building them early risks rework if the core engine changes. The Photos Edit Extension (Phase 6) is explicitly deferred — high engineering cost, constrained environment, and its value proposition needs market validation first.

### Research Flags

**Phases needing deeper research during planning (use `/gsd-plan-phase --research-phase <N>`):**
- **Phase 2 (Photo Processing):** HDR gain map preservation pipeline — extracting, transforming, and re-attaching gain map auxiliary data through a Core Image filter chain. This is the most technically nuanced aspect of photo processing and is poorly covered in community resources.
- **Phase 4 (Video Processing):** HDR video preservation with custom compositions — Dolby Vision and HLG metadata handling through AVAssetWriter, 10-bit color pipeline configuration, and platform-specific encoder behavior. Needs a Spike with sample footage.
- **Phase 6 (Photos Edit Extension):** `PHAdjustmentData` size limits are undocumented — needs empirical testing to determine safe payload sizes. `PHContentEditingController` lifecycle edge cases (cancelContentEditing, shouldShowCancelConfirmation).

**Phases with standard patterns (skip research-phase):**
- **Phase 1 (WatermarkCore):** Core Image filter chaining and position calculation are well-documented, pure functions, highly testable.
- **Phase 3 (Main App UI):** SwiftUI picker, position grid, and share sheet integration are standard iOS patterns with extensive official documentation.
- **Phase 5 (Share Extension):** Share extension patterns are well-documented in Apple's App Extension Programming Guide.
- **Phase 7 (Polish & QA):** Standard QA methodology — no research needed, just execution against the pitfall checklist.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All recommended technologies are Apple system frameworks with comprehensive official documentation, WWDC sessions, and multi-year community validation. Zero third-party dependencies eliminate version/policy risk. |
| Features | HIGH | Competitive analysis verified through App Store listings, feature pages, and user reviews for Watermarkly, eZy Watermark, EXIFrame, OneLine, and Canva. The "share without save" whitespace was validated by searching all major competitors — none advertise this workflow. |
| Architecture | HIGH | MVVM with @Observable, Core Image filter graph, extension-as-thin-shell, and async processing pipeline are all established iOS patterns. Project structure (shared Swift Package + thin extension targets) is the Apple-recommended approach for multi-target apps. |
| Pitfalls | HIGH | All 10 pitfalls are sourced from official documentation (Apple AVFoundation/Core Image/ImageIO docs), WWDC session warnings, and consistent community post-mortems across Stack Overflow and developer forums. HDR gain map behavior is specifically called out in Apple's "Supporting HDR images in your app" (WWDC24). |

**Overall confidence: HIGH.** All four research areas have strong primary source coverage. The few gaps are empirical (exact PHAdjustmentData limits, specific Video HDR encoder behavior on device) and will be resolved during phase-planning Spikes.

### Gaps to Address

- **Exact HDR preservation guarantees for competitors (Watermarkly, eZy Watermark):** Their documentation is unclear on HDR handling. We infer they strip HDR based on user reports of "washed out" exports. This needs validation by downloading and testing the top 5 competitors with HDR test photos. Handle during planning: mark as "validate competitor HDR behavior" in the requirements phase.
- **PHAdjustmentData size limit:** Apple does not document the exact byte limit. Community reports suggest it is very small (likely <1KB). Needs empirical testing with progressively larger payloads on device before Phase 6. Handle during Phase 6 planning: Spike with size-limit discovery.
- **Video HDR encoder behavior across iPhone models:** AVAssetWriter HDR configuration may behave differently on A14 vs A17 chips due to hardware encoder differences. Needs testing matrix during Phase 4 planning. Handle: Spike with Dolby Vision test footage on oldest and newest supported devices.
- **Share extension memory behavior on specific devices:** The ~120 MB limit is a guideline — actual behavior varies by device RAM and system state. Needs physical device testing across the supported device range. Handle during Phase 5 execution: test on the oldest supported device with 48MP ProRAW as worst case.

## Sources

### Primary (HIGH confidence)
- Apple Developer Documentation — Core Image, AVFoundation, ImageIO, PhotosUI, PHContentEditingController, App Extension Programming Guide
- Apple WWDC Sessions (2020-2024) — "Supporting HDR images in your app," "What's new in SwiftUI," "What's new in Photos," HDR video editing pipeline
- Swift Evolution — SE-0395: Observation Framework (@Observable macro)
- Apple App Store — Competitive listings for Watermarkly, eZy Watermark, EXIFrame, OneLine, Canva
- Greg Benz Photography — Technical analysis of Apple HDR gain map architecture

### Secondary (MEDIUM confidence)
- Stack Overflow, Apple Developer Forums — Community validation of CGImageSource→CGImageDestination metadata preservation, CIImage coordinate system handling, share extension memory debugging
- Kodeco (formerly raywenderlich.com) — AVVideoCompositionCoreAnimationTool patterns
- Community post-mortems (forasoft.com, nonstrict.eu) — HDR metadata preservation challenges during custom AVVideoComposition
- Industry analysis (2025-2026) — iOS 18 minimum target recommendation for new apps; 95%+ adoption coverage
- "Taken by: iPhone" trend analysis — 3dotsdesign.in, lemon8-app.com, medium.com, RoutineHub Shortcuts

### Tertiary (LOW confidence — needs validation)
- Competitor HDR behavior for Watermarkly, eZy Watermark — inferred from user reports; not verified through direct testing
- Exact PHAdjustmentData size limit — inferred from community reports; not documented by Apple

---

*Research completed: 2026-06-17*
*Ready for roadmap: yes*
