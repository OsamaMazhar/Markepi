# Phase 04: Photos Edit Extension & Polish - Pattern Map

**Mapped:** 2026-06-18
**Files analyzed:** 8 (7 new, 1 modified)
**Analogs found:** 7 / 8

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `PhotoEditExtension/PhotoEditingViewController.swift` | controller | request-response (PHContentEditingController lifecycle) | `ShareExtension/ShareViewController.swift` | exact (role + pattern match) |
| `PhotoEditExtension/PhotosExtensionRootView.swift` | component | request-response (SwiftUI host for ControlsView) | `ShareExtension/ShareExtensionRootView.swift` | exact (role + layout match) |
| `PhotoEditExtension/PhotosExtensionViewModel.swift` | model | request-response (@Observable ViewModel, WatermarkConfigurable) | `ShareExtension/ShareExtensionViewModel.swift` | exact (role + protocol conformance match) |
| `PhotoEditExtension/Info.plist` | config | n/a (extension manifest) | `ShareExtension/Info.plist` | role-match (different extension type) |
| `PhotoEditExtension/PhotoEditExtension.entitlements` | config | n/a (App Group capability) | `ShareExtension/ShareExtension.entitlements` | exact |
| `Watermark.xcodeproj/project.pbxproj` (modified) | config | n/a (Xcode project structure) | existing `project.pbxproj` → WatermarkApp target pattern | exact (same project, new target) |
| `Packages/WatermarkCore/Tests/WatermarkCoreTests/PhotosExtensionTests.swift` | test | transform (unit/integration tests) | `Packages/WatermarkCore/Tests/WatermarkCoreTests/WatermarkEngineTests.swift` | exact (Swift Testing framework, same target) |
| `.planning/phases/04-photos-edit-extension-polish/04-QA-CHECKLIST.md` | documentation | n/a (manual QA checklist) | *(no existing QA checklist files)* | none (new artifact type) |

---

## Pattern Assignments

### `PhotoEditExtension/PhotoEditingViewController.swift` (controller, request-response)

**Analog:** `ShareExtension/ShareViewController.swift` (84 lines)

**Why:** Both are `UIViewController` subclasses that host SwiftUI via `UIHostingController`. Both serve as the principal class for their respective app extensions. The Photos extension adds `PHContentEditingController` protocol conformance and bridges its lifecycle callbacks to the ViewModel — the same delegation pattern as `ShareViewController` bridging `NSItemProvider` loading and `completeRequest` to its ViewModel.

**Imports pattern** (ShareViewController.swift lines 1-2):
```swift
import UIKit
import SwiftUI
```
For PhotoEditingViewController, adds `PhotosUI`:
```swift
import UIKit
import SwiftUI
import PhotosUI
import WatermarkCore
```

**Hosting controller setup pattern** (ShareViewController.swift lines 32-45):
```swift
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
```

**Property declaration pattern** (ShareViewController.swift lines 18-19):
```swift
private let viewModel = ShareExtensionViewModel()
private var hostingController: UIHostingController<ShareExtensionRootView>?
```
For PhotoEditingViewController:
```swift
private let viewModel = PhotosExtensionViewModel()
private var hostingController: UIHostingController<PhotosExtensionRootView>?
```

**Delegation-to-ViewModel pattern** (ShareViewController.swift lines 52-58):
```swift
private func setupDismissHandler() {
    viewModel.completeRequest = { [weak self] in
        self?.extensionContext?.completeRequest(returningItems: nil)
    }
    viewModel.openURL = { [weak self] url in
        self?.extensionContext?.open(url, completionHandler: nil)
    }
}
```
For PhotoEditingViewController, this becomes the PHContentEditingController protocol methods bridging to the ViewModel:
```swift
func canHandle(_ adjustmentData: PHAdjustmentData) -> Bool {
    return viewModel.canHandle(adjustmentData)
}

func startContentEditing(with contentEditingInput: PHContentEditingInput,
                         placeholderImage: UIImage) {
    viewModel.startEditing(with: contentEditingInput, placeholderImage: placeholderImage)
    setupHostingController()
}

func finishContentEditing(completionHandler: @escaping (PHContentEditingOutput?) -> Void) {
    viewModel.finishEditing(completionHandler: completionHandler)
}

func cancelContentEditing() {
    viewModel.cancelEditing()
}

var shouldShowCancelConfirmation: Bool {
    return viewModel.hasUnsavedChanges
}
```

**Error handling pattern:** The ViewModel owns all error state (`showError`, `errorMessage`). The ViewController does NO direct error handling — it delegates all work and state to the ViewModel. This is the established pattern from both `WatermarkViewModel` and `ShareExtensionViewModel`.

---

### `PhotoEditExtension/PhotosExtensionRootView.swift` (component, request-response)

**Analog:** `ShareExtension/ShareExtensionRootView.swift` (223 lines)

**Why:** Both are SwiftUI root views hosting `ControlsView` in an extension context. Both use the 60/40 preview/controls split. The Photos extension differs in: (1) "Done" button instead of "Share" (D-02), (2) no multi-item progress bar, (3) no share sheet, (4) no unsupported type fallback.

**Imports pattern** (ShareExtensionRootView.swift lines 1-2):
```swift
import SwiftUI
import WatermarkCore
```

**Root view struct declaration** (ShareExtensionRootView.swift line 10):
```swift
struct ShareExtensionRootView: View {
    @State var viewModel: ShareExtensionViewModel
```
For Photos extension:
```swift
struct PhotosExtensionRootView: View {
    @State var viewModel: PhotosExtensionViewModel
```

**Layout pattern — 60/40 split** (ShareExtensionRootView.swift lines 14-58):
```swift
GeometryReader { geometry in
    VStack(spacing: 0) {
        previewArea
            .frame(height: geometry.size.height * 0.60)

        Color(.separator)
            .frame(height: 1)

        // ... warnings and indicator overlays ...

        controlsArea
            .frame(height: geometry.size.height * 0.40)
    }
}
```

**Preview area pattern** (ShareExtensionRootView.swift lines 96-141):
```swift
private var previewArea: some View {
    ZStack {
        if viewModel.isLoadingMedia {
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                Text("Loading...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } else if let previewImage = viewModel.previewImage {
            Image(uiImage: previewImage)
                .resizable()
                .scaledToFit()
        } else if let errorMessage = viewModel.errorMessage, viewModel.previewImage == nil {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "photo")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text("Preparing photo...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
```
For Photos extension: replace "Preparing photo..." with "Loading from Photos..." and remove "Photo" system image — use a more descriptive placeholder.

**Controls area pattern** (ShareExtensionRootView.swift lines 145-147):
```swift
private var controlsArea: some View {
    ControlsView(viewModel: viewModel)
}
```
**Identical in Photos extension** — `ControlsView` is generic over `WatermarkConfigurable`, reused unchanged.

**Preview regeneration trigger** (ShareExtensionRootView.swift lines 88-91):
```swift
.task(id: viewModel.previewIdentifier) {
    guard viewModel.sourceURL != nil else { return }
    await viewModel.generatePreview()
}
```

**Key difference — Done button instead of Share:** The Photos extension does NOT use `ControlsView`'s built-in share button. Instead, the root view should override or replace the button behavior. Options:
1. Add a local "Done" button overlay in `PhotosExtensionRootView` that calls `viewModel.finishEditing()`
2. Or: modify the `ControlsView` share button behavior via a callback closure on the ViewModel

**Recommended approach per D-02:** The root view presents a "Done" toolbar button. When tapped, it calls `viewModel.finishEditing()` which triggers render → output → `finishContentEditing` callback.

**Video preview indicator** (ShareExtensionRootView.swift lines 38-54): Copy the "▶ Video" overlay for the Photos extension as well.

---

### `PhotoEditExtension/PhotosExtensionViewModel.swift` (model, request-response)

**Analog:** `ShareExtension/ShareExtensionViewModel.swift` (689 lines)

**Why:** Both are `@Observable @MainActor` ViewModels conforming to `WatermarkConfigurable`. Both manage config, source URL, preview generation, and full-resolution rendering. The key differences: Photos extension uses `PHContentEditingInput` instead of `NSItemProvider`, has a `finishContentEditing` callback instead of `completeRequest`/share sheet, and must handle `PHAdjustmentData` for undo/re-edit.

**Imports pattern** (ShareExtensionViewModel.swift lines 1-8):
```swift
import CoreImage
import Foundation
import Observation
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import WatermarkCore
```

**@Observable @MainActor declaration + WatermarkConfigurable conformance** (ShareExtensionViewModel.swift lines 17-18):
```swift
@Observable @MainActor
final class ShareExtensionViewModel: WatermarkConfigurable {
```
For Photos extension:
```swift
@Observable @MainActor
final class PhotosExtensionViewModel: WatermarkConfigurable {
```

**Config property with AppGroupConfigSync** (ShareExtensionViewModel.swift lines 26-28):
```swift
var config: WatermarkConfiguration {
    didSet { AppGroupConfigSync.save(config) }
}
```
**Identical** — this is the canonical pattern across ALL ViewModels (WatermarkViewModel, ShareExtensionViewModel). Copy exactly.

**Init pattern** (ShareExtensionViewModel.swift lines 138-148):
```swift
init() {
    let defaultConfig = WatermarkConfiguration(watermarks: [
        .text(
            TextWatermarkInput(text: "", fontSize: 48, color: CGColor(gray: 1, alpha: 1), opacity: 1.0),
            position: .bottomRight,
            scale: 0.15
        )
    ])
    self.config = AppGroupConfigSync.load() ?? defaultConfig
}
```
**Copy exactly** — same default config, same AppGroupConfigSync.load() fallback.

**Core state properties** (from ShareExtensionViewModel, extract the subset relevant to single-item Photos editing):
```swift
var config: WatermarkConfiguration { didSet { AppGroupConfigSync.save(config) } }
var sourceURL: URL?
var isVideo: Bool = false
var isLoadingMedia: Bool = true
var previewImage: UIImage?
var isGeneratingPreview: Bool = false
var renderingState: RenderingState = .idle
var fullResResult: ProcessingResult?
var errorMessage: String?
var showError: Bool = false
var showLogoPicker: Bool = false
var activeLayerIndex: Int = 0

// Photos extension-specific
var hasUnsavedChanges: Bool = false  // Pitfall 5: drives shouldShowCancelConfirmation
var showHDRWarning: Bool = false
var hdrWarningMessage: String?

private let engine = WatermarkEngine.shared
private var input: PHContentEditingInput?
private var finishHandler: ((PHContentEditingOutput?) -> Void)?
```

**NOT needed (removed from ShareExtensionViewModel):**
- `sharedItems`, `currentItemIndex`, `itemResults`, `failedItemIndices` — single-item only
- `showShareSheet`, `completeRequest`, `openURL` — no share sheet in edit extension
- `showAudioWarning`, `unsupportedType` — simpler flow

**PHContentEditingInput loading pattern** (replaces `loadSharedMedia(from:)` from ShareExtensionViewModel):
```swift
func startEditing(with input: PHContentEditingInput, placeholderImage: UIImage) {
    self.input = input
    self.previewImage = placeholderImage

    // D-06: source URL from PHContentEditingInput
    if let imageURL = input.fullSizeImageURL {
        self.sourceURL = imageURL
        self.isVideo = false
    } else if let avAsset = input.audiovisualAsset {
        // D-08: video source — AVAsset may be URL-based or composed
        if let urlAsset = avAsset as? AVURLAsset {
            self.sourceURL = urlAsset.url
        }
        self.isVideo = true
    }

    self.isLoadingMedia = false

    // D-05: Re-load config from prior adjustment data (re-edit)
    if let adjustmentData = input.adjustmentData,
       ViewModel.canHandle(adjustmentData),
       let savedConfig = decodeAdjustmentData(adjustmentData) {
        self.config = savedConfig
    }

    Task { await generatePreview() }
}
```

**canHandle pattern** (D-09):
```swift
func canHandle(_ adjustmentData: PHAdjustmentData) -> Bool {
    return adjustmentData.formatIdentifier == AdjustmentConstants.formatIdentifier
        && adjustmentData.formatVersion == AdjustmentConstants.formatVersion
}
```

**Finish editing pattern** (replaces `renderAndPrepareShare` + `presentShareSheet` from ShareExtensionViewModel):
```swift
func finishEditing(completionHandler: @escaping (PHContentEditingOutput?) -> Void) {
    self.finishHandler = completionHandler
    Task { await renderAndCommit() }
}

private func renderAndCommit() async {
    guard let input = input, let sourceURL = sourceURL else {
        finishHandler?(nil)
        return
    }

    renderingState = .rendering

    do {
        let result: ProcessingResult
        if isVideo {
            // D-08: Video processing via existing engine
            result = try await engine.processVideo(sourceURL: sourceURL, config: config)
        } else {
            // D-06: Photo processing via existing engine
            result = try await engine.process(sourceURL: sourceURL, config: config)
        }

        // D-06: Create PHContentEditingOutput
        let output = PHContentEditingOutput(contentEditingInput: input)

        // Copy rendered data to renderedContentURL
        if let renderedURL = result.url {
            let renderedData = try Data(contentsOf: renderedURL)
            try renderedData.write(to: output.renderedContentURL, options: .atomic)
            try? TempFileManager.cleanup(url: renderedURL)
        }

        // D-04: Attach PHAdjustmentData (config as JSON)
        if let adjustmentData = encodeAdjustmentData(config) {
            output.adjustmentData = PHAdjustmentData(
                formatIdentifier: AdjustmentConstants.formatIdentifier,
                formatVersion: AdjustmentConstants.formatVersion,
                data: adjustmentData
            )
        }

        // Check HDR preservation for video
        if let validation = result.videoValidation, !validation.hdrPreserved {
            showHDRWarning = true
            hdrWarningMessage = validation.warnings.first(where: { $0.contains("HDR") })
        }

        renderingState = .done
        finishHandler?(output)
    } catch {
        renderingState = .error(error)
        errorMessage = error.localizedDescription
        showError = true
        finishHandler?(nil)
    }
}

func cancelEditing() {
    finishHandler?(nil)
}
```

**PHAdjustmentData encode/decode** (D-04):
```swift
private enum AdjustmentConstants {
    static let formatIdentifier = "com.watermark.app.adjustment"
    static let formatVersion = "1.0"
}

private func encodeAdjustmentData(_ config: WatermarkConfiguration) -> Data? {
    // Pitfall 1: Strip image watermark PNG data to keep adjustment data small
    let lightweightConfig = config.strippingImageData()
    return try? JSONEncoder().encode(lightweightConfig)
}

private func decodeAdjustmentData(_ data: PHAdjustmentData) -> WatermarkConfiguration? {
    guard data.formatIdentifier == AdjustmentConstants.formatIdentifier,
          data.formatVersion == AdjustmentConstants.formatVersion else { return nil }
    guard var config = try? JSONDecoder().decode(WatermarkConfiguration.self, from: data.data) else { return nil }
    config.rehydrateImageData()
    return config
}
```

**Layer management methods** — copy exactly from ShareExtensionViewModel (lines 557-648):
- `addLogoLayer(pngData:)` (lines 576-589)
- `removeLayer(at:)` (lines 593-599)
- `updateLayerPosition(at:position:)` (lines 605-614)
- `updateLayerScale(at:scale:)` (lines 620-630)
- `toggleWhiteFrame()` (lines 633-639)
- `whiteFrameEnabled` computed property (lines 642-644)

**Preview generation pattern** — copy from ShareExtensionViewModel (lines 415-438):
```swift
func generatePreview() async {
    guard !isGeneratingPreview, sourceURL != nil else { return }
    guard let sourceURL = sourceURL else { return }
    isGeneratingPreview = true
    defer { isGeneratingPreview = false }

    try? await Task.sleep(for: .milliseconds(350))
    guard !Task.isCancelled else { return }

    let result = try? await engine.process(sourceURL: sourceURL, config: config)
    if let url = result?.url,
       let data = try? Data(contentsOf: url),
       let uiImage = UIImage(data: data) {
        previewImage = uiImage
    }
}
```

**previewIdentifier pattern** — copy from ShareExtensionViewModel (lines 667-679) for `.task(id:)`-driven preview regeneration.

**WatermarkConfigurable protocol methods** that must be implemented (from `WatermarkConfigurable.swift` lines 16-33):
- `addLogoLayer(pngData:)` — copy from ShareExtensionViewModel
- `removeLayer(at:)` — copy from ShareExtensionViewModel
- `updateLayerPosition(at:position:)` — copy from ShareExtensionViewModel
- `updateLayerScale(at:scale:)` — copy from ShareExtensionViewModel
- `toggleWhiteFrame()` — copy from ShareExtensionViewModel
- `renderAndPrepareShare()` — **renamed/adapted** to `finishEditing()` for Photos extension
- `presentShareSheet()` — **not applicable** to Photos extension (implement as no-op or remove from protocol requirement for this ViewModel)

---

### `PhotoEditExtension/Info.plist` (config)

**Analog:** `ShareExtension/Info.plist` (25 lines)

**Why:** Both are extension Info.plist files with `NSExtension` configuration. The Photos editing extension uses different `NSExtensionPointIdentifier` and `NSExtensionPrincipalClass` values, and adds `PHSupportedMediaTypes`.

**Structure pattern** (ShareExtension/Info.plist, full file):
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>NSExtension</key>
    <dict>
        <key>NSExtensionAttributes</key>
        <dict>
            <!-- Extension-specific attributes here -->
        </dict>
        <key>NSExtensionPrincipalClass</key>
        <string>$(PRODUCT_MODULE_NAME).PrincipalClassName</string>
        <key>NSExtensionPointIdentifier</key>
        <string>com.apple.EXTENSION-POINT</string>
    </dict>
    <key>CFBundleDisplayName</key>
    <string>Watermark</string>
</dict>
</plist>
```

**Key differences for Photos extension:**

Replace `NSExtensionAttributes` contents:
- Share extension uses: `NSExtensionActivationRule` with `NSExtensionActivationSupportsImageWithMaxCount` and `NSExtensionActivationSupportsMovieWithMaxCount`
- Photos extension uses: `PHSupportedMediaTypes` array with `Image` and `Video`

Replace extension point values:
- `NSExtensionPointIdentifier`: `com.apple.photo-editing`
- `NSExtensionPrincipalClass`: `$(PRODUCT_MODULE_NAME).PhotoEditingViewController`

Copy `CFBundleDisplayName`: `Watermark` (same as share extension).

---

### `PhotoEditExtension/PhotoEditExtension.entitlements` (config)

**Analog:** `ShareExtension/ShareExtension.entitlements` (10 lines)

**Why:** Both declare the App Group entitlement for config sync via `AppGroupConfigSync`. Identical structure and content.

**Exact copy** (ShareExtension/ShareExtension.entitlements lines 1-10):
```xml
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

---

### `Watermark.xcodeproj/project.pbxproj` (modified, config)

**Analog:** existing `project.pbxproj` lines 180-201 (WatermarkApp PBXNativeTarget) + full file structure

**Why:** The existing project has one target (WatermarkApp). We need to add two extension targets (PhotoEditExtension + ShareExtension) following the same structural patterns. The `objectVersion` is 77 (Xcode 16+), hex refs use 3-digit convention.

**Target structure pattern** (from WatermarkApp target, lines 180-201):
```
PBXNativeTarget {
    isa = PBXNativeTarget;
    buildConfigurationList = <configListRef>;
    buildPhases = (<sourcesPhaseRef>, <frameworksPhaseRef>, <resourcesPhaseRef>);
    buildRules = ();
    dependencies = ();
    name = TargetName;
    packageProductDependencies = (<watermarkCoreProductRef>);
    productName = TargetName;
    productReference = <productFileRef>;
    productType = "com.apple.product-type.EXTENSION_TYPE";
}
```

**For PhotoEditExtension target:**
- `productType`: `"com.apple.product-type.app-extension"`
- `name`: `PhotoEditExtension`
- Links to `WatermarkCore` package (same `30E` ref)
- Needs its own Sources, Frameworks, and Resources build phases
- Needs its own build configurations (Debug/Release) with:
  - `INFOPLIST_FILE = PhotoEditExtension/Info.plist`
  - `PRODUCT_BUNDLE_IDENTIFIER = com.watermark.app.photoedit`
  - Extension-specific: `ASSETCATALOG_COMPILER_APPICON_NAME` and app-specific keys NOT needed
  - `CODE_SIGN_ENTITLEMENTS = PhotoEditExtension/PhotoEditExtension.entitlements`
  - `LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks"`

**For ShareExtension target (Phase 3 gap fix):**
- Same structure as PhotoEditExtension but:
  - `name`: `ShareExtension`
  - `INFOPLIST_FILE = ShareExtension/Info.plist`
  - `PRODUCT_BUNDLE_IDENTIFIER = com.watermark.app.share`
  - `CODE_SIGN_ENTITLEMENTS = ShareExtension/ShareExtension.entitlements`

**Embed App Extensions build phase:** Must add to WatermarkApp target a new `PBXCopyFilesBuildPhase` with `dstPath = ""` and `dstSubfolderSpec = 13` (PlugIns) containing the extension product references. This is how the main app embeds its extensions.

**Project-level changes:**
- `targets` array (line 232-234): add both new target refs
- `TargetAttributes` dict (lines 210-215): add entries for both new targets
- New groups under `300 /* = */` for `PhotoEditExtension/` and `ShareExtension/`
- New products under `303 /* Products */` for `.appex` files

**File reference ID convention:** The project uses sequential 3-digit hex IDs (001–503). New IDs should continue in this range (starting around 600 for new sections). PBXBuildFile entries use the same numeric range. Follow the existing pattern where:
- File refs: 100-series
- Build files: 000-series
- Build phases: 200/400-series
- Groups: 300-series
- Targets: 400-series
- Project: 500
- Configurations: 600-series
- Config lists: 700-series

---

### `Packages/WatermarkCore/Tests/WatermarkCoreTests/PhotosExtensionTests.swift` (test)

**Analog:** `Packages/WatermarkCore/Tests/WatermarkCoreTests/WatermarkEngineTests.swift` (1018 lines)

**Why:** Both use Swift Testing (`@Suite`, `@Test`, `#expect`). Both test pipeline correctness for photo processing. The Photos extension tests add PHAdjustmentData encode/decode round-trip and PhotosExtensionViewModel state transitions.

**Imports pattern** (WatermarkEngineTests.swift lines 1-8):
```swift
import Testing
import ImageIO
import CoreImage
import Foundation
#if canImport(UIKit)
import UIKit
#endif
@testable import WatermarkCore
```

**Suite declaration pattern** (WatermarkEngineTests.swift line 14-15):
```swift
@Suite("PhotosExtensionViewModel")
struct PhotosExtensionViewModelTests {
```

**Test structure pattern** (from WatermarkEngineTests.swift):
```swift
@Test("Descriptive test name describing expected behavior")
func testFunctionName() async throws {
    // 1. Create test inputs
    // 2. Execute code under test
    // 3. Assert expectations with #expect
    // 4. Cleanup temp files
}
```

**Helper patterns** — copy these patterns from WatermarkEngineTests.swift:
- `createTempInputFile(data:name:)` (lines 18-22) — create temp files for test input
- `cleanup(_:)` (lines 26-29) — cleanup temp files after test

**Key tests to implement per D-10:**
1. `@Test("PHAdjustmentData encode/decode round-trip with text watermark config")` — encode config, decode it, verify config equality
2. `@Test("PHAdjustmentData strips image PNG data to stay under size limit")` — config with image watermark → encoded data < 1 MB
3. `@Test("canHandle returns true for valid formatIdentifier + formatVersion")` — test the adjustment data format check
4. `@Test("canHandle returns false for unknown formatIdentifier")` — test rejection of foreign adjustment data
5. `@Test("PhotosExtensionViewModel startEditing sets sourceURL from fullSizeImageURL")` — ViewModel initialization with mock input
6. `@Test("cancelEditing calls finishHandler with nil")` — verify cancel behavior
7. `@Test("Pipeline correctness with PHContentEditingInput → photo output")` — end-to-end using WatermarkEngine
8. `@Test("HDR gain map preserved through processing pipeline")` — verify auxiliary data survives
9. `@Test("EXIF metadata preserved through processing pipeline")` — metadata round-trip verification
10. `@Test("Orientation normalization for all 8 EXIF orientations")` — orientation handling

**Error/red-green pattern** (WatermarkEngineTests.swift lines 50-63):
```swift
do {
    let result = try await engine.process(sourceURL: inputURL, config: config)
    #expect(result.url != nil, "Expected non-nil output URL")
    cleanup(inputURL, result.url!)
} catch {
    Issue.record("Engine threw: \(error) — expected in GREEN phase")
    cleanup(inputURL)
}
```

---

## Shared Patterns

### WatermarkConfigurable Protocol
**Source:** `Packages/WatermarkCore/Sources/WatermarkCore/UI/WatermarkConfigurable.swift`
**Apply to:** `PhotosExtensionViewModel`
```swift
@MainActor
public protocol WatermarkConfigurable: AnyObject {
    var config: WatermarkConfiguration { get set }
    var activeLayerIndex: Int { get set }
    var renderingState: RenderingState { get }
    var whiteFrameEnabled: Bool { get }
    func addLogoLayer(pngData: Data)
    func removeLayer(at index: Int)
    func updateLayerPosition(at index: Int, position: WatermarkPosition)
    func updateLayerScale(at index: Int, scale: CGFloat)
    func toggleWhiteFrame()
    func renderAndPrepareShare() async
    func presentShareSheet()
}
```
**Note:** `renderAndPrepareShare()` and `presentShareSheet()` are share-centric. For the Photos extension, `renderAndPrepareShare()` becomes the internal `renderAndCommit()` workflow. `presentShareSheet()` can be a no-op since the Photos extension doesn't have a share sheet. The `ControlsView` share button will need to be adapted for the Photos extension context — either by adding a `finishEditing` callback to the protocol or by using a local override in `PhotosExtensionRootView`.

### App Group Config Sync
**Source:** `Packages/WatermarkCore/Sources/WatermarkCore/Storage/AppGroupConfigSync.swift`
**Apply to:** All extension targets (PhotoEditExtension, ShareExtension, WatermarkApp)
```swift
// Save on every config mutation (in ViewModel didSet):
var config: WatermarkConfiguration {
    didSet { AppGroupConfigSync.save(config) }
}

// Load on ViewModel init:
self.config = AppGroupConfigSync.load() ?? defaultConfig

// Suite name: "group.com.watermark.app" (must match entitlements)
```

### UIHostingController Pattern for Extensions
**Source:** `ShareExtension/ShareViewController.swift` lines 32-45
**Apply to:** `PhotoEditingViewController`
```swift
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
```

### @Observable + @MainActor ViewModel Pattern
**Source:** `ShareExtension/ShareExtensionViewModel.swift` lines 17-18 + `App/ViewModels/WatermarkViewModel.swift` lines 9-10
**Apply to:** `PhotosExtensionViewModel`
```swift
@Observable @MainActor
final class PhotosExtensionViewModel: WatermarkConfigurable {
```
All ViewModels use this exact declaration. All state properties are `var` (not `let`) and declared at the top of the class. Config save is via `didSet`. The private `engine` property uses `WatermarkEngine.shared`.

### RenderingState Enum
**Source:** `Packages/WatermarkCore/Sources/WatermarkCore/Models/ProcessingResult.swift` lines 47-70
**Apply to:** `PhotosExtensionViewModel` rendering state tracking
```swift
public enum RenderingState: Equatable, Sendable {
    case idle
    case rendering
    case done
    case error(Error)
}
```

### Temp File Cleanup
**Source:** `ShareExtension/ShareExtensionViewModel.swift` lines 487-496
**Apply to:** `PhotosExtensionViewModel` post-render cleanup
```swift
if let url = fullResResult?.url {
    try? TempFileManager.cleanup(url: url)
}
fullResResult = nil
renderingState = .idle
```

### ControlsView Reuse
**Source:** `Packages/WatermarkCore/Sources/WatermarkCore/UI/ControlsView.swift`
**Apply to:** `PhotosExtensionRootView`
```swift
ControlsView(viewModel: viewModel)
```
Generic over `<ViewModel: WatermarkConfigurable & Observable>`. The Photos extension ViewModel conforms to both, so `ControlsView` compiles without changes.

---

## No Analog Found

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `04-QA-CHECKLIST.md` | documentation | manual QA validation | No prior QA checklist artifacts exist in the project. This is a new artifact type specific to this phase's manual device testing requirements. Planner should reference the `04-CONTEXT.md` D-11 and D-12 for the checklist template structure. |

### QA Checklist Structure (to be derived from D-11/D-12):
```markdown
# Phase 4: Photos Edit Extension - QA Checklist

**Device:** [Model, iOS version]
**Tester:** [Name]
**Date:** [Date]

## Extension Appearance
| # | Test Case | Expected Behavior | Pass/Fail | Notes |
|---|-----------|-------------------|-----------|-------|
| 1 | Extension visible in Photos edit menu for HEIC photo | "Watermark" option appears | | |
| 2 | Extension visible for JPEG photo | "Watermark" option appears | | |
| ... | ... | ... | ... | ... |

## Photo Processing
| # | Test Case | Expected Behavior | Pass/Fail | Notes |
|---|-----------|-------------------|-----------|-------|
| ... | Watermark renders correctly on photo | Watermark visible at configured position | | |
| ... | HDR gain map preserved | exiftool confirms gain map auxiliary data | | |
| ... | EXIF metadata preserved | exiftool before/after comparison matches | | |
| ... | All 8 EXIF orientations handled | No rotated/stretched output | | |

## Video Processing
| ... | ... | ... | ... | ... |

## PHAdjustmentData (Undo/Re-edit)
| ... | ... | ... | ... | ... |

## Memory & Stability
| ... | ... | ... | ... | ... |

## Deviations
- [Any test failures or behavioral differences from expected]
```

---

## Metadata

**Analog search scope:** `ShareExtension/`, `Packages/WatermarkCore/Sources/WatermarkCore/UI/`, `Packages/WatermarkCore/Sources/WatermarkCore/Storage/`, `Packages/WatermarkCore/Tests/WatermarkCoreTests/`, `App/ViewModels/`, `Watermark.xcodeproj/`
**Files scanned:** 18
**Pattern extraction date:** 2026-06-18
