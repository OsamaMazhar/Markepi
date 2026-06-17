# Phase 3: Video Processing & Share Extension - Context

**Gathered:** 2026-06-17
**Status:** Ready for planning

## Phase Boundary

This phase delivers video watermarking (AVFoundation-based CALayer overlay pipeline) with full HDR/audio/quality preservation, plus an iOS share extension target that receives photos and videos from other apps. The share extension hosts the same SwiftUI watermarking UI as the main app via UIHostingController.

**In scope:** Video watermarking engine (AVMutableComposition + CALayer overlay), share extension target with full watermarking UI, photo processing in extension via existing WatermarkEngine, HDR video preservation (Dolby Vision, HLG, HDR10), audio track passthrough, App Group config sync between extension and main app, multi-item sequential processing in extension

**Out of scope:** Photos edit extension (Phase 4), ProRAW + EXIF tokens + multi-layer (Phase 5), export format/quality control (Phase 6), before/after comparison (Phase 6), video progress bar / cancel / backgrounding (Phase 6), Live Photos processing (Phase 7), batch processing (v2)

## Implementation Decisions

### Video Compositing
- **D-01:** Use AVVideoComposition + AVVideoCompositionCoreAnimationTool with CALayer overlay. Watermark layers sit above the video layer in a CALayer hierarchy. Does NOT reuse the CIFilter per-frame pipeline from WatermarkCore.
- **D-02:** Full watermark layer parity with photos — text watermark, image/logo watermark, and white frame with device attribution all render on video frames.
- **D-03:** Video preview uses a single static representative frame (first or middle frame) with watermark overlay applied. Lightweight, no video render loop for preview.
- **D-04:** Preserve source video format — match container, codec, and bitrate. H.264 in → H.264 out, HEVC in → HEVC out. No forced re-encoding to a different codec.

### Share Extension UX
- **D-05:** Full watermarking UI inside the extension — host the same SwiftUI watermarking views from the main app via UIHostingController. Complete parity: text, logo, position, white frame controls all available.
- **D-06:** Extension flow: Configure → Render → Share. User sees watermark config UI first, adjusts settings with static/video preview, taps Share button, engine renders at full resolution, share sheet opens within the extension.
- **D-07:** One-shot workflow — after share sheet dismisses, call `completeRequest` and close the extension. No return to config screen.
- **D-08:** Sync watermark configuration between extension and main app via App Group UserDefaults. Watermark setup in either context becomes the default in the other.

### Video HDR & Quality
- **D-09:** Validate all common HDR formats — Dolby Vision (profile 8.4), HLG, and HDR10. Test and verify all three in output.
- **D-10:** If HDR cannot be preserved (e.g., CALayer overlay strips it, unsupported color space), fall back to SDR with tone mapping and show a warning to the user. Do not silently drop HDR.
- **D-11:** Passthrough all audio tracks from source intact — preserve stereo, spatial audio, multi-channel. No mixdown.
- **D-12:** Post-export validation — inspect output video tracks for HDR metadata (color primaries, transfer function, YCbCr matrix) and audio track count. Log warnings if anything was lost.

### Photo Handling in Extension
- **D-13:** Photos shared to the extension are processed inline via the existing WatermarkEngine. No choice presented — seamless, user doesn't know where processing happens.
- **D-14:** Multi-item shares process all items sequentially — configure watermark once, apply to each item, show share sheet for each in sequence.
- **D-15:** Share extension NSExtensionActivationRule accepts photos, videos, and Live Photos (even though Live Photo processing is Phase 7 — accepting now avoids a later extension update).
- **D-16:** Unsupported media types offer to open in main app via URL scheme. User sees a dialog explaining the item type isn't supported yet with an option to open it in the full app.

### Claude's Discretion
- CALayer hierarchy design for watermark overlay layers (cascading vs sibling layers, frame-synced positioning)
- AVAssetExportSession preset selection for HDR preservation
- Export validation heuristic details (which metadata keys to check, tolerance thresholds)
- App Group UserDefaults serialization format for WatermarkConfiguration sync
- Multi-item sequential processing orchestration in ShareViewController
- UIHostingController integration pattern for hosting SwiftUI views in the extension
- NSItemProvider async loading strategy and error recovery
- Temp file lifecycle in extension sandbox (caches dir vs App Group container)
- ShareViewController lifecycle management with NSExtensionContext

## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project Foundation
- `.planning/PROJECT.md` — Core value, constraints, key decisions
- `.planning/REQUIREMENTS.md` — v1 requirements: MEDI-02 (share sheet), QUAL-04 (video quality/HDR)
- `.planning/config.json` — Workflow preferences (granularity: coarse, parallelization: true)

### Prior Phases (Dependencies)
- `.planning/phases/01-core-engine-photo-pipeline/01-CONTEXT.md` — Phase 1 decisions: watermark compositing (D-01 through D-10), format handling, font choice, metadata content, HDR gain map pipeline
- `.planning/phases/02-main-app-photo-watermark-share/02-CONTEXT.md` — Phase 2 decisions: PhotosPicker flow (D-01 through D-04), preview pipeline (D-05 through D-08), UI layout (D-09 through D-13), state/lifecycle (D-14 through D-16), accessibility (D-18)

### Engine API (WatermarkCore)
- `Packages/WatermarkCore/Sources/WatermarkCore/Engine/WatermarkEngine.swift` — `process(sourceURL:config:) async throws -> ProcessingResult` (photo-only currently, video method to be added)
- `Packages/WatermarkCore/Sources/WatermarkCore/Models/WatermarkConfiguration.swift` — `WatermarkConfiguration`, `WatermarkLayer` enum, `OutputFormat` enum
- `Packages/WatermarkCore/Sources/WatermarkCore/Models/ProcessingResult.swift` — `ProcessingResult` (url, data, outputUTI)
- `Packages/WatermarkCore/Sources/WatermarkCore/Output/TempFileManager.swift` — Temp file creation and lifecycle
- `Packages/WatermarkCore/Sources/WatermarkCore/Rendering/` — All renderers (text, image, frame, compositor, position calculator)

### Research
- `.planning/research/STACK.md` — Technology stack: AVFoundation, AVVideoCompositionCoreAnimationTool, AVAssetExportSession, NSItemProvider, App Groups
- `.planning/research/ARCHITECTURE.md` — MVVM + @Observable pattern, shared WatermarkCore package
- `.planning/research/PITFALLS.md` — Critical pitfalls for video processing

### Phase Tracking
- `.planning/ROADMAP.md` Phase 3 — Goal, requirements (MEDI-02, QUAL-04), success criteria
- `.planning/STATE.md` — Current position, blockers/concerns for Phase 3

## Existing Code Insights

### Reusable Assets
- **WatermarkCore Swift Package** — Full photo watermarking engine. Video processing will extend this package with a VideoEngine module. Existing models (WatermarkConfiguration, WatermarkLayer, ProcessingResult) are reusable without changes.
- **TempFileManager** — File lifecycle management. May need extension-aware overload for App Group container paths.
- **Main app SwiftUI views** — `ControlsView`, `TextWatermarkInputView`, `PositionGridView`, `LogoPickerView`, `WhiteFrameToggleView`, etc. These will be hosted inside the share extension via UIHostingController.
- **ShareSheetView** — UIActivityViewController bridge. Reusable in extension context.
- **WatermarkViewModel** — @Observable state management pattern. Extension needs its own ViewModel (different input source: NSItemProvider vs PhotosPickerItem) but same pattern.

### Established Patterns
- **@Observable + MVVM** — All ViewModels follow this. Extension ViewModel follows same pattern with NSItemProvider input.
- **Static processing pipeline** — Functional pattern with static methods on struct types. Video processor should follow similar: load tracks → build composition → build video composition with CALayer tool → export → validate.
- **Shared CIContext** — `CIContextProvider.shared` for GPU reuse. Video pipeline may need this for watermark layer rendering (CIImage → CGImage for CALayer contents).
- **Sendable / Actor isolation** — `WatermarkEngine` is an actor. Video engine should be similarly isolated or part of the same actor.
- **Error typing** — `PipelineError` enum. Extend with video-specific cases.
- **Temp file lifecycle** — Create → use → cleanup on dismiss → stale purge on launch.

### Integration Points
- **WatermarkCore package** — Linked to main app, share extension, and future Photos extension targets. VideoEngine module added to this package.
- **Share extension target** — New target to create: `ShareViewController` (UIViewController subclass), `Info.plist` with `NSExtensionActivationRule`, App Group entitlements.
- **App Group container** — `group.com.watermark.app` for config sync (UserDefaults suite) and potentially shared temp files.
- **Main app URL scheme** — For "Open in app" fallback from extension when unsupported media types are received.

## Specific Ideas

- CALayer overlay should mirror the existing 9-position layout used by photos — same WatermarkPosition enum driving frame coordinates.
- Static frame preview for video should render the same WatermarkCore compositing pipeline on a single video frame (first frame extracted via AVAssetImageGenerator), so preview is true WYSIWYG.
- The extension's SwiftUI hosting should feel seamless — users shouldn't perceive a difference between the main app and the extension UI. Same fonts, same layout proportions, same interaction patterns.
- App Group config sync should use Codable serialization of WatermarkConfiguration to JSON in shared UserDefaults. Load on extension launch / save on config change.
- Video export should use `AVAssetExportSession` with `outputFileType` matching the source container and `shouldOptimizeForNetworkUse = false` (for quality preservation, not streaming optimization).

## Deferred Ideas

None — discussion stayed within phase scope.

---

*Phase: 3-Video Processing & Share Extension*
*Context gathered: 2026-06-17*
