# Phase 6: Export Control & UX Polish - Context

**Gathered:** 2026-06-18
**Status:** Ready for planning

## Phase Boundary

This phase adds three UX capabilities on top of the existing photo and video pipelines: (1) export format and quality selection (HEIC, JPEG, PNG, TIFF with a quality slider), (2) before/after comparison via long-press gesture, and (3) a polished video export experience with real-time progress, cancellation, and background notifications.

**In scope:** Format picker + quality slider in ControlsView, engine format override support, HDR→SDR warning on lossy conversion, long-press comparison toggle for photos and videos, video progress bar with ETA, cancel button, UNNotification on background completion, RenderingState extension for video progress

**Out of scope:** Batch processing (v2), custom format profiles/presets (v2), rotating watermarks (v2), Live Photos processing (Phase 7), Files app import (Phase 7), signature capture (Phase 7)

## Implementation Decisions

### Export Format & Quality Control

- **D-01:** Format conversion warning — when user selects a lossy format (JPEG) from an HDR source, show a confirmation dialog explaining HDR gain maps will be lost. Follows the Phase 3 D-10 "warn on HDR loss" pattern. Lossless→lossless (HEIC→PNG) and lossless→lossy with confirmation proceed without blocking. The warning is advisory, not a hard block — user choice prevails.

- **D-02:** Quality slider — continuous 0.6–1.0 range stored as `Float` in `WatermarkConfiguration.outputQuality: Float` (default 1.0). Displayed as percentage in UI (60–100%). Applies only to lossy formats (JPEG, HEIC). Disabled/grayed out when PNG or TIFF is selected (lossless, ignore quality).

- **D-03:** TIFF support — add `.tiff` to `OutputFormat` enum. UTI: `public.tiff`. Photo-only — TIFF is not a video container. For videos, format picker is limited to preserveSource (match source container: H.264/HEVC). TIFF rendering uses CGImageDestination with the TIFF UTI. Note: iOS CGImageDestination writes TIFF at 8-bit depth — this is an inherent platform limitation, not a bug.

- **D-04:** Engine format override — `WatermarkEngine.process()` and `ImageWriter.write()` respect `config.outputFormat`:
  - `.preserveSource` → use source UTI (current behavior, Phase 1 D-09)
  - Explicit format → use that format's UTI for `CGImageDestinationCreateWithURL`
  - `ImageWriter` destination UTI parameter changes from `sourceUTI` to the resolved output UTI
  - Metadata and gain map dictionaries are still re-attached (HDR gain map is embedded in HEIC output even if source was HEIC → output is HEIC; for JPEG output, gain map can't be embedded — this is where D-01 warning triggers)

- **D-05:** Quality application — the quality value maps to `kCGImageDestinationLossyCompressionQuality` (0.6–1.0) for JPEG and HEIC destinations in `ImageWriter`. PNG and TIFF ignore this key (lossless). The value travels through the pipeline via `config.outputQuality` — `ImageWriter` reads it directly from the config.

### Before/After Comparison

- **D-06:** Long-press gesture — press and hold in the preview area toggles from watermarked preview to original source. Release returns to watermarked. Matches iOS "peek" interaction pattern. Swipe is already used for thumbnail navigation (goToNext/goToPrev in `WatermarkViewModel`) — long-press avoids gesture conflict.

- **D-07:** Comparison visual feedback — "Original" label overlay appears during long-press (fades in over 150ms, out on release). Uses `.light` impact haptic feedback (`UIImpactFeedbackGenerator`) on state transition. Clean overlay — no other UI elements change.

- **D-08:** Video comparison — for video, long-press shows the original static frame (extracted once via `AVAssetImageGenerator` and cached). Release shows the watermarked static frame. Both extracted from the same timestamp for apples-to-apples comparison. Per COMP-02: "works for both photos and videos."

- **D-09:** Comparison availability — long-press gesture only active when preview is loaded (`previewImage != nil`). No-op when no media is selected. Gesture is attached to the preview area (`PreviewView`), not the entire screen.

### Video Export UX

- **D-10:** Progress bar placement — replaces the share button area in `ControlsView` during video export. Shows a `ProgressView` (linear determinate) with percentage label (e.g., "78%") and ETA (e.g., "~12s remaining"). Below the progress bar: a Cancel button (tinted red, `.bordered` style). Spans the same width as the share button for visual consistency.

- **D-11:** ETA calculation — simple linear projection: `estimatedTimeRemaining = elapsedTime / max(progress, 0.01) - elapsedTime`. `AVAssetExportSession.progress` (KVO via `.publisher(for: \.progress)`) provides progress updates. ETA displayed as "~Xs remaining" or "--" when progress < 0.01 (insufficient data). No moving average or complex prediction — linear is sufficient for AVAssetExportSession's relatively constant encoding speed.

- **D-12:** Cancel behavior — cancel button calls `exportSession.cancelExport()`. When the export session reports `.cancelled`, the state transitions back to `.idle` with the watermark configuration preserved. No data loss, no config reset. The temp output file (incomplete) is cleaned up via `TempFileManager.cleanup()`. User can modify config and re-render.

- **D-13:** RenderingState video extension — add `.renderingVideo(progress: Double, estimatedTimeRemaining: TimeInterval?)` to the `RenderingState` enum. The existing `.rendering` case stays for photo rendering (unchanged — photos render fast, no progress tracking needed). The `ControlsView` share button area switches on `renderingState` and renders either the photo "Rendering..." spinner or the video progress bar with cancel.

- **D-14:** Background notification — use `UNUserNotificationCenter` for completion notification. Request authorization on first video export (fallback: proceed silently if denied). When export completes while app is backgrounded:
  - Success: `"Video watermarked"` body, tap opens app with the output URL in App Group container
  - Failure: `"Video export failed"` body, tap opens app to retry
  - Use `UIApplication.shared.beginBackgroundTask` to request extra time for export completion + notification scheduling
  - Notification identifier: `"com.watermark.app.video-export-{UUID}"` for deduplication

### Export Options UI

- **D-15:** ControlsView placement — "Export Options" `DisclosureGroup` (collapsible section) inserted between existing watermark controls and the share button area. Contains a `Picker` for format selection (HEIC, JPEG, PNG, TIFF for photos; preserveSource only for video) and a `Slider` for quality (60–100%, disabled when PNG/TIFF selected). Default: collapsed. When `.preserveSource` is the format, show the detected source format as a read-only label next to the picker.

### Claude's Discretion

- TIFF bit depth limitation on iOS (8-bit) — document, don't hack around
- TIFF UTI: `public.tiff` — add to `FormatDetector` and `OutputFormat` enum
- Haptic style for comparison toggle (`.light` impact preferred)
- Notification deep-link URL scheme (App Group container URL vs custom scheme)
- Progress bar animation curve and refresh rate (KVO publisher throttle interval)
- `WatermarkConfigurable` protocol — whether to add `outputFormat` and `outputQuality` to the protocol or keep them ViewModel-local
- Whether video format picker shows explicit HEVC/H.264 options or only preserveSource
- Color profile handling when converting HEIC→JPEG (color space mapping)
- `ImageWriter` signature change from `sourceUTI: String` to accept resolved output UTI
- How `config.outputFormat` interacts with `VideoProcessor` (currently ignores format — uses source matching via `matchSourceFormat`)
- Cancellation edge case: what happens if user backgrounds the app during export (UI lifecycle)

### Folded Todos

None — no todos matched phase 6 scope.

## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project Foundation
- `.planning/PROJECT.md` — Core value, constraints, key decisions
- `.planning/REQUIREMENTS.md` — v1 requirements: EXPT-01, EXPT-02, EXPT-03, COMP-01, COMP-02, VIDX-01, VIDX-02, VIDX-03
- `.planning/STATE.md` — Current position, Phase 6 blocker note (format conversion HDR→SDR, video progress bridging)

### Prior Phases (Dependencies)
- `.planning/phases/01-core-engine-photo-pipeline/01-CONTEXT.md` — Phase 1 D-09 (format preservation), D-10 (metadata handling), HDR gain map pipeline
- `.planning/phases/02-main-app-photo-watermark-share/02-CONTEXT.md` — Phase 2 UI layout (D-09 through D-13), preview pipeline (D-05 through D-08), state lifecycle (D-14 through D-16)
- `.planning/phases/03-video-processing-share-extension/03-CONTEXT.md` — Phase 3 D-10 (HDR fallback warning pattern), D-04 (source format matching), D-12 (post-export validation)
- `.planning/phases/05-extended-engine-proraw-exif-tokens-multi-layer/05-CONTEXT.md` — Phase 5 D-12 (compositing order), D-13 (layer model), D-14 (per-layer opacity)

### Engine API (WatermarkCore)
- `Packages/WatermarkCore/Sources/WatermarkCore/Engine/WatermarkEngine.swift` — `process(sourceURL:config:)` and `processVideo(sourceURL:config:)` entry points, `buildFilterGraph()` compositing logic
- `Packages/WatermarkCore/Sources/WatermarkCore/Models/WatermarkConfiguration.swift` — `WatermarkConfiguration`, `WatermarkLayer`, `OutputFormat` enum (to extend with `.tiff` and `outputQuality`)
- `Packages/WatermarkCore/Sources/WatermarkCore/Models/ProcessingResult.swift` — `ProcessingResult` and `RenderingState` enum (to extend with `.renderingVideo`)
- `Packages/WatermarkCore/Sources/WatermarkCore/Output/ImageWriter.swift` — `write(cgImage:metadata:gainMapAuxData:dngMetadata:sourceUTI:to:)` — destination UTI to accept resolved output format
- `Packages/WatermarkCore/Sources/WatermarkCore/Processing/VideoProcessor.swift` — `process(sourceURL:config:)`, `AVAssetExportSession` usage, `matchSourceFormat()` — to accept format override
- `Packages/WatermarkCore/Sources/WatermarkCore/Processing/ExportValidator.swift` — Post-export validation for video
- `Packages/WatermarkCore/Sources/WatermarkCore/Input/FormatDetector.swift` — Format detection (to extend with TIFF)
- `Packages/WatermarkCore/Sources/WatermarkCore/UI/ControlsView.swift` — Share button area, to add export options section and video progress
- `Packages/WatermarkCore/Sources/WatermarkCore/UI/WatermarkConfigurable.swift` — Shared protocol for ViewModel conformance

### Main App
- `App/ViewModels/WatermarkViewModel.swift` — State management, renderAndPrepareShare(), preview pipeline — to extend with video progress + comparison
- `App/Views/ContentView.swift` — Main layout (60/40 split), toolbar, share sheet
- `App/Views/PreviewArea/PreviewView.swift` — Preview rendering, pinch gesture, drawingGroup() — to add long-press comparison

### Share Extension
- `ShareExtension/ShareExtensionViewModel.swift` — Extension ViewModel — to extend with video progress + comparison
- `ShareExtension/ShareExtensionRootView.swift` — Extension root view layout

### Research
- `.planning/research/STACK.md` — Technology stack: AVFoundation, Core Image, ImageIO, UserNotifications framework
- `.planning/research/PITFALLS.md` — Critical pitfalls: HDR gain map stripping on format conversion, PHAdjustmentData size limits

### Phase Tracking
- `.planning/ROADMAP.md` Phase 6 — Goal, requirements, success criteria

## Existing Code Insights

### Reusable Assets
- **OutputFormat enum** — Already exists with `.preserveSource`, `.heic`, `.jpeg`, `.png`. Needs `.tiff` case. Already Codable with String raw values.
- **RenderingState enum** — Already drives the share button UI with states `.idle`, `.rendering`, `.done`, `.error`. Need to add `.renderingVideo(progress:estimatedTimeRemaining:)`.
- **ControlsView** — Generic over `WatermarkConfigurable`. Share button area already switches on `renderingState`. Export options and video progress extend this pattern.
- **WatermarkViewModel** — `renderAndPrepareShare()` already manages the idle→rendering→done flow. Video path needs KVO-based progress tracking.
- **PreviewView** — `Image(uiImage:)` with `drawingGroup()`. Already has `MagnifyGesture` for pinch zoom. Long-press gesture added as a simultaneous gesture.
- **ImageWriter** — Already writes metadata + HDR gain map via CGImageDestination. Needs to accept resolved output UTI instead of source UTI.
- **VideoProcessor** — Already uses AVAssetExportSession. Needs format override + progress KVO callback.
- **AppGroupConfigSync** — Already syncs config bidirectionally. Format/quality choices are serialized in WatermarkConfiguration JSON.
- **TempFileManager** — Already handles temp file creation and cleanup lifecycle.

### Established Patterns
- **@Observable + @MainActor ViewModel** — All state management follows this. Progress tracking via `@MainActor` property updates on KVO callbacks.
- **Static processing pipeline** — `ImageWriter.write()` and `VideoProcessor.process()` are static methods. Format override flows through the config, not as separate parameters.
- **Codable WatermarkConfiguration** — Config serialization with `decodeIfPresent` defaults for backward compatibility. `outputQuality` uses this pattern for old JSON payloads.
- **User choice > quality warning** — Phase 3 D-10 established: warn about quality loss, don't block. D-01 follows the same pattern.
- **Generic ControlsView<ViewModel>** — Any UI added to ControlsView works in both main app and share extension automatically.

### Integration Points
- **WatermarkEngine.process()** — Currently uses `loaded.sourceUTI` directly. Must resolve `config.outputFormat` to the target UTI before passing to ImageWriter.
- **VideoProcessor.process()** — Currently uses `matchSourceFormat()` to auto-match. Must accept an explicit format from config.
- **ControlsView share button area** — The `switch renderingState` block must handle `.renderingVideo` with progress bar + cancel button.
- **WatermarkConfigurable protocol** — May need `outputFormat` and `outputQuality` accessors if export options are shared UI across targets.
- **PreviewView** — Long-press gesture must coordinate with existing pinch gesture. Use `.simultaneously(with:)` for gesture composition.
- **Notification center + App Group** — Deep link on notification tap requires App Group container for passing output URL across targets.

## Specific Ideas

- The "Export Options" disclosure group should feel lightweight — not a separate settings page. A single row that expands inline. Uses `.disclosureGroupStyle(.automatic)`.
- Long-press comparison should feel responsive — keep the original source image cached as a `UIImage` alongside `previewImage` in the ViewModel. No reload from disk on each long-press.
- Video progress updates should be throttled — AVAssetExportSession.progress is a Float (0.0–1.0). Use Combine `.throttle(for: 0.1, scheduler: RunLoop.main)` to avoid excessive UI updates.
- The quality slider should snap to 100% when the user is very close (>= 0.98) — provides a satisfying "max quality" feel without precise slider manipulation.
- TIFF is a niche format for this app — don't over-invest. Add the enum case, wire it through, test basic 8-bit output, document the depth limitation.
- Background notification should include the output file URL in `userInfo` when possible, but fall back to App Group UserDefaults key if `userInfo` size is constrained.
- When format conversion causes HDR loss (HEIC HDR→JPEG), the warning dialog should be concise: "JPEG does not support HDR. The image will be converted to standard dynamic range." with "Convert to JPEG" and "Cancel" buttons.

## Deferred Ideas

None — discussion stayed within phase scope.

---

*Phase: 6-Export Control & UX Polish*
*Context gathered: 2026-06-18*
