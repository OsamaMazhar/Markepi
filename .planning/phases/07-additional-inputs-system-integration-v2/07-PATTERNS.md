# Phase 07: Additional Inputs & System Integration (v2) - Pattern Map

**Mapped:** 2026-06-18
**Files analyzed:** 20 new/modified files
**Analogs found:** 15 / 20

## File Classification

### New Files

| New File | Role | Data Flow | Closest Analog | Match Quality |
|----------|------|-----------|----------------|---------------|
| `Packages/WatermarkCore/Sources/WatermarkCore/Processing/LivePhotoProcessor.swift` | service | streaming/transform | `Processing/VideoProcessor.swift` | role-match |
| `Packages/WatermarkCore/Sources/WatermarkCore/Processing/SignatureRenderer.swift` | utility (renderer) | transform | `Rendering/ImageWatermarkRenderer.swift` | exact |
| `Packages/WatermarkCore/Sources/WatermarkCore/Models/SignatureInput.swift` | model | CRUD | `Models/TextWatermarkInput.swift` | exact |
| `Packages/WatermarkCore/Sources/WatermarkCore/UI/SignatureCaptureView.swift` | component | event-driven | `UI/LogoPickerView.swift` | role-match |
| `App/AppDelegate.swift` | config/bridge | event-driven | `ShareExtension/ShareViewController.swift` | partial |
| `App/SceneDelegate.swift` | bridge/utility | event-driven | _(none in codebase)_ | no-exact-match |
| `App/Intents/WatermarkPhotoIntent.swift` | intent/provider | event-driven | _(none in codebase)_ | no-exact-match |
| `App/Intents/WatermarkVideoIntent.swift` | intent/provider | event-driven | _(none in codebase)_ | no-exact-match |
| `App/Intents/WatermarkAppShortcuts.swift` | provider | event-driven | _(none in codebase)_ | no-exact-match |

### Modified Files

| Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---------------|------|-----------|----------------|---------------|
| `Packages/.../Engine/WatermarkEngine.swift` | engine | transform | **self** (existing pattern extended) | exact |
| `Packages/.../Engine/PipelineError.swift` | enum/model | CRUD | **self** (existing pattern extended) | exact |
| `Packages/.../Models/WatermarkConfiguration.swift` | model | CRUD | **self** (existing pattern extended) | exact |
| `Packages/.../Models/ProcessingResult.swift` | model | CRUD | **self** (existing pattern extended) | exact |
| `Packages/.../UI/ControlsView.swift` | component | request-response | **self** (existing pattern extended) | exact |
| `Packages/.../UI/LayerListView.swift` | component | request-response | **self** (existing pattern extended) | exact |
| `Packages/.../UI/WatermarkConfigurable.swift` | protocol | request-response | **self** (existing pattern extended) | exact |
| `App/WatermarkApp.swift` | app entry | event-driven | **self** (existing pattern extended) | exact |
| `App/Info.plist` | config | static | `ShareExtension/Info.plist` (plist declarative pattern) | role-match |
| `App/ViewModels/WatermarkViewModel.swift` | controller | CRUD/event-driven | **self** (existing pattern extended) | exact |
| `App/Views/ContentView.swift` | component | request-response | **self** (existing pattern extended) | exact |

---

## Pattern Assignments

### 1. `SignatureInput.swift` (model, data model)

**Analog:** `Models/TextWatermarkInput.swift`

**Imports pattern** (lines 1):
```swift
import CoreImage
```

**Struct pattern** (lines 3-71):
```swift
/// Configuration for a text-based watermark overlay.
/// Uses SF system fonts per D-02 decision. Defaults: system font size 72, white color, opacity 0.8.
public struct TextWatermarkInput: Sendable, Codable {
    public let text: String
    public let fontSize: CGFloat
    public let color: CGColor
    public let opacity: CGFloat

    public init(
        text: String,
        fontSize: CGFloat = 72,
        color: CGColor = CGColor(red: 1, green: 1, blue: 1, alpha: 1),
        opacity: CGFloat = 0.8
    ) { ... }

    // MARK: - Codable (CGColor)
    enum CodingKeys: String, CodingKey {
        case text, fontSize, colorRGBA, opacity
    }
    // ... CGColor encode/decode ...
}
```

**CGColor Codable pattern** (lines 45-70) — **CRITICAL: exact copy for SignatureInput.inkColor**:
```swift
public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    text = try container.decode(String.self, forKey: .text)
    fontSize = try container.decode(CGFloat.self, forKey: .fontSize)
    opacity = try container.decode(CGFloat.self, forKey: .opacity)
    let rgba = try container.decode([CGFloat].self, forKey: .colorRGBA)
    guard rgba.count == 4,
          let cgColor = CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                                components: rgba) else {
        throw DecodingError.dataCorruptedError(forKey: .colorRGBA, in: container,
            debugDescription: "Invalid RGBA components for CGColor")
    }
    color = cgColor
}

public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(text, forKey: .text)
    try container.encode(fontSize, forKey: .fontSize)
    try container.encode(opacity, forKey: .opacity)
    let components = color.components ?? [1, 1, 1, 1]
    let rgba: [CGFloat] = components.count >= 4
        ? [components[0], components[1], components[2], components[3]]
        : [1, 1, 1, 1]
    try container.encode(rgba, forKey: .colorRGBA)
}
```

**Also reference:** `Models/ImageWatermarkInput.swift` (lines 1-45) for validation-in-init pattern (throw `PipelineError` for invalid data).

---

### 2. `WatermarkConfiguration.swift` — Add `.signature` case (model, modified)

**Analog:** `Models/WatermarkConfiguration.swift` (existing `WatermarkLayer` enum)

**WatermarkLayer enum pattern to extend** (lines 77-117):
```swift
public enum WatermarkLayer: Sendable {
    case text(TextWatermarkInput, position: WatermarkPosition, scale: CGFloat, opacity: CGFloat, isVisible: Bool)
    case image(ImageWatermarkInput, position: WatermarkPosition, scale: CGFloat, opacity: CGFloat, isVisible: Bool)
    // NEW: case signature(SignatureInput, position: WatermarkPosition, scale: CGFloat, opacity: CGFloat, isVisible: Bool)

    public var position: WatermarkPosition {
        switch self {
        case .text(_, let position, _, _, _): return position
        case .image(_, let position, _, _, _): return position
        // NEW: case .signature(_, let position, _, _, _): return position
        }
    }
    // ... repeat for scale, opacity, isVisible ...
}
```

**Codable extension to extend** (lines 122-166):
```swift
enum LayerType: String, Codable {
    case text, image
    // NEW: case signature
}

// In init(from:):
// NEW: case .signature:
//     let config = try container.decode(SignatureInput.self, forKey: .signatureConfig)
//     self = .signature(config, position: position, scale: scale, opacity: opacity, isVisible: isVisible)

// In encode(to:):
// NEW: case .signature(let config, _, _, let opacity, let isVisible):
//     try container.encode(LayerType.signature, forKey: .type)
//     try container.encode(config, forKey: .signatureConfig)
//     try container.encode(opacity, forKey: .opacity)
//     try container.encode(isVisible, forKey: .isVisible)
```

**strippingImageData() to extend** (lines 279-309) — add `.signature` no-op case:
```swift
case .signature:
    return layer  // Signature stroke data is small (<100KB), no stripping needed (per D-07)
```

---

### 3. `SignatureRenderer.swift` (utility, transform)

**Analog:** `Rendering/ImageWatermarkRenderer.swift` (lines 1-61)

**Imports and struct pattern:**
```swift
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import PencilKit  // NEW

public struct SignatureRenderer {
    /// Renders a signature watermark to a CIImage.
    /// - Parameter input: Signature input (PKDrawing Data, ink color, stroke width)
    /// - Returns: A CIImage representing the rendered signature with transparent background
    public static func render(input: SignatureInput) throws -> CIImage { ... }
}
```

**Core render pattern** (from ImageWatermarkRenderer lines 27-60):
```swift
// 1. Decode data to CIImage
guard let ciImage = CIImage(data: config.pngData) else {
    throw PipelineError.invalidImageData
}
// 2. Scale via CGAffineTransform
let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: config.scale, y: config.scale))
// 3. Apply opacity via CIFilter.colorMatrix alpha modulation
if config.opacity < 1.0 {
    let colorMatrix = CIFilter.colorMatrix()
    colorMatrix.inputImage = scaled
    colorMatrix.aVector = CIVector(x: 0, y: 0, z: 0, w: opacity)
    colorMatrix.biasVector = CIVector(x: 0, y: 0, z: 0, w: 0)
    return colorMatrix.outputImage ?? scaled
}
return scaled
```

**For SignatureRenderer:** Replace step 1 with `PKDrawing(data: input.strokeData)?.image(from:scale:)` → `UIImage → CIImage`. Then apply ink color via `CIFilter.colorMatrix` (tint RGB channels), then scale/opacity as above.

---

### 4. `WatermarkEngine.swift` — Add `.signature` in `buildFilterGraph` (engine, modified)

**Analog:** `Engine/WatermarkEngine.swift` `buildFilterGraph()` (lines 172-248)

**Pattern to extend** (lines 186-199):
```swift
for watermark in config.watermarks {
    guard watermark.isVisible else { continue }
    let watermarkImage: CIImage
    switch watermark {
    case .text(let textConfig, _, _, _, _):
        watermarkImage = TextWatermarkRenderer.render(config: textConfig, metadata: metadata)
    case .image(let imageConfig, _, _, _, _):
        watermarkImage = try ImageWatermarkRenderer.render(config: imageConfig)
    // NEW: case .signature(let signatureInput, _, _, _, _):
    //     watermarkImage = try SignatureRenderer.render(input: signatureInput)
    }
    // ... scale, opacity, position (unchanged for new case) ...
}
```

**Scale/opacity/positioning** (lines 201-228) — identical for `.signature` as for `.text`/`.image`:
```swift
let scaled = watermarkImage.transformed(by: CGAffineTransform(scaleX: watermark.scale, y: watermark.scale))
let opacityAdjusted: CIImage
if watermark.opacity < 1.0 {
    let matrix = CIFilter.colorMatrix()
    matrix.inputImage = scaled
    matrix.aVector = CIVector(x: 0, y: 0, z: 0, w: CGFloat(watermark.opacity))
    matrix.biasVector = CIVector(x: 0, y: 0, z: 0, w: 0)
    opacityAdjusted = matrix.outputImage ?? scaled
} else { opacityAdjusted = scaled }
let position = PositionCalculator.position(for: watermark.position, watermarkExtent: ..., baseExtent: extent, padding: config.padding)
```

---

### 5. `LivePhotoProcessor.swift` (service, transform/streaming)

**Analog:** `Processing/VideoProcessor.swift` (lines 1-303)

**Struct + static method pattern** (lines 25-51):
```swift
public struct VideoProcessor {
    public static func process(
        sourceURL: URL,
        config: WatermarkConfiguration,
        onProgress: (@Sendable (Double, TimeInterval?) -> Void)? = nil
    ) async throws -> (outputURL: URL, validation: ExportValidator.ExportValidationResult) { ... }
}
```

**For LivePhotoProcessor:**
```swift
import Photos
import CoreImage
import WatermarkCore

public struct LivePhotoProcessor {
    public static func process(
        pairedAsset: LivePhotoPair,
        config: WatermarkConfiguration
    ) async throws -> ProcessingResult { ... }
}
```

**Error handling pattern** (from VideoProcessor lines 64-67):
```swift
guard let videoTrack = videoTracks.first else {
    throw PipelineError.videoTrackNotFound
}
```

**Cleanup/fallback pattern** (from signature capture pattern, based on VideoProcessor's `defer` and try/catch):
```swift
// PHLivePhotoEditingContext init may return nil
guard let editingContext = PHLivePhotoEditingContext(livePhotoEditingInput: input) else {
    throw PipelineError.livePhotoUnsupported
}
```

---

### 6. `PipelineError.swift` — Add `livePhotoUnsupported` (enum, modified)

**Analog:** `Engine/PipelineError.swift` (lines 1-189)

**Pattern for adding error cases** (lines 56-80 for video errors):
```swift
// MARK: - Forward-declared Live Photo Errors (Plan 07)
/// Live Photo editing context initialization failed
case livePhotoUnsupported
```

**errorDescription pattern** (lines 87-137):
```swift
case .livePhotoUnsupported:
    return "This Live Photo could not be processed. The format may be unsupported."
```

**_isEqual pattern** (lines 160-188):
```swift
case (.livePhotoUnsupported, .livePhotoUnsupported): return true
```

---

### 7. `SignatureCaptureView.swift` (component, event-driven)

**Analog:** `UI/LogoPickerView.swift` (lines 1-120)

**Generic ViewModel + modal pattern** (lines 10-11, 21-32):
```swift
public struct LogoPickerView<ViewModel: WatermarkConfigurable & Observable>: View {
    @Bindable var viewModel: ViewModel
    public init(viewModel: ViewModel) { self.viewModel = viewModel }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Logo Watermark")
                .font(.title3.weight(.semibold))
            if hasLogoLayer { logoSelectedView }
            else { addLogoButton }
        }
        .confirmationDialog("Add Logo Watermark", isPresented: $showConfirmationDialog) { ... }
        // modal triggers
    }
}
```

**For SignatureCaptureView:** Follow same structure — "Signature" title, `if hasSignatureLayer` → show selected state, else → "Add Signature" button that presents full-screen modal. The PKCanvasView is a UIViewRepresentable embedded in the modal sheet.

**UIViewRepresentable pattern** (no direct analog in codebase; use RESEARCH.md Pattern 3):
```swift
import SwiftUI
import PencilKit

struct SignatureCanvasView: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    var inkColor: UIColor = .black
    var strokeWidth: CGFloat = 3.0

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawingPolicy = .anyInput
        canvas.tool = PKInkingTool(.pen, color: inkColor, width: strokeWidth)
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.delegate = context.coordinator
        return canvas
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        if uiView.drawing != drawing { uiView.drawing = drawing }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: SignatureCanvasView
        init(_ parent: SignatureCanvasView) { self.parent = parent }
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            DispatchQueue.main.async { self.parent.drawing = canvasView.drawing }
        }
    }
}
```

---

### 8. `LayerListView.swift` — Add signature icon/description (component, modified)

**Analog:** `UI/LayerListView.swift` (lines 72-87)

**layerIcon pattern to extend:**
```swift
private func layerIcon(for layer: WatermarkLayer) -> String {
    switch layer {
    case .text: return "textformat"
    case .image: return "photo"
    // NEW: case .signature: return "signature"
    }
}
```

**layerDescription pattern to extend:**
```swift
private func layerDescription(for layer: WatermarkLayer) -> String {
    switch layer {
    case .text(let input, _, _, _, _): ...
    case .image: return "Logo"
    // NEW: case .signature: return "Signature"
    }
}
```

---

### 9. `WatermarkConfigurable.swift` — Add `addSignatureLayer` (protocol, modified)

**Analog:** `UI/WatermarkConfigurable.swift` (lines 16-43)

**Pattern to extend** (add after `addLogoLayer`):
```swift
@MainActor
public protocol WatermarkConfigurable: AnyObject {
    // ... existing ...
    func addLogoLayer(pngData: Data)
    // NEW:
    func addSignatureLayer(strokeData: Data, inkColor: CGColor, strokeWidth: CGFloat)
    // ... existing ...
}
```

---

### 10. `WatermarkViewModel.swift` — Add signature, Live Photo, file import, quick action methods (controller, modified)

**Analog:** `App/ViewModels/WatermarkViewModel.swift` (lines 1-431)

**addLogoLayer pattern to clone for addSignatureLayer** (lines 340-353):
```swift
func addLogoLayer(pngData: Data) {
    guard let _ = CIImage(data: pngData) else {
        errorMessage = "The selected image is not a valid PNG file."
        showError = true
        return
    }
    guard let input = try? ImageWatermarkInput(pngData: pngData) else {
        errorMessage = "The selected image is not a valid PNG file."
        showError = true
        return
    }
    config.watermarks.append(.image(input, position: .bottomRight, scale: 0.15))
    activeLayerIndex = config.watermarks.count - 1
}

// NEW addSignatureLayer:
func addSignatureLayer(strokeData: Data, inkColor: CGColor, strokeWidth: CGFloat) {
    let input = SignatureInput(strokeData: strokeData, inkColor: inkColor, strokeWidth: strokeWidth)
    config.watermarks.append(.signature(input, position: .bottomRight, scale: 0.15))
    activeLayerIndex = config.watermarks.count - 1
}
```

**updateLayerPosition/updateLayerScale pattern to extend** (lines 363-384):
```swift
func updateLayerPosition(at index: Int, position: WatermarkPosition) {
    // ... switch over .text, .image ...
    // NEW: case .signature(let input, _, _):
    //     config.watermarks[index] = .signature(input, position: position, scale: scale)
}
```

**handleSelection Live Photo pairing** — extend `handleSelection` (lines 76-102):
```swift
func handleSelection(_ items: [PhotosPickerItem]) {
    Task {
        // NEW: detect Live Photo pairs before loading (D-03)
        let pairedItems = detectLivePhotoPairs(items)
        // ... load non-paired items individually, load paired items together ...
    }
}
```

**New methods** — `handleIncomingFile(url:)`, `handleQuickAction(_:)`, `fetchMostRecentPhoto()`, `loadFromClipboard()` — follow same `@MainActor` + `errorMessage`/`showError` error pattern as `addLogoLayer`.

---

### 11. `AppDelegate.swift` (bridge, event-driven)

**Analog:** `ShareExtension/ShareViewController.swift` (lines 1-84) — UIController entry point bridge pattern

**Pattern:** Simple `NSObject` + `UIApplicationDelegate` class (no hosting controller needed — just scene configuration):
```swift
import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: session.role)
        config.delegateClass = SceneDelegate.self
        return config
    }
}
```

**No exact analog in codebase** — follow RESEARCH.md Pattern 5 (lines 542-551). This is a standard Apple pattern.

---

### 12. `SceneDelegate.swift` (bridge/utility, event-driven)

**Analog:** No direct analog in codebase; uses `NotificationCenter` communication pattern from `ShareViewController` (viewModel closure communication).

**Pattern** (from RESEARCH.md lines 553-580):
```swift
import UIKit

class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options: UIScene.ConnectionOptions) {
        if let shortcutItem = options.shortcutItem {
            handleShortcut(shortcutItem)
        }
    }

    func windowScene(_ windowScene: UIWindowScene,
                     performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        handleShortcut(shortcutItem)
        completionHandler(true)
    }

    private func handleShortcut(_ item: UIApplicationShortcutItem) {
        NotificationCenter.default.post(
            name: .didReceiveQuickAction,
            object: item.type
        )
    }
}

extension Notification.Name {
    static let didReceiveQuickAction = Notification.Name("didReceiveQuickAction")
}
```

---

### 13. `WatermarkApp.swift` — Add `.onOpenURL`, `AppDelegateAdaptor` (app entry, modified)

**Analog:** `App/WatermarkApp.swift` (lines 1-12)

**Pattern to extend:**
```swift
import SwiftUI

@main
struct WatermarkApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate  // NEW
    @State private var viewModel = WatermarkViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .onOpenURL { url in                              // NEW
                    viewModel.handleIncomingFile(url: url)
                }
                .onReceive(NotificationCenter.default.publisher( // NEW
                    for: .didReceiveQuickAction
                )) { notif in
                    guard let type = notif.object as? String else { return }
                    viewModel.handleQuickAction(type)
                }
        }
    }
}
```

---

### 14. `Info.plist` — Add CFBundleDocumentTypes, UIApplicationShortcutItems (config, static)

**Analog:** `ShareExtension/Info.plist` (declarative plist pattern, lines 1-25)

**Pattern** — follow the same XML plist structure with `<dict>/<key>/<array>` nesting. Add `CFBundleDocumentTypes` array with two dicts (Image, Video) and `UIApplicationShortcutItems` array with two dicts. See RESEARCH.md Pattern 4 (lines 442-467) and Pattern 5 (lines 521-540) for exact keys/values.

---

### 15. `ContentView.swift` — Add `.fileImporter`, Browse Files button (component, modified)

**Analog:** `UI/LogoPickerView.swift` `.fileImporter` usage (lines 47-57):
```swift
.fileImporter(
    isPresented: $showFileImporter,
    allowedContentTypes: [.png]
) { result in
    switch result {
    case .success(let url):
        guard let data = try? Data(contentsOf: url) else { return }
        viewModel.addLogoLayer(pngData: data)
    case .failure:
        break
    }
}
```

**For ContentView:** Copy this `.fileImporter` pattern with `allowedContentTypes: [.image, .movie]` (broader set), and on success call `viewModel.handleIncomingFile(url:)`.

---

### 16. `WatermarkPhotoIntent.swift` / `WatermarkVideoIntent.swift` (intent, event-driven)

**No exact analog in codebase.** Follow RESEARCH.md Pattern 6 (lines 602-673).

```swift
import AppIntents
import WatermarkCore

@AssistantIntent(schema: .photos.edit)
struct WatermarkPhotoIntent: AppIntent {
    static var title: LocalizedStringResource = "Watermark Photo"
    static var description = IntentDescription("Adds a watermark overlay to a photo.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Photo",
               description: "The photo to watermark.",
               supportedTypeIdentifiers: ["public.image"])
    var photo: IntentFile

    @Parameter(title: "Configuration",
               description: "Optional watermark configuration as JSON.",
               default: nil)
    var configJSON: String?

    @MainActor
    func perform() async throws -> some IntentResult {
        // Store IntentFile data + config in App Group for main app to consume
        if let data = photo.data {
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("intent_photo_\(UUID().uuidString)")
            try data.write(to: tempURL)
            UserDefaults(suiteName: "group.com.watermark.app")?
                .set(tempURL.absoluteString, forKey: "pendingIntentMediaURL")
        }
        if let json = configJSON {
            UserDefaults(suiteName: "group.com.watermark.app")?
                .set(json, forKey: "pendingIntentConfigJSON")
        }
        return .result()
    }
}
```

---

### 17. `WatermarkAppShortcuts.swift` (provider, event-driven)

**No exact analog in codebase.** Follow RESEARCH.md Pattern 6 (lines 650-673).

```swift
import AppIntents

struct WatermarkAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: WatermarkPhotoIntent(),
            phrases: [
                "Watermark a photo in \(.applicationName)",
                "Add watermark to photo with \(.applicationName)"
            ],
            shortTitle: "Watermark Photo",
            systemImageName: "photo.badge.plus"
        )
        AppShortcut(
            intent: WatermarkVideoIntent(),
            phrases: [
                "Watermark a video in \(.applicationName)",
                "Add watermark to video with \(.applicationName)"
            ],
            shortTitle: "Watermark Video",
            systemImageName: "video.badge.plus"
        )
    }
}
```

---

### 18. `ControlsView.swift` — Add SignaturePickerView (component, modified)

**Analog:** `UI/ControlsView.swift` `LogoPickerView` slot (line 36):
```swift
LogoPickerView(viewModel: viewModel)
// NEW: add after LogoPickerView:
// SignaturePickerView(viewModel: viewModel)
```

---

## Shared Patterns

### CGColor Codable
**Source:** `Models/TextWatermarkInput.swift` lines 45-70
**Apply to:** `SignatureInput.swift`
**Pattern:** Encode CGColor components as RGBA `[CGFloat]` array. Decode via `CGColor(colorSpace: CGColorSpace.sRGB!, components: rgba)`. Use `decodeIfPresent` with default values for backward compatibility.

### WatermarkLayer Codable
**Source:** `Models/WatermarkConfiguration.swift` lines 122-166
**Apply to:** `WatermarkConfiguration.swift` (new `.signature` case)
**Pattern:** Discriminated union enum with `LayerType` for type tag. Each case gets its own config key. `decodeIfPresent` on `opacity` (default 1.0) and `isVisible` (default true).

### Generic ViewModel Protocol
**Source:** `UI/WatermarkConfigurable.swift` lines 16-43
**Apply to:** `WatermarkViewModel.swift`, new protocol methods
**Pattern:** `@MainActor public protocol WatermarkConfigurable: AnyObject` with `config: WatermarkConfiguration`, layer management methods. All Views are `struct ViewName<ViewModel: WatermarkConfigurable & Observable>: View`.

### @Observable + @MainActor ViewModel
**Source:** `App/ViewModels/WatermarkViewModel.swift` line 12
**Apply to:** All ViewModel modifications
**Pattern:** `@Observable @MainActor final class WatermarkViewModel: WatermarkConfigurable`. All state mutations are on the main actor. Error handling uses `errorMessage`/`showError` String/Bool pair.

### App Group Config Sync
**Source:** `Storage/AppGroupConfigSync.swift` lines 1-67
**Apply to:** Intent config passing, signature config serialization
**Pattern:** `JSONEncoder` → `UserDefaults(suiteName:).set(data, forKey:)` for writes. `UserDefaults(suiteName:).data(forKey:)` → `JSONDecoder` for reads. Suite name: `"group.com.watermark.app"`.

### Static Processor Struct Pattern
**Source:** `Processing/VideoProcessor.swift` lines 25-303
**Apply to:** `LivePhotoProcessor.swift`
**Pattern:** `public struct XxxProcessor { public static func process(...) async throws -> ... }`. Pipelined stages documented via doc comments. Error logging via `os_log`. Multiple guard/throw validation steps.

### Static Renderer Struct Pattern
**Source:** `Rendering/ImageWatermarkRenderer.swift` lines 1-61, `Rendering/TextWatermarkRenderer.swift` lines 1-81
**Apply to:** `SignatureRenderer.swift`
**Pattern:** `public struct XxxRenderer { public static func render(config:) throws -> CIImage }`. Platform conditional imports (`#if canImport(UIKit)`). Returns pure CIImage for lazy filter graph compositing.

---

## No Analog Found

Files with no close match in the codebase (planner should use RESEARCH.md patterns):

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `App/SceneDelegate.swift` | bridge | event-driven | No SwiftUI SceneDelegate exists in codebase; use RESEARCH.md Pattern 5 |
| `App/Intents/WatermarkPhotoIntent.swift` | intent | event-driven | App Intents not previously used; use RESEARCH.md Pattern 6 |
| `App/Intents/WatermarkVideoIntent.swift` | intent | event-driven | Same as above — copy WatermarkPhotoIntent pattern, swap UTIs |
| `App/Intents/WatermarkAppShortcuts.swift` | provider | event-driven | No prior AppShortcutsProvider; use RESEARCH.md Pattern 6 |
| `App/AppDelegate.swift` | config | event-driven | No prior SwiftUI AppDelegateAdaptor; use RESEARCH.md Pattern 5 |

---

## Metadata

**Analog search scope:** `Packages/WatermarkCore/Sources/WatermarkCore/*`, `App/*`, `ShareExtension/*`, `PhotoEditExtension/*`
**Files scanned:** 30
**Pattern extraction date:** 2026-06-18
**Confidence:** HIGH — All modified files have exact analogs (themselves). Most new files have strong analog matches in the same package. Only App Intents and App/Scene delegates are novel patterns requiring RESEARCH.md guidance.
