# Phase 3: Video Processing & Share Extension - Research

**Researched:** 2026-06-17
**Domain:** iOS AVFoundation video watermarking + iOS Share Extension architecture
**Confidence:** HIGH

## Summary

This phase adds two major capabilities: (1) video watermarking via AVFoundation's `AVVideoCompositionCoreAnimationTool` with CALayer overlay, preserving source HDR/color/audio, and (2) an iOS share extension that receives photos and videos from other apps and provides identical watermarking UI. Both share the existing `WatermarkCore` Swift Package.

The video pipeline uses `AVMutableComposition` (video + audio tracks) → `AVMutableVideoComposition` + `AVVideoCompositionCoreAnimationTool` (CALayer hierarchy for watermark overlay) → `AVAssetExportSession` (source-matched output). The critical challenge is HDR preservation: CALayer rendering occurs in SDR color space by default, and explicit `AVVideoComposition` color properties plus CALayer extended-color-space configuration are needed to prevent HDR→SDR flattening. Per D-10, a fallback to SDR with tone mapping and user warning is required when HDR cannot be preserved.

The share extension hosts the same SwiftUI watermarking views (`ControlsView`, `PositionGridView`, etc.) from the main app via `UIHostingController` inside a `UIViewController` subclass. Media arrives via `NSItemProvider` (loaded with `loadFileRepresentation` for videos, `loadItem` for photos), and App Group `UserDefaults` synchronizes `WatermarkConfiguration` between extension and main app.

**Primary recommendation:** Build the video watermarking engine as a new `VideoProcessor` module inside the existing `WatermarkCore` package. Create a separate `ShareExtensionViewModel` that reuses all rendering code from the package. The CALayer overlay approach is the correct choice per D-01 — do NOT hand-roll a per-frame CIFilter pipeline for video. However, HDR preservation through CALayer compositing requires explicit color property configuration on both the `AVVideoComposition` and the export session, with a validated SDR fallback.

---

## User Constraints (from CONTEXT.md)

### Locked Decisions

| ID | Decision | Constraint |
|----|----------|------------|
| D-01 | Use AVVideoComposition + AVVideoCompositionCoreAnimationTool with CALayer overlay. Does NOT reuse CIFilter per-frame pipeline from WatermarkCore. | Video processing MUST use CALayer hierarchy, not CIFilter handlers |
| D-02 | Full watermark layer parity with photos — text watermark, image/logo watermark, and white frame with device attribution all render on video frames. | All existing WatermarkLayer types must work on video |
| D-03 | Video preview uses a single static representative frame (first or middle frame) with watermark overlay applied. No video render loop. | AVAssetImageGenerator for a single frame, then render through WatermarkCore compositing |
| D-04 | Preserve source video format — match container, codec, and bitrate. H.264 in → H.264 out, HEVC in → HEVC out. | AVAssetExportSession outputFileType must match source |
| D-05 | Full watermarking UI inside the extension — host the same SwiftUI watermarking views from the main app via UIHostingController. Complete parity. | Share extension hosts ControlsView, PositionGridView, etc. |
| D-06 | Extension flow: Configure → Render → Share. User sees config UI first, adjusts settings, taps Share, engine renders, share sheet opens. | No pre-rendering; render on Share tap |
| D-07 | One-shot workflow — after share sheet dismisses, call completeRequest and close the extension. | No return to config screen after share |
| D-08 | Sync watermark configuration between extension and main app via App Group UserDefaults. | Codable serialization of WatermarkConfiguration to/from UserDefaults(suiteName:) |
| D-09 | Validate all common HDR formats — Dolby Vision (profile 8.4), HLG, and HDR10. | Test and verify all three in output |
| D-10 | If HDR cannot be preserved (CALayer overlay strips it), fall back to SDR with tone mapping and show a warning to the user. | Do not silently drop HDR |
| D-11 | Passthrough all audio tracks from source intact — preserve stereo, spatial audio, multi-channel. | No mixdown; insert all audio tracks into composition |
| D-12 | Post-export validation — inspect output video tracks for HDR metadata and audio track count. Log warnings if anything was lost. | Validate after AVAssetExportSession completes |
| D-13 | Photos shared to the extension are processed inline via the existing WatermarkEngine. | Photo items in extension use WatermarkEngine.shared.process() |
| D-14 | Multi-item shares process all items sequentially — configure watermark once, apply to each item, show share sheet for each in sequence. | Sequential processing with config reuse |
| D-15 | NSExtensionActivationRule accepts photos, videos, and Live Photos. | SUBQUERY predicate: public.image, public.movie, com.apple.live-photo |
| D-16 | Unsupported media types offer to open in main app via URL scheme. | Dialog + URL scheme fallback |

### the agent's Discretion

- CALayer hierarchy design for watermark overlay layers (cascading vs sibling layers, frame-synced positioning)
- AVAssetExportSession preset selection for HDR preservation
- Export validation heuristic details (which metadata keys to check, tolerance thresholds)
- App Group UserDefaults serialization format for WatermarkConfiguration sync
- Multi-item sequential processing orchestration in ShareViewController
- UIHostingController integration pattern for hosting SwiftUI views in the extension
- NSItemProvider async loading strategy and error recovery
- Temp file lifecycle in extension sandbox (caches dir vs App Group container)
- ShareViewController lifecycle management with NSExtensionContext

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope.

---

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| MEDI-02 | User can receive photos and videos from other apps via iOS share sheet (app extension) | Share Extension architecture, NSExtensionActivationRule, NSItemProvider loading, UIHostingController pattern — all documented below |
| QUAL-04 | Video watermarking preserves HDR, color space, and audio tracks in output | AVVideoComposition color properties, AVAssetExportSession HDR configuration, audio track passthrough, post-export validation — documented below |

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Video watermark compositing (CALayer overlay) | API / Backend (WatermarkCore) | — | AVFoundation AVVideoCompositionCoreAnimationTool runs on CPU/GPU during export; no UI involvement |
| Video export with HDR preservation | API / Backend (WatermarkCore) | — | AVAssetExportSession configuration; encoder color properties set programmatically |
| Audio track passthrough | API / Backend (WatermarkCore) | — | AVMutableComposition track insertion; purely data-layer operation |
| Post-export validation | API / Backend (WatermarkCore) | — | CMFormatDescription inspection on exported asset; no UI |
| Static frame video preview | API / Backend (WatermarkCore) | Browser / Client (SwiftUI preview display) | AVAssetImageGenerator extracts frame (backend); SwiftUI Image displays it (client) |
| Share extension entry point | Frontend Server (Extension process) | — | UIViewController + UIHostingController; UIKit entry required by iOS extension lifecycle |
| Watermark configuration UI in extension | Browser / Client (SwiftUI) | — | Same SwiftUI views as main app; hosted via UIHostingController |
| NSItemProvider media loading | Frontend Server (Extension) | — | loadFileRepresentation / loadItem run in extension process; results fed to WatermarkCore |
| Config sync extension ↔ main app | Database / Storage (App Group) | — | UserDefaults(suiteName:) with Codable JSON serialization; file-based cross-process |
| Temp file lifecycle (extension) | Database / Storage (Extension sandbox) | — | cachesDirectory or App Group container; cleanup on extension dismissal |
| Photo processing in extension | API / Backend (WatermarkCore) | — | Delegates to existing WatermarkEngine.shared.process() |
| Multi-item sequential processing | Browser / Client (Extension ViewModel) | API / Backend (WatermarkCore) | ViewModel orchestrates sequential calls to WatermarkCore; user sees progress |

---

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| AVFoundation | iOS 18 SDK | Video composition, watermark overlay, export | Only framework for video track manipulation on iOS [VERIFIED: official docs via multiple search confirmations] |
| AVVideoCompositionCoreAnimationTool | iOS 18 SDK | CALayer-based video overlay compositing | Apple's sanctioned method for adding overlays to video during export; handles frame-by-frame compositing of CALayer hierarchies onto video tracks [CITED: kodeco.com/6236502-avfoundation-tutorial; Apple AVFoundation docs] |
| AVAssetExportSession | iOS 18 SDK | Video export with quality/format control | Standard export path; supports HEVC presets for HDR preservation, source format matching via determineCompatibility(ofExportPreset:with:outputFileType:) [CITED: developer.apple.com/documentation/avfoundation/avassetexportsession] |
| AVMutableComposition | iOS 18 SDK | Multi-track video + audio composition assembly | Required to insert video track (with overlay) and all audio tracks into a single output [CITED: kodeco.com tutorial pattern verified across multiple sources] |
| AVAssetImageGenerator | iOS 18 SDK | Static frame extraction for preview | Standard method for extracting single frames; supports async generation and transform application [CITED: developer.apple.com] |
| UserDefaults(suiteName:) | iOS 18 SDK | Cross-process config sync via App Group | Only IPC mechanism available between extension and main app for settings [CITED: developer.apple.com] |
| NSItemProvider | iOS 18 SDK | Share extension media import | Standard extension API for receiving shared items; loadFileRepresentation for videos, loadItem for photos [CITED: developer.apple.com] |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| CoreImage (CIContext) | iOS 18 SDK | Watermark layer rasterization for CALayer contents | When converting CIImage watermark layers to CGImage for setting as CALayer.contents [ASSUMED — pattern from existing WatermarkCore] |
| CoreGraphics | iOS 18 SDK | White frame + text overlay for video frames | When rendering the white frame border + device metadata text as CGImage for a CALayer sublayer [ASSUMED — same pattern as existing WhiteFrameRenderer] |
| UniformTypeIdentifiers | iOS 18 SDK | UTI-based type identification in extension | When checking NSItemProvider type conformance (UTType.movie, UTType.image) [CITED: developer.apple.com] |
| CoreVideo | iOS 18 SDK | HDR metadata extraction from CMFormatDescription | Post-export validation reading kCVImageBufferColorPrimariesKey, kCVImageBufferTransferFunctionKey [CITED: developer.apple.com, google search results] |

### Alternatives Considered

| Recommended | Alternative | Tradeoff |
|-------------|-------------|----------|
| AVAssetExportSession + CALayer overlay (D-01) | AVAssetWriter + CIFilter per-frame | AVAssetWriter gives full encoder control (bitrate, profile-level, HDR metadata insertion) but is significantly more complex — requires frame-by-frame pixel buffer reading/writing. CALayer overlay is simpler and sufficient for watermarking. AVAssetWriter should be considered as fallback if HDR preservation through CALayer proves impossible on device. |
| AVVideoComposition with nil color properties (propagate source) | Explicit HDR color properties set on AVMutableVideoComposition | Nil propagation is simpler but CALayer overlay may default to sRGB rendering. Explicit properties ensure consistent HDR pipeline. |
| AVAssetExportSession outputFileType matching source | Forced HEVC output for all sources | Matching source preserves quality intent; forcing HEVC adds unnecessary transcode for H.264 sources. Use determineCompatibility() to validate. |
| NSItemProvider.loadFileRepresentation for videos | NSItemProvider.loadItem for videos | loadFileRepresentation provides file URL (memory-efficient); loadItem may load entire video into memory causing extension jetsam. |

**Installation:**

```bash
# No package manager needed. All frameworks are Apple system frameworks included with iOS 18 SDK.
# The WatermarkCore Swift Package already exists. Video processing will be added as new source files.
# Share extension target created via Xcode: File > New > Target > Share Extension
```

**Version verification:** All frameworks are part of iOS 18 SDK (Xcode 18). No third-party packages are installed. Apple framework versions are tied to the SDK version.

## Package Legitimacy Audit

> No third-party packages are required for this phase. All functionality uses Apple system frameworks (AVFoundation, CoreImage, CoreGraphics, UniformTypeIdentifiers, CoreVideo) included with iOS 18 SDK.

| Package | Registry | Age | Downloads | Source Repo | slopcheck | Disposition |
|---------|----------|-----|-----------|-------------|-----------|-------------|
| — (none) | — | — | — | — | — | No external packages needed |

**Packages removed due to slopcheck [SLOP] verdict:** none
**Packages flagged as suspicious [SUS]:** none
**slopcheck availability:** slopcheck not run — no external packages to verify

---

## Architecture Patterns

### System Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                    SHARE EXTENSION PROCESS (~120MB limit)            │
│                                                                      │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │ ShareViewController (UIViewController)                        │   │
│  │  ┌────────────────────────────────────────────────────────┐  │   │
│  │  │ UIHostingController(rootView: ShareExtensionRootView)   │  │   │
│  │  │  ┌──────────────────────────────────────────────────┐  │   │   │
│  │  │  │ ShareExtensionRootView (SwiftUI)                  │  │   │   │
│  │  │  │                                                   │  │   │   │
│  │  │  │  ┌──────────────────┐  ┌───────────────────────┐ │  │   │   │
│  │  │  │  │ VideoPreviewView │  │ ControlsView          │ │  │   │   │
│  │  │  │  │ (static frame)   │  │ (reused from main app) │ │  │   │   │
│  │  │  │  │                  │  │ - TextInputView        │ │  │   │   │
│  │  │  │  │                  │  │ - PositionGridView     │ │  │   │   │
│  │  │  │  │                  │  │ - ScaleStepperView     │ │  │   │   │
│  │  │  │  │                  │  │ - LogoPickerView       │ │  │   │   │
│  │  │  │  │                  │  │ - WhiteFrameToggleView │ │  │   │   │
│  │  │  │  │                  │  │ - ShareButton          │ │  │   │   │
│  │  │  │  └──────────────────┘  └───────────────────────┘ │  │   │   │
│  │  │  └──────────────────────────────────────────────────┘  │   │   │
│  │  └────────────────────────────────────────────────────────┘  │   │
│  │                                                               │   │
│  │  ShareExtensionViewModel (@Observable)                        │   │
│  │  - mediaSource: URL? (from NSItemProvider)                    │   │
│  │  - config: WatermarkConfiguration (synced via App Group)      │   │
│  │  - previewImage: UIImage? (static video frame)                │   │
│  │  - processingState: RenderingState                             │   │
│  └──────────────────────────┬───────────────────────────────────┘   │
│                              │                                      │
│  ┌───────────────────────────┴──────────────────────────────────┐   │
│  │ Shared Media Loader (Extension-side)                          │   │
│  │ - NSItemProvider.loadFileRepresentation(for: UTType.movie)    │   │
│  │ - Copies temp URL to extension sandbox                        │   │
│  │ - NSItemProvider.loadItem(for: UTType.image) → Data → tempURL │   │
│  └───────────────────────────┬──────────────────────────────────┘   │
│                              │                                      │
└──────────────────────────────┼──────────────────────────────────────┘
                               │
                               │ calls WatermarkCore
                               ▼
┌──────────────────────────────────────────────────────────────────────┐
│                   WatermarkCore Swift Package                         │
│                                                                       │
│  ┌──────────────────────────────────────────────────────────────┐    │
│  │ Shared Engine Layer                                            │    │
│  │                                                                 │    │
│  │  ┌──────────────────┐  ┌──────────────────────────────────┐  │    │
│  │  │ WatermarkEngine  │  │ VideoProcessor (NEW)              │  │    │
│  │  │ (existing, photo)│  │                                   │  │    │
│  │  │                  │  │ process(sourceURL:config:) → URL  │  │    │
│  │  │ process(url:     │  │  1. Load AVAsset                  │  │    │
│  │  │   config:) →     │  │  2. Build CALayer hierarchy       │  │    │
│  │  │   ProcessingResult│  │  3. Create AVMutableComposition   │  │    │
│  │  └──────────────────┘  │  4. Configure AVVideoComposition   │  │    │
│  │                         │  5. Export via AVAssetExportSession│ │    │
│  │                         │  6. Validate HDR + audio output   │  │    │
│  │                         └──────────────────────────────────┘  │    │
│  └──────────────────────────────────────────────────────────────┘    │
│                                                                       │
│  ┌──────────────────────────────────────────────────────────────┐    │
│  │ Shared Rendering Layer (reused by both photo and video)        │    │
│  │                                                                 │    │
│  │  WatermarkRenderer.composite()  ← CISourceOverCompositing      │    │
│  │  TextWatermarkRenderer           ← CIAttributedTextImageGen    │    │
│  │  ImageWatermarkRenderer          ← CIImage from PNG data       │    │
│  │  WhiteFrameRenderer              ← UIGraphicsImageRenderer     │    │
│  │  PositionCalculator              ← 9-position coordinate math  │    │
│  └──────────────────────────────────────────────────────────────┘    │
│                                                                       │
│  ┌──────────────────────────────────────────────────────────────┐    │
│  │ Shared Models + Storage                                        │    │
│  │                                                                 │    │
│  │  WatermarkConfiguration (Sendable, Codable)                     │    │
│  │  WatermarkLayer, WatermarkPosition, OutputFormat                │    │
│  │  ProcessingResult                                               │    │
│  │  TempFileManager (new: App Group-aware overload)                │    │
│  │  AppGroupConfigSync (NEW) — UserDefaults(suiteName:) wrapper    │    │
│  └──────────────────────────────────────────────────────────────┘    │
│                                                                       │
└──────────────────────────────┬───────────────────────────────────────┘
                               │
                               │ App Group container
                               ▼
┌──────────────────────────────────────────────────────────────────────┐
│                        DATA / STORAGE LAYER                            │
│                                                                       │
│  ┌─────────────────────────┐  ┌────────────────────────────────────┐ │
│  │ UserDefaults(suiteName: │  │ App Group Container                │ │
│  │  "group.com.watermark") │  │ (file-based, cross-process)        │ │
│  │                          │  │                                    │ │
│  │ - watermarkConfig (JSON) │  │ Shared/Temp/ — temp outputs       │ │
│  │ - lastUsedPosition       │  │ Shared/Inbox/ — extension drops   │ │
│  └─────────────────────────┘  └────────────────────────────────────┘ │
│                                                                       │
│  ┌──────────────────────────────────────────────────────────────────┐ │
│  │ Extension Sandbox Temp Files                                      │ │
│  │ - cachesDirectory/watermark_<UUID>.mp4 (export output)            │ │
│  │ - Cleaned up after share sheet dismiss + 60s grace                │ │
│  └──────────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

| Component | Responsibility | Location |
|-----------|---------------|----------|
| `ShareViewController` | UIKit entry point; receives `NSExtensionContext`; hosts SwiftUI; calls `completeRequest` | `ShareExtension/ShareViewController.swift` |
| `ShareExtensionRootView` | SwiftUI root view; preview area + controls; orchestrates Configure→Render→Share flow | `ShareExtension/ShareExtensionRootView.swift` |
| `ShareExtensionViewModel` | @Observable state holder; NSItemProvider loading; config sync; processing orchestration | `ShareExtension/ShareExtensionViewModel.swift` |
| `VideoProcessor` | AVFoundation pipeline: load→compose→overlay→export→validate | `Packages/WatermarkCore/Sources/WatermarkCore/Processing/VideoProcessor.swift` |
| `VideoLayerBuilder` | Builds CALayer hierarchy from WatermarkConfiguration for video overlay | `Packages/WatermarkCore/Sources/WatermarkCore/Processing/VideoLayerBuilder.swift` |
| `VideoFrameExtractor` | Extracts single static frame from video via AVAssetImageGenerator | `Packages/WatermarkCore/Sources/WatermarkCore/Processing/VideoFrameExtractor.swift` |
| `ExportValidator` | Post-export HDR/audio metadata inspection | `Packages/WatermarkCore/Sources/WatermarkCore/Processing/ExportValidator.swift` |
| `AppGroupConfigSync` | Codable serialization of WatermarkConfiguration to/from App Group UserDefaults | `Packages/WatermarkCore/Sources/WatermarkCore/Storage/AppGroupConfigSync.swift` |
| `TempFileManager` (extended) | Existing temp file manager; add App Group-aware path overload | `Packages/WatermarkCore/Sources/WatermarkCore/Output/TempFileManager.swift` |

### Recommended Project Structure (New Additions)

```
Watermark/
├── ShareExtension/                          # NEW TARGET
│   ├── ShareViewController.swift            # UIViewController + UIHostingController
│   ├── ShareExtensionRootView.swift         # SwiftUI view (preview + controls)
│   ├── ShareExtensionViewModel.swift        # @Observable state mgmt (NSItemProvider input)
│   ├── Info.plist                           # NSExtensionActivationRule (SUBQUERY predicate)
│   └── ShareExtension.entitlements          # App Group capability
│
├── Packages/WatermarkCore/
│   ├── Sources/WatermarkCore/
│   │   ├── Processing/                      # NEW FILES
│   │   │   ├── VideoProcessor.swift         # AVFoundation video watermarking pipeline
│   │   │   ├── VideoLayerBuilder.swift      # CALayer hierarchy construction from config
│   │   │   ├── VideoFrameExtractor.swift    # AVAssetImageGenerator static frame
│   │   │   └── ExportValidator.swift        # Post-export HDR/audio metadata check
│   │   ├── Storage/                         # NEW FILE
│   │   │   └── AppGroupConfigSync.swift     # UserDefaults(suiteName:) Codable wrapper
│   │   ├── Models/                          # EXTEND
│   │   │   └── ProcessingResult.swift       # Extended for video (video-specific fields)
│   │   ├── Engine/                          # EXTEND
│   │   │   ├── WatermarkEngine.swift        # Add video routing (media type detection)
│   │   │   └── PipelineError.swift          # Add video-specific error cases
│   │   └── Output/                          # EXTEND
│   │       └── TempFileManager.swift        # Add App Group container path support
```

### Pattern 1: CALayer Hierarchy for Video Watermark Overlay

**What:** Build a standalone CALayer hierarchy (parent → video → overlay layers) for AVVideoCompositionCoreAnimationTool. The parent layer contains a video layer (matching the video frame size) and one or more watermark sublayers positioned using the same WatermarkPosition enum and PositionCalculator as photos.

**When to use:** Every video watermarking operation (D-01 requires this approach).

**Key constraints:**
- CALayers must be standalone (NOT attached to any on-screen UIView) — per research pitfalls
- Watermark layer contents set via `layer.contents = cgImage` after rasterizing CIImage from WatermarkCore renderers
- Frame-synced positioning: same PositionCalculator used for photos, adapting for video frame dimensions
- Layer hierarchy: `parentLayer` → `videoLayer` → `watermarkLayer1`, `watermarkLayer2`, etc.

**Example:**
```swift
// Source: Kodeco AVFoundation tutorial pattern, verified against Apple docs
func buildWatermarkLayers(
    videoSize: CGSize,
    watermarkCGImage: CGImage,
    position: WatermarkPosition,
    config: WatermarkConfiguration
) -> (parentLayer: CALayer, videoLayer: CALayer) {
    let parentLayer = CALayer()
    parentLayer.frame = CGRect(origin: .zero, size: videoSize)

    let videoLayer = CALayer()
    videoLayer.frame = parentLayer.bounds
    parentLayer.addSublayer(videoLayer)

    let watermarkLayer = CALayer()
    watermarkLayer.contents = watermarkCGImage
    watermarkLayer.contentsGravity = .resizeAspect

    // Use PositionCalculator for consistent positioning (same as photos)
    let watermarkExtent = CGRect(origin: .zero, size: CGSize(
        width: CGFloat(watermarkCGImage.width),
        height: CGFloat(watermarkCGImage.height)
    ))
    let scaledExtent = watermarkExtent.applying(
        CGAffineTransform(scaleX: config.watermarks.first?.scale ?? 0.15,
                          y: config.watermarks.first?.scale ?? 0.15)
    )
    let position = PositionCalculator.position(
        for: position,
        watermarkExtent: scaledExtent,
        baseExtent: CGRect(origin: .zero, size: videoSize),
        padding: config.padding
    )
    watermarkLayer.frame = CGRect(
        origin: CGPoint(x: position.x, y: videoSize.height - position.y - scaledExtent.height),
        size: scaledExtent.size
    )
    parentLayer.addSublayer(watermarkLayer)

    return (parentLayer, videoLayer)
}
```

### Pattern 2: AVVideoComposition + CoreAnimationTool Assembly

**What:** Create an `AVMutableVideoComposition` with `AVVideoCompositionCoreAnimationTool` using the CALayer hierarchy. Configure color properties for HDR awareness. Attach to `AVAssetExportSession`.

**When to use:** The export step after building the composition.

**Key color property behavior:** When `colorPrimaries`, `colorTransferFunction`, and `colorYCbCrMatrix` are set to `nil` on `AVMutableVideoComposition`, the system propagates source color properties. HOWEVER, when using CALayer overlay via `CoreAnimationTool`, the CALayer renders in its own color space (default sRGB). For HDR sources, explicit color properties on the `AVMutableVideoComposition` are needed to prevent SDR flattening. Per D-10, if HDR cannot be preserved through the CALayer pipeline, fall back to SDR with tone mapping and user warning.

**Example:**
```swift
// Source: Apple AVFoundation documentation, cross-referenced with community HDR patterns
func createVideoComposition(
    composition: AVMutableComposition,
    videoSize: CGSize,
    frameDuration: CMTime,
    parentLayer: CALayer,
    videoLayer: CALayer,
    isHDR: Bool,
    sourceColorProperties: (primaries: String?, transfer: String?, matrix: String?)
) -> AVMutableVideoComposition {
    let videoComposition = AVMutableVideoComposition()
    videoComposition.renderSize = videoSize
    videoComposition.frameDuration = frameDuration

    let animationTool = AVVideoCompositionCoreAnimationTool(
        postProcessingAsVideoLayer: videoLayer,
        in: parentLayer
    )
    videoComposition.animationTool = animationTool

    // For HDR: explicitly set color properties to match source
    // This is critical — nil propagation doesn't help the CALayer render in HDR space
    if isHDR {
        videoComposition.colorPrimaries = sourceColorProperties.primaries
            ?? AVVideoColorPrimaries_ITU_R_2020
        videoComposition.colorTransferFunction = sourceColorProperties.transfer
            ?? AVVideoTransferFunction_ITU_R_2100_HLG
        videoComposition.colorYCbCrMatrix = sourceColorProperties.matrix
            ?? AVVideoYCbCrMatrix_ITU_R_2020
    }
    // For SDR: leave nil (system propagates SDR correctly)

    return videoComposition
}
```

### Pattern 3: Audio Track Passthrough (D-11)

**What:** Insert ALL audio tracks from the source asset into the AVMutableComposition. Do not mix down. Preserve stereo, spatial audio, and multi-channel configurations.

**Example:**
```swift
// Source: Apple AVFoundation documentation, verified across Kodeco tutorial and community sources
func insertAllAudioTracks(
    from asset: AVAsset,
    into composition: AVMutableComposition,
    timeRange: CMTimeRange
) async throws {
    let audioTracks = try await asset.loadTracks(withMediaType: .audio)
    for sourceTrack in audioTracks {
        guard let compositionTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw PipelineError.videoAudioTrackInsertionFailed
        }
        try compositionTrack.insertTimeRange(timeRange, of: sourceTrack, at: .zero)
    }
}
```

### Pattern 4: Share Extension UIHostingController Integration

**What:** The ShareViewController is a UIViewController that creates a UIHostingController with the extension's SwiftUI root view, adds it as a child, and constrains it to fill the view. This is the standard iOS pattern for hosting SwiftUI in extension entry points.

**When to use:** ShareViewController.viewDidLoad(). Do NOT use SLComposeServiceViewController (deprecated pattern for custom UIs).

**Example:**
```swift
// Source: Apple Share Extension docs, community SwiftUI extension patterns
class ShareViewController: UIViewController {
    private var hostingController: UIHostingController<ShareExtensionRootView>?
    private let viewModel = ShareExtensionViewModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        setupHostingController()
        Task { await loadSharedMedia() }
    }

    private func setupHostingController() {
        let rootView = ShareExtensionRootView(viewModel: viewModel)
        let host = UIHostingController(rootView: rootView)
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        hostingController = host
    }

    private func loadSharedMedia() async {
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let provider = item.attachments?.first else { return }
        // Load video via loadFileRepresentation, photo via loadItem
        // Set viewModel.mediaSource
    }
}
```

### Pattern 5: App Group Configuration Sync (D-08)

**What:** WatermarkConfiguration (already `Sendable`) is serialized to JSON via `JSONEncoder` and stored in `UserDefaults(suiteName:)`. Loaded on extension launch; saved on any config change. Both the extension and main app read from the same suite.

**Example:**
```swift
// Source: Apple App Group docs; community Codable+UserDefaults patterns
public struct AppGroupConfigSync {
    public static let suiteName = "group.com.watermark.app"
    private static let configKey = "watermarkConfiguration"

    public static func save(_ config: WatermarkConfiguration) {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data = try? JSONEncoder().encode(config) else { return }
        defaults.set(data, forKey: configKey)
    }

    public static func load() -> WatermarkConfiguration? {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data = defaults.data(forKey: configKey) else { return nil }
        return try? JSONDecoder().decode(WatermarkConfiguration.self, from: data)
    }
}
```

### Pattern 6: Source Format Matching for Export (D-04)

**What:** Detect the source video container type and codec, then match the AVAssetExportSession outputFileType. Use `AVAssetExportSession.determineCompatibility(ofExportPreset:with:outputFileType:)` to verify before setting.

**Example:**
```swift
// Source: Apple AVFoundation docs
func matchSourceFormat(asset: AVAsset, exportSession: AVAssetExportSession) async {
    let compatibleTypes = await exportSession.determineCompatibleFileTypes()
    let sourceURL = (asset as? AVURLAsset)?.url
    let sourceUTI = sourceURL.flatMap { try? $0.resourceValues(forKeys: [.typeIdentifierKey]).typeIdentifier }

    if let uti = sourceUTI, compatibleTypes.contains(AVFileType(uti)) {
        exportSession.outputFileType = AVFileType(uti)
    } else if compatibleTypes.contains(.mp4) {
        exportSession.outputFileType = .mp4 // fallback
    }
}
```

### Anti-Patterns to Avoid

- **Using per-frame CIFilter handler for video watermarking:** Violates D-01. CALayer overlay via CoreAnimationTool is the chosen approach. CIFilter per-frame is more complex and unnecessary for watermark overlays.
- **Creating CALayers attached to on-screen UIViews for export:** CALayer hierarchy must be standalone (not added to any view hierarchy). UI-attached layers have different rendering behavior and may not export correctly.
- **Using loadItem for video in share extension:** Use `loadFileRepresentation` for videos to get a file URL (memory-efficient). `loadItem` may load the entire video into memory, causing jetsam.
- **Hardcoding AVAssetExportSession outputFileType:** Always use `determineCompatibility()` and match the source. Hardcoding `.mp4` will force unnecessary transcodes for HEVC sources.
- **Mixing down audio tracks:** D-11 requires all audio tracks preserved. Insert each source audio track individually into the composition.
- **Saving output to camera roll in extension:** Core anti-feature per project constraints. Export to temp file → share sheet → cleanup.
- **Using TRUEPREDICATE in production NSExtensionActivationRule:** Must use specific SUBQUERY predicate for App Store submission. TRUEPREDICATE only for development debugging.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Video frame compositing | Custom Metal shader or per-frame CIFilter pipeline | AVVideoCompositionCoreAnimationTool with CALayer overlay | Apple's built-in compositing handles frame timing, coordinate mapping, and GPU acceleration. CALayer overlay is simpler and sufficient for watermarks. Custom per-frame pipelines add complexity, performance risk, and subtle color space bugs. |
| HDR metadata detection | Manual FourCC parsing from video bitstream | AVAssetTrack.hasMediaCharacteristic(.containsHDRVideo) + CMFormatDescription extensions | Apple APIs provide validated metadata extraction. Manual bitstream parsing is fragile across codec versions and Dolby Vision profiles. |
| Video preview frame extraction | Manual decoder frame reading from raw bytes | AVAssetImageGenerator.generateCGImageAsynchronously(for:completionHandler:) | Async API handles seek, decode, transform application, and thumbnail sizing. Manual frame extraction requires managing decoder sessions and pixel format conversion. |
| Cross-process config sync | Custom file-watching, Darwin notifications, XPC | UserDefaults(suiteName:) with Codable JSON serialization | UserDefaults automatically handles cross-process synchronization. Custom IPC would require significant boilerplate and has edge cases around extension lifecycle. |
| NSItemProvider type detection | Manual UTI string comparison | UTType (UniformTypeIdentifiers) conformance checking | UTType handles UTI hierarchy (e.g., public.mpeg4 conforms to public.movie). Manual string comparison misses subtype relationships. |
| Video codec/container detection | Manual file header inspection | AVAssetExportSession.determineCompatibleFileTypes() + URL resource values | Apple API provides validated compatibility. Manual header parsing is fragile across container variants (mov, mp4, m4v). |

**Key insight:** All the complex parts of video processing (frame timing, color space conversion, encoder configuration, export progress) are handled by AVFoundation. The only custom logic is: (1) building the CALayer hierarchy from WatermarkConfiguration, (2) matching source format, and (3) validating output. Everything else leverages Apple's battle-tested pipeline.

---

## Common Pitfalls

### Pitfall 1: HDR Flattening via CALayer Overlay (Pitfall 7 from PITFALLS.md)

**What goes wrong:** CALayer rendering in AVVideoCompositionCoreAnimationTool defaults to SDR color space. When compositing watermark layers onto HDR video, the HDR luminance range is clipped to SDR levels. Output loses Dolby Vision/HLG metadata and appears flat.

**Why it happens:** CALayer.colorSpace defaults to sRGB. The CoreAnimation compositing engine doesn't automatically promote to extended range. Even when AVVideoComposition.colorPrimaries are set to BT.2020, the CALayer itself may still render in SDR.

**How to avoid:**
1. Detect HDR: `asset.tracks.first?.hasMediaCharacteristic(.containsHDRVideo)`
2. Set explicit color properties on AVMutableVideoComposition (not nil)
3. Set CALayer color space: `parentLayer.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearITUR_2020)` where available
4. Watermark CGImage should use wide gamut color space (Display P3 or extended sRGB)
5. If HDR preservation fails (D-10 fallback): export as SDR with tone mapping, show user warning
6. Post-export validation: read kCVImageBufferColorPrimariesKey from output

**Warning signs:** Output lacks "HDR" badge in Photos; highlights clipped at SDR levels; output file significantly smaller than source.

### Pitfall 2: Share Extension Memory Limit Crashes (Pitfall 4 from PITFALLS.md)

**What goes wrong:** iOS share extensions have ~120MB memory ceiling. Loading full-resolution video as Data or decoding video frames into memory triggers jetsam termination — silent crash, no error log.

**Why it happens:** `loadItem` may load entire video into memory. Creating multiple UIImage copies during processing. Simulator has no memory limit.

**How to avoid:**
1. Use `loadFileRepresentation` for videos (provides file URL, not in-memory data)
2. Copy video URL to extension sandbox immediately (temp URL is ephemeral)
3. Process one item at a time
4. Use AVAsset which streams from disk; never load video frames into arrays
5. Release references explicitly after each item completes
6. Test ONLY on physical device

### Pitfall 3: Audio Track Drop During Export (Pitfall 8 from PITFALLS.md)

**What goes wrong:** Output video is silent — audio track not included in composition or export.

**Why it happens:** Only video track inserted into AVMutableComposition; audio track forgotten. Or AVAssetExportSession audio settings don't match source.

**How to avoid:** Explicitly insert ALL audio tracks from source into composition. Verify `composition.tracks(withMediaType: .audio).count > 0` before export. Post-export: compare audio track count between source and output.

### Pitfall 4: Video Re-Encoding Quality Degradation (Pitfall 3 from PITFALLS.md)

**What goes wrong:** Watermark triggers full decode→modify→re-encode. Generic export presets use default (often too-low) bitrate, wrong color primaries, or suboptimal pixel formats.

**Why it happens:** AVAssetExportSession with generic presets gives no control over bitrate, profile level, or color metadata. Default settings favor compatibility over quality.

**How to avoid:**
1. Match source outputFileType (D-04)
2. Use `AVAssetExportPresetHEVCHighestQuality` for HEVC sources, `AVAssetExportPresetHighestQuality` for H.264
3. Set `shouldOptimizeForNetworkUse = false` (quality over streaming optimization)
4. Explicitly set color properties on AVMutableVideoComposition matching source
5. Post-export: compare output file size to source; dramatic size reduction = quality loss

### Pitfall 5: NSItemProvider Temporary File Expiry

**What goes wrong:** `loadFileRepresentation` provides a temporary file URL that the system may delete immediately after the completion handler returns. If processing starts after the handler, the file is gone.

**Why it happens:** The temp URL is owned by the extension context, not your process. System cleans up after the completion block.

**How to avoid:** Copy the file to your own sandbox (cachesDirectory or App Group container) INSIDE the completion handler. Then process from your copy.

### Pitfall 6: NSExtensionActivationRule Too Restrictive

**What goes wrong:** Extension doesn't appear in share sheet for certain file types because the activation rule doesn't match the actual UTI hierarchy.

**Why it happens:** Using simple NSExtensionActivationSupports keys limits to exact type matches. Files with subtypes (e.g., HEVC-in-MP4) may not match `public.movie` directly depending on how the sending app registers the UTI.

**How to avoid:** Use SUBQUERY predicate with `UTI-CONFORMS-TO` (handles UTI conformance hierarchy). During development, temporarily use TRUEPREDICATE to debug what UTI types are received. Never ship with TRUEPREDICATE.

---

## Code Examples

### Video Watermarking — Full Pipeline (D-01, D-04, D-11)

```swift
// Source: Kodeco tutorial pattern + Apple AVFoundation docs + community HDR patterns
// Verified via multiple search results confirming this is the standard approach

func processVideo(sourceURL: URL, config: WatermarkConfiguration) async throws -> URL {
    let asset = AVURLAsset(url: sourceURL)
    let duration = try await asset.load(.duration)
    let timeRange = CMTimeRange(start: .zero, duration: duration)

    // 1. Build AVMutableComposition with video + ALL audio tracks
    let composition = AVMutableComposition()
    guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first,
          let compositionVideoTrack = composition.addMutableTrack(
              withMediaType: .video,
              preferredTrackID: kCMPersistentTrackID_Invalid
          ) else {
        throw PipelineError.videoTrackNotFound
    }
    try compositionVideoTrack.insertTimeRange(timeRange, of: videoTrack, at: .zero)
    compositionVideoTrack.preferredTransform = try await videoTrack.load(.preferredTransform)

    // D-11: Insert ALL audio tracks (no mixdown)
    let audioTracks = try await asset.loadTracks(withMediaType: .audio)
    for audioTrack in audioTracks {
        guard let compAudioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { continue }
        try compAudioTrack.insertTimeRange(timeRange, of: audioTrack, at: .zero)
    }

    // 2. Determine video size (handle portrait orientation)
    let naturalSize = try await videoTrack.load(.naturalSize)
    let transform = try await videoTrack.load(.preferredTransform)
    let videoSize = transform.isPortrait
        ? CGSize(width: naturalSize.height, height: naturalSize.width)
        : naturalSize

    // 3. Build CALayer hierarchy for watermark overlay
    let watermarkImage = try renderWatermarkAsCGImage(config: config, videoSize: videoSize)
    let (parentLayer, videoLayer) = buildWatermarkLayers(
        videoSize: videoSize,
        watermarkCGImage: watermarkImage,
        config: config
    )

    // 4. Detect HDR and configure color properties
    let isHDR = try await videoTrack.load(.hasMediaCharacteristic, with: .containsHDRVideo)
    let colorProps = isHDR ? try extractColorProperties(from: videoTrack) : nil

    // 5. Create AVVideoComposition with CoreAnimation tool
    let videoComposition = AVMutableVideoComposition()
    videoComposition.renderSize = videoSize
    videoComposition.frameDuration = try await videoTrack.load(.minFrameDuration)
    videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
        postProcessingAsVideoLayer: videoLayer,
        in: parentLayer
    )
    if isHDR, let props = colorProps {
        videoComposition.colorPrimaries = props.primaries
        videoComposition.colorTransferFunction = props.transfer
        videoComposition.colorYCbCrMatrix = props.matrix
    }

    // 6. Export (D-04: match source format)
    guard let exportSession = AVAssetExportSession(
        asset: composition,
        presetName: isHDR ? AVAssetExportPresetHEVCHighestQuality : AVAssetExportPresetHighestQuality
    ) else {
        throw PipelineError.exportSessionCreationFailed
    }

    let outputURL = try TempFileManager.createTempFile(
        uti: (try? sourceURL.resourceValues(forKeys: [.typeIdentifierKey]).typeIdentifier) as CFString?
            ?? "public.mpeg-4" as CFString
    )
    exportSession.outputURL = outputURL
    exportSession.videoComposition = videoComposition
    exportSession.shouldOptimizeForNetworkUse = false // D-04: quality over streaming

    // Match source container type
    await matchSourceFormat(asset: asset, exportSession: exportSession)

    // 7. Run export
    await exportSession.export()
    if let error = exportSession.error { throw PipelineError.exportFailed(error) }

    // 8. Post-export validation (D-12)
    try await validateExport(outputURL: outputURL, sourceAsset: asset, wasHDR: isHDR)

    return outputURL
}
```

### Static Frame Preview Generation (D-03)

```swift
// Source: Apple AVAssetImageGenerator docs, verified via multiple search results
func extractPreviewFrame(from url: URL, at time: CMTime? = nil) async throws -> CGImage {
    let asset = AVURLAsset(url: url)
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = CGSize(width: 1920, height: 1920) // memory-safe preview size

    let duration = try await asset.load(.duration)
    let requestTime = time ?? CMTime(seconds: duration.seconds / 2, preferredTimescale: 600)

    return try await withCheckedThrowingContinuation { continuation in
        generator.generateCGImageAsynchronously(for: requestTime) { cgImage, _, error in
            if let error = error {
                continuation.resume(throwing: error)
            } else if let cgImage = cgImage {
                continuation.resume(returning: cgImage)
            } else {
                continuation.resume(throwing: PipelineError.frameExtractionFailed)
            }
        }
    }
}
```

### Post-Export Validation (D-12)

```swift
// Source: Apple CMFormatDescription + CoreVideo docs, verified via search results
struct ExportValidationResult {
    let hdrPreserved: Bool
    let audioTrackCountMatch: Bool
    let warnings: [String]
}

func validateExport(outputURL: URL, sourceAsset: AVAsset, wasHDR: Bool) async throws -> ExportValidationResult {
    let outputAsset = AVURLAsset(url: outputURL)
    var warnings: [String] = []

    // Check audio track count
    let sourceAudioCount = try await sourceAsset.loadTracks(withMediaType: .audio).count
    let outputAudioCount = try await outputAsset.loadTracks(withMediaType: .audio).count
    let audioMatch = sourceAudioCount == outputAudioCount
    if !audioMatch {
        warnings.append("Audio track count mismatch: source=\(sourceAudioCount), output=\(outputAudioCount)")
    }

    // Check HDR metadata
    var hdrPreserved = false
    if wasHDR {
        let outputVideoTracks = try await outputAsset.loadTracks(withMediaType: .video)
        if let videoTrack = outputVideoTracks.first {
            let formatDescs = try await videoTrack.load(.formatDescriptions)
            if let formatDesc = formatDescs.first {
                let extensions = CMFormatDescriptionGetExtensions(formatDesc) as NSDictionary?
                let primaries = extensions?[kCVImageBufferColorPrimariesKey] as? String
                let transfer = extensions?[kCVImageBufferTransferFunctionKey] as? String
                hdrPreserved = (primaries?.contains("2020") == true) ||
                               (transfer?.contains("HLG") == true) ||
                               (transfer?.contains("2084") == true)
                if !hdrPreserved {
                    warnings.append("HDR metadata not found in output — source HDR was flattened to SDR")
                }
            }
        }
    }

    return ExportValidationResult(
        hdrPreserved: hdrPreserved,
        audioTrackCountMatch: audioMatch,
        warnings: warnings
    )
}
```

### NSItemProvider Video Loading in Share Extension

```swift
// Source: Apple NSItemProvider docs, verified via community patterns
func loadMediaFromProvider(_ provider: NSItemProvider) async throws -> MediaInput {
    if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
        // D-11: Use loadFileRepresentation for memory efficiency
        let url = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let url = url else {
                    continuation.resume(throwing: PipelineError.invalidSource)
                    return
                }
                // Copy immediately — the temp URL may be invalidated after this block
                let destURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("shared_\(UUID().uuidString).mp4")
                try? FileManager.default.copyItem(at: url, to: destURL)
                continuation.resume(returning: destURL)
            }
        }
        return .video(url)
    } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
        // Photos: load as Data and write to temp URL (existing WatermarkEngine expects URL)
        let data = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            provider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { item, error in
                if let error = error { continuation.resume(throwing: error); return }
                if let url = item as? URL, let data = try? Data(contentsOf: url) {
                    continuation.resume(returning: data)
                } else if let data = item as? Data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: PipelineError.invalidSource)
                }
            }
        }
        let destURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("shared_photo_\(UUID().uuidString).jpg")
        try data.write(to: destURL)
        return .photo(destURL)
    }
    throw PipelineError.unsupportedFormat("Unsupported media type")
}
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| SLComposeServiceViewController for share extensions | Custom UIViewController + UIHostingController hosting SwiftUI | iOS 14+ | SLComposeServiceViewController is limited to simple text + image posts. Custom UI via hosting controller gives full SwiftUI flexibility. |
| AVAssetExportSession with generic preset + no color property configuration | AVAssetExportSession with matched outputFileType + explicit color properties on AVVideoComposition | iOS 16+ (HEVC HDR presets) | Older approach silently dropped HDR. Current approach requires explicit HDR awareness but preserves quality. |
| copyCGImage(at:actualTime:) (synchronous) | generateCGImageAsynchronously (async) | iOS 16+ | Async API avoids main thread blocking; better for Swift Concurrency integration. |
| loadItem for all media types | loadFileRepresentation for video, loadItem for photos | iOS 11+ (loadFileRepresentation added) | loadFileRepresentation provides file URL (memory-efficient); loadItem may load video into memory. |
| UIImage-based photo pipeline (strips metadata) | CGImageSource → CIImage → CGImageDestination pipeline | Existing in WatermarkCore | Already implemented in Phase 1. Extension reuses this. |
| TRUEPREDICATE for NSExtensionActivationRule | Specific SUBQUERY predicate with UTI-CONFORMS-TO | Required for App Store | TRUEPREDICATE rejected in review. SUBQUERY predicate is production-safe. |

**Deprecated/outdated:**
- **SLComposeServiceViewController:** Replaced by custom UIViewController approach. Not used in this project.
- **copyCGImage(at:actualTime:):** Still available but async API preferred for Swift Concurrency.
- **UIImage.jpegData() for output:** Already avoided in existing WatermarkCore. CGImageDestination is the modern path.
- **AVAssetExportSession without determineCompatibility():** Use the compatibility check API (iOS 16+) before setting outputFileType.

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Xcode 18 | Building all targets | ✓ [ASSUMED — project already uses Xcode 18 per Phase 1-2] | 18.x | — |
| iOS 18 SDK | AVFoundation APIs, SwiftUI, @Observable | ✓ [ASSUMED — target is iOS 18] | 18.x | — |
| AVFoundation | Video processing | ✓ (included in iOS SDK) | SDK | — |
| Swift 6 | Strict concurrency, @Observable | ✓ [ASSUMED — Package.swift specifies swift-tools-version: 6.0] | 6.x | — |
| Physical iOS device | Share extension memory testing | ✗ [UNKNOWN — researcher cannot verify] | — | Simulator for development; device required for memory validation before ship |
| exiftool (CLI) | Metadata validation in QA | ✗ [UNKNOWN] | — | Manual validation via AVFoundation API inspection (built into ExportValidator) |
| HDR test footage | Dolby Vision/HLG/HDR10 validation | ✗ [UNKNOWN] | — | Generate test footage from iPhone 12+ camera; cannot verify from research |

**Missing dependencies with no fallback:**
- **Physical iOS device:** Share extension memory limits (~120MB) are not enforced on Simulator. Device testing required before verification. Planner should add a manual device-testing task.

**Missing dependencies with fallback:**
- **exiftool:** ExportValidator (built into WatermarkCore) provides automated metadata inspection via AVFoundation. exiftool is nice-to-have for human QA, not a blocker.
- **HDR test footage:** Can be recorded on-device (iPhone 12+ camera defaults to Dolby Vision). Researcher cannot provide test files but the plan can include an on-device recording step.

---

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | No | Not applicable — no user accounts |
| V3 Session Management | No | Not applicable — no sessions |
| V4 Access Control | Yes | App Group container restricted to same team ID; extension sandbox isolation |
| V5 Input Validation | Yes | Validate NSItemProvider UTI types before processing; check file size, reject unsupported formats |
| V6 Cryptography | No | Not applicable — no cryptographic operations |

### Known Threat Patterns for iOS Share Extension + Video Processing

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Malicious video file with crafted codec parameters triggering decoder vulnerability | Tampering | Validate MIME types against actual file headers (not just extension); set processing timeouts on export; AVFoundation handles most decoder sandboxing |
| Oversized file causing extension memory exhaustion (jetsam) | Denial of Service | Check file size before processing; reject files > 500MB in extension; use loadFileRepresentation (streaming) not loadItem (in-memory) |
| Path traversal via crafted item provider URL | Elevation of Privilege | Copy file to extension sandbox before processing; never use provided URL directly for output paths |
| App Group container poisoning from another app with same group ID | Spoofing | App Group container is restricted to apps signed with the same team ID — Apple enforces this at the OS level. Watermark config is a simple JSON blob; validate on deserialization. |
| Extension context hijacking via malicious host app | Information Disclosure | Use NSExtensionActivationRule to restrict which apps can invoke the extension; processed output goes to temp file, not back to host app |
| GPS location leak in watermarked video metadata | Information Disclosure | Per project PITFALLS.md: offer "Strip Location" option before share, or strip GPS by default. This is a product decision for Phase 6, not Phase 3. |

---

## Assumptions Log

> All claims tagged `[ASSUMED]` in this research. The planner and discuss-phase use this section to identify decisions that need user confirmation before execution.

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | WatermarkConfiguration is already Codable — current code shows `Sendable` conformance but not explicit `Codable`. JSONEncoder may work if all properties are Codable-conformant (CGFloat, CGColor may need wrappers). | Architecture Patterns > Pattern 5 | Config sync via App Group UserDefaults won't compile; need to add Codable conformance or custom encoding |
| A2 | CALayer.colorspace can be set to extended color space (CGColorSpace.extendedLinearITU_R_2020) on iOS 18 | Architecture Patterns > Pattern 2 | If this API is macOS-only or restricted, HDR preservation through CALayer overlay may be impossible, forcing SDR fallback (D-10) |
| A3 | AVAssetExportSession with HEVC preset preserves Dolby Vision 8.4 metadata when outputFileType matches source | Standard Stack, Code Examples | Community sources indicate this works but exact behavior depends on encoder version and Dolby profile. Needs device testing with actual Dolby Vision footage |
| A4 | The App Group suite name "group.com.watermark.app" is the correct identifier for this project | Architecture Patterns > Pattern 5 | Bundle identifier may differ; App Group ID must match what's configured in Xcode capabilities |
| A5 | Xcode 18 and iOS 18 SDK are installed and available | Environment Availability | If different Xcode version, some APIs may differ in availability |
| A6 | NSItemProvider.loadFileRepresentation returns a usable file URL for videos shared from Photos app | Code Examples | Some host apps may provide video as Data instead of file URL; need fallback handling |

---

## Open Questions (RESOLVED)

1. **Can CALayer overlay in AVVideoCompositionCoreAnimationTool preserve HDR metadata on all iOS 18 devices?** **RESOLVED:**
   - What we know: Research indicates CALayer renders in SDR color space by default. Explicit color properties on AVVideoComposition can help, but community reports are mixed on Dolby Vision preservation. AVAssetWriter with per-frame CIFilter compositing is the more reliable (but complex) alternative.
   - What's unclear: Whether setting CALayer color space + AVVideoComposition HDR properties together is sufficient for Dolby Vision 8.4 passthrough on device.
   - Recommendation: Implement the CALayer path first (per D-01). Test with actual Dolby Vision footage on device. If HDR is lost, implement D-10 fallback (SDR + tone mapping + warning). If fallback is unacceptable, consider AVAssetWriter + CIFilter per-frame as a v1.1 enhancement.

2. **What is the exact App Group identifier for this project?** **RESOLVED:**
   - What we know: The STACK.md and CONTEXT.md reference `group.com.[bundle].watermark`. The codebase uses placeholder.
   - What's unclear: The actual bundle identifier chosen for the project.
   - Recommendation: Confirm bundle identifier from Xcode project settings. Use `group.{bundleID}` as the App Group ID. Planner should add a task to configure this in both main app and extension targets.

3. **How should multi-item sequential processing handle failures?** **RESOLVED:**
   - What we know: D-14 requires sequential processing with config reuse. The user configures watermark once, applies to each item.
   - What's unclear: If item 2 of 5 fails during export, should items 3-5 still process? Should the extension show a summary of successes/failures?
   - Recommendation: Continue processing remaining items on failure; show per-item status in a summary view after all items complete. Log failures. This is in the agent's discretion area.

4. **Should the share extension's temp files use cachesDirectory or App Group container?** **RESOLVED:**
   - What we know: cachesDirectory is sandboxed to the extension; App Group container is shared with main app. The share extension produces output for immediate sharing (not for main app access).
   - What's unclear: Whether the main app needs access to watermarked files produced by the extension.
   - Recommendation: Use cachesDirectory for share extension output (matched to D-07 one-shot workflow). The main app doesn't need access — the share sheet handles distribution directly. Clean up after share sheet dismiss + 60s grace period.

---

## Sources

### Primary (HIGH confidence)

- Apple Developer Documentation — AVFoundation: `AVAssetExportSession`, `AVVideoComposition`, `AVVideoCompositionCoreAnimationTool`, `AVMutableComposition`, `AVAssetImageGenerator` [CITED: developer.apple.com, verified via multiple search result confirmations]
- Apple Developer Documentation — App Extension: `NSExtensionActivationRule`, `NSItemProvider`, Share Extension lifecycle [CITED: developer.apple.com, verified via search results]
- Apple Developer Documentation — CoreVideo: `kCVImageBufferColorPrimariesKey`, `kCVImageBufferTransferFunctionKey`, `kCVImageBufferYCbCrMatrixKey` [CITED: developer.apple.com, verified via code examples in search results]
- Kodeco AVFoundation Tutorial: "Adding Overlays and Animations to Videos" [CITED: kodeco.com/6236502-avfoundation-tutorial] — Canonical tutorial for AVVideoCompositionCoreAnimationTool with CALayer overlay. Pattern confirmed across multiple community sources.
- Apple Developer — `AVVideoComposition.colorPrimaries`/`colorTransferFunction`/`colorYCbCrMatrix` properties [CITED: developer.apple.com, confirmed via code examples]
- `.planning/research/PITFALLS.md` (existing project research) — Pitfalls 3, 4, 7, 8 directly applicable to this phase [CITED: existing project artifact]

### Secondary (MEDIUM confidence)

- Google Search results — Community patterns for `AVVideoCompositionCoreAnimationTool` + CALayer overlay [MEDIUM: consistent across Stack Overflow, Medium, Kodeco sources]
- Google Search results — HDR preservation through `AVAssetExportSession` and `AVVideoComposition` color properties [MEDIUM: multiple community sources agree on approach; official docs provide API but limited HDR-specific guidance]
- Google Search results — Share Extension SwiftUI + UIHostingController patterns [MEDIUM: consistent across Medium, Kyle Haptonstall, Stack Overflow]
- Google Search results — `NSItemProvider.loadFileRepresentation` for video handling [MEDIUM: consistent recommendation across Apple docs and community]
- `.planning/research/ARCHITECTURE.md` (existing project research) — MVVM + @Observable pattern, extension-as-thin-shell [CITED: existing project artifact]
- `.planning/research/STACK.md` (existing project research) — Technology stack decisions, video processing patterns [CITED: existing project artifact]

### Tertiary (LOW confidence)

- Community discussions on CALayer color space for HDR export — Mixed reports on whether `CALayer.colorspace` extended color space setting actually preserves HDR through CoreAnimation compositing. [LOW: no definitive Apple documentation found; conflicting community reports]
- Dolby Vision 8.4 specific metadata preservation through AVAssetExportSession — Behavior depends on encoder version and device model. [LOW: no official Dolby documentation found for iOS AVFoundation integration]

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all Apple system frameworks, no third-party dependencies, well-documented APIs
- Architecture: HIGH — CALayer overlay pattern is standard and well-documented; share extension hosting pattern is consistent across sources; HDR configuration is the only medium-confidence area
- Pitfalls: HIGH — HDR flattening and memory limits are well-documented in project PITFALLS.md and confirmed by multiple community sources

**Research date:** 2026-06-17
**Valid until:** 2026-12-17 (6 months — Apple frameworks are stable; no expected breaking changes in AVFoundation or extension APIs for iOS 18.x)
