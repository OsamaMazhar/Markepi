# Phase 2: Main App (Photo Watermark & Share) - Context

**Gathered:** 2026-06-17
**Status:** Ready for planning

## Phase Boundary

This phase delivers the main app UI — a SwiftUI app that lets users import photos via PhotosPicker, configure text/image watermarks with real-time preview, navigate between multiple selected photos, and share the watermarked output immediately without saving to the camera roll. The app consumes the WatermarkCore Swift Package (Phase 1) for all rendering.

**In scope:** PhotosPicker import, multi-photo sequential flow, real-time low-res preview, watermark configuration UI (text, image/logo, white frame), pinch-to-resize on preview, share sheet integration, temp file management, error handling, accessibility

**Out of scope:** Video processing (Phase 3), share extension (Phase 3), Photos edit extension (Phase 4), batch processing with templates (v2), custom font import (v2), ProRAW support (Phase 5), export format choice (Phase 6)

## Implementation Decisions

### Import & Photo Loading
- **D-01:** PhotosPicker opens immediately on first launch — no intermediate empty screen. Direct-to-picker for minimum friction.
- **D-02:** Multi-select enabled — user picks N photos, configures each sequentially with prev/next navigation. Not batch (templates), each photo gets individual config.
- **D-03:** Photo loading uses thumbnail-first strategy: show low-res thumbnail from PhotosPicker immediately for responsive feel, async load full-resolution in background. Preview updates when full-res is ready.
- **D-04:** Logo/watermark image picker offers both "From Photos" (PhotosPicker) and "From Files" (document picker) as a choice.

### Preview & Render Pipeline
- **D-05:** Real-time preview uses low-res engine render through the same WatermarkCore pipeline. Debounced at 0.3–0.5s. True WYSIWYG — what you see is what gets shared.
- **D-06:** Share flow is two-tap: user taps Share → engine renders at full resolution → shows result in preview → user confirms → tap share → iOS share sheet opens.
- **D-07:** Share button animates to ProgressView spinner during render. Rest of UI remains interactive (no full-screen block).
- **D-08:** Watermark scale controlled via pinch-to-resize directly on the preview (interactive gesture). Accessibility fallback: stepper with ±5% increments in controls section.

### UI Layout & Controls
- **D-09:** Split layout — preview occupies top 60% of screen, scrollable watermark controls occupy bottom 40%. Always visible, no sheet gesture conflicts.
- **D-10:** PhotosPicker trigger is a large prominent "+" / photo icon button centered in the UI.
- **D-11:** Text watermark input is a multi-line TextField allowing line breaks.
- **D-12:** Each watermark layer has an X button for removal. Per-layer granular control, not a single "Reset All."
- **D-13:** Multi-photo navigation via horizontal scrollable thumbnail strip below the preview. Tap to jump to any photo.

### State & Lifecycle
- **D-14:** Watermark configuration persists across photos within a session (user keeps same watermark for multiple photos). Resets only when user explicitly clears or app restarts.
- **D-15:** Multi-photo cancel shows confirmation alert ("Discard changes to remaining photos?") and returns to picker/single-photo mode. Already-processed configs stay in memory only.
- **D-16:** Temp files cleaned up immediately after share sheet dismisses. Re-sharing requires a fresh render. Minimum disk usage, no accumulation.

### Error Handling
- **D-17:** Engine failures display as UIAlertController modal with error message and OK dismiss. Standard iOS pattern, blocks interaction until acknowledged.

### Accessibility
- **D-18:** Pinch-to-resize has a stepper fallback (±5% increments) for VoiceOver and assistive touch users. Scale slider always visible in controls as backup.

### Claude's Discretion
- Debounce implementation details (Combine throttle vs Task.sleep, exact interval tuning)
- Thumbnail loading approach (PhotosPickerItem.loadTransferable vs CGImageSourceCreateThumbnail)
- Low-res preview resolution (e.g., max 1200px on longest side)
- Multi-photo state management pattern (@Observable model holding [PhotoItem] + currentIndex)
- Pinch gesture implementation (MagnifyGesture + simultaneous gesture coordination with scroll)
- Share sheet presentation (UIViewControllerRepresentable wrapping UIActivityViewController)
- TempFileManager integration (reuse from Phase 1 WatermarkCore)
- SwiftUI view hierarchy and component decomposition

## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project Foundation
- `.planning/PROJECT.md` — Core value, constraints, out-of-scope, key decisions
- `.planning/REQUIREMENTS.md` — v1 requirements: MEDI-01, WMRK-04, SHAR-01
- `.planning/config.json` — Workflow preferences (granularity, parallelization)

### Phase 1 (Dependency)
- `.planning/phases/01-core-engine-photo-pipeline/01-CONTEXT.md` — All Phase 1 decisions: watermark composition (D-01 through D-10), format handling, font choice, metadata content

### Engine API (WatermarkCore)
- `Packages/WatermarkCore/Sources/WatermarkCore/Engine/WatermarkEngine.swift` — `process(sourceURL:config:) async throws -> ProcessingResult`
- `Packages/WatermarkCore/Sources/WatermarkCore/Models/WatermarkConfiguration.swift` — `WatermarkConfiguration` (watermarks, padding, whiteFrame, outputFormat), `WatermarkLayer` enum, `OutputFormat` enum
- `Packages/WatermarkCore/Sources/WatermarkCore/Models/ProcessingResult.swift` — `ProcessingResult` (url, data, outputUTI)
- `Packages/WatermarkCore/Sources/WatermarkCore/Output/TempFileManager.swift` — Temp file creation and lifecycle

### Research
- `.planning/research/STACK.md` — Technology stack: SwiftUI, PhotosPicker, UIKit bridging for share sheet
- `.planning/research/ARCHITECTURE.md` — MVVM + @Observable pattern, shared WatermarkCore package

### Phase Tracking
- `.planning/ROADMAP.md` Phase 2 — Goal, requirements, success criteria
- `.planning/STATE.md` — Current position (Phase 1 complete, Phase 2 next)

## Existing Code Insights

### Reusable Assets
- **WatermarkCore Swift Package** — Full photo watermarking engine. Entry point: `WatermarkEngine.shared.process(sourceURL:config:)`. Returns `ProcessingResult` with temp file URL for share sheet.
- **TempFileManager** — Creates temp files in app's temp directory. Phase 2 will use this for output and trigger cleanup on share dismiss.
- **WatermarkConfiguration / WatermarkLayer** — The configuration model the UI will build. `WatermarkLayer` discriminates `.text` (TextWatermarkInput + position + scale) and `.image` (ImageWatermarkInput + position + scale).
- **WhiteFrameConfig** — White frame configuration consumed by the engine.

### Established Patterns
- **@Observable + MVVM** — Phase 1 establishes MVVM with `@Observable` for state management. Phase 2's view models follow this.
- **Sendable models** — All WatermarkCore models are `Sendable`. Phase 2 UI models should also be sendable or `@MainActor`-bound.
- **Swift 6 strict concurrency** — iOS 18 target. No `@unchecked Sendable` unless absolutely necessary.

### Integration Points
- The WatermarkCore package is linked to the main app target. Phase 2 creates the main app target and links it.
- Engine output (`ProcessingResult.url`) is a temp file URL — passed to `UIActivityViewController` for sharing.
- No camera roll save — temp file cleanup on share dismiss aligns with core value.

## Specific Ideas

- Two-tap share flow should feel instant — the first "Share" tap starts the render, the second opens the share sheet. Consider a brief animation on the preview when render completes to signal readiness.
- Thumbnail strip should show small previews of all selected photos with the current one highlighted. Should be horizontally scrollable if 5+ photos.
- Pinch-to-resize should feel natural — use `MagnifyGesture` with a scale clamp at 0.01–0.90 (matching engine validation range). Show a subtle scale percentage label during pinch.
- The "From Photos / From Files" choice for logo picker could be a `.confirmationDialog` or `.actionSheet`.

## Deferred Ideas

None — discussion stayed within phase scope.

---

*Phase: 2-Main App (Photo Watermark & Share)*
*Context gathered: 2026-06-17*
