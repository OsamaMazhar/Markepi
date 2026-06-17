# Stack Research

**Domain:** iOS Photo/Video Watermarking App
**Researched:** 2026-06-17
**Confidence:** HIGH

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| **Swift** | 6.x (Xcode 18) | Language | Required for modern SwiftUI, Swift Concurrency, and `@Observable`. Swift 6 strict concurrency checking eliminates data-race bugs in async media pipelines. |
| **SwiftUI** | iOS 18 SDK | UI framework (main app + extension UI) | Declarative, Apple's definitive UI framework since iOS 18. Use `UIHostingController` to bridge into extension entry points where UIKit is mandatory. |
| **UIKit** | iOS 18 SDK | Extension entry points only | `PHContentEditingController` and `ShareViewController` require UIKit `UIViewController` subclasses. Host SwiftUI inside them — do not build UIKit view hierarchies. |
| **Xcode** | 18.x | IDE & toolchain | Required for iOS 18 SDK, Swift 6, and modern extension target templates. |

### Media Frameworks

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| **PhotosUI (PhotosPicker)** | iOS 18 SDK | In-app media picker | Privacy-first, no photo library permission needed. Supports photos + videos, single/multi select via `maxSelectionCount`, and async `loadTransferable`. Do NOT use `UIImagePickerController` (deprecated pattern) or raw `PHPicker` (PhotosPicker wraps it better). |
| **AVFoundation** | iOS 18 SDK | Video processing + composition | The only framework for video track manipulation. Use `AVMutableComposition` + `AVVideoComposition` + `AVAssetExportSession`. Modern async APIs via `AVAsset.load(_:)` (iOS 16+). Required for video watermark overlay. |
| **Core Image** | iOS 18 SDK | GPU-accelerated image watermarking | Use `CIFilter.sourceOverCompositing` to blend watermark onto photo/video frames. Reuse a single `CIContext` across operations. Supports HDR pixel formats via `expandToHDR`. |
| **ImageIO** | iOS 18 SDK | Metadata + HDR gain map preservation | `CGImageSource` → `CGImageDestination` pipeline preserves all EXIF, color profile, and HDR gain map auxiliary data. Use `CGImageDestinationCopyImageSource` with `kCGImageDestinationMergeMetadata`. |
| **Core Graphics** | iOS 18 SDK | White frame + text overlay rendering | `UIGraphicsImageRenderer` for drawing the white frame border + device metadata text (e.g., "Taken by: iPhone 16 Pro"). Used for the frame prior to final watermark compositing. |
| **Photos (PHContentEditingController)** | iOS 18 SDK | Photos app edit extension | Required protocol for the "Edit in Watermark" extension. Receives `PHContentEditingInput`, returns `PHContentEditingOutput` with rendered media. |

### Extension Architecture

| Technology | Purpose | Why Recommended |
|------------|---------|-----------------|
| **Share Extension target** | Receive media via iOS share sheet | `NSExtensionPrincipalClass` points to a `UIViewController` subclass hosting SwiftUI. Uses `NSItemProvider` to load incoming photo/video data. |
| **Photo Editing Extension target** | Edit from within Photos app | Implements `PHContentEditingController`. Hosts same SwiftUI watermarking UI as main app. |
| **App Groups capability** | Shared container between app + extensions | `group.com.[bundle].watermark` for sharing processed output between extension and main app. Also enables `UserDefaults(suiteName:)` for coordination. |
| **Swift Package (shared)** | Shared processing logic | Single Swift Package consumed by main app, share extension, and photo extension targets. Contains all watermarking, metadata, and rendering logic. Eliminates code duplication. |

### Supporting Libraries

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| — _(none)_ | — | — | No third-party libraries are needed. Apple system frameworks provide complete coverage for photo/video processing, watermarking, metadata preservation, and HDR handling. Third-party dependencies would add unnecessary complexity to a privacy-focused, on-device-only app. |

### Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| **Xcode 18** | IDE | Required for iOS 18 SDK. Use Swift 6 language mode with strict concurrency checking. |
| **Swift Testing** | Unit + integration tests | Apple's modern testing framework. Test watermark rendering output, metadata preservation, and extension data flow. |
| **Xcode Previews** | SwiftUI rapid iteration | Preview watermark layout at 8 positions without building to device. |
| **Instruments (Allocations, Leaks)** | Memory profiling | Critical for video export — ensure no memory pressure spikes during large file processing. |
| **exiftool** (CLI) | Metadata validation | Verify EXIF/GPS/XMP and gain map preservation in output files during QA. |

## Installation

```bash
# No package manager needed. Apple frameworks are included with the iOS SDK.
# Project setup via Xcode:

# 1. Create iOS App target (SwiftUI)
# 2. Create Swift Package: File > New > Package > "WatermarkEngine"
# 3. Add Share Extension target: File > New > Target > Share Extension
# 4. Add Photo Editing Extension target: File > New > Target > Photo Editing Extension
# 5. Link WatermarkEngine package to all 3 targets
# 6. Enable App Groups capability on all targets: group.com.[bundle].watermark
```

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| SwiftUI + UIHostingController for extensions | Full UIKit for extensions | Only if targeting iOS 15 or below (not recommended). SwiftUI in hosting controllers is the modern standard. |
| PhotosPicker (PhotosUI) | PHPicker (PhotosUI) | PHPicker is the lower-level API. Use only if you need `PHPickerConfiguration.selection` behavior not exposed by PhotosPicker. For this project, PhotosPicker covers all needs. |
| AVAssetExportSession + CALayer overlay | AVAssetWriter + CIFilter per-frame | Use AVAssetWriter when you need frame-by-frame control with Metal shaders or complex compositing beyond CALayer capabilities. For watermark overlays, CALayer-based composition is simpler and sufficient. |
| Core Image (CIFilter) | vImage / Accelerate | Only if you need maximum performance on very large images and are willing to write manual pixel-level compositing. CIFilter is GPU-accelerated and easier to use. |
| CGImageDestination (ImageIO) for export | PHPhotoLibrary save | Use PHPhotoLibrary save only when the user explicitly wants to save to camera roll. This app's core flow is share-without-saving, so CGImageDestination writes to temp files. |
| No third-party libs (recommended) | SDWebImage, GPUImage, etc. | Third-party image libs add dependency risk and often strip metadata/HDR. Apple frameworks handle everything this app needs natively. |

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| **UIImagePickerController** | Deprecated pattern, requires full photo library permission, no modern async support. | `PhotosPicker` (PhotosUI) |
| **UIImage** for processing pipeline | Converting to/from `UIImage` strips EXIF metadata, color profiles, and HDR gain maps. This is the #1 cause of "why did my photo lose quality?" bugs. | `CGImageSource` → `CIImage` → `CGImageDestination` pipeline. Only use `UIImage` for transient display in SwiftUI `Image` views. |
| **PHPicker** directly (without PhotosPicker) | Lower-level Objective-C API. PhotosPicker provides the SwiftUI-native wrapper with cleaner `PhotosPickerItem` / `Transferable` integration. | `PhotosPicker` |
| **SiriKit** for intents | Dead framework for new integrations since iOS 18. | App Intents (if exposing watermark actions to Siri/Shortcuts in future). Not needed for v1. |
| **Third-party image processing libraries** | They often don't handle HDR gain maps, strip metadata, or introduce re-encoding quality loss. | Apple system frameworks (Core Image, ImageIO, vImage) |
| **Saving to camera roll as default flow** | Core product anti-feature — clutters library, contradicts the "watermark and share" value proposition. | Export to temp directory → share sheet → discard temp file. |
| **iOS 16 or below as minimum target** | Requires maintaining `ObservableObject` alongside `@Observable`, missing modern SwiftUI features, App Intents degraded, and significantly higher maintenance burden for <1% of users in 2026. | iOS 18 minimum |

## Stack Patterns by Variant

**For photo watermarking:**
- Use `CGImageSource` to read, extract metadata dictionary + HDR gain map auxiliary data
- Create `CIImage` from `CGImageSource`, pass through CIFilter pipeline (`CISourceOverCompositing` for watermark)
- Optionally use `UIGraphicsImageRenderer` for white frame + device text overlay (converted back to `CIImage`)
- Render via shared `CIContext` to `CGImage`
- Write via `CGImageDestination` with original metadata + gain map re-attached
- Export to temp file → present share sheet

**For video watermarking:**
- Use `AVAsset.load(_:)` async to get tracks + metadata
- Create `AVMutableComposition` with video + audio tracks
- Create `AVVideoComposition` with `AVVideoCompositionCoreAnimationTool` using a `CALayer` hierarchy (video layer + watermark overlay layer)
- Export via `AVAssetExportSession` with HEVC preset (preserves HDR)
- Monitor progress, cancel on memory pressure

**For share extension import:**
- Receive `NSItemProvider` from `NSExtensionContext`
- Load as `Data` (for photos) or `URL` (for videos) using async `loadItem`
- Process in background `Task`, save result to App Group shared container
- Call `completeRequest(returningItems:completionHandler:)` when done

**For Photos edit extension import:**
- `PHContentEditingController.startContentEditing(with:placeholderImage:)` receives `PHContentEditingInput`
- Load full-resolution asset from `input.fullSizeImageURL` or `input.audiovisualAsset`
- Apply watermark within shared WatermarkEngine Swift Package
- Write to `PHContentEditingOutput.renderedContentURL`
- Call `finishContentEditing` completion with output

## Version Compatibility

| Framework | Minimum iOS | Notes |
|-----------|-------------|-------|
| `PhotosPicker` (PhotosUI) | iOS 16 | Basic picker; iOS 17 adds `.photosPickerStyle(.inline)`; iOS 18 full maturity |
| `@Observable` macro | iOS 17 | Required for modern SwiftUI state management |
| `AVAsset.load(_:)` async | iOS 16 | Modern async asset loading |
| `CGImageDestinationCopyImageSource` | iOS 16 | Simplest metadata-preserving copy |
| `expandToHDR` (CIImage) | iOS 17 | HDR-aware image loading for Core Image pipeline |
| `Transferable` protocol | iOS 16 | Used by PhotosPickerItem for async data loading |
| `PHContentEditingController` | iOS 8+ | Stable, no version-specific concerns |
| App Intents (if added later) | iOS 17 basic / iOS 18 full | iOS 18 required for full Apple Intelligence integration |

**Target: iOS 18 minimum.** This is the industry-standard recommendation for new apps in 2026. It covers >95% of active devices, removes legacy SwiftUI patterns (`ObservableObject`/`StateObject`), provides full App Intents support, and aligns with Swift 6 strict concurrency.

## Sources

- Apple Developer Documentation — PhotosPicker, PHContentEditingController, AVFoundation, Core Image, ImageIO
- Apple Developer — "Supporting HDR images in your app" (WWDC24 session) — HDR gain map preservation via CGImageDestination
- Apple Developer — "What's new in SwiftUI" (WWDC24) — @Observable migration, modern SwiftUI patterns
- Apple Developer — "What's new in Photos" (WWDC24) — PhotosPicker enhancements
- Industry analysis (multiple sources, 2025-2026) — iOS 18 minimum target recommendation for new apps; 95%+ adoption coverage
- Stack Overflow, Apple Developer Forums — Community validation of CGImageSource → CGImageDestination metadata preservation pipeline
- Kodeco (formerly raywenderlich.com) — AVVideoCompositionCoreAnimationTool patterns for video watermarking
- Greg Benz Photography — Technical deep-dive on Apple HDR gain map architecture and preservation techniques

---

*Stack research for: iOS Photo/Video Watermarking App*
*Researched: 2026-06-17*
