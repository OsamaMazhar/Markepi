<!-- GSD:project-start source:PROJECT.md -->
## Project

**Watermark**

An iOS app that lets users add watermarks or white-frame metadata overlays to photos and videos, then immediately share them to social media without saving. Users can import media from the in-app picker or the iOS share sheet. Works for both photos and videos while preserving all metadata, HDR, and original image quality.

**Core Value:** Add a watermark and share it instantly — without ever cluttering the camera roll.

### Constraints

- **Platform**: iOS — native (Swift/SwiftUI or UIKit)
- **Quality**: Must preserve HDR, color profile, and all EXIF/metadata in output
- **Performance**: Watermarking must work on-device for large video files without excessive memory pressure
- **Privacy**: No network calls required; all processing on-device
- **Compatibility**: Support in-app import and the iOS share sheet app extension
<!-- GSD:project-end -->

<!-- GSD:stack-start source:research/STACK.md -->
## Technology Stack

## Recommended Stack
### Core Technologies
| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| **Swift** | 6.x (Xcode 18) | Language | Required for modern SwiftUI, Swift Concurrency, and `@Observable`. Swift 6 strict concurrency checking eliminates data-race bugs in async media pipelines. |
| **SwiftUI** | iOS 18 SDK | UI framework (main app + Share Extension UI) | Declarative, Apple's definitive UI framework since iOS 18. Use `UIHostingController` to bridge into the Share Extension entry point where UIKit is mandatory. |
| **UIKit** | iOS 18 SDK | Share Extension entry point only | `ShareViewController` requires a UIKit `UIViewController` subclass. Host SwiftUI inside it — do not build a UIKit view hierarchy. |
| **Xcode** | 18.x | IDE & toolchain | Required for iOS 18 SDK, Swift 6, and modern extension target templates. |
### Media Frameworks
| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| **PhotosUI (PhotosPicker)** | iOS 18 SDK | In-app media picker | Privacy-first, no photo library permission needed. Supports photos + videos, single/multi select via `maxSelectionCount`, and async `loadTransferable`. Do NOT use `UIImagePickerController` (deprecated pattern) or raw `PHPicker` (PhotosPicker wraps it better). |
| **AVFoundation** | iOS 18 SDK | Video processing + composition | The only framework for video track manipulation. Use `AVMutableComposition` + `AVVideoComposition` + `AVAssetExportSession`. Modern async APIs via `AVAsset.load(_:)` (iOS 16+). Required for video watermark overlay. |
| **Core Image** | iOS 18 SDK | GPU-accelerated image watermarking | Use `CIFilter.sourceOverCompositing` to blend watermark onto photo/video frames. Reuse a single `CIContext` across operations. Supports HDR pixel formats via `expandToHDR`. |
| **ImageIO** | iOS 18 SDK | Metadata + HDR gain map preservation | `CGImageSource` → `CGImageDestination` pipeline preserves all EXIF, color profile, and HDR gain map auxiliary data. Use `CGImageDestinationCopyImageSource` with `kCGImageDestinationMergeMetadata`. |
| **Core Graphics** | iOS 18 SDK | White frame + text overlay rendering | `UIGraphicsImageRenderer` for drawing the white frame border + device metadata text (e.g., "Taken by: iPhone 16 Pro"). Used for the frame prior to final watermark compositing. |
### Extension Architecture
| Technology | Purpose | Why Recommended |
|------------|---------|-----------------|
| **Share Extension target** | Receive media via iOS share sheet | `NSExtensionPrincipalClass` points to a `UIViewController` subclass hosting SwiftUI. Uses `NSItemProvider` to load incoming photo/video data. |
| **App Groups capability** | Shared container between app + Share Extension | `group.com.[bundle].watermark` for sharing configuration between the extension and main app. Also enables `UserDefaults(suiteName:)` for coordination. |
| **Swift Package (shared)** | Shared processing logic | Single Swift Package consumed by the main app and Share Extension. Contains all watermarking, metadata, and rendering logic. Eliminates code duplication. |
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
# No package manager needed. Apple frameworks are included with the iOS SDK.
# Project setup via Xcode:
# 1. Create iOS App target (SwiftUI)
# 2. Create Swift Package: File > New > Package > "WatermarkEngine"
# 3. Add Share Extension target: File > New > Target > Share Extension
# 4. Link WatermarkEngine package to both targets
# 5. Enable App Groups capability on both targets: group.com.[bundle].watermark
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
- Use `CGImageSource` to read, extract metadata dictionary + HDR gain map auxiliary data
- Create `CIImage` from `CGImageSource`, pass through CIFilter pipeline (`CISourceOverCompositing` for watermark)
- Optionally use `UIGraphicsImageRenderer` for white frame + device text overlay (converted back to `CIImage`)
- Render via shared `CIContext` to `CGImage`
- Write via `CGImageDestination` with original metadata + gain map re-attached
- Export to temp file → present share sheet
- Use `AVAsset.load(_:)` async to get tracks + metadata
- Create `AVMutableComposition` with video + audio tracks
- Create `AVVideoComposition` with `AVVideoCompositionCoreAnimationTool` using a `CALayer` hierarchy (video layer + watermark overlay layer)
- Export via `AVAssetExportSession` with HEVC preset (preserves HDR)
- Monitor progress, cancel on memory pressure
- Receive `NSItemProvider` from `NSExtensionContext`
- Load as `Data` (for photos) or `URL` (for videos) using async `loadItem`
- Process in background `Task`, save result to App Group shared container
- Call `completeRequest(returningItems:completionHandler:)` when done
## Version Compatibility
| Framework | Minimum iOS | Notes |
|-----------|-------------|-------|
| `PhotosPicker` (PhotosUI) | iOS 16 | Basic picker; iOS 17 adds `.photosPickerStyle(.inline)`; iOS 18 full maturity |
| `@Observable` macro | iOS 17 | Required for modern SwiftUI state management |
| `AVAsset.load(_:)` async | iOS 16 | Modern async asset loading |
| `CGImageDestinationCopyImageSource` | iOS 16 | Simplest metadata-preserving copy |
| `expandToHDR` (CIImage) | iOS 17 | HDR-aware image loading for Core Image pipeline |
| `Transferable` protocol | iOS 16 | Used by PhotosPickerItem for async data loading |
| App Intents (if added later) | iOS 17 basic / iOS 18 full | iOS 18 required for full Apple Intelligence integration |
## Sources
- Apple Developer Documentation — PhotosPicker, AVFoundation, Core Image, ImageIO
- Apple Developer — "Supporting HDR images in your app" (WWDC24 session) — HDR gain map preservation via CGImageDestination
- Apple Developer — "What's new in SwiftUI" (WWDC24) — @Observable migration, modern SwiftUI patterns
- Apple Developer — "What's new in Photos" (WWDC24) — PhotosPicker enhancements
- Industry analysis (multiple sources, 2025-2026) — iOS 18 minimum target recommendation for new apps; 95%+ adoption coverage
- Stack Overflow, Apple Developer Forums — Community validation of CGImageSource → CGImageDestination metadata preservation pipeline
- Kodeco (formerly raywenderlich.com) — AVVideoCompositionCoreAnimationTool patterns for video watermarking
- Greg Benz Photography — Technical deep-dive on Apple HDR gain map architecture and preservation techniques
<!-- GSD:stack-end -->

<!-- GSD:conventions-start source:CONVENTIONS.md -->
## Conventions

### Design System (shared package)
- **Token home:** `Packages/WatermarkCore/Sources/WatermarkCore/DesignSystem/` — shared with the Share Extension.
- **Colors:** `MarkepiColors` uses `UIColor` dynamic providers (no asset catalog needed). Two buckets: canvas (never flips: `canvasBackground = .black`, `canvasOverlayText = .white`) and chrome (flips via `traits.userInterfaceStyle`).
- **Spacing / Radius / Sizing:** Semantic enums (`MarkepiSpacing`, `MarkepiRadius`, `MarkepiSizing`) in the shared package. Use these for recurring values; one-shot isolated literals can stay inline.
- **Typography:** `MarkepiTypography` enum with semantic cases (`sectionHeader`, `controlLabel`, `value`, `metadata`, `pillLabel`, `largeTitle`, `glyph`). Apply via `.markepiTypography(.case)` — no raw `.font(.system(size:))` on text.

### Appearance Preference
- `AppearancePreference` enum (`.system`, `.light`, `.dark`) with `colorScheme: ColorScheme?` mapping.
- Stored via `@AppStorage("appearancePreference")` at the app root (`WatermarkApp.swift`).
- Consumed with `.preferredColorScheme(appearance.colorScheme)`.

### Landscape Side-Rail Layout
- Landscape trigger: `width > height && height >= 320` — driven by aspect ratio, not device identity, so it applies to iPhone **and** iPad landscape alike.
- Size read via `onGeometryChange(for: CGSize.self)` — prefer over `GeometryReader`.
- Portrait (phone + iPad): bottom-dock chrome. Landscape (phone + iPad): `HStack` with canvas column (left) + right-edge rail. The rail collapses to a vertical tool dock when no panel is open (photo fills the rest) and grows a tool-panel column beside the dock when a tool is active.
- Never persist layout state — drive everything from live container size.
<!-- GSD:conventions-end -->

<!-- GSD:architecture-start source:ARCHITECTURE.md -->
## Architecture

Architecture not yet mapped. Follow existing patterns found in the codebase.
<!-- GSD:architecture-end -->

<!-- GSD:skills-start source:skills/ -->
## Project Skills

No project skills found. Add skills to any of: `.claude/skills/`, `.agents/skills/`, `.cursor/skills/`, `.github/skills/`, or `.codex/skills/` with a `SKILL.md` index file.
<!-- GSD:skills-end -->

<!-- GSD:workflow-start source:GSD defaults -->
## GSD Workflow Enforcement

Before using Edit, Write, or other file-changing tools, start work through a GSD command so planning artifacts and execution context stay in sync.

Use these entry points:
- `/gsd-quick` for small fixes, doc updates, and ad-hoc tasks
- `/gsd-debug` for investigation and bug fixing
- `/gsd-execute-phase` for planned phase work

Do not make direct repo edits outside a GSD workflow unless the user explicitly asks to bypass it.
<!-- GSD:workflow-end -->

<!-- GSD:post-plan-start source=.planning/phases/08-traceability-reconciliation-recurrence-guard -->
## GSD Post-Plan Step

After writing a plan's SUMMARY.md, the gsd-executor MUST run:

```
bash scripts/sync-requirements.sh <path-to-summary>
```

This keeps `.planning/REQUIREMENTS.md` checkboxes and traceability table in sync with shipped features, preventing the manual drift that affected v1.0 (10/35 requirements unchecked at milestone close).

### Exit Codes and Resolution

| Exit | Meaning | Action |
|------|---------|--------|
| 0 | All requirement IDs marked complete or already complete. No `not_found`. | Proceed — plan completion is unblocked. |
| 1 | At least one requirement ID in `not_found`. **BLOCKER.** | Resolve before marking plan complete: |
| 2+ | Script error (missing SUMMARY, invalid frontmatter, tool failure). **BLOCKER.** | Diagnose and fix the script or SUMMARY. |

### Not-Found Resolution Path

If the script exits 1 (IDs in `not_found`):

1. **Typo in SUMMARY `requirements-completed`:** Fix the requirement ID in the SUMMARY frontmatter, then re-run the script.
2. **Requirement ID missing from REQUIREMENTS.md:** Add the requirement definition to `.planning/REQUIREMENTS.md` (with `- [ ] **ID**:` checkbox and traceability table row), then re-run the script.
3. The script is idempotent — re-running with corrected data is always safe.

### Regression Check

Verify the guard works:

```bash
bash scripts/test-sync-requirements.sh
```

This self-contained fixture test validates three branches (happy path, not_found, already_complete) and exits non-zero on failure. Run after any change to `sync-requirements.sh` or the GSD `mark-complete` tool.

<!-- GSD:post-plan-end -->

<!-- GSD:post-wave-start source=Phase 9 -->
## GSD Post-Wave Build Gate

After all plans in an execution wave complete (all SUMMARY.md files written) and before the next wave begins, the gsd-executor MUST run:

```
bash scripts/build-gate.sh
```

This gate replaces file-existence-only self-checks as the source of truth for "build PASSED" in the execute workflow. It runs `xcodebuild` across both targets (WatermarkApp and ShareExtension) via the single WatermarkApp scheme.

### Exit Codes and Resolution

| Exit | Meaning | Action |
|------|---------|--------|
| 0 | All targets compiled successfully. "BUILD GATE: PASSED" | Proceed to next wave. |
| non-zero | At least one target failed compilation. "BUILD GATE: FAILED" | **BLOCKER.** Resolve build errors before proceeding. Compilation errors appear inline in the xcodebuild output above. If xcodebuild reports errors that don't appear in Xcode IDE, run `xcodebuild -project Watermark.xcodeproj -scheme WatermarkApp clean` and retry. |

### Regression Check

Verify the gate works:

```bash
bash scripts/test-build-gate.sh
```

This self-contained fixture test validates three branches (clean build, broken build caught, gate blocks wave progression) and exits non-zero on failure. Run after any change to `build-gate.sh` or the Xcode project structure.
<!-- GSD:post-wave-end -->

<!-- GSD:profile-start -->
## Developer Profile

> Profile not yet configured. Run `/gsd-profile-user` to generate your developer profile.
> This section is managed by `generate-claude-profile` -- do not edit manually.
<!-- GSD:profile-end -->
