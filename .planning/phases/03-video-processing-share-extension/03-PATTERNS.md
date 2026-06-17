# Phase 03: Video Processing & Share Extension - Pattern Map

**Mapped:** 2026-06-17
**Files analyzed:** 14 (10 new, 4 modified)
**Analogs found:** 14 / 14

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `WatermarkCore/Sources/WatermarkCore/Processing/VideoProcessor.swift` | service | streaming (AVFoundation pipeline) | `Engine/WatermarkEngine.swift` | role-match |
| `WatermarkCore/Sources/WatermarkCore/Processing/VideoLayerBuilder.swift` | utility | transform (CALayer hierarchy) | `Rendering/WhiteFrameRenderer.swift` | partial (same rendering domain) |
| `WatermarkCore/Sources/WatermarkCore/Processing/VideoFrameExtractor.swift` | utility | streaming (media loading) | `Input/ImageLoader.swift` | role-match |
| `WatermarkCore/Sources/WatermarkCore/Processing/ExportValidator.swift` | utility | transform (post-export validation) | `Input/FormatDetector.swift` | role-match |
| `WatermarkCore/Sources/WatermarkCore/Storage/AppGroupConfigSync.swift` | utility | request-response (UserDefaults I/O) | `Output/TempFileManager.swift` | role-match |
| `ShareExtension/ShareViewController.swift` | controller | request-response (UIKit lifecycle) | `App/Views/Share/ShareSheetView.swift` | partial (UIKit bridge) |
| `ShareExtension/ShareExtensionRootView.swift` | component | request-response (SwiftUI) | `App/Views/ContentView.swift` | role-match |
| `ShareExtension/ShareExtensionViewModel.swift` | model | request-response (@Observable state) | `App/ViewModels/WatermarkViewModel.swift` | exact |
| `WatermarkCore/Engine/WatermarkEngine.swift` (modify) | service | streaming (add video routing) | itself (extend existing) | exact (same file) |
| `WatermarkCore/Engine/PipelineError.swift` (modify) | model | n/a (add error cases) | itself (extend enum) | exact (same file) |
| `WatermarkCore/Models/ProcessingResult.swift` (modify) | model | n/a (add video fields) | itself (extend struct) | exact (same file) |
| `WatermarkCore/Output/TempFileManager.swift` (modify) | utility | file-I/O (add App Group paths) | itself (extend utility) | exact (same file) |
| `ShareExtension/Info.plist` | config | n/a (extension metadata) | `App/Info.plist` | partial (different target type) |
| `ShareExtension/ShareExtension.entitlements` | config | n/a (App Group capability) | *(no existing entitlements file)* | none |

---

## Pattern Assignments

### `WatermarkCore/Sources/WatermarkCore/Processing/VideoProcessor.swift` (service, streaming)

**Analog:** `Engine/WatermarkEngine.swift`

**Why:** Same role — processing pipeline orchestrator. VideoProcessor will follow the same static-pipeline pattern: load → build → export → validate. Both are actor-isolated or use `public actor` + `static let shared` and follow the same async-await and error typing conventions.

**Imports pattern** (WatermarkEngine.swift lines 1-3):
```swift
import CoreImage
import Foundation
import ImageIO
```
For VideoProcessor, these become:
```swift
import AVFoundation
import CoreImage
import CoreGraphics
import Foundation
```

**Actor isolation pattern** (WatermarkEngine.swift lines 5-17):
```swift
/// Actor-isolated photo watermarking engine (Pattern 3).
///
/// Orchestrates the full input → render → output pipeline:
///   1. Load: ...
///   2. Normalize: ...
///   ...
public actor WatermarkEngine {

    public static let shared = WatermarkEngine()

    /// Shared CIContext with RGBAh + displayP3 configuration (Pitfall 4)
    private let context = CIContextProvider.shared
```

**Core pipeline pattern** (WatermarkEngine.swift lines 39-78):
```swift
    public func process(
        sourceURL: URL,
        config: WatermarkConfiguration
    ) async throws -> ProcessingResult {
        // 1. Load (validates size, extracts metadata + HDR + CIImage)
        let loaded = try ImageLoader.load(from: sourceURL)

        // 2. Normalize orientation (Pitfall 3 prevention)
        let normalized = OrientationNormalizer.normalize(loaded.ciImage)

        // 3. Build filter graph (pure CIImage ops, no context needed)
        let composited = try buildFilterGraph(
            base: normalized,
            config: config,
            metadata: loaded.metadata
        )

        // 4. Render via shared CIContext → CGImage
        guard let cgImage = context.createCGImage(...) else {
            throw PipelineError.renderFailed
        }

        // 5. Write to temp file with metadata + HDR re-attached
        let outputURL = try TempFileManager.createTempFile(uti: loaded.sourceUTI as CFString)
        // ...

        // 6. Return result
        return ProcessingResult(...)
    }
```

**Error handling pattern** (WatermarkEngine.swift lines 63, 78 — throws PipelineError):
```swift
        guard let cgImage = context.createCGImage(...) else {
            throw PipelineError.renderFailed
        }
```
Video-specific errors follow same pattern:
```swift
        guard let exportSession = AVAssetExportSession(...) else {
            throw PipelineError.videoExportSessionCreationFailed
        }
```

**Static pipeline pattern:** Both follow functional decomposition with static methods on structs. The VideoProcessor should be a `public struct` (not actor, since AVFoundation handles its own threading) with a single `public static func process(sourceURL:config:) async throws -> URL`.

---

### `WatermarkCore/Sources/WatermarkCore/Processing/VideoLayerBuilder.swift` (utility, transform)

**Analog:** `Rendering/WhiteFrameRenderer.swift` + `Rendering/PositionCalculator.swift`

**Why:** WhiteFrameRenderer builds visual layers (frame + text) from config into a renderable image — same pattern as building CALayer hierarchies from watermark config. PositionCalculator provides coordinate math reused by both photo and video paths.

**Imports pattern** (WhiteFrameRenderer.swift lines 1-8):
```swift
import CoreImage
import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
import CoreText
#endif
```

**Static struct + single static method pattern** (WhiteFrameRenderer.swift lines 28-45):
```swift
public struct WhiteFrameRenderer {

    /// Renders a white frame border with optional metadata text.
    ///
    /// - Parameters:
    ///   - config: White frame configuration
    ///   - baseExtent: The base image extent
    ///   - metadata: Source image metadata dictionary
    ///   - scale: Display scale factor
    /// - Returns: A CIImage with the white frame border + optional text
    /// - Throws: `PipelineError.frameRenderFailed` if conversion fails
    public static func render(
        config: WhiteFrameConfig,
        baseExtent: CGRect,
        metadata: [String: Any],
        scale: CGFloat = 1.0
    ) throws -> CIImage {
```

**PositionCalculator coordinate pattern** (PositionCalculator.swift lines 8-31):
```swift
public struct PositionCalculator {

    /// Calculates the bottom-left origin position for a watermark layer.
    public static func position(
        for watermarkPosition: WatermarkPosition,
        watermarkExtent: CGRect,
        baseExtent: CGRect,
        padding: CGFloat
    ) -> CGPoint {
        let transform = watermarkPosition.translation(
            watermarkExtent: watermarkExtent,
            baseExtent: baseExtent,
            padding: padding
        )
        return CGPoint(x: transform.tx, y: transform.ty)
    }
}
```
VideoLayerBuilder reuses this same `PositionCalculator.position()` for CALayer frame coordinates.

---

### `WatermarkCore/Sources/WatermarkCore/Processing/VideoFrameExtractor.swift` (utility, streaming)

**Analog:** `Input/ImageLoader.swift`

**Why:** Both are media-loading utilities that extract pixel data from source files. ImageLoader uses `CGImageSource` for photos; VideoFrameExtractor uses `AVAssetImageGenerator` for videos. Same static struct pattern with configuration.

**Imports pattern** (ImageLoader.swift lines 1-3):
```swift
import CoreImage
import ImageIO
import Foundation
```

**Static struct + nested LoadedImage result pattern** (ImageLoader.swift lines 12-30):
```swift
public struct ImageLoader {

    /// Result of loading an image — contains the CIImage and all extracted metadata.
    public struct LoadedImage: @unchecked Sendable {
        public let ciImage: CIImage
        public let metadata: [String: Any]
        public let gainMapAuxData: [String: Any]?
        public let colorSpace: CGColorSpace?
        public let sourceUTI: String
    }
```

**Static load method pattern** (ImageLoader.swift lines 44-45):
```swift
    public static func load(from url: URL) throws -> LoadedImage {
```
VideoFrameExtractor follows:
```swift
public struct VideoFrameExtractor {
    public static func extract(from url: URL, at time: CMTime? = nil) async throws -> CGImage {
```

**Security validation pattern** (ImageLoader.swift lines 33-36, 47-53):
```swift
    private static let maxFileSize: Int64 = 500_000_000
    private static let maxMegapixels: Int = 100

    public static func load(from url: URL) throws -> LoadedImage {
        let fileAttributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = (fileAttributes?[.size] as? Int64) ?? 0
        guard fileSize > 0 else {
            throw PipelineError.invalidSource
        }
        guard fileSize <= maxFileSize else {
            throw PipelineError.dataTooLarge
        }
```

---

### `WatermarkCore/Sources/WatermarkCore/Processing/ExportValidator.swift` (utility, transform)

**Analog:** `Input/FormatDetector.swift`

**Why:** Both inspect media format properties (FormatDetector for source images, ExportValidator for output videos). Same static struct pattern with a single `detect`/`validate` method that reads metadata and returns structured results.

**Imports pattern** (FormatDetector.swift lines 1-3):
```swift
import ImageIO
import UniformTypeIdentifiers
```
For ExportValidator:
```swift
import AVFoundation
import CoreVideo
import UniformTypeIdentifiers
```

**Static struct + supported set pattern** (FormatDetector.swift lines 10-17):
```swift
public struct FormatDetector {

    private static let supportedUTIs: Set<String> = [
        "public.heic",
        "public.jpeg",
        "public.png",
    ]
```

**Structured return type pattern** (FormatDetector lines 24-41 — returns tuple):
```swift
    public static func detect(from source: CGImageSource) throws -> (UTType, CFString) {
        guard let sourceUTI = CGImageSourceGetType(source) else {
            throw PipelineError.unsupportedFormat("unknown")
        }
        // ...
    }
```
ExportValidator returns a struct (from RESEARCH.md):
```swift
    public static func validate(outputURL: URL, sourceAsset: AVAsset, wasHDR: Bool) async throws -> ExportValidationResult {
```

---

### `WatermarkCore/Sources/WatermarkCore/Storage/AppGroupConfigSync.swift` (utility, request-response)

**Analog:** `Output/TempFileManager.swift`

**Why:** Both are storage utilities with static methods for file/configuration I/O. Same `public struct` pattern with `public static` methods and no instance state.

**Imports pattern** (TempFileManager.swift line 1):
```swift
import Foundation
```

**Static struct with public static methods pattern** (TempFileManager.swift lines 9-25):
```swift
/// Manages temporary file creation and cleanup in the app's caches directory.
///
/// Uses UUID-based filenames to prevent predictable temp file paths (threat T-01-04).
/// Temp files are created in `FileManager.default.cachesDirectory`.
/// The engine writes watermarked output to temp files, which are cleaned up
/// after sharing or on next engine initialization.
public struct TempFileManager {

    /// Creates a unique temp file URL with the correct extension for the source UTI.
    ///
    /// - Parameter uti: Source format UTI as CFString (e.g., "public.heic")
    /// - Returns: URL to the new temp file (file does not exist yet)
    /// - Throws: If caches directory is not accessible
    public static func createTempFile(uti: CFString) throws -> URL {
        let cachesDir = try FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let filename = "watermark_\(UUID().uuidString).\(FormatDetector.fileExtension(for: uti))"
        return cachesDir.appendingPathComponent(filename)
    }
```

**Cleanup method pattern** (TempFileManager.swift lines 29-35):
```swift
    /// Removes a temp file at the given URL.
    ///
    /// Silently ignores if the file doesn't exist (already cleaned up).
    /// - Parameter url: The temp file URL to remove
    public static func cleanup(url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
```
AppGroupConfigSync will similarly use static methods (save/load) with UserDefaults(suiteName:).

---

### `ShareExtension/ShareViewController.swift` (controller, request-response)

**Analog:** `App/Views/Share/ShareSheetView.swift` (UIKit bridge pattern)

**Why:** ShareSheetView demonstrates the UIKit ↔ SwiftUI bridge pattern (`UIViewControllerRepresentable`). ShareViewController is the inverse — it's a UIKit `UIViewController` that hosts SwiftUI via `UIHostingController`. Both bridge UIKit and SwiftUI.

**UIViewControllerRepresentable pattern** (ShareSheetView.swift lines 4-32):
```swift
import SwiftUI
import UIKit

struct ShareSheetView: UIViewControllerRepresentable {
    let activityItems: [Any]
    let excludedActivityTypes: [UIActivity.ActivityType]?
    let onDismiss: () -> Void

    init(
        activityItems: [Any],
        excludedActivityTypes: [UIActivity.ActivityType]? = nil,
        onDismiss: @escaping () -> Void
    ) {
        self.activityItems = activityItems
        self.excludedActivityTypes = excludedActivityTypes
        self.onDismiss = onDismiss
    }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
        controller.excludedActivityTypes = [.saveToCameraRoll]
        controller.modalPresentationStyle = .pageSheet
        controller.completionWithItemsHandler = { _, _, _, _ in
            onDismiss()
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
```

**Extension context + completeRequest pattern** (from RESEARCH.md Pattern 4, lines 432-463):
```swift
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
}
```

---

### `ShareExtension/ShareExtensionRootView.swift` (component, request-response)

**Analog:** `App/Views/ContentView.swift`

**Why:** Both are root-level SwiftUI views that compose a preview area + controls area. ContentView uses `PhotosPicker`; ShareExtensionRootView uses a different input source (NSItemProvider) but the same layout composition. Both accept a `@State var viewModel` and use `.task` for async preview generation.

**Imports pattern** (ContentView.swift lines 1-2):
```swift
import PhotosUI
import SwiftUI
```
For ShareExtensionRootView:
```swift
import SwiftUI
```

**Root structure pattern** (ContentView.swift lines 4-18):
```swift
struct ContentView: View {
    @State var viewModel: WatermarkViewModel

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    previewArea
                        .frame(height: geometry.size.height * 0.60)

                    Color(.separator)
                        .frame(height: 1)

                    controlsArea
                        .frame(height: geometry.size.height * 0.40)
                }
```

**Error handling + share sheet pattern** (ContentView.swift lines 46-67):
```swift
                .alert("Rendering Error", isPresented: $viewModel.showError) {
                    Button("OK") {
                        viewModel.errorMessage = nil
                    }
                } message: {
                    Text(viewModel.errorMessage ?? "Unknown error")
                }
                // ...
                .sheet(isPresented: $viewModel.showShareSheet) {
                    if let url = viewModel.fullResResult?.url {
                        ShareSheetView(activityItems: [url]) {
                            viewModel.cleanupTempFile()
                        }
                    }
                }
                .task(id: viewModel.previewIdentifier) {
                    guard viewModel.currentPhoto != nil else { return }
                    await viewModel.generatePreview()
                }
```

ShareExtensionRootView differs: it doesn't use NavigationStack (extension has no nav), uses `.sheet` with `onDismiss` calling `completeRequest`, and may show multi-item progress.

---

### `ShareExtension/ShareExtensionViewModel.swift` (model, request-response)

**Analog:** `App/ViewModels/WatermarkViewModel.swift` — **exact match**

**Why:** Both are `@Observable @MainActor final class` ViewModels. WatermarkViewModel uses `PhotosPickerItem` input; ShareExtensionViewModel uses `NSItemProvider` input, but the config, rendering state, error handling, and preview generation patterns are identical. The `@Observable` macro pattern, `RenderingState` enum, and delegate-to-`WatermarkEngine.shared.process()` pattern are the same.

**@Observable + @MainActor pattern** (WatermarkViewModel.swift lines 9-10):
```swift
@Observable @MainActor
final class WatermarkViewModel {
```

**Core state properties pattern** (WatermarkViewModel.swift lines 11-31):
```swift
    var config = WatermarkConfiguration(watermarks: [
        .text(
            TextWatermarkInput(text: "", fontSize: 48, color: CGColor(gray: 1, alpha: 1), opacity: 1.0),
            position: .bottomRight,
            scale: 0.15
        )
    ])

    var previewImage: UIImage?
    var isGeneratingPreview: Bool = false

    var renderingState: RenderingState = .idle
    var fullResResult: ProcessingResult?
    var showShareSheet: Bool = false
    var errorMessage: String?
    var showError: Bool = false
```

**Engine delegation pattern** (WatermarkViewModel.swift lines 35, 96-122):
```swift
    private let engine = WatermarkEngine.shared

    func renderAndPrepareShare() async {
        guard let sourceURL = currentPhoto?.sourceURL else { return }
        renderingState = .rendering

        do {
            let result = try await engine.process(sourceURL: sourceURL, config: config)
            fullResResult = result
            renderingState = .done
            // ...
        } catch {
            renderingState = .error(error)
            errorMessage = error.localizedDescription
            showError = true
        }
    }
```

**Layer management pattern** (WatermarkViewModel.swift lines 149-193):
```swift
    func addLogoLayer(pngData: Data) {
        guard let _ = CIImage(data: pngData) else {
            errorMessage = "The selected image is not a valid PNG file."
            showError = true
            return
        }
        guard let input = try? ImageWatermarkInput(pngData: pngData) else { ... }
        config.watermarks.append(.image(input, position: .bottomRight, scale: 0.15))
        activeLayerIndex = config.watermarks.count - 1
    }

    func removeLayer(at index: Int) { ... }
    func updateLayerPosition(at index: Int, position: WatermarkPosition) { ... }
    func updateLayerScale(at index: Int, scale scaleInput: CGFloat) { ... }
    func toggleWhiteFrame() { ... }
```

**RenderingState enum** (PhotoItem.swift lines 18-34):
```swift
enum RenderingState: Equatable {
    case idle
    case rendering
    case done
    case error(Error)

    static func == (lhs: RenderingState, rhs: RenderingState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.rendering, .rendering), (.done, .done):
            return true
        case (.error, .error):
            return true
        default:
            return false
        }
    }
}
```

**Key differences for ShareExtensionViewModel:**
- Input: `var sharedMedia: [MediaInput]` (from NSItemProvider), not `[PhotosPickerItem]`
- Media detection: `var isVideo: Bool` to gate video vs photo processing path
- Config sync: call `AppGroupConfigSync.load()` on init, `AppGroupConfigSync.save()` on config change
- Multi-item orchestration: `var currentItemIndex: Int`, `processNextItem()` method
- `completeRequest()` called from ViewModel or passed as closure from ShareViewController

---

### `WatermarkCore/Engine/WatermarkEngine.swift` (modify — add video routing)

**Analog:** itself — extend existing actor

**Why:** The engine already handles photo processing; it's the natural dispatcher for video. Add media type detection and a `processVideo(sourceURL:config:)` method or a unified `process` method that detects media type and routes accordingly.

**Current pattern to extend** (WatermarkEngine.swift lines 39-78):
```swift
    public func process(
        sourceURL: URL,
        config: WatermarkConfiguration
    ) async throws -> ProcessingResult {
        // 1. Load (validates size, extracts metadata + HDR + CIImage)
        let loaded = try ImageLoader.load(from: sourceURL)
        // ...
    }
```

**Addition pattern** — add new method following same conventions:
```swift
    /// Processes a video file, applying watermark via AVFoundation CALayer overlay.
    ///
    /// - Parameters:
    ///   - sourceURL: File URL to the source video
    ///   - config: Watermark configuration
    /// - Returns: `ProcessingResult` with the output file URL
    /// - Throws: `PipelineError` for any pipeline stage failure
    public func processVideo(
        sourceURL: URL,
        config: WatermarkConfiguration
    ) async throws -> ProcessingResult {
        let outputURL = try await VideoProcessor.process(sourceURL: sourceURL, config: config)
        let sourceUTI = (try? sourceURL.resourceValues(forKeys: [.typeIdentifierKey]).typeIdentifier)
            ?? "public.mpeg-4"
        return ProcessingResult(url: outputURL, data: nil, outputUTI: sourceUTI)
    }
```

---

### `WatermarkCore/Engine/PipelineError.swift` (modify — add video cases)

**Analog:** itself — extend existing enum

**Current pattern** (PipelineError.swift lines 8-40):
```swift
public enum PipelineError: Error, LocalizedError, Sendable, Equatable {
    case invalidSource
    case failedToCreateCIImage
    case renderFailed
    case failedToCreateDestination
    case failedToFinalize
    case invalidImageData
    case dataTooLarge
    case imageTooLarge
    case invalidScale(Double)
    case frameRenderFailed
    case unsupportedFormat(String)
    case emptyData

    public var errorDescription: String? {
        switch self {
        case .invalidSource:
            return "The source file does not contain valid image data."
        // ...
        }
    }
```

**Add video-specific cases** following the same enum case + errorDescription pattern:
```swift
    // Video pipeline errors
    case videoTrackNotFound
    case videoAudioTrackInsertionFailed
    case videoExportSessionCreationFailed
    case videoExportFailed(Error?)
    case videoFrameExtractionFailed
    case videoHDRPreservationFailed
    case videoValidationFailed(String)
    case videoSourceFormatMismatch
```

---

### `WatermarkCore/Models/ProcessingResult.swift` (modify — add video fields)

**Analog:** itself — extend existing struct

**Current pattern** (ProcessingResult.swift lines 10-25):
```swift
public struct ProcessingResult: Sendable {
    public let url: URL?
    public let data: Data?
    public let outputUTI: String

    public init(url: URL?, data: Data?, outputUTI: String) {
        self.url = url
        self.data = data
        self.outputUTI = outputUTI
    }
}
```

**Addition:** Add optional video-specific fields (validation result info):
```swift
    /// Optional video validation result (nil for photo processing)
    public let videoValidation: ExportValidationResult?
```

---

### `WatermarkCore/Output/TempFileManager.swift` (modify — add App Group paths)

**Analog:** itself — extend existing utility

**Current pattern** (TempFileManager.swift lines 9-25):
```swift
public struct TempFileManager {

    public static func createTempFile(uti: CFString) throws -> URL {
        let cachesDir = try FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let filename = "watermark_\(UUID().uuidString).\(FormatDetector.fileExtension(for: uti))"
        return cachesDir.appendingPathComponent(filename)
    }
```

**Addition pattern** — add an overload that accepts a custom base directory:
```swift
    /// Creates a unique temp file URL in the specified directory.
    /// Used by the share extension to write to extension sandbox cachesDirectory.
    ///
    /// - Parameters:
    ///   - uti: Source format UTI as CFString
    ///   - directory: Base directory to create the file in
    /// - Returns: URL to the new temp file
    public static func createTempFile(uti: CFString, in directory: URL) throws -> URL {
        let filename = "watermark_\(UUID().uuidString).\(FormatDetector.fileExtension(for: uti))"
        return directory.appendingPathComponent(filename)
    }
```

---

### `ShareExtension/Info.plist` (config)

**Analog:** `App/Info.plist` (basic structure only)

**Pattern:** Standard plist with `NSExtension` dictionary and `NSExtensionPrincipalClass` pointing to `ShareViewController`. The `NSExtensionActivationRule` uses a SUBQUERY predicate per D-15/D-16.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>NSExtension</key>
    <dict>
        <key>NSExtensionAttributes</key>
        <dict>
            <key>NSExtensionActivationRule</key>
            <dict>
                <key>NSExtensionActivationSupportsImageWithMaxCount</key>
                <integer>20</integer>
                <key>NSExtensionActivationSupportsMovieWithMaxCount</key>
                <integer>5</integer>
            </dict>
        </dict>
        <key>NSExtensionPrincipalClass</key>
        <string>$(PRODUCT_MODULE_NAME).ShareViewController</string>
        <key>NSExtensionPointIdentifier</key>
        <string>com.apple.share-services</string>
    </dict>
</dict>
</plist>
```

---

## Shared Patterns

### @Observable + @MainActor ViewModel
**Source:** `App/ViewModels/WatermarkViewModel.swift` (lines 9-10, entire file)
**Apply to:** `ShareExtensionViewModel.swift`
```swift
@Observable @MainActor
final class ShareExtensionViewModel {
    var renderingState: RenderingState = .idle
    var config = WatermarkConfiguration(...)
    // ...
}
```

### Static Struct + Static Method Pattern
**Source:** `Rendering/WhiteFrameRenderer.swift`, `Input/ImageLoader.swift`, `Output/TempFileManager.swift`
**Apply to:** `VideoProcessor.swift`, `VideoLayerBuilder.swift`, `VideoFrameExtractor.swift`, `ExportValidator.swift`, `AppGroupConfigSync.swift`
```swift
public struct XxxProcessor {
    public static func process(...) async throws -> Result { ... }
}
```

### PipelineError Typed Error Enum
**Source:** `Engine/PipelineError.swift` (lines 8-73)
**Apply to:** All new video processing code in WatermarkCore
```swift
throw PipelineError.videoExportFailed(error)
```

### TempFileManager Cleanup
**Source:** `Output/TempFileManager.swift` (lines 29-35)
**Apply to:** Video export output, extension temp files
```swift
func cleanupTempFile() {
    if let url = fullResResult?.url {
        try? TempFileManager.cleanup(url: url)
    }
}
```

### ShareSheetView UIKit Bridge
**Source:** `App/Views/Share/ShareSheetView.swift` (entire file)
**Apply to:** Extension's share presentation
```swift
.sheet(isPresented: $viewModel.showShareSheet) {
    if let url = viewModel.fullResResult?.url {
        ShareSheetView(activityItems: [url]) {
            viewModel.cleanupTempFile()
        }
    }
}
```

### SwiftUI Controls Reuse
**Source:** `App/Views/Controls/` (all files)
**Apply to:** `ShareExtensionRootView.swift` — reuse controls as-is
```
ControlsView, TextWatermarkInputView, PositionGridView, ScaleStepperView,
LogoPickerView, WhiteFrameToggleView, LayerListView
```

### PositionCalculator Coordinate Math
**Source:** `Rendering/PositionCalculator.swift` (lines 8-31)
**Apply to:** `VideoLayerBuilder.swift` — same coordinate math for CALayer positioning
```swift
let position = PositionCalculator.position(
    for: watermark.position,
    watermarkExtent: scaledExtent,
    baseExtent: CGRect(origin: .zero, size: videoSize),
    padding: config.padding
)
```

### CIContextProvider for Watermark Rasterization
**Source:** `Utilities/CIContextProvider.swift` (lines 11-22)
**Apply to:** `VideoLayerBuilder.swift` — when rasterizing watermark CIImage → CGImage for CALayer.contents
```swift
let cgImage = CIContextProvider.shared.createCGImage(ciImage, from: ciImage.extent, ...)
watermarkLayer.contents = cgImage
```

### Swift Testing Framework
**Source:** `Tests/WatermarkCoreTests/WatermarkEngineTests.swift` (lines 1-8)
**Apply to:** Video processing tests
```swift
import Testing
import AVFoundation
@testable import WatermarkCore

@Suite("VideoProcessor Tests")
struct VideoProcessorTests { ... }
```

---

## No Analog Found

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `ShareExtension/ShareExtension.entitlements` | config | n/a | No existing entitlements file in project; standard App Group pattern from RESEARCH.md |

---

## Metadata

**Analog search scope:** `Packages/WatermarkCore/Sources/**/*.swift`, `App/**/*.swift`
**Files scanned:** 32 (all Swift files in project)
**Pattern extraction date:** 2026-06-17
