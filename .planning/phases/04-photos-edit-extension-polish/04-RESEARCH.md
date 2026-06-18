# Phase 4: Photos Edit Extension & Polish - Research

**Researched:** 2026-06-18
**Domain:** iOS Photo Editing Extension (PHContentEditingController) + quality validation
**Confidence:** HIGH

## Summary

This phase implements the Photos app native edit extension — users open any photo or video in Photos, tap Edit, select "Watermark" from the extensions menu, configure their watermark with the same SwiftUI UI as the main app, and tap Done to commit the edit back to Photos with a non-destructive undo entry (PHAdjustmentData). The extension reuses the existing WatermarkCore Swift Package for all rendering, the same `ControlsView` + `WatermarkConfigurable` protocol pattern as the Share Extension, and the same App Group config sync.

The extension follows the same `UIViewController` + `UIHostingController` pattern established by `ShareViewController`. A new `PhotoEditingViewController` conforms to `PHContentEditingController`, hosts a new `PhotosExtensionRootView` (SwiftUI), and drives a new `PhotosExtensionViewModel` conforming to `WatermarkConfigurable`. The ViewModel loads media from `PHContentEditingInput`, delegates rendering to `WatermarkEngine`, writes output to `PHContentEditingOutput.renderedContentURL`, and serializes config into `PHAdjustmentData`.

**Primary recommendation:** Implement the Photos extension as a new Xcode target using the exact same architecture pattern as `ShareExtension` (UIViewController + UIHostingController + @Observable ViewModel + ControlsView reuse). The PHAdjustmentData uses JSON-serialized `WatermarkConfiguration` minus image watermark PNG data (stored externally via App Group) to stay within PHAdjustmentData size constraints. Write JPEG to `renderedContentURL` for compatibility; HEIC source preservation is handled via PHAdjustmentData undo, not output format matching.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| MEDI-03 | User can receive photos and videos via Photos app native edit extension | PHContentEditingController protocol, Photo Editing Extension target, PHContentEditingInput/Output integration with existing WatermarkEngine |
</phase_requirements>

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Full UI parity with the main app — same `ControlsView`, same `WatermarkConfigurable` protocol, same configure→render→done flow. Hosted via `UIHostingController` in a `UIViewController` subclass implementing `PHContentEditingController`. Follows the same pattern established by `ShareViewController` (Phase 3 D-05).
- **D-02:** Extension flow: User opens media in Photos → taps Edit → selects Watermark extension → sees full watermarking UI with real-time preview → configures watermark → taps Done → engine renders at full resolution → `PHContentEditingOutput` written with rendered content + `PHAdjustmentData` → Photos saves the edit. No separate "Share" step — Done commits the edit.
- **D-03:** Extension shares the same `WatermarkConfigurable` protocol, `ControlsView`, and all shared UI components from `WatermarkCore/UI/`. The extension ViewModel follows the same `@Observable @MainActor` pattern as `WatermarkViewModel` and `ShareExtensionViewModel`.
- **D-04:** PHAdjustmentData serializes `WatermarkConfiguration` as JSON with a `"formatVersion": "1.0"` key for forward compatibility. This is the same format used by `AppGroupConfigSync` — the extension writes the config used to produce the output. Photos uses this data to display an "Undo" button and to enable re-editing the same configuration later.
- **D-05:** Undo behavior: Revert to Original removes the extension's adjustment entry, restoring the unmodified media. Re-editing re-loads the serialized `WatermarkConfiguration` so the user can modify their previous settings.
- **D-06:** Photo processing reuses the existing `WatermarkEngine.process(sourceURL:config:)` pipeline. `PHContentEditingInput.fullSizeImageURL` provides the source URL. Output written to `PHContentEditingOutput.renderedContentURL`.
- **D-07:** Source format preservation: match input format via engine's `FormatDetector`. HEIC → HEIC, JPEG → JPEG, PNG → PNG. Consistent with Phase 1 D-09 and D-10.
- **D-08:** Video processing reuses the existing `VideoProcessor` via `WatermarkEngine.processVideo(sourceURL:config:)`. `PHContentEditingInput.audiovisualAsset` provides the `AVAsset` URL. Same HDR preservation, audio passthrough, and post-export validation as Phase 3 (D-09 through D-12).
- **D-09:** `canHandle(_ adjustmentData:)` returns true for any `PHAdjustmentData` with `formatVersion` "1.0" (our own format) and false for unknown formats — the standard extension availability check.
- **D-10:** Automated unit tests in `WatermarkCoreTests` for: pipeline correctness (photo + video paths), HDR gain map detection and re-attachment, EXIF/metadata preservation across all supported formats, orientation normalization for all 8 EXIF orientations, PHAdjustmentData encode/decode round-trip.
- **D-11:** Manual QA on physical iPhone device (iOS 18, A13 Bionic or newer): verify extension appears in Photos edit menu for HEIC, JPEG, PNG photos; verify for H.264 and HEVC video; exiftool before/after comparison confirming all EXIF fields survive; HDR gain map preservation in HEIC output; PHAdjustmentData undo restores original; Photos edit history shows "Watermark" entry; no memory crashes with large 4K video assets.
- **D-12:** QA checklist delivered as `04-QA-CHECKLIST.md` in the phase directory with pass/fail rows for each test case, device info, and any deviations found.

### the agent's Discretion
- PHContentEditingController lifecycle: `startContentEditing(with:placeholderImage:)`, `canHandle(_:)`, `finishContentEditing(completionHandler:)`, `cancelContentEditing`
- PHContentEditingOutput file format and extension selection for `renderedContentURL`
- Memory management for large video asset loading in extension's constrained sandbox
- Photos Extension `Info.plist` configuration (NSExtensionPointIdentifier: `com.apple.photo-editing`, NSExtensionPrincipalClass)
- Preview image generation for `placeholderImage` in `startContentEditing`
- Error handling: `cancelContentEditing` on unrecoverable errors
- Adding the Photo Editing Extension target to `project.pbxproj` (the share extension target also needs integration — noted in Phase 3 but files exist on disk without Xcode target entry)
- Extension entitlements: App Groups (`group.com.watermark.app`) for config sync
- Handling `adjustmentData` when `canHandle` returns `false` (fresh edit, no prior state)

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope.
</user_constraints>

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Extension entry point (PHContentEditingController) | Photo Editing Extension target | — | System protocol required in extension's principal UIViewController class; cannot be in shared package |
| iOS Photos edit menu discovery | Photo Editing Extension | Info.plist | Info.plist NSExtensionPointIdentifier + PHSupportedMediaTypes control visibility |
| Watermarking UI (SwiftUI controls) | WatermarkCore/UI (shared) | Photo Editing Extension | ControlsView and all sub-views are reusable unchanged; extension only hosts them |
| ViewModel (@Observable, WatermarkConfigurable) | Photo Editing Extension | WatermarkCore | Protocol defined in WatermarkCore; ViewModel implementation is extension-specific |
| Photo rendering (full-res) | WatermarkCore (shared) | Photo Editing Extension | WatermarkEngine.process() actor-isolated; called from extension's ViewModel |
| Video rendering (full-res) | WatermarkCore (shared) | Photo Editing Extension | VideoProcessor uses AVAssetExportSession which streams, not loads — extension-safe |
| PHAdjustmentData serialization | Photo Editing Extension | WatermarkCore/Models | Config JSON encode/decode uses existing Codable conformance on WatermarkConfiguration |
| App Group config sync | WatermarkCore/Storage | All targets | AppGroupConfigSync already shared via WatermarkCore; extension loads/saves same suite |
| PHContentEditingOutput file write | Photo Editing Extension | WatermarkCore/Output | Extension writes processed data to renderedContentURL; engine produces the data |
| QA validation | Automated tests (Swift Testing) | Manual device QA (exiftool) | Test target covers pipeline correctness; manual QA on physical device covers integration |

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| PhotosUI (PHContentEditingController) | iOS 18 SDK | Photos edit extension protocol | Only way to provide custom edit capabilities in the Photos app; stable since iOS 8, not deprecated |
| PHContentEditingInput | iOS 18 SDK | Source media + adjustment data | Provides fullSizeImageURL (photos) and audiovisualAsset (videos) |
| PHContentEditingOutput | iOS 18 SDK | Rendered output + adjustment data | renderedContentURL for processed media; adjustmentData for undo |
| PHAdjustmentData | iOS 18 SDK | Non-destructive edit recipe | Enables undo/re-edit; formatIdentifier + formatVersion + Data |
| WatermarkCore (existing) | — | Shared rendering engine + UI | Reused unchanged; all processing, models, UI components, config sync |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| SwiftUI + UIHostingController | iOS 18 SDK | Host SwiftUI UI in UIKit extension | Required for extension entry points; established pattern from ShareViewController |
| AVFoundation | iOS 18 SDK | Video source access | PHContentEditingInput.audiovisualAsset returns AVAsset; VideoProcessor handles export |
| Core Image + ImageIO | iOS 18 SDK | Photo rendering + metadata | Engine already uses these; extension renders through same pipeline |
| App Groups entitlement | — | Shared config between app + extensions | group.com.watermark.app already configured for share extension |
| Xcode project (pbxproj editing) | — | Target registration | Both share extension AND photo editing extension targets need formal pbxproj entries |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| PHContentEditingController (standard) | Direct PHPhotoLibrary write | No edit menu integration; no undo history; doesn't meet MEDI-03 |
| UIHostingController for SwiftUI | Full UIKit in extension | More code; inconsistent with main app UI; violates D-01 |
| WatermarkEngine.process() (reused) | New extension-specific pipeline | Duplicated code; maintenance burden; Phase 1-3 engine is already tested |
| JSON WatermarkConfiguration in PHAdjustmentData | Binary plist / custom format | JSON via existing Codable is simpler; formatVersion key enables forward compat |

**Installation:**
No package manager needed. Apple frameworks are included with the iOS SDK. Extension target added via Xcode:
```bash
# 1. Add Photo Editing Extension target to Xcode project (File > New > Target > Photo Editing Extension)
# 2. Link WatermarkCore package to new target
# 3. Enable App Groups capability on new target: group.com.watermark.app
# 4. Configure Info.plist: NSExtensionPointIdentifier = com.apple.photo-editing
```

## Package Legitimacy Audit

> No third-party packages are installed in this phase. All dependencies are Apple system frameworks (PhotosUI, AVFoundation, Core Image, ImageIO) and the existing WatermarkCore Swift Package (local). No external package verification needed.

| Package | Registry | Age | Downloads | Source Repo | slopcheck | Disposition |
|---------|----------|-----|-----------|-------------|-----------|-------------|
| — (none) | — | — | — | — | — | No external packages |

**Packages removed due to slopcheck [SLOP] verdict:** none
**Packages flagged as suspicious [SUS]:** none

## Architecture Patterns

### System Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Photos App (Host)                            │
│  User opens photo/video → taps Edit → selects "Watermark" extension │
└───────────────────────────┬─────────────────────────────────────────┘
                            │ Extension launched
                            ▼
┌──────────────────────────────────────────────────────────────────┐
│              Photo Editing Extension (Sandbox Process)            │
│                                                                    │
│  ┌──────────────────────────────────────────────────┐            │
│  │  PhotoEditingViewController (UIViewController)    │            │
│  │  conforms to: PHContentEditingController          │            │
│  │                                                    │            │
│  │  Lifecycle:                                        │            │
│  │  1. canHandle(adjustmentData) → Bool               │            │
│  │  2. startContentEditing(input, placeholder)        │            │
│  │     ├─ Load config from AppGroupConfigSync         │            │
│  │     ├─ If adjustmentData exists → decode config    │            │
│  │     ├─ Create PhotosExtensionViewModel             │            │
│  │     ├─ Host PhotosExtensionRootView (SwiftUI)      │            │
│  │     └─ Set sourceURL from input.fullSizeImageURL   │            │
│  │  3. User configures watermark (ControlsView)        │            │
│  │  4. User taps Done                                  │            │
│  │     └─ finishContentEditing(completionHandler)      │            │
│  │        ├─ Render via WatermarkEngine.process()      │            │
│  │        ├─ Write to output.renderedContentURL        │            │
│  │        ├─ Create PHAdjustmentData (config JSON)     │            │
│  │        └─ completionHandler(output)                 │            │
│  │  5. cancelContentEditing() if user cancels          │            │
│  └──────────────────────────────────────────────────┘            │
│                          │                                         │
│                          ▼                                         │
│  ┌──────────────────────────────────────────────────┐            │
│  │  PhotosExtensionViewModel (@Observable @MainActor)│            │
│  │  conforms to: WatermarkConfigurable               │            │
│  │                                                    │            │
│  │  State:                                            │            │
│  │  - config: WatermarkConfiguration (didSet→sync)   │            │
│  │  - sourceURL: URL? (from fullSizeImageURL)        │            │
│  │  - isVideo: Bool (from input.mediaType)            │            │
│  │  - previewImage: UIImage? (debounced preview)      │            │
│  │  - renderingState: RenderingState                  │            │
│  │  - finishHandler: ((PHContentEditingOutput?)→Void)?│            │
│  └───────────────┬──────────────────────────────────┘            │
│                  │                                                 │
│                  ▼                                                 │
│  ┌──────────────────────────────────────────────────┐            │
│  │  PhotosExtensionRootView (SwiftUI)               │            │
│  │  - 60/40 preview/controls split                  │            │
│  │  - ControlsView(viewModel:) ← shared from Core   │            │
│  │  - "Done" button (not Share)                      │            │
│  │  - Loading/rendering states                       │            │
│  └──────────────────────────────────────────────────┘            │
│                          │                                         │
└──────────────────────────┼─────────────────────────────────────────┘
                           │
                           ▼
┌──────────────────────────────────────────────────────────────────┐
│               WatermarkCore (Shared Swift Package)                 │
│                                                                     │
│  Engine:                                                            │
│  - WatermarkEngine.process(sourceURL:config:) → ProcessingResult    │
│  - WatermarkEngine.processVideo(sourceURL:config:) → ProcessingRes. │
│                                                                     │
│  Models:                                                            │
│  - WatermarkConfiguration (Codable, Sendable)                       │
│  - WatermarkLayer, WatermarkPosition, etc.                          │
│                                                                     │
│  Storage:                                                           │
│  - AppGroupConfigSync.save(config) / .load() → config?              │
│  - suite: "group.com.watermark.app"                                 │
│                                                                     │
│  UI:                                                                │
│  - ControlsView, PositionGridView, TextWatermarkInputView, etc.     │
│  - WatermarkConfigurable protocol                                   │
└──────────────────────────────────────────────────────────────────┘
```

### Recommended Project Structure
```
Watermark.xcodeproj/
└── project.pbxproj              # Add PhotoEditExtension target + ShareExtension target

PhotoEditExtension/              # NEW: Photo Editing Extension target
├── Info.plist                   # NSExtensionPointIdentifier: com.apple.photo-editing
├── PhotoEditExtension.entitlements  # App Group: group.com.watermark.app
├── PhotoEditingViewController.swift  # UIViewController + PHContentEditingController
├── PhotosExtensionViewModel.swift    # @Observable ViewModel, WatermarkConfigurable
└── PhotosExtensionRootView.swift     # SwiftUI root view with Done button

ShareExtension/                  # EXISTING (files on disk, needs pbxproj target entry)
├── Info.plist
├── ShareExtension.entitlements
├── ShareViewController.swift
├── ShareExtensionViewModel.swift
└── ShareExtensionRootView.swift

Packages/WatermarkCore/          # EXISTING (unchanged)
├── Sources/WatermarkCore/
│   ├── Engine/WatermarkEngine.swift
│   ├── Models/WatermarkConfiguration.swift
│   ├── Storage/AppGroupConfigSync.swift
│   ├── UI/ControlsView.swift
│   ├── UI/WatermarkConfigurable.swift
│   └── ...
└── Tests/WatermarkCoreTests/    # Add: PhotosExtensionViewModelTests, AdjustmentDataTests
    └── ...
```

### Pattern 1: PHContentEditingController + UIHostingController
**What:** The extension's principal class is a `UIViewController` subclass conforming to `PHContentEditingController`. It hosts SwiftUI via `UIHostingController` and bridges the PHContentEditingController callbacks to the ViewModel.

**When to use:** Every Photos edit extension. This is the only way to provide custom editing in the Photos app.

**Example:**
```swift
// Source: Apple PHContentEditingController documentation + ShareViewController pattern
import UIKit
import SwiftUI
import PhotosUI

class PhotoEditingViewController: UIViewController, PHContentEditingController {

    private let viewModel = PhotosExtensionViewModel()
    private var hostingController: UIHostingController<PhotosExtensionRootView>?
    var input: PHContentEditingInput?

    // MARK: - PHContentEditingController

    func canHandle(_ adjustmentData: PHAdjustmentData) -> Bool {
        return adjustmentData.formatVersion == "1.0"
    }

    func startContentEditing(with contentEditingInput: PHContentEditingInput,
                             placeholderImage: UIImage) {
        self.input = contentEditingInput
        viewModel.startEditing(with: contentEditingInput, placeholderImage: placeholderImage)
        setupHostingController()
    }

    func finishContentEditing(completionHandler: @escaping (PHContentEditingOutput?) -> Void) {
        viewModel.finishEditing(input: input, completionHandler: completionHandler)
    }

    func cancelContentEditing() {
        viewModel.cancelEditing()
    }

    var shouldShowCancelConfirmation: Bool {
        return viewModel.hasUnsavedChanges
    }

    // MARK: - Hosting Controller Setup

    private func setupHostingController() {
        let rootView = PhotosExtensionRootView(viewModel: viewModel)
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
}
```

### Pattern 2: PHAdjustmentData Serialization
**What:** WatermarkConfiguration is JSON-encoded into PHAdjustmentData. Image watermark PNG data is stripped before serialization and stored in App Group UserDefaults instead (referenced by a hash key). Text-only configs fit comfortably within PHAdjustmentData size limits (~2 MB effective ceiling).

**When to use:** Every time `finishContentEditing` creates a PHContentEditingOutput.

**Example:**
```swift
// Source: CONTEXT.md D-04, PHAdjustmentData best practices
import PhotosUI

struct AdjustmentDataHelper {
    static let formatIdentifier = "com.watermark.app.adjustment"
    static let formatVersion = "1.0"

    /// Encodes a WatermarkConfiguration for PHAdjustmentData.
    /// Strips large image watermark PNG data — stores those externally.
    static func encode(_ config: WatermarkConfiguration) -> Data? {
        // Strip image data to keep adjustment data small
        let lightweightConfig = config.strippingImageData()
        return try? JSONEncoder().encode(lightweightConfig)
    }

    /// Decodes a PHAdjustmentData back to WatermarkConfiguration.
    /// Rehydrates image data from App Group storage if present.
    static func decode(from adjustmentData: PHAdjustmentData) -> WatermarkConfiguration? {
        guard adjustmentData.formatIdentifier == formatIdentifier,
              adjustmentData.formatVersion == formatVersion else { return nil }
        guard var config = try? JSONDecoder().decode(WatermarkConfiguration.self,
                                                      from: adjustmentData.data) else { return nil }
        // Rehydrate image data
        config.rehydrateImageData()
        return config
    }
}
```

### Pattern 3: @Observable ViewModel for Extension
**What:** The extension ViewModel follows the same `@Observable @MainActor` pattern as `WatermarkViewModel` and `ShareExtensionViewModel`, conforming to `WatermarkConfigurable` for direct `ControlsView` reuse.

**What's different from ShareExtensionViewModel:**
- Input source: `PHContentEditingInput` instead of `NSItemProvider`
- No share sheet (`showShareSheet` removed); "Done" button commits edit
- `finishContentEditing` callback instead of `completeRequest`
- No multi-item sequential processing (Photos edits are always single-item)

**Example:**
```swift
@Observable @MainActor
final class PhotosExtensionViewModel: WatermarkConfigurable {
    var config: WatermarkConfiguration {
        didSet { AppGroupConfigSync.save(config) }
    }
    var sourceURL: URL?
    var isVideo: Bool = false
    var previewImage: UIImage?
    var renderingState: RenderingState = .idle
    var activeLayerIndex: Int = 0
    var showLogoPicker: Bool = false
    var hasUnsavedChanges: Bool = false
    var errorMessage: String?
    var showError: Bool = false

    private let engine = WatermarkEngine.shared
    private var finishHandler: ((PHContentEditingOutput?) -> Void)?
    private var input: PHContentEditingInput?

    init() {
        self.config = AppGroupConfigSync.load() ?? WatermarkConfiguration.default
    }

    func startEditing(with input: PHContentEditingInput, placeholderImage: UIImage) {
        self.input = input
        self.sourceURL = input.fullSizeImageURL
        self.isVideo = input.mediaType == .video
        self.previewImage = placeholderImage

        // Load existing config if re-editing
        if let adjustmentData = input.adjustmentData,
           let savedConfig = AdjustmentDataHelper.decode(from: adjustmentData) {
            self.config = savedConfig
        }

        Task { await generatePreview() }
    }

    func finishEditing(input: PHContentEditingInput?,
                       completionHandler: @escaping (PHContentEditingOutput?) -> Void) {
        self.finishHandler = completionHandler
        Task { await renderAndCommit() }
    }

    func cancelEditing() {
        // Clean up temp files, reset state
        finishHandler?(nil)
    }
}
```

### Anti-Patterns to Avoid
- **Loading full-res asset into UIImage:** Always use file URL pipelines (CGImageSource → CIImage → CGImageDestination). Extension memory ceiling is ~120 MB.
- **Storing large PNG data in PHAdjustmentData:** Strip image watermark data; only store text config + image references. PHAdjustmentData is a "recipe," not a "document."
- **Using UIImagePickerController in extension:** This is forbidden — extensions use only PHContentEditingInput.
- **Calling finishContentEditing without PHAdjustmentData:** The Photos framework rejects output with no adjustment data (error 3303). Always attach PHAdjustmentData.
- **Assuming renderedContentURL accepts non-JPEG formats:** While HEIC may work on newer iOS versions, write JPEG for maximum compatibility. HEIC sources preserve quality via the undo mechanism (non-destructive editing).
- **Forgetting to disable UI during rendering:** The user can tap Done multiple times. Guard with `renderingState` to prevent double-render.
- **Building a new ViewModel without WatermarkConfigurable conformance:** This would mean building a new ControlsView — duplication and maintenance burden. Reuse the protocol.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Photos edit extension entry point | Custom extension mechanism | `PHContentEditingController` protocol | Only way to integrate with Photos edit menu; handles lifecycle, sandbox, undo |
| Non-destructive edit undo | Custom undo stack | `PHAdjustmentData` | Photos framework handles undo UI, edit history, re-edit flow |
| Watermark rendering engine | New extension-specific pipeline | Existing `WatermarkEngine.process()` | Already tested; handles HDR, metadata, orientation, all formats |
| Watermark UI controls | New extension UI | `ControlsView` (WatermarkCore/UI) | Same UI as main app + share extension; D-01 requires parity |
| Config sync between targets | New sync mechanism | `AppGroupConfigSync` (existing) | Already uses App Group UserDefaults; same suite for all targets |
| Video export in extension | Custom AVAssetWriter pipeline | Existing `VideoProcessor` (AVAssetExportSession) | Streams frames, doesn't load video into memory; extension-safe |
| PHAdjustmentData encode/decode | Custom binary format | JSON via `WatermarkConfiguration.Codable` | Same format as AppGroupConfigSync; formatVersion key for forward compat |
| Xcode target creation | Manual pbxproj editing from scratch | Copy-paste-adapt Share Extension target pattern | Same structure: UIViewController + UIHostingController + WatermarkCore linkage |

**Key insight:** The Photos extension is structurally identical to the Share Extension (Phase 3). Both are app extensions that host SwiftUI via UIHostingController, use WatermarkConfigurable, and delegate rendering to WatermarkEngine. The only differences are: (1) input source (PHContentEditingInput vs NSItemProvider), (2) output destination (PHContentEditingOutput vs share sheet), and (3) the presence of PHAdjustmentData for undo. Building a completely new architecture would violate D-01 and create maintenance debt.

## Common Pitfalls

### Pitfall 1: PHAdjustmentData Size Exceeds Implicit Limit
**What goes wrong:** Serializing the full `WatermarkConfiguration` with embedded PNG image data (from `ImageWatermarkInput.pngData`) into PHAdjustmentData causes the Photos framework to reject the edit or silently drop the adjustment data. Developers report an effective limit of ~2 MB.

**Why it happens:** PHAdjustmentData is designed as a lightweight "recipe" for reconstructing edits. It is synced via iCloud with the Photos library. Large data blobs cause sync failures and memory pressure in the Photos daemon.

**How to avoid:** Strip image watermark PNG data from the config before JSON-encoding into PHAdjustmentData. Store the full config (with images) in App Group UserDefaults for config sync, and only store the "lightweight recipe" (text config + image hash references) in PHAdjustmentData. On re-edit, rehydrate images from App Group storage.

**Warning signs:** `finishContentEditing` callback receives nil output (silent failure); Photos app shows "Unable to Save Edits" alert; edit history entry is missing the "Watermark" label.

### Pitfall 2: Extension Sandbox Memory Pressure with Large Video
**What goes wrong:** The Photos extension process is terminated by the system (jetsam) when processing large video files, especially 4K HEVC with Dolby Vision + spatial audio.

**Why it happens:** iOS app extensions have a stricter memory ceiling (~120 MB) than main apps. Loading full video frames into RAM or creating multiple CIImage/CGImage copies simultaneously can trigger jetsam.

**How to avoid:** 
- Videos: Use the existing `VideoProcessor` which streams via `AVAssetExportSession` — it never loads the full video into memory.
- Photos: Use the existing `WatermarkEngine.process()` which uses lazy CIImage filter graphs and renders via CIContext to a single CGImage output.
- Never create `UIImage` or `Data` from the full-res source — work with file URLs.
- Monitor memory with Instruments (Allocations template) during development.
- If a video is too large for the extension, consider showing an "Open in Watermark App" fallback (though the engine's streaming approach should handle most cases).

**Warning signs:** Extension process disappears without crash log; Xcode console shows "Message from debugger: Terminated due to memory issue"; Instruments shows memory spike above ~120 MB.

### Pitfall 3: renderedContentURL Format Mismatch
**What goes wrong:** The existing engine preserves source format (HEIC→HEIC per D-07), but Apple's `PHContentEditingOutput` documentation and historical behavior expect JPEG at `renderedContentURL`. Writing HEIC data may cause Photos to reject the output (error 3302).

**Why it happens:** The Photos framework validates the data written to `renderedContentURL`. Traditional documentation specifies JPEG for photos, QuickTime .mov for videos. While iOS 17+ has relaxed format constraints, HEIC output is not universally reliable in the extension context.

**How to avoid:** 
- Write JPEG to `renderedContentURL` for reliability. Use high quality (0.95+) to minimize quality loss.
- The non-destructive editing model (PHAdjustmentData + undo) means the original HEIC is always recoverable via "Revert to Original."
- **Decision point for discussion:** Empirical testing on iOS 18 devices may confirm HEIC works at `renderedContentURL`. If so, format preservation (D-07) can be fully honored. If not, fall back to JPEG with a note that this is a Photos framework limitation, not an app limitation.

**Warning signs:** `finishContentEditing` callback with nil output; Photos error code 3302 in console; "Cannot Save Changes" alert.

### Pitfall 4: Missing Share Extension Target in Xcode Project
**What goes wrong:** The ShareExtension files exist on disk (`ShareExtension/ShareViewController.swift`, etc.) but the `project.pbxproj` only has one native target (`WatermarkApp`). The share extension is not buildable from Xcode without the target entry.

**Why it happens:** The files were created programmatically during Phase 3 execution, but the Xcode project target was never added to `project.pbxproj`. This is documented as a known gap in Phase 3 context notes.

**How to avoid:** This phase must add BOTH the Share Extension target AND the Photo Editing Extension target to `project.pbxproj`. They follow the same structural pattern (UIViewController + UIHostingController + WatermarkCore linkage + App Group entitlement). Adding them together in one wave avoids duplicating the pbxproj editing workflow.

**Warning signs:** Share extension not listed in Xcode scheme selector; build fails with "No such module 'WatermarkCore'" in share extension files; share extension not visible in system share sheet.

### Pitfall 5: Forgetting shouldShowCancelConfirmation
**What goes wrong:** Users accidentally dismiss the extension (tap Cancel) after spending time configuring their watermark, losing all work without a confirmation prompt.

**Why it happens:** `PHContentEditingController.shouldShowCancelConfirmation` defaults to `false`. Without overriding it to `true` when the user has made changes, the Photos app dismisses the extension immediately on Cancel.

**How to avoid:** Override `shouldShowCancelConfirmation` in `PhotoEditingViewController` to return `true` when `viewModel.hasUnsavedChanges == true`. Set `hasUnsavedChanges` to `true` on any config mutation.

**Warning signs:** Tapping Cancel immediately dismisses; no "Discard Changes?" alert; user frustration at lost work.

## Code Examples

### PHContentEditingController Lifecycle Integration
```swift
// Verified pattern: Apple PHContentEditingController documentation + ShareViewController pattern
// Context7/Apple docs: https://developer.apple.com/documentation/photosui/phcontenteditingcontroller

import UIKit
import SwiftUI
import PhotosUI
import WatermarkCore

class PhotoEditingViewController: UIViewController, PHContentEditingController {

    private let viewModel = PhotosExtensionViewModel()
    private var hostingController: UIHostingController<PhotosExtensionRootView>?

    // MARK: - PHContentEditingController

    func canHandle(_ adjustmentData: PHAdjustmentData) -> Bool {
        // D-09: Return true only for our format
        return adjustmentData.formatIdentifier == "com.watermark.app.adjustment"
            && adjustmentData.formatVersion == "1.0"
    }

    func startContentEditing(with contentEditingInput: PHContentEditingInput,
                             placeholderImage: UIImage) {
        // D-02: Present full watermarking UI
        viewModel.startEditing(with: contentEditingInput, placeholderImage: placeholderImage)

        let rootView = PhotosExtensionRootView(viewModel: viewModel)
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
        self.hostingController = host
    }

    func finishContentEditing(completionHandler: @escaping (PHContentEditingOutput?) -> Void) {
        viewModel.commitEdit(completionHandler: completionHandler)
    }

    func cancelContentEditing() {
        viewModel.cancelEditing()
    }

    var shouldShowCancelConfirmation: Bool {
        // Pitfall 5: Only show confirmation if user made changes
        return viewModel.hasUnsavedChanges
    }
}
```

### PHContentEditingOutput Creation with PHAdjustmentData
```swift
// D-04, D-06: Create output with rendered content + adjustment data
// Verified: Apple PHContentEditingOutput documentation

func commitEdit(completionHandler: @escaping (PHContentEditingOutput?) -> Void) {
    guard let input = input, let sourceURL = sourceURL else {
        completionHandler(nil)
        return
    }

    Task {
        do {
            let output = PHContentEditingOutput(contentEditingInput: input)

            // D-06/D-08: Render via existing engine
            let result: ProcessingResult
            if isVideo {
                result = try await engine.processVideo(sourceURL: sourceURL, config: config)
            } else {
                result = try await engine.process(sourceURL: sourceURL, config: config)
            }

            // Copy rendered data to output URL
            if let renderedURL = result.url {
                let renderedData = try Data(contentsOf: renderedURL)
                try renderedData.write(to: output.renderedContentURL)
                try? TempFileManager.cleanup(url: renderedURL)
            }

            // D-04: Serialize config as PHAdjustmentData
            if let adjustmentData = AdjustmentDataHelper.encode(config) {
                output.adjustmentData = PHAdjustmentData(
                    formatIdentifier: "com.watermark.app.adjustment",
                    formatVersion: "1.0",
                    data: adjustmentData
                )
            }

            completionHandler(output)
        } catch {
            completionHandler(nil)
        }
    }
}
```

### Photos Extension Info.plist
```xml
<!-- Pattern: ShareExtension/Info.plist + Apple Photo Editing Extension docs -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>NSExtension</key>
    <dict>
        <key>NSExtensionAttributes</key>
        <dict>
            <key>PHSupportedMediaTypes</key>
            <array>
                <string>Image</string>
                <string>Video</string>
            </array>
        </dict>
        <key>NSExtensionPrincipalClass</key>
        <string>$(PRODUCT_MODULE_NAME).PhotoEditingViewController</string>
        <key>NSExtensionPointIdentifier</key>
        <string>com.apple.photo-editing</string>
    </dict>
    <key>CFBundleDisplayName</key>
    <string>Watermark</string>
</dict>
</plist>
```

### Photos Extension Entitlements
```xml
<!-- Pattern: ShareExtension/ShareExtension.entitlements -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.com.watermark.app</string>
    </array>
</dict>
</plist>
```

## Runtime State Inventory

> Phase 4 is neither a rename, refactor, nor migration phase. It is a greenfield addition (new extension target + new files). No runtime state needs migration. Existing targets (main app, share extension files, WatermarkCore) are unchanged.

| Category | Items Found | Action Required |
|----------|-------------|-----------------|
| Stored data | None — no databases or datastores carry phase-specific state | None |
| Live service config | None — no external services configured | None |
| OS-registered state | None — extension auto-registers when installed; no manual registration | None |
| Secrets/env vars | None — no secrets or env vars required | None |
| Build artifacts | None — existing WatermarkCore and main app targets are unchanged | None |

**Nothing found in any category:** Verified by examining existing codebase — this phase adds a new target and new files; no existing state requires modification.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Xcode 18 | Building/archiving | ✓ | 26.0 (Xcode 18) | — |
| Swift 6 | Compilation | ✓ | 6.0 (toolchain) | — |
| iOS 18 SDK | System frameworks | ✓ | 26.0 | — |
| exiftool (CLI) | QA metadata validation | ✗ | — | Manual verification via Photos.app info panel; install via `brew install exiftool` for QA |
| Physical iPhone (A13+) | Manual QA (D-11) | ✗ | — | iOS Simulator for unit tests; physical device needed for completion gate |
| group.com.watermark.app | App Group config sync | ✓ | — | Already configured in main app + share extension entitlements |

**Missing dependencies with no fallback:**
- Physical iPhone device (iOS 18, A13 Bionic or newer) — required for Phase 4 QA gate (D-11). Unit tests run on simulator. Manual QA checklist cannot be completed without physical device.

**Missing dependencies with fallback:**
- exiftool CLI — optional for automated QA; manual verification via Photos app metadata panel is a viable fallback.

## Common Pitfalls (Extended)

### Pitfall 6: placeholderImage Is Not a Preview
**What goes wrong:** The `placeholderImage` parameter in `startContentEditing(with:placeholderImage:)` is a low-resolution thumbnail provided by Photos for display while the extension loads. Developers sometimes mistake it for the full image or use it as the watermark preview base, resulting in pixelated previews.

**Why it happens:** The placeholder is a downscaled UIImage — not the full-resolution `fullSizeImageURL`. Photos provides it so the extension can show *something* before the real asset loads.

**How to avoid:** Display the `placeholderImage` immediately as a loading state. Then, asynchronously generate a proper preview from `fullSizeImageURL` via `WatermarkEngine.process(sourceURL:config:)` in a background task. Replace the placeholder with the rendered preview once available.

### Pitfall 7: Extension Target Not Visible in Photos Edit Menu
**What goes wrong:** After building and installing the app with the Photo Editing Extension target, the "Watermark" option does not appear in the Photos edit menu.

**Why it happens:** Common causes:
1. `PHSupportedMediaTypes` missing or incorrect in Info.plist
2. `NSExtensionPrincipalClass` doesn't match the actual class name (case-sensitive, module-qualified)
3. Extension target not embedded in the app's `Embed App Extensions` build phase
4. `CFBundleDisplayName` missing
5. Extension is code-signed with a different team/provisioning profile than the main app

**How to avoid:** 
- Ensure Info.plist has `PHSupportedMediaTypes` with both `Image` and `Video`
- Verify `NSExtensionPrincipalClass` = `$(PRODUCT_MODULE_NAME).PhotoEditingViewController`
- Add extension to "Embed App Extensions" build phase in main app target
- Set `CFBundleDisplayName` to "Watermark"
- Confirm code signing matches between main app and extension targets

**Warning signs:** Extension builds without errors but doesn't appear in Photos; no crash logs; "Edit" button in Photos shows only built-in editing tools.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| UIImage-based processing in extensions | CGImageSource → CIImage pipeline | iOS 16+ | HDR + metadata preservation; critical for this app |
| JPEG-only renderedContentURL | Format-flexible (HEIC may work) | iOS 17+ (relaxed) | Potential for HEIC source preservation; needs empirical testing |
| PHContentEditingController (stable since iOS 8) | No change — same protocol | — | Fully supported in iOS 18; no deprecation concerns |
| Storyboard-based extension UI | Programmatic UIHostingController | iOS 13+ | Modern pattern; matches ShareViewController approach |
| UIImagePickerController in extensions | Not applicable — never worked in extensions | — | Extensions use PHContentEditingInput only |

**Deprecated/outdated:**
- Storyboard-based extension templates: Xcode's "Photo Editing Extension" template still generates a Storyboard by default. Discard it and use programmatic UIHostingController as established by the ShareViewController pattern. This avoids dual UI paradigms in the same project.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | PHAdjustmentData effective size limit is ~2 MB (based on developer reports, not Apple documentation) | Pitfall 1 | Configs with embedded PNG data would silently fail; need image data stripping strategy. If limit is higher, stripping adds unnecessary complexity. If lower, even text-heavy configs could fail. |
| A2 | HEIC output at `renderedContentURL` may be rejected by Photos framework — JPEG is the safe default | Pitfall 3 | If HEIC actually works reliably on iOS 18, we'd unnecessarily re-encode HEIC→JPEG, losing format preservation. Needs empirical device testing. |
| A3 | `PHContentEditingInput.fullSizeImageURL` always provides a valid file URL for photos | Architecture | If nil (edge case with iCloud-optimized photos), need fallback to `requestContentEditingInput` or graceful error handling. |
| A4 | `AVAssetExportSession` used by VideoProcessor is extension-safe (streams, doesn't load full video) | Pitfall 2 | If the Photos extension restricts AVAssetExportSession more aggressively than the share extension, video processing could still trigger jetsam. |
| A5 | The share extension target is not currently in `project.pbxproj` (files exist but no target entry) | Pitfall 4 | If it IS already in pbxproj (not visible in grep due to naming convention), adding a duplicate entry would break the project. Verify before adding. |

**If this table is empty:** Not applicable — see 5 assumptions above that need validation.

## Open Questions

1. **HEIC vs JPEG at renderedContentURL — does iOS 18 support HEIC output in Photo Editing Extensions?**
   - What we know: Apple docs historically say JPEG. Developer forums report mixed results — some say HEIC works on iOS 17+, others report error 3302.
   - What's unclear: Whether the Photos framework on iOS 18 reliably accepts HEIC data at `renderedContentURL` for photos originally captured as HEIC.
   - Recommendation: Spike on physical device with a test HEIC photo → engine renders → write HEIC to renderedContentURL → check Photos app. If it works, honor D-07 (format preservation). If not, use JPEG with a comment explaining the framework limitation.

2. **PHAdjustmentData actual size ceiling on iOS 18?**
   - What we know: No Apple-documented limit. Developers anecdotally cite ~2 MB. Our WatermarkConfiguration without images is ~2-5 KB (text + position + scale).
   - What's unclear: Whether the limit applies to the raw Data size or the serialized form; whether it varies by device RAM or iCloud status.
   - Recommendation: Implement image data stripping regardless (text-only configs are always safe). For image watermarks, store PNG data externally and reference by hash. This is future-proof regardless of actual limit.

3. **Should the share extension target be added to pbxproj in this phase or as a separate task?**
   - What we know: Share extension files exist on disk. The `project.pbxproj` only shows 1 native target (WatermarkApp). Phase 3 was completed but the target was never formally integrated.
   - What's unclear: Whether the share extension was intentionally left out of pbxproj (e.g., developer builds via command line/xcodebuild with manual target specification) or this is a gap.
   - Recommendation: Add BOTH targets (share extension + photo editing extension) to pbxproj in a single wave. They share the same structural pattern, so doing them together avoids duplicate work. This resolves the Phase 3 gap as a side effect.

## Validation Architecture

> `workflow.nyquist_validation` is explicitly `false` in `.planning/config.json`. Validation Architecture section is skipped per instructions.

## Security Domain

> `security_enforcement` is not explicitly set to `false` in config. Treat as enabled per default. However, Apple system frameworks (PhotosUI) handle extension sandboxing automatically — no custom authentication, session management, or access control is implemented in this phase.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|------------------|
| V2 Authentication | No | No user authentication in app; no accounts |
| V3 Session Management | No | No sessions; stateless utility app |
| V4 Access Control | No (handled by system) | iOS sandbox + App Groups entitlement control access between app and extensions |
| V5 Input Validation | Yes | Validate `PHContentEditingInput` (nil checks for fullSizeImageURL, audiovisualAsset); validate `PHAdjustmentData` formatIdentifier/formatVersion before decoding; validate `WatermarkConfiguration` on decode (scale range 0.01-0.90, text non-empty, etc.) |
| V6 Cryptography | No | No cryptographic operations; no user data at rest |

### Known Threat Patterns for iOS Photo Editing Extensions

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Malformed PHAdjustmentData injected via Photos library sync | Tampering | Validate `formatIdentifier` + `formatVersion` before decoding; graceful decode failure returns `false` from `canHandle()` |
| Memory exhaustion from large source assets | Denial of Service | Use streaming pipelines (AVAssetExportSession, lazy CIImage); guard source size before processing; extension sandbox naturally limits attack surface |
| Cross-extension data leakage via App Group | Information Disclosure | App Group `group.com.watermark.app` is shared only between our own targets; no third-party extensions have access |
| Path traversal in `renderedContentURL` | Tampering | System-provided URL; write using `Data.write(to:)` which fails for paths outside sandbox |
| Config injection via UserDefaults (App Group) | Tampering | WatermarkConfiguration decode validates scale ranges, text non-empty; invalid configs fall back to defaults |

## Sources

### Primary (HIGH confidence)
- Apple Developer Documentation — `PHContentEditingController` protocol (canHandle, startContentEditing, finishContentEditing, cancelContentEditing, shouldShowCancelConfirmation) — confirmed active and not deprecated in iOS 18
- Apple Developer Documentation — `PHContentEditingInput` (fullSizeImageURL, audiovisualAsset, adjustmentData, mediaType, placeholderImage)
- Apple Developer Documentation — `PHContentEditingOutput` (renderedContentURL, adjustmentData, init(contentEditingInput:))
- Apple Developer Documentation — `PHAdjustmentData` (formatIdentifier, formatVersion, data)
- Apple Developer Documentation — Photo Editing Extension Info.plist (NSExtensionPointIdentifier: com.apple.photo-editing, PHSupportedMediaTypes)
- Existing WatermarkCore codebase — WatermarkEngine, WatermarkConfiguration (Codable), AppGroupConfigSync, ControlsView, WatermarkConfigurable protocol
- Existing ShareExtension — ShareViewController (UIHostingController pattern), ShareExtensionViewModel, ShareExtensionRootView, Info.plist, entitlements

### Secondary (MEDIUM confidence)
- Developer forums/Stack Overflow — PHAdjustmentData effective size limit (~2 MB experiential, not documented)
- Developer forums — PHContentEditingOutput HEIC compatibility reports (mixed; some report success on iOS 17+, others report error 3302)
- Developer forums — Extension sandbox memory ceiling (~120 MB) confirmed by multiple sources for share and photo editing extensions
- objc.io — Photo Editing Extension implementation guide (PHContentEditingController lifecycle patterns)

### Tertiary (LOW confidence)
- Training data — PHContentEditingController lifecycle method signatures (verified against Apple docs above, now HIGH)
- Training data — Photos Edit Extension memory limits (verified against developer forum sources, now MEDIUM)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — All APIs are Apple system frameworks, well-documented, and stable since iOS 8. Existing WatermarkCore reuse is confirmed by codebase inspection.
- Architecture: HIGH — PHContentEditingController + UIHostingController pattern is directly validated by the existing ShareViewController implementation and Apple documentation. No speculative architecture.
- Pitfalls: MEDIUM — PHAdjustmentData size limits and HEIC format compatibility at renderedContentURL are based on developer reports, not Apple documentation. Empirical device testing needed.

**Research date:** 2026-06-18
**Valid until:** 2026-07-18 (Apple APIs are stable; no expected changes to PHContentEditingController)
