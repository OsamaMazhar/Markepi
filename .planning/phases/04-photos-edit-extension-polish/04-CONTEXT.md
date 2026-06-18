# Phase 4: Photos Edit Extension & Polish - Context

**Gathered:** 2026-06-18
**Status:** Ready for planning

## Phase Boundary

This phase delivers the Photos app edit extension (PHContentEditingController) — users can open any photo or video in the Photos app and select "Watermark" from the edit extensions menu to watermark the media. The extension hosts the same SwiftUI watermarking UI as the main app and share extension via UIHostingController, produces an undoable adjustment (PHAdjustmentData), and passes comprehensive quality validation on physical iOS 18 devices.

**In scope:** Photo Editing Extension target, PHContentEditingController implementation, SwiftUI watermarking UI hosted in extension, PHAdjustmentData for undoable edits, App Group config sync, comprehensive QA validation (HDR preservation, metadata integrity, orientation correctness, memory safety)

**Out of scope:** ProRAW + EXIF tokens + multi-layer compositing (Phase 5), export format/quality UI (Phase 6), before/after comparison (Phase 6), video progress UX (Phase 6), Live Photos processing (Phase 7), batch processing (v2)

## Implementation Decisions

### Photos Extension UI & Flow
- **D-01:** Full UI parity with the main app — same `ControlsView`, same `WatermarkConfigurable` protocol, same configure→render→done flow. Hosted via `UIHostingController` in a `UIViewController` subclass implementing `PHContentEditingController`. Follows the same pattern established by `ShareViewController` (Phase 3 D-05).
- **D-02:** Extension flow: User opens media in Photos → taps Edit → selects Watermark extension → sees full watermarking UI with real-time preview → configures watermark → taps Done → engine renders at full resolution → `PHContentEditingOutput` written with rendered content + `PHAdjustmentData` → Photos saves the edit. No separate "Share" step — Done commits the edit.
- **D-03:** Extension shares the same `WatermarkConfigurable` protocol, `ControlsView`, and all shared UI components from `WatermarkCore/UI/`. The extension ViewModel follows the same `@Observable @MainActor` pattern as `WatermarkViewModel` and `ShareExtensionViewModel`.

### PHAdjustmentData & Undo
- **D-04:** PHAdjustmentData serializes `WatermarkConfiguration` as JSON with a `"formatVersion": "1.0"` key for forward compatibility. This is the same format used by `AppGroupConfigSync` — the extension writes the config used to produce the output. Photos uses this data to display an "Undo" button and to enable re-editing the same configuration later.
- **D-05:** Undo behavior: Revert to Original removes the extension's adjustment entry, restoring the unmodified media. Re-editing re-loads the serialized `WatermarkConfiguration` so the user can modify their previous settings.

### Photo & Video Processing in Extension
- **D-06:** Photo processing reuses the existing `WatermarkEngine.process(sourceURL:config:)` pipeline. `PHContentEditingInput.fullSizeImageURL` provides the source URL. Output written to `PHContentEditingOutput.renderedContentURL`.
- **D-07:** Source format preservation: match input format via engine's `FormatDetector`. HEIC → HEIC, JPEG → JPEG, PNG → PNG. Consistent with Phase 1 D-09 and D-10.
- **D-08:** Video processing reuses the existing `VideoProcessor` via `WatermarkEngine.processVideo(sourceURL:config:)`. `PHContentEditingInput.audiovisualAsset` provides the `AVAsset` URL. Same HDR preservation, audio passthrough, and post-export validation as Phase 3 (D-09 through D-12).
- **D-09:** `canHandle(_ adjustmentData:)` returns true for any `PHAdjustmentData` with `formatVersion` "1.0" (our own format) and false for unknown formats — the standard extension availability check.

### Quality Validation (QA)
- **D-10:** Automated unit tests in `WatermarkCoreTests` for: pipeline correctness (photo + video paths), HDR gain map detection and re-attachment, EXIF/metadata preservation across all supported formats, orientation normalization for all 8 EXIF orientations, PHAdjustmentData encode/decode round-trip.
- **D-11:** Manual QA on physical iPhone device (iOS 18, A13 Bionic or newer): verify extension appears in Photos edit menu for HEIC, JPEG, PNG photos; verify for H.264 and HEVC video; exiftool before/after comparison confirming all EXIF fields survive; HDR gain map preservation in HEIC output; PHAdjustmentData undo restores original; Photos edit history shows "Watermark" entry; no memory crashes with large 4K video assets.
- **D-12:** QA checklist delivered as `04-QA-CHECKLIST.md` in the phase directory with pass/fail rows for each test case, device info, and any deviations found.

### Claude's Discretion
- PHContentEditingController lifecycle: `startContentEditing(with:placeholderImage:)`, `canHandle(_:)`, `finishContentEditing(completionHandler:)`, `cancelContentEditing`
- PHContentEditingOutput file format and extension selection for `renderedContentURL`
- Memory management for large video asset loading in extension's constrained sandbox
- Photos Extension `Info.plist` configuration (NSExtensionPointIdentifier: `com.apple.photo-editing`, NSExtensionPrincipalClass)
- Preview image generation for `placeholderImage` in `startContentEditing`
- Error handling: `cancelContentEditing` on unrecoverable errors
- Adding the Photo Editing Extension target to `project.pbxproj` (the share extension target also needs integration — noted in Phase 3 but files exist on disk without Xcode target entry)
- Extension entitlements: App Groups (`group.com.watermark.app`) for config sync
- Handling `adjustmentData` when `canHandle` returns `false` (fresh edit, no prior state)

## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project Foundation
- `.planning/PROJECT.md` — Core value, constraints, out-of-scope
- `.planning/REQUIREMENTS.md` — v1 requirement MEDI-03 (Photos edit extension)
- `.planning/STATE.md` — Current position, Phase 4 blocker note (PHAdjustmentData size limits)

### Prior Phases (Dependencies)
- `.planning/phases/01-core-engine-photo-pipeline/01-CONTEXT.md` — Phase 1 decisions: watermark compositing (D-01 through D-10), format preservation, font choice, metadata content, HDR pipeline
- `.planning/phases/02-main-app-photo-watermark-share/02-CONTEXT.md` — Phase 2 decisions: UI layout (D-09 through D-13), preview pipeline (D-05 through D-08), state lifecycle (D-14 through D-16), accessibility (D-18)
- `.planning/phases/03-video-processing-share-extension/03-CONTEXT.md` — Phase 3 decisions: share extension pattern (D-05 through D-08), video compositing (D-01 through D-04), HDR preservation (D-09 through D-12), photo handling in extension (D-13 through D-16), App Group config sync

### Engine API (WatermarkCore)
- `Packages/WatermarkCore/Sources/WatermarkCore/Engine/WatermarkEngine.swift` — `process(sourceURL:config:)` and `processVideo(sourceURL:config:)` entry points, `mediaType(for:)` static UTI detection
- `Packages/WatermarkCore/Sources/WatermarkCore/Models/WatermarkConfiguration.swift` — `WatermarkConfiguration`, `WatermarkLayer`, `OutputFormat` — the config serialized as PHAdjustmentData
- `Packages/WatermarkCore/Sources/WatermarkCore/Models/ProcessingResult.swift` — `ProcessingResult` (url, data, outputUTI, videoValidation)
- `Packages/WatermarkCore/Sources/WatermarkCore/Processing/VideoProcessor.swift` — Video compositing pipeline (AVMutableComposition + CALayer overlay)
- `Packages/WatermarkCore/Sources/WatermarkCore/Output/TempFileManager.swift` — Temp file creation and lifecycle
- `Packages/WatermarkCore/Sources/WatermarkCore/Storage/AppGroupConfigSync.swift` — App Group UserDefaults sync
- `Packages/WatermarkCore/Sources/WatermarkCore/Input/FormatDetector.swift` — Source format detection

### Share Extension (Pattern Reference)
- `ShareExtension/ShareViewController.swift` — UIViewController subclass pattern for hosting SwiftUI in extensions
- `ShareExtension/ShareExtensionViewModel.swift` — @Observable ViewModel with WatermarkConfigurable conformance
- `ShareExtension/ShareExtensionRootView.swift` — SwiftUI root view hosting ControlsView in extension
- `ShareExtension/Info.plist` — NSExtension configuration pattern
- `ShareExtension/ShareExtension.entitlements` — App Group entitlement

### Research
- `.planning/research/STACK.md` — Technology stack: PHContentEditingController, PHContentEditingInput, PHContentEditingOutput, PHAdjustmentData, Photos framework
- `.planning/research/ARCHITECTURE.md` — MVVM + @Observable pattern, shared WatermarkCore package across targets
- `.planning/research/PITFALLS.md` — Critical pitfalls for image quality and metadata preservation

### Phase Tracking
- `.planning/ROADMAP.md` Phase 4 — Goal, requirements (MEDI-03), success criteria
- `.planning/STATE.md` — Current position, blocker note about PHAdjustmentData size limits

### Apple Documentation (for implementation reference)
- `PHContentEditingController` protocol — `startContentEditing(with:placeholderImage:)`, `canHandle(_:)`, `finishContentEditing(completionHandler:)`, `cancelContentEditing`
- `PHContentEditingInput` — `fullSizeImageURL`, `audiovisualAsset`, `adjustmentData`, `mediaType`
- `PHContentEditingOutput` — `renderedContentURL`, `adjustmentData`
- `PHAdjustmentData` — `init(formatIdentifier:formatVersion:data:)` for undoable edit entries

## Existing Code Insights

### Reusable Assets
- **WatermarkCore Swift Package** — All rendering, processing, and UI modules are linked to the main app and share extension. The Photos extension will link to this same package. No new engine code needed.
- **WatermarkConfigurable protocol** — The shared protocol implemented by both `WatermarkViewModel` and `ShareExtensionViewModel`. The Photos extension ViewModel conforms to this same protocol, enabling direct reuse of `ControlsView` and all sub-views.
- **ControlsView + all UI components** — `ControlsView`, `TextWatermarkInputView`, `PositionGridView`, `ScaleStepperView`, `LogoPickerView`, `WhiteFrameToggleView`, `LayerListView` — all reusable unchanged in the Photos extension.
- **AppGroupConfigSync** — Load/save `WatermarkConfiguration` from App Group UserDefaults. Reused for extension ↔ main app config sync.
- **ShareViewController pattern** — The UIViewController + UIHostingController pattern from `ShareViewController.swift` is the direct template for the Photos extension's principal class.

### Established Patterns
- **UIHostingController for hosting SwiftUI in UIKit extensions** — `ShareViewController` (84 lines) is the template: init ViewModel, create hosting controller with root view, constrain to view bounds, wire lifecycle callbacks.
- **@Observable + @MainActor ViewModel** — All ViewModels follow this. Photos extension ViewModel uses the same pattern with `PHContentEditingInput` instead of `NSItemProvider`.
- **Config sync on every change** — `didSet` on config triggers `AppGroupConfigSync.save()`. Photos extension follows this for cross-target consistency.
- **Static pipeline with async throws** — Render path: load input → detect format → process → write output → validate. Same pattern for extension.
- **Temp file lifecycle** — Create → use → cleanup. Extension writes to `PHContentEditingOutput.renderedContentURL` directly instead of temp directory.

### Integration Points
- **App Group** — `group.com.watermark.app` already configured in `ShareExtension.entitlements`. Photos extension adds the same entitlement for config sync.
- **Xcode project** — New Photo Editing Extension target to add to `project.pbxproj`. The share extension target also needs formal integration into the project (files exist on disk but no target entry in pbxproj).
- **Info.plist** — New extension requires `NSExtensionPointIdentifier: com.apple.photo-editing` and `NSExtensionPrincipalClass` pointing to the `PHContentEditingController`-conforming `UIViewController` subclass.
- **WatermarkCore package** — Already linked to main app target. Must also be linked to the new Photos extension target.

## Specific Ideas

- The Photos extension should feel like a natural extension of the Photos app's edit flow — the same UI as the main app but with a "Done" button (not Share) since the edit commits back to the Photos library.
- `placeholderImage` in `startContentEditing` should show a downscaled preview with the current watermark config applied, so the user sees something meaningful while the full-res image loads.
- `PHAdjustmentData.formatIdentifier` should use a reverse-DNS identifier like `com.watermark.app.adjustment` and `formatVersion "1.0"` for forward compatibility.
- QA should include a device test with the largest file the app supports: 4K HEVC video with Dolby Vision + spatial audio. Verify no memory crash.
- If the share extension target isn't yet integrated into `project.pbxproj`, this phase should integrate BOTH the share extension AND the photo editing extension targets in a single wave (they follow the same Xcode project pattern).

## Deferred Ideas

None — discussion stayed within phase scope.

---

*Phase: 4-Photos Edit Extension & Polish*
*Context gathered: 2026-06-18*
