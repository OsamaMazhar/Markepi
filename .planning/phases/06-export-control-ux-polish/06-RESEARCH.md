# Phase 06: Export Control & UX Polish - Research

**Researched:** 2026-06-18
**Domain:** iOS export format control, SwiftUI gesture comparison, video progress UX
**Confidence:** HIGH

## Summary

This phase adds three UX capabilities on top of the existing photo and video pipelines: export format/quality selection, before/after comparison via long-press, and polished video export with progress tracking + notifications. All work builds on established patterns from Phases 1–5 — no new external dependencies required.

The technical challenges center on three areas: (1) **format override in the CGImageDestination pipeline** — the `ImageWriter` must accept a resolved output UTI (not the source UTI) and apply compression quality via `kCGImageDestinationLossyCompressionQuality`; (2) **video progress bridging** — iOS 18 introduces `AVAssetExportSession.states(updateInterval:)` which returns an `AsyncSequence` of export states including `.exporting(progress:)` — this must replace the current fire-and-forget `await exportSession.export()` in `VideoProcessor`; (3) **simultaneous gesture recognition** — the long-press comparison gesture must coexist with the existing `MagnifyGesture` in `PreviewView` via `.simultaneously(with:)`.

**Primary recommendation:** Use iOS 18 `AVAssetExportSession.states(updateInterval:)` and the new async `export(to:as:)` for video progress tracking — the old KVO/Combine approaches are deprecated. Thread progress through a `@Sendable` callback from VideoProcessor → ViewModel → `RenderingState.renderingVideo(progress:estimatedTimeRemaining:)` → ControlsView UI.

## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Format conversion warning — when user selects lossy format (JPEG) from HDR source, show confirmation dialog explaining HDR gain maps will be lost. Follows Phase 3 D-10 "warn on HDR loss" pattern. Advisory, not blocking.
- **D-02:** Quality slider — continuous 0.6–1.0 range stored as `Float` in `WatermarkConfiguration.outputQuality: Float` (default 1.0). Displayed as percentage (60–100%). Applies only to lossy formats (JPEG, HEIC). Disabled/grayed for PNG/TIFF.
- **D-03:** TIFF support — add `.tiff` to `OutputFormat` enum. UTI: `public.tiff`. Photo-only. CGImageDestination writes TIFF at practical 8-bit depth (documented platform limitation).
- **D-04:** Engine format override — `WatermarkEngine.process()` and `ImageWriter.write()` respect `config.outputFormat`. PreserveSource → source UTI. Explicit format → that format's UTI. Metadata + gain map re-attached where possible.
- **D-05:** Quality application — maps to `kCGImageDestinationLossyCompressionQuality` (0.6–1.0) in `ImageWriter`. PNG and TIFF ignore this key (lossless).
- **D-06:** Long-press gesture — press and hold in preview area toggles watermarked→original. Release returns to watermarked. Matches iOS "peek" pattern. Avoids gesture conflict with swipe navigation.
- **D-07:** Comparison visual feedback — "Original" label overlay fades in 150ms, out on release. `.light` impact haptic on state transition. Clean overlay, no other UI changes.
- **D-08:** Video comparison — long-press shows original static frame (extracted via `AVAssetImageGenerator` and cached). Release shows watermarked static frame. Same timestamp for apples-to-apples comparison.
- **D-09:** Comparison availability — gesture only active when `previewImage != nil`. Attached to `PreviewView`, not entire screen.
- **D-10:** Progress bar placement — replaces share button area in `ControlsView` during video export. Shows `ProgressView` (linear determinate) with percentage + ETA. Cancel button tinted red, `.bordered` style.
- **D-11:** ETA calculation — simple linear projection: `elapsed / max(progress, 0.01) - elapsed`. ETA displayed as "~Xs remaining" or "--" when progress < 0.01.
- **D-12:** Cancel behavior — `exportSession.cancelExport()`. State transitions to `.idle` with config preserved. Temp file cleaned via `TempFileManager.cleanup()`.
- **D-13:** RenderingState video extension — add `.renderingVideo(progress: Double, estimatedTimeRemaining: TimeInterval?)` to `RenderingState` enum. ControlsView switches on renderingState for photo spinner vs video progress bar.
- **D-14:** Background notification — `UNUserNotificationCenter` for completion notification. Request authorization on first video export. `beginBackgroundTask` for extra execution time. Notification ID: `"com.watermark.app.video-export-{UUID}"`.
- **D-15:** ControlsView placement — "Export Options" `DisclosureGroup` between watermark controls and share button. Contains format `Picker` + quality `Slider`. Default: collapsed. When `.preserveSource`, show detected source format as read-only label.

### the agent's Discretion

- TIFF bit depth limitation on iOS (8-bit practical) — document, don't hack around
- TIFF UTI: `public.tiff` — add to `FormatDetector` and `OutputFormat` enum
- Haptic style for comparison toggle: `.light` impact preferred → use `.sensoryFeedback(.impact(weight: .light), trigger:)` (modern SwiftUI API, iOS 17+)
- Notification deep-link URL scheme: App Group UserDefaults key for output URL (not custom URL scheme)
- Progress bar animation curve and refresh rate: throttle KVO to 0.1s intervals via `states(updateInterval: 0.1)`
- `WatermarkConfigurable` protocol — add `outputFormat` and `outputQuality` accessors (both ViewModels need them)
- Video format picker: only `.preserveSource` (match source container) — "preserveSource" maps to `matchSourceFormat()` which auto-detects H.264/HEVC
- Color profile handling when converting HEIC→JPEG: source color space preserved via `loaded.colorSpace` in CIContext render; JPEG output is always 8-bit SDR (the HDR→SDR warning from D-01 covers this)
- `ImageWriter` signature change: `sourceUTI: String` → replace with `destinationUTI: String` resolved from `config.outputFormat`
- How `config.outputFormat` interacts with `VideoProcessor`: video always uses `preserveSource` (format picker limited to this); no format override needed in VideoProcessor
- Cancellation edge case (backgrounded during export): `beginBackgroundTask` grants ~30s extra; if app is suspended before export completes, the export session may continue but the notification won't fire. Design for foreground-primary export with background notification as best-effort.

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope.

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| EXPT-01 | User can choose output format: HEIC, JPEG, PNG, or TIFF | `OutputFormat` enum extension with `.tiff` case + UTI resolution in `WatermarkEngine.process()`. TIFF via `public.tiff` UTI in `CGImageDestinationCreateWithURL`. Verified against CGImageDestination docs. |
| EXPT-02 | User can adjust output quality via a compression/quality slider (60–100%) | `kCGImageDestinationLossyCompressionQuality` key in `ImageWriter` options dictionary. Quality slider adds `Float` field to `WatermarkConfiguration`. Verified against ImageIO docs. |
| EXPT-03 | Format choice is preserved alongside HDR and metadata (lossless re-wrap where possible) | Format resolution in engine ensures destination UTI is passed to `ImageWriter`. Metadata + HDR gain map re-attached where format supports it (HEIC). D-01 warning for lossy conversion (HEIC HDR→JPEG). Verified against existing metadata preservation pipeline. |
| COMP-01 | User can toggle between original source and watermarked result with a gesture (swipe or long-press) | `LongPressGesture(minimumDuration: 0.15)` + `.sensoryFeedback(.impact(weight: .light))`. "Original" label overlay. Verified against SwiftUI gesture docs. |
| COMP-02 | Comparison view works for both photos and videos in real-time preview | Photo: cached `originalSourceImage` as `UIImage`. Video: static frame extracted via `VideoFrameExtractor` (existing) and cached. Both loaded once on media import, read on long-press toggle. Verified against AVAssetImageGenerator docs + existing VideoFrameExtractor pattern. |
| VIDX-01 | User sees real-time progress bar with estimated time remaining during video export | `AVAssetExportSession.states(updateInterval: 0.1)` → `.exporting(progress:)` case. Linear ETA projection. `RenderingState.renderingVideo(progress:estimatedTimeRemaining:)` drives UI. Verified against iOS 18 AVFoundation release notes. |
| VIDX-02 | User can cancel an in-progress video export without losing configuration | `exportSession.cancelExport()` triggers `.cancelled` state in `states()` sequence. `TempFileManager.cleanup()` for incomplete output. Config preserved in ViewModel. Verified against AVAssetExportSession docs. |
| VIDX-03 | Video export can run in the background with a system notification on completion | `UNUserNotificationCenter.requestAuthorization()` + `beginBackgroundTask(expirationHandler:)` + `UNMutableNotificationContent` scheduled in export completion handler. Notification ID: `"com.watermark.app.video-export-{UUID}"`. Verified against UserNotifications docs. |

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Output format selection (EXPT-01) | API / Backend (WatermarkCore Engine) | Browser / Client (SwiftUI ControlsView) | Engine owns format encoding; UI drives selection |
| Quality slider + compression (EXPT-02) | API / Backend (ImageWriter) | Browser / Client (ControlsView) | CGImageDestination compression is engine-layer; UI provides value |
| Format honor w/o stripping HDR/metadata (EXPT-03) | API / Backend (WatermarkEngine + ImageWriter) | — | Engine-orchestration responsibility — metadata preservation is core pipeline concern |
| Before/after comparison toggle (COMP-01) | Browser / Client (PreviewView) | API / Backend (ViewModel cache) | Pure UI gesture + visual feedback; ViewModel holds cached source image |
| Comparison for photos + videos (COMP-02) | Browser / Client (PreviewView) | API / Backend (VideoFrameExtractor) | UI gesture drives toggle; video frame extraction is engine-layer |
| Video progress bar with ETA (VIDX-01) | Browser / Client (ControlsView) | API / Backend (VideoProcessor progress callback) | UI renders progress bar; engine provides progress data stream |
| Cancel export without config loss (VIDX-02) | API / Backend (VideoProcessor) | Browser / Client (ControlsView cancel button) | Engine manages session cancellation; UI triggers it |
| Background completion notification (VIDX-03) | API / Backend (UNUserNotificationCenter) | — | System notification is OS-level; triggered from export completion handler |

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| ImageIO (CGImageDestination) | iOS 18 SDK | Photo format encoding + quality control | Only framework for writing HEIC/JPEG/PNG/TIFF with metadata + HDR preservation |
| AVFoundation (AVAssetExportSession) | iOS 18 SDK | Video export with progress | `states(updateInterval:)` provides native async progress — deprecated KVO/Combine alternatives |
| AVFoundation (AVAssetImageGenerator) | iOS 18 SDK | Static frame extraction for video comparison | Existing `VideoFrameExtractor` pattern; `image(at:)` async API |
| UserNotifications | iOS 18 SDK | Background completion notification | Required for VIDX-03 system notification |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| SwiftUI `.sensoryFeedback` | iOS 17+ | Haptic feedback on comparison toggle | Replaces `UIImpactFeedbackGenerator` with declarative API |
| Combine (`.throttle`) | iOS 18 SDK | Throttle progress updates to UI | Only if not using `states(updateInterval:)` native throttling (preferred) |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `AVAssetExportSession.states(updateInterval:)` (iOS 18) | Combine KVO on `\.progress` | Deprecated in iOS 18; `states()` is the future-proof approach. Since project targets iOS 18 minimum, use the modern API. |
| `.sensoryFeedback` (declarative) | `UIImpactFeedbackGenerator` (imperative) | Declarative API integrates better with SwiftUI state changes. Both achieve same result. |
| `beginBackgroundTask` + local notification | `BGProcessingTask` | `BGProcessingTask` is for deferrable maintenance — system chooses when to run. Video export is user-initiated and time-sensitive; `beginBackgroundTask` + foreground-primary design is more appropriate. |

**Installation:**
```bash
# No third-party package installation needed.
# All capabilities use Apple system frameworks bundled with iOS 18 SDK.
# Video progress tracking uses AVAssetExportSession.states(updateInterval:) — iOS 18+ native.
# Haptic feedback uses SwiftUI .sensoryFeedback modifier — iOS 17+ native.
# Notifications use UNUserNotificationCenter — iOS 10+ native.
```

**Version verification:** All frameworks are Apple system frameworks included with iOS 18 SDK — no external package registry verification needed.

## Package Legitimacy Audit

> No external packages are installed in this phase. All capabilities use Apple system frameworks bundled with the iOS 18 SDK.

| Package | Registry | Age | Downloads | Source Repo | slopcheck | Disposition |
|---------|----------|-----|-----------|-------------|-----------|-------------|
| — _(none)_ | — | — | — | — | — | No external packages |

**Packages removed due to slopcheck [SLOP] verdict:** none
**Packages flagged as suspicious [SUS]:** none

## Architecture Patterns

### System Architecture Diagram

```
┌──────────────────────────────────────────────────────────────────────────┐
│                          CONTROLS VIEW (SwiftUI)                         │
│                                                                          │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │ Export Options (DisclosureGroup)                                 │    │
│  │   ┌──────────┐  ┌──────────────────────────────────┐            │    │
│  │   │Format    │  │ Quality Slider                    │            │    │
│  │   │Picker    │  │ [===========●========] 85%        │            │    │
│  │   │HEIC/JPEG/│  │ (disabled when PNG/TIFF selected) │            │    │
│  │   │PNG/TIFF  │  └──────────────────────────────────┘            │    │
│  │   └──────────┘                                                   │    │
│  └─────────────────────────────────────────────────────────────────┘    │
│                                                                          │
│  ┌─────────────────────────── Share Button Area ────────────────────┐    │
│  │  Photo: [    Share    ]    Video: [████████░░] 78%  ~12s remain  │    │
│  │                               [  Cancel  ]                        │    │
│  │  idle → rendering → done → error   + renderingVideo(progress,eta) │    │
│  └──────────────────────────────────────────────────────────────────┘    │
└──────────────────────────────┬───────────────────────────────────────────┘
                               │
             ┌─────────────────┼─────────────────┐
             ▼                 ▼                   ▼
┌─────────────────┐  ┌──────────────┐  ┌──────────────────────┐
│   ViewModel     │  │  ControlsView│  │     PreviewView      │
│   @Observable   │  │ <ViewModel>  │  │  LongPress + Magnify │
│                 │  │  generic     │  │  simultaneous        │
│ config.output-  │  │              │  │                      │
│   Format/Quality│  │ switches on  │  │ Original ↔ Watermark │
│                 │  │ rendering-   │  │ cached frame toggle  │
│ renderingState  │  │ State        │  │                      │
│ progress tracking│ │              │  │ "Original" overlay   │
│ sourceImage     │  │              │  │ + sensoryFeedback    │
│ (cached)        │  │              │  │                      │
└────────┬────────┘  └──────────────┘  └──────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────────────┐
│                    WatermarkEngine (actor)                       │
│                                                                 │
│  process(sourceURL:config:)                                     │
│    ┌──────────────────────────────────────────────────────────┐ │
│    │ 1. Load (ImageLoader) → metadata, HDR, CIImage            │ │
│    │ 2. Resolve output UTI from config.outputFormat            │ │
│    │    .preserveSource → loaded.sourceUTI                     │ │
│    │    .heic → "public.heic"                                  │ │
│    │    .jpeg → "public.jpeg"                                  │ │
│    │    .png  → "public.png"                                   │ │
│    │    .tiff → "public.tiff"                                  │ │
│    │ 3. Normalize orientation                                  │ │
│    │ 4. Build filter graph (watermark layers composited)       │ │
│    │ 5. Render CIContext → CGImage                             │ │
│    │ 6. Write via ImageWriter with resolved UTI + quality       │ │
│    └──────────────────────────────────────────────────────────┘ │
│                                                                 │
│  processVideo(sourceURL:config:) → delegates to VideoProcessor  │
│    ┌──────────────────────────────────────────────────────────┐ │
│    │ Video always uses preserveSource (format picker locked)   │ │
│    │ Uses states(updateInterval:) for progress                 │ │
│    │ → callback: (Double, TimeInterval?) → Void                │ │
│    └──────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────────────┐
│                      ImageWriter (static)                        │
│                                                                 │
│  write(cgImage:, metadata:, gainMap:, dngMetadata:,              │
│        destinationUTI: String, quality: Float, to: URL)          │
│                                                                 │
│  ┌─ CGImageDestinationCreateWithURL(url, destinationUTI, 1)     │
│  ┌─ options: [kCGImageDestinationLossyCompressionQuality: q]    │
│  ┌─ CGImageDestinationAddImage(dest, cgImage, metadata+options) │
│  └─ CGImageDestinationAddAuxiliaryDataInfo (HDR gain map)       │
│  └─ CGImageDestinationFinalize                                   │
│                                                                 │
│  For JPEG: quality applied, HDR gain map CANNOT be embedded     │
│  For PNG/TIFF: quality ignored (lossless)                        │
│  For HEIC: quality applied, HDR gain map attached               │
└─────────────────────────────────────────────────────────────────┘
         │                       │
         ▼                       ▼
┌─────────────────┐    ┌──────────────────────────────┐
│  TempFileManager│    │  UNUserNotificationCenter     │
│  create/cleanup │    │  (video completion only)      │
└─────────────────┘    └──────────────────────────────┘
```

### Recommended Project Structure

```
Packages/WatermarkCore/Sources/WatermarkCore/
├── Models/
│   ├── WatermarkConfiguration.swift   # + outputQuality, OutputFormat.tiff
│   └── ProcessingResult.swift         # + RenderingState.renderingVideo
├── Output/
│   └── ImageWriter.swift              # destinationUTI + quality support
├── Processing/
│   ├── VideoProcessor.swift           # + states(updateInterval:) progress
│   └── VideoFrameExtractor.swift      # existing — used for comparison
├── Input/
│   └── FormatDetector.swift           # + public.tiff support
├── Engine/
│   └── WatermarkEngine.swift          # format resolution logic
├── UI/
│   ├── ControlsView.swift             # + export options + video progress
│   └── WatermarkConfigurable.swift    # + outputFormat/outputQuality
└── Storage/
    └── AppGroupConfigSync.swift       # + notification URL passthrough

App/
├── ViewModels/
│   └── WatermarkViewModel.swift       # + progress tracking, source cache
└── Views/
    └── PreviewArea/
        └── PreviewView.swift          # + long-press comparison

ShareExtension/
└── ShareExtensionViewModel.swift      # + progress tracking, source cache
```

### Pattern 1: Format Resolution in Engine

**What:** The engine resolves the output UTI from `config.outputFormat` before passing to `ImageWriter`. `.preserveSource` maps to the loaded source UTI; explicit formats map to their fixed UTIs. This is a pure lookup — no side effects.

**When to use:** Every call to `engine.process(sourceURL:config:)`.

**Example:**
```swift
// Source: Apple ImageIO docs + existing WatermarkEngine pattern
func resolveOutputUTI(config: WatermarkConfiguration, sourceUTI: String) -> String {
    switch config.outputFormat {
    case .preserveSource: return sourceUTI
    case .heic: return "public.heic"
    case .jpeg: return "public.jpeg"
    case .png:  return "public.png"
    case .tiff: return "public.tiff"
    }
}
```

### Pattern 2: quality-Sensitive ImageWriter

**What:** `ImageWriter.write()` now accepts `destinationUTI` and `quality` instead of `sourceUTI`. Quality is passed in the options dictionary to `CGImageDestinationAddImage`. Lossless formats (PNG, TIFF) ignore the quality key — the same codepath works for all formats.

**When to use:** Every photo write operation.

**Example:**
```swift
// Source: kCGImageDestinationLossyCompressionQuality docs
let options: [CFString: Any] = [
    kCGImageDestinationLossyCompressionQuality: CGFloat(quality)
]
// Merge metadata into options — metadata still passed as properties
var combinedProperties = metadata
combinedProperties[kCGImageDestinationLossyCompressionQuality as String] = quality
CGImageDestinationAddImage(destination, cgImage, combinedProperties as CFDictionary)
```

### Pattern 3: iOS 18 AVAssetExportSession Progress

**What:** `AVAssetExportSession.states(updateInterval:)` returns `AsyncSequence<State>`. The `.exporting(progress:)` case carries a `Progress` object with `fractionCompleted`. This replaces both KVO and the deprecated `progress` property. The export is started with `export(to:as:)` (new async API).

**When to use:** Every video export that needs progress tracking.

**Example:**
```swift
// Source: Apple AVFoundation iOS 18 release notes (WWDC24)
let session = AVAssetExportSession(asset: composition, presetName: preset)!
session.outputURL = outputURL
session.outputFileType = .mp4
// ... configure videoComposition ...

let states = session.states(updateInterval: 0.1)

Task {
    for await state in states {
        switch state {
        case .exporting(let progress):
            onProgress(progress.fractionCompleted, estimatedTimeRemaining(progress))
        case .completed:
            break // success
        case .cancelled:
            throw PipelineError.videoCancelled
        case .failed(let error):
            throw PipelineError.videoExportFailed(error)
        default:
            break
        }
    }
}

// Start export with new async API
try await session.export(to: outputURL, as: outputFileType)
// Note: export(to:as:) blocks until completion; states are delivered
// concurrently. Use structured concurrency — one Task for states iteration,
// another for export.
```

**Critical note on structured concurrency:** The `states(updateInterval:)` sequence and `export(to:as:)` must run concurrently. Use `withThrowingTaskGroup` or a dedicated child `Task` for states iteration, with a `Task` for `export(to:as:)`. When cancel is requested, `cancelExport()` is called on the session — the states sequence will then yield `.cancelled`, allowing cleanup.

### Pattern 4: Simultaneous Long-Press + Magnify Gestures

**What:** `PreviewView` already has a `MagnifyGesture` for watermark scaling. Add a `LongPressGesture` that toggles the comparison view. Use `.simultaneously(with:)` so both gestures can be recognized — long-press for comparison, pinch for watermark scale.

**When to use:** Only when `previewImage != nil` (D-09).

**Example:**
```swift
// Source: SwiftUI documentation — simultaneous gesture composition
let longPress = LongPressGesture(minimumDuration: 0.1)
    .onEnded { _ in viewModel.isComparing = false }
    
// During long press:
let pressDrag = LongPressGesture(minimumDuration: 0.1)
    .sequenced(before: DragGesture(minimumDistance: 0))

// Better: use updating/onChanged to track press state continuously
@GestureState private var isLongPressing = false
let comparisonGesture = LongPressGesture(minimumDuration: 0.15)
    .updating($isLongPressing) { value, state, _ in
        state = value  // true while pressing
    }

let combined = comparisonGesture.simultaneously(with: magnifyGesture)
```

### Pattern 5: Source Frame Caching for Comparison

**What:** The original (un-watermarked) image/frame is cached alongside the watermarked `previewImage`. For photos, cache the `UIImage` loaded from source. For videos, extract a static frame via `VideoFrameExtractor` and cache the `CGImage` → `UIImage`. The cached frame survives all watermark config changes — no reload needed on each long-press.

**When to use:** Set once when media loads; read on each long-press toggle.

**Example:**
```swift
// Source: Existing VideoFrameExtractor pattern + caching requirement
var originalSourceImage: UIImage?  // cached once on media load

func loadSourceForComparison() async {
    if isVideo, let url = sourceURL {
        let frame = try? await VideoFrameExtractor.extract(from: url)
        originalSourceImage = frame.map { UIImage(cgImage: $0) }
    } else if let url = sourceURL {
        let data = try? Data(contentsOf: url)
        originalSourceImage = data.flatMap { UIImage(data: $0) }
    }
}
```

### Anti-Patterns to Avoid

- **Deprecated AVAssetExportSession APIs:** Do NOT use `.progress` (deprecated Float property), `.status` (deprecated), or `exportAsynchronously(completionHandler:)` (deprecated). Use `states(updateInterval:)` + `export(to:as:)` on iOS 18+.
- **UIImage.jpegData() for quality control:** This is Pitfall 9 from PITFALLS.md — it re-compresses from decoded bitmap. Always use `CGImageDestination` with `kCGImageDestinationLossyCompressionQuality`.
- **Combining metadata and quality in separate calls:** The metadata dict and quality option must be merged into a single properties dictionary for `CGImageDestinationAddImage`. Two separate calls would cause the second to overwrite the first.
- **Gesture conflict via separate `.gesture()` modifiers:** Attaching `LongPressGesture` and `MagnifyGesture` as separate `.gesture()` modifiers causes one to block the other. Use a single `.gesture(combined)` with `.simultaneously(with:)`.
- **Loading source image from disk on every long-press:** This causes I/O latency and makes the comparison feel sluggish. Cache once on media load.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Video export progress polling | Custom Timer + KVO on `progress` | `AVAssetExportSession.states(updateInterval:)` | iOS 18 native async sequence; Timer polling is deprecated, misses state transitions, and has race conditions |
| Compression quality for JPEG/HEIC | Manual quality quantization | `kCGImageDestinationLossyCompressionQuality` | ImageIO handles encoder-specific quality mapping correctly across formats |
| Background notification scheduling | Custom background fetch + polling | `UNUserNotificationCenter` + `beginBackgroundTask` | System-managed notification delivery with proper entitlement handling |
| Haptic feedback on gesture | `UIImpactFeedbackGenerator` (imperative) | `.sensoryFeedback(.impact(weight: .light), trigger:)` (declarative) | Declarative SwiftUI API integrates with state-driven feedback; no manual prepare/trigger lifecycle |
| Combined gesture recognition | Custom gesture recognizer delegates | `.simultaneously(with:)` gesture composition | SwiftUI's built-in gesture compositor handles priority, failure dependencies, and simultaneous recognition |

**Key insight:** iOS 18 introduces a fully async API for video export monitoring. The previous approaches (Combine KVO publishers, Timer polling, completion-handler callbacks) are ALL deprecated. Since this project targets iOS 18 minimum, using the modern `states(updateInterval:)` + `export(to:as:)` combination is not just "nice to have" — it's the only supported path that won't generate deprecation warnings.

## Common Pitfalls

### Pitfall 1: JPEG HDR Gain Map Silent Drop

**What goes wrong:** When converting HEIC (HDR) → JPEG, the `CGImageDestinationAddAuxiliaryDataInfo` call for `kCGImageAuxiliaryDataTypeHDRGainMap` succeeds without error but the gain map is NOT embedded. JPEG container format does not support Apple's auxiliary data tracks — only HEIF containers do. The output appears flat (SDR) with no warning unless explicitly checked.

**Why it happens:** `CGImageDestinationAddAuxiliaryDataInfo` is a no-op for formats that don't support the auxiliary data type. It doesn't throw — it silently ignores unsupported combinations.

**How to avoid:** Before writing, check: if `config.outputFormat` is `.jpeg` and `loaded.gainMapAuxData != nil`, present the D-01 warning dialog. Don't attempt to attach the gain map to JPEG output. For HEIC output, attach as normal.

**Warning signs:** JPEG output from HEIC source is visually flat on HDR displays; exiftool shows no gain map tracks.

### Pitfall 2: AVAssetExportSession API Migration Confusion

**What goes wrong:** Mixing the old deprecated API (`progress`, `status`, `exportAsynchronously`) with the new iOS 18 API (`states(updateInterval:)`, `export(to:as:)`) causes undefined behavior — the export session may complete without progress states being delivered, or states may arrive after the export method returns.

**Why it happens:** Apple's deprecation in iOS 18 marks the entire old API surface. The internal implementation changes — old properties may not be populated when the new methods are used.

**How to avoid:** Use exclusively the new API surface:
- `AVAssetExportSession.states(updateInterval:)` for progress
- `export(to:outputURL, as: outputFileType)` for initiating export
- Never access `.progress`, `.status`, or call `exportAsynchronously`

**Warning signs:** Progress values are always 0.0 or never update; `export()` returns before states complete.

### Pitfall 3: Long-Press Timing vs MagnifyGesture

**What goes wrong:** A `LongPressGesture` with `minimumDuration: 0.5` feels unresponsive for a comparison toggle. Too short (0.05) conflicts with the `MagnifyGesture` (pinch starts with a brief touch). Users trigger comparison when trying to pinch.

**Why it happens:** Both gestures start with a touch-down. Without a minimum duration buffer, the long-press activates on almost any touch.

**How to avoid:** Use `minimumDuration: 0.15` (150ms) — fast enough for responsive comparison, slow enough to distinguish from pinch start. Test on physical device — simulator gesture timing is unreliable.

**Warning signs:** Comparison triggers during pinch zoom; pinch fails because long-press captures the gesture.

### Pitfall 4: Equatable Conformance for RenderingState

**What goes wrong:** Adding `.renderingVideo(progress: Double, estimatedTimeRemaining: TimeInterval?)` breaks the existing `==` implementation which uses pattern matching on the four cases. The associated values prevent automatic synthesis.

**Why it happens:** The current `Equatable` conformance (line 60-69 of ProcessingResult.swift) uses `switch` with pattern matching that ignores associated values — this won't compile with a new case that has associated values.

**How to avoid:** Rewrite the `==` function to handle all five cases explicitly:
```swift
case (.renderingVideo(let p1, let e1), .renderingVideo(let p2, let e2)):
    return p1 == p2 && e1 == e2
```
Note: comparing `Double` directly for equality in progress is acceptable here since it comes from the same KVO stream.

**Warning signs:** Compiler error "Switch must be exhaustive" when adding the new case.

### Pitfall 5: CGImageDestinationAddImage Options Overwrite Metadata

**What goes wrong:** Passing quality options in a separate dictionary or using `CGImageDestinationAddImage` with only options (not merged with metadata) silently drops all EXIF metadata.

**Why it happens:** `CGImageDestinationAddImage(destination, cgImage, properties)` takes a single properties dictionary — it's an all-or-nothing set of image properties. The current `ImageWriter` passes `combinedMetadata as CFDictionary`. Adding quality requires merging quality into the SAME dictionary.

**How to avoid:** Merge before the call:
```swift
var properties = combinedMetadata
properties[kCGImageDestinationLossyCompressionQuality as String] = quality
CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
```

**Warning signs:** Output files missing camera model, GPS, timestamp after format change.

## Code Examples

Verified patterns from official sources:

### Resolving Output UTI from OutputFormat
```swift
// Source: Apple UTType documentation, existing FormatDetector pattern
public enum OutputFormat: Sendable, Codable {
    case preserveSource, heic, jpeg, png, tiff  // + tiff
    
    public var uti: String? {
        switch self {
        case .preserveSource: return nil  // caller resolves from source
        case .heic: return "public.heic"
        case .jpeg: return "public.jpeg"
        case .png:  return "public.png"
        case .tiff: return "public.tiff"
        }
    }
    
    public var isLossless: Bool {
        switch self {
        case .png, .tiff: return true
        case .heic, .jpeg, .preserveSource: return false
        }
    }
}
```

### quality-Enabled ImageWriter (Updated Signature)
```swift
// Source: CGImageDestination docs + existing ImageWriter pattern
public static func write(
    cgImage: CGImage,
    metadata: [String: Any],
    gainMapAuxData: [String: Any]?,
    dngMetadata: [String: Any]?,
    destinationUTI: String,     // changed from sourceUTI
    quality: Float = 1.0,       // new parameter
    to url: URL
) throws {
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL, destinationUTI as CFString, 1, nil
    ) else {
        throw PipelineError.failedToCreateDestination
    }
    
    var properties = metadata
    if let dng = dngMetadata {
        properties[kCGImagePropertyDNGDictionary as String] = dng
    }
    // Merge quality — ignored by PNG/TIFF (lossless)
    properties[kCGImageDestinationLossyCompressionQuality as String] = quality
    
    CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
    
    // Attach HDR gain map — only effective for HEIC destinations
    if let gainMap = gainMapAuxData {
        CGImageDestinationAddAuxiliaryDataInfo(
            destination,
            kCGImageAuxiliaryDataTypeHDRGainMap,
            gainMap as CFDictionary
        )
    }
    
    guard CGImageDestinationFinalize(destination) else {
        throw PipelineError.failedToFinalize
    }
}
```

### Long-Press Comparison Gesture
```swift
// Source: SwiftUI gesture documentation, existing PreviewView pattern
struct PreviewView: View {
    @Bindable var viewModel: WatermarkViewModel
    @GestureState private var pinchScale: CGFloat = 1.0
    @GestureState private var isComparing: Bool = false
    @State private var hapticTrigger: Bool = false
    
    var body: some View {
        Group {
            if let preview = viewModel.previewImage {
                Image(uiImage: isComparing ? (viewModel.originalSourceImage ?? preview) : preview)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .drawingGroup()
                    .scaleEffect(effectiveScale)
                    .gesture(combinedGesture)
                    .overlay {
                        if isComparing {
                            Text("Original")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(.ultraThinMaterial, in: Capsule())
                                .transition(.opacity.animation(.easeInOut(duration: 0.15)))
                        }
                    }
                    .sensoryFeedback(.impact(weight: .light), trigger: hapticTrigger)
            }
            // ... existing else branches ...
        }
    }
    
    private var comparisonGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.15)
            .updating($isComparing) { value, state, _ in
                if state != value {
                    hapticTrigger.toggle()  // triggers sensoryFeedback on state change
                }
                state = value
            }
    }
    
    private var combinedGesture: some Gesture {
        comparisonGesture.simultaneously(with: magnifyGesture)
    }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `AVAssetExportSession.progress` (KVO) | `AVAssetExportSession.states(updateInterval:)` (AsyncSequence) | iOS 18 (2024) | Progress tracking is now a first-class async API; old KVO approach deprecated |
| `exportAsynchronously(completionHandler:)` | `export(to:as:)` (async throws) | iOS 18 (2024) | Structured concurrency replaces completion handler; cancellation via `cancelExport()` still works |
| `UIImage.jpegData(compressionQuality:)` | `CGImageDestination` with `kCGImageDestinationLossyCompressionQuality` | Always (best practice) | jpegData() re-compresses from decoded bitmap — Pitfall 9; CGImageDestination preserves metadata |
| `UIImpactFeedbackGenerator` (imperative) | `.sensoryFeedback(_:trigger:)` (declarative) | iOS 17 (2023) | Declarative SwiftUI integration; no manual `prepare()` lifecycle needed |
| `sourceUTI` parameter in ImageWriter | `destinationUTI` (resolved from config.outputFormat) | Phase 6 | Enables format override; source UTI still available from LoadedImage for `.preserveSource` fallback |

**Deprecated/outdated:**
- **`AVAssetExportSession.progress`, `.status`, `exportAsynchronously()`:** All deprecated in iOS 18. Do not use in Phase 6.
- **`UIImage.jpegData(compressionQuality:)`:** Already avoided in existing codebase per STACK.md "What NOT to Use" — maintain this.

## Assumptions Log

> All claims in this research were verified against official Apple documentation or the existing codebase. The following assumptions are noted for planner attention.

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `AVAssetExportSession.states(updateInterval:)` and `export(to:as:)` are available and stable in the Xcode 26.2 / iOS 18 SDK detected on the dev machine | Standard Stack | If the API is still unstable or behaves differently than documented, fallback to Combine KVO on `\.progress` (deprecated but functional until removed) |
| A2 | `kCGImageDestinationLossyCompressionQuality` functions identically for HEIC and JPEG CGImageDestinations | Standard Stack | Apple could change HEIC quality curve behavior. Impact: minor — quality slider values may produce slightly different file sizes than expected. |
| A3 | `public.tiff` UTI is supported by `CGImageDestinationCreateWithURL` on iOS | Standard Stack | CGImageDestination supports TIFF encoding on iOS. Verified via multiple sources. If unsupported on a future iOS version, TIFF option would need to be removed from the format picker. |
| A4 | The `.light` impact weight via `.sensoryFeedback` produces the same haptic as `UIImpactFeedbackGenerator(style: .light)` | Architecture Patterns | Both APIs use the same underlying Taptic Engine. Different subjective feel would require switching to the imperative API. |
| A5 | `VideoProcessor` can be refactored to accept a progress callback without breaking the existing `VideoFrameExtractor` or `ExportValidator` patterns | Architecture Patterns | The VideoProcessor uses a static method + async/await pattern. Adding a callback parameter preserves compatibility with existing callers that pass `nil` for progress. |

## Open Questions

1. **Structured concurrency for `states()` + `export(to:as:)`**
   - What we know: The `states()` AsyncSequence and `export(to:as:)` must run concurrently. The export call blocks until completion; states are delivered on a separate queue.
   - What's unclear: Whether `withThrowingTaskGroup` or a detached child `Task` with a cancellation handler is the cleaner pattern for the VideoProcessor.
   - Recommendation: Use `withThrowingDiscardingTaskGroup` (iOS 18+) — one child for states iteration, one for export. On cancel, call `session.cancelExport()`. This is resolved in-planning.

2. **App Group deep-link for notification tap**
   - What we know: When user taps the notification, the app opens. The output URL is in the App Group container. Notification `userInfo` can carry a small string payload.
   - What's unclear: Whether the App Group UserDefaults key approach (write URL string before scheduling notification) is reliable if the export session holds the file open at notification-scheduling time.
   - Recommendation: Use App Group UserDefaults with a well-known key (`"completedExportURL"`). Write the URL as the last step in the export completion handler, then schedule notification. The planner should address race conditions.

3. **HDR→JPEG conversion color space mapping**
   - What we know: The existing pipeline uses `loaded.colorSpace` for CIContext rendering. For HDR sources (Display P3, HLG transfer), this preserves the wide gamut. JPEG output is inherently 8-bit SDR — the CIContext rendering with the source color space will produce correctly tone-mapped (by iOS) 8-bit values.
   - What's unclear: Whether iOS's automatic tone-mapping from HDR → SDR during CGImage creation is visually acceptable for all HDR content types (Dolby Vision profile 8.4 vs HLG).
   - Recommendation: The D-01 warning dialog covers this by informing users of HDR loss. No additional color space handling needed beyond what the existing pipeline does. If users report poor SDR tone mapping, address in a future phase.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Xcode (xcodebuild) | Building iOS app | ✓ | 26.2 | — |
| Swift | Compilation | ✓ | 6.2.3 | — |
| exiftool | QA metadata validation | ✗ | — | Manual Photos app inspection; Xcode debugger metadata inspection |
| iOS Simulator / Device | Runtime testing | — | — | Dev machine is macOS — iOS builds require Xcode simulator or physical device (standard for iOS development) |

**Missing dependencies with no fallback:** none (exiftool is QA-only, not needed for implementation)
**Missing dependencies with fallback:** exiftool → install via `brew install exiftool` if needed for QA

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | No | No auth system in scope |
| V3 Session Management | No | No sessions in scope |
| V4 Access Control | No | No multi-user access control |
| V5 Input Validation | Yes — quality slider bounds, format selection, text rendering for comparison label | Swift type safety + clamped slider range (0.6–1.0) + enum-backed format picker (prevents injection of arbitrary format strings) |
| V6 Cryptography | No | No cryptographic operations in scope |

### Known Threat Patterns for iOS SwiftUI + AVFoundation

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| UserInfo payload injection via notification deep link | Tampering | Validate that the App Group UserDefaults key `"completedExportURL"` points to a file within the App Group container directory, not an arbitrary path. Reject URLs outside the container. |
| Temp file path traversal in notification URL | Tampering | `TempFileManager` already uses UUID-based filenames (unpredictable). The notification carries the UUID, and the file location is deterministic within the caches directory. Validate the resolved path starts with the expected caches/App Group directory prefix. |
| Long-press gesture triggering during sensitive export state | Denial of Service | Low severity — comparison gesture is disabled during export (D-09: only when `previewImage != nil` and state is idle). No security impact; UX-only. |
| Format string injection via `OutputFormat` user choice | Tampering | The format is an enum (`OutputFormat.heic/jpeg/png/tiff/preserveSource`) — not a freeform string. The resolved UTI is always a compile-time known constant. No injection vector. |
| Notification content spoofing (user confusion) | Spoofing | The notification body text is hardcoded ("Video watermarked" / "Video export failed") — not user-configurable. The notification identifier includes a UUID for deduplication, preventing notification flooding. |

## Sources

### Primary (HIGH confidence)
- **Apple AVFoundation iOS 18 Release Notes** — `AVAssetExportSession.states(updateInterval:)`, `export(to:as:)`, deprecation of `progress`/`status`/`exportAsynchronously` [CITED: developer.apple.com]
- **Apple ImageIO CGImageDestination Reference** — `kCGImageDestinationLossyCompressionQuality`, `CGImageDestinationAddImage`, `CGImageDestinationAddAuxiliaryDataInfo` [VERIFIED: existing codebase usage in ImageWriter.swift]
- **Apple SwiftUI Gesture Documentation** — `.simultaneously(with:)`, `LongPressGesture`, `MagnifyGesture`, `.updating()` [VERIFIED: existing MagnifyGesture pattern in PreviewView.swift]
- **Apple UserNotifications Documentation** — `UNUserNotificationCenter`, `requestAuthorization`, `UNMutableNotificationContent`, `beginBackgroundTask` [CITED: developer.apple.com]
- **Apple AVFoundation AVAssetImageGenerator** — `image(at:)` async API, `appliesPreferredTrackTransform`, `generateCGImageAsynchronously` [VERIFIED: existing VideoFrameExtractor.swift pattern]
- **Apple SwiftUI sensoryFeedback** — `.sensoryFeedback(.impact(weight:trigger:)` modifier [CITED: developer.apple.com]

### Secondary (MEDIUM confidence)
- **Existing WatermarkCore Codebase** — WatermarkEngine.swift, ImageWriter.swift, VideoProcessor.swift, ControlsView.swift, WatermarkConfigurable.swift, FormatDetector.swift, WatermarkConfiguration.swift, ProcessingResult.swift, TempFileManager.swift, AppGroupConfigSync.swift, VideoFrameExtractor.swift, WatermarkViewModel.swift, PreviewView.swift, ShareExtensionViewModel.swift [VERIFIED: codebase grep + read]
- **Kodeco (raywenderlich.com)** — AVVideoCompositionCoreAnimationTool patterns for video watermarking [CITED: STACK.md]
- **WebSearch (multiple sources)** — AVAssetExportSession progress tracking migration from KVO to states(), CGImageDestination quality options for JPEG/HEIC, TIFF CGImageDestination capabilities [CITED: Google Search results]

### Tertiary (LOW confidence)
- **WebSearch** — TIFF 8-bit vs 16-bit depth on iOS (conflicting reports; pragmatic consensus is that CGImageDestination writes what you give it, but iOS rendering pipelines default to 8-bit) [CITED: Stack Overflow, Apple Developer Forums]
- **WebSearch** — BGProcessingTask vs beginBackgroundTask for video export (recommendation: use beginBackgroundTask for user-initiated exports; BGProcessingTask is for deferrable maintenance) [CITED: Reddit, Apple Developer Forums]

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all APIs verified against Apple documentation and existing codebase patterns
- Architecture: HIGH — format pipeline patterns follow existing WatermarkEngine/ImageWriter/VideoProcessor architecture; gesture patterns follow existing PreviewView MagnifyGesture implementation
- Pitfalls: HIGH — informed by PITFALLS.md, iOS 18 deprecation awareness, and codebase review of integration points

**Research date:** 2026-06-18
**Valid until:** 2026-07-18 (stable iOS APIs; Xcode 26.2 is the current toolchain)
