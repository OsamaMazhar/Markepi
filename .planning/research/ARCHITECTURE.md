# Architecture Research

**Domain:** iOS Photo/Video Watermarking App
**Researched:** 2026-06-17
**Confidence:** HIGH

## Standard Architecture

### System Overview

```
┌──────────────────────────────────────────────────────────────────────────┐
│                           PRESENTATION LAYER (SwiftUI)                     │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                           │
│  ┌──────────────────┐  ┌──────────────────┐  ┌────────────────────────┐ │
│  │   MainAppView    │  │ ShareExtension   │  │ PhotoEditExtension     │ │
│  │                  │  │  ViewController  │  │  ViewController         │ │
│  │  - ImagePicker   │  │  (UIHostingCtrl  │  │  (PHContentEditing      │ │
│  │  - PositionGrid  │  │   wrapping       │  │   Controller impl)     │ │
│  │  - StylePicker   │  │   SwiftUI view)  │  │                         │ │
│  │  - PreviewArea   │  │                  │  │  - Start content edit  │ │
│  │  - ShareButton   │  │  - Process &     │  │  - Finish w/ rendered  │ │
│  │                  │  │    share flow    │  │    content + adjust.   │ │
│  └───────┬──────────┘  └───────┬──────────┘  └───────────┬────────────┘ │
│          │                     │                         │               │
├──────────┼─────────────────────┼─────────────────────────┼───────────────┤
│          │          STATE / VIEWMODEL LAYER               │               │
│          │     (all targets link SharedCore Swift Pkg)    │               │
│          │                     │                         │               │
│  ┌───────┴─────────────────────┴─────────────────────────┴──────────┐   │
│  │                    WatermarkViewModel (@Observable)               │   │
│  │  ┌──────────────┐  ┌────────────────┐  ┌───────────────────────┐ │   │
│  │  │ MediaInputVM │  │ ProcessingVM   │  │  ShareCoordinatorVM   │ │   │
│  │  │ - source URL │  │ - progress     │  │  - UIActivityVC       │ │   │
│  │  │ - media type │  │ - result URL   │  │  - temp file cleanup  │ │   │
│  │  │ - thumbnail  │  │ - error state  │  │                       │ │   │
│  │  └──────┬───────┘  └───────┬────────┘  └───────────┬───────────┘ │   │
│  └─────────┼──────────────────┼───────────────────────┼─────────────┘   │
│            │                  │                       │                 │
├────────────┼──────────────────┼───────────────────────┼─────────────────┤
│            │        PROCESSING ENGINE LAYER            │                 │
│            │     (SharedCore Swift Package)            │                 │
│            │                  │                       │                 │
│  ┌─────────┴──────────────────┴───────────────────────┴──────────────┐  │
│  │                      ProcessingEngine                              │  │
│  │  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐ │  │
│  │  │ PhotoProcessor   │  │ VideoProcessor   │  │ MetadataPreserver│ │  │
│  │  │                  │  │                  │  │                  │ │  │
│  │  │ - CIImage chain  │  │ - AVVideoComp.   │  │ - EXIF passthru  │ │  │
│  │  │ - CGImageDest.   │  │ - AVAssetExport  │  │ - Color profile  │ │  │
│  │  │ - Position calc  │  │ - HDR config     │  │ - Orientation    │ │  │
│  │  └────────┬─────────┘  └────────┬─────────┘  └────────┬─────────┘ │  │
│  │           │                     │                     │           │
│  │  ┌────────┴─────────────────────┴─────────────────────┴─────────┐ │  │
│  │  │                    Core Image Pipeline                         │ │  │
│  │  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐ │ │  │
│  │  │  │Watermark     │  │TextOverlay   │  │WhiteFrame            │ │ │  │
│  │  │  │OverlayFilter │  │Generator     │  │Generator             │ │ │  │
│  │  │  │              │  │(CIAttribText │  │(CIConstantColor +    │ │ │  │
│  │  │  │CISrcOverComp │  │ ImageGen)    │  │ padding transform)   │ │ │  │
│  │  │  └──────────────┘  └──────────────┘  └──────────────────────┘ │ │  │
│  │  └───────────────────────────────────────────────────────────────┘ │  │
│  └────────────────────────────────────────────────────────────────────┘  │
│                                                                           │
├───────────────────────────────────────────────────────────────────────────┤
│                          DATA / STORAGE LAYER                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────────────────┐ │
│  │ AppGroup     │  │ TempFileMgr  │  │ UserDefaults(suiteName:)         │ │
│  │ Container    │  │ (.cachesDir) │  │ - Last used position             │ │
│  │ (ext ↔ app)  │  │              │  │ - Default watermark style        │ │
│  └──────────────┘  └──────────────┘  └──────────────────────────────────┘ │
└───────────────────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

| Component | Responsibility | Typical Implementation |
|-----------|---------------|----------------------|
| `MainAppView` | Primary UI: media picker, position grid, style picker, preview, share button | SwiftUI `View` with `@Environment(ViewModel.self)` |
| `ShareExtensionVC` | Receives media from iOS share sheet, presents watermark UI, triggers share | `UIViewController` hosting SwiftUI via `UIHostingController` |
| `PhotoEditExtensionVC` | Receives photo/video from Photos app edit mode, applies watermark, returns rendered output | `UIViewController` conforming to `PHContentEditingController` |
| `WatermarkViewModel` | Central state holder: current media, selected position, overlay style, processing state | `@Observable` class, shared via dependency injection |
| `MediaInputVM` | Sub-viewmodel: manages media source (URL, type, thumbnail generation) | `@Observable` class, owns `AVAssetImageGenerator` for thumbs |
| `ProcessingViewModel` | Sub-viewmodel: progress tracking, result URL, error state during processing | `@Observable` class, communicates with ProcessingEngine via async tasks |
| `ShareCoordinatorVM` | Sub-viewmodel: presents `UIActivityViewController`, manages temp file lifecycle | `@Observable` class, SwiftUI `UIViewControllerRepresentable` bridge |
| `ProcessingEngine` | Entry point: routes to PhotoProcessor or VideoProcessor based on media type | Actor or class on background queue |
| `PhotoProcessor` | Constructs CIImage filter graph → renders via `CIContext` → writes via `CGImageDestination` with metadata passthrough | `class` on `.utility` QoS DispatchQueue |
| `VideoProcessor` | Configures `AVVideoComposition` with custom CIFilter handler → exports via `AVAssetExportSession` (HDR via `AVAssetWriter` if needed) | `class` on background queue |
| `MetadataPreserver` | Extracts EXIF/color profile from source, re-applies to output. Extracts `AVMetadataItem` array for videos | Utility struct, used by both processors |
| `WatermarkOverlayFilter` | Constructs CIAffineTransform → CISourceOverCompositing chain for a given position | Pure function returning `CIImage` |
| `TextOverlayGenerator` | Generates CIAttributedTextImageGenerator output for device metadata text ("Taken by: iPhone") | Pure function returning `CIImage` |
| `WhiteFrameGenerator` | Generates white border frame with inner content area for watermark + metadata | Pure function using CIConstantColor + scale/translate |
| `AppGroupContainer` | Shared file storage between main app and extensions (share extension passes media, app reads it) | `FileManager` with App Group container URL |
| `TempFileManager` | Manages temporary output files in `cachesDirectory`, cleans up after share completes | Singleton, auto-cleanup on launch |
| `UserDefaults(suiteName:)` | Persists last-used position, preferred overlay style, and default text across app + extensions | App Group `UserDefaults` |

## Recommended Project Structure

```
Watermark/
├── App/                              # Main app target
│   ├── WatermarkApp.swift            # @main App entry point
│   ├── ContentView.swift             # Root view (NavigationSplitView or TabView)
│   ├── Features/
│   │   ├── MediaImport/              # In-app picker flow
│   │   │   ├── MediaPickerView.swift
│   │   │   └── MediaPickerViewModel.swift
│   │   ├── WatermarkConfig/          # Position grid, style selector
│   │   │   ├── PositionGridView.swift
│   │   │   ├── StylePickerView.swift
│   │   │   ├── TextInputView.swift
│   │   │   └── WatermarkConfigViewModel.swift
│   │   ├── Preview/                  # Live preview of watermarked result
│   │   │   └── PreviewView.swift
│   │   └── Share/                    # Share sheet presentation
│   │       ├── ShareSheetView.swift
│   │       └── ShareCoordinator.swift
│   └── UI/                           # Design system components
│       ├── Components/               # Reusable UI primitives
│       └── Extensions/               # View modifiers, CIImage+Extensions
│
├── ShareExtension/                   # Share sheet extension target
│   ├── ShareViewController.swift     # UIViewController + UIHostingController
│   ├── ShareExtensionView.swift      # SwiftUI view (watermark config + share)
│   ├── Info.plist                    # NSExtensionActivationRule config
│   └── ShareExtension.entitlements   # App Group capability
│
├── PhotoEditExtension/               # Photos app edit extension target
│   ├── PhotoEditViewController.swift # PHContentEditingController impl
│   ├── PhotoEditView.swift           # SwiftUI view (watermark UI)
│   ├── Info.plist                    # PHSupportedMediaTypes: Image, Video
│   └── PhotoEditExtension.entitlements # App Group capability
│
├── Packages/
│   └── WatermarkCore/                # LOCAL SWIFT PACKAGE — shared code
│       ├── Package.swift
│       ├── Sources/
│       │   ├── Models/
│       │   │   ├── WatermarkConfiguration.swift   # Position, style, text
│       │   │   ├── MediaSource.swift              # URL, type enum
│       │   │   └── ProcessingResult.swift         # Output URL, metadata
│       │   ├── Processing/
│       │   │   ├── ProcessingEngine.swift         # Router: photo vs video
│       │   │   ├── PhotoProcessor.swift           # CIImage pipeline
│       │   │   ├── VideoProcessor.swift           # AVVideoComposition pipeline
│       │   │   └── MetadataPreserver.swift        # EXIF/AVMetadata passthru
│       │   ├── Rendering/
│       │   │   ├── WatermarkRenderer.swift        # Overlay compositing
│       │   │   ├── TextOverlayRenderer.swift      # CIAttributedTextImageGen
│       │   │   ├── WhiteFrameRenderer.swift       # White border + content inset
│       │   │   └── PositionCalculator.swift       # 8-position coordinate math
│       │   ├── Storage/
│       │   │   ├── AppGroupContainer.swift        # Shared container access
│       │   │   └── TempFileManager.swift          # Temp output lifecycle
│       │   └── Utilities/
│       │       ├── ImageOrientation.swift         # EXIF orientation handling
│       │       └── DeviceMetadataProvider.swift   # "Taken by: iPhone 15 Pro"
│       └── Tests/
│           ├── PhotoProcessorTests.swift
│           ├── VideoProcessorTests.swift
│           └── PositionCalculatorTests.swift
│
└── Watermark.xcodeproj/
```

### Structure Rationale

- **`WatermarkCore/` (Local Swift Package):** The most critical architectural decision. All processing logic, models, renderers, and storage utilities live here. Both the main app and both extension targets link this package. This eliminates code duplication, enforces a single source of truth, and keeps extension targets lightweight. The package is marked "Require Only App-Extension-Safe API" to prevent accidental use of forbidden APIs in extensions.

- **`App/Features/`:** Each feature folder is self-contained with its own Views and ViewModels. This prevents "Massive ViewModel" syndrome — each feature owns its state but coordinates through the root WatermarkViewModel when needed.

- **`ShareExtension/` and `PhotoEditExtension/`:** Minimal targets. Each contains only the entry-point view controller, a thin SwiftUI view, and target-specific plist/entitlements. All heavy logic is in `WatermarkCore`. Extensions have strict memory limits (~120MB), so they must not duplicate processing code or load unnecessary resources.

- **`WatermarkCore/Processing/` vs `WatermarkCore/Rendering/`:** Deliberate separation. Processing owns the pipeline lifecycle (setup, progress, completion). Rendering owns the Core Image filter graph construction (pure functions that take config + input → return CIImage). This lets us unit-test rendering logic independently of AVFoundation session management.

## Architectural Patterns

### Pattern 1: MVVM with @Observable (iOS 17+)

**What:** View observes ViewModel via Swift's `@Observable` macro. ViewModel holds UI state and delegates heavy work to service actors. Views are declarative; ViewModels are imperative coordinators.

**When to use:** Every screen in this app. The `@Observable` macro replaces `ObservableObject`/`@Published` with property-level granularity — SwiftUI only redraws views that depend on the specific changed property, critical for preview updates during processing.

**Trade-offs:** Requires iOS 17+ deployment target. Since this is a greenfield 2026 project, this is an acceptable constraint. The granular tracking prevents unnecessary preview re-renders when only the progress value changes.

**Example:**
```swift
// WatermarkCore — shared model
@Observable
class WatermarkConfiguration {
    var selectedPosition: WatermarkPosition = .bottomRight
    var overlayStyle: OverlayStyle = .watermark
    var customText: String = ""
    var watermarkScale: CGFloat = 0.15  // % of image width
}

// Main app — ViewModel
@Observable
final class WatermarkViewModel {
    var config = WatermarkConfiguration()
    var mediaSource: MediaSource?
    var processingState: ProcessingState = .idle
    var previewImage: UIImage?
    
    private let engine = ProcessingEngine()
    
    func process() async {
        processingState = .processing(progress: 0)
        guard let source = mediaSource else { return }
        do {
            let result = try await engine.process(source, config: config)
            processingState = .complete(result)
        } catch {
            processingState = .error(error)
        }
    }
}
```

### Pattern 2: Core Image Filter Graph (Lazy Evaluation)

**What:** Instead of rendering pixel-by-pixel, chain CIImage transforms into a directed acyclic graph. Core Image defers actual rendering until `CIContext.createCGImage()` or similar is called, optimizing the entire chain into a single Metal shader.

**When to use:** Every photo watermarking operation. For video, the same chain runs inside the `AVVideoComposition` CIFilter handler closure.

**Trade-offs:** The lazy graph is extremely memory-efficient (no intermediate buffers), but you must be careful about `extent` management — transformed images have infinite extents unless cropped.

**Example:**
```swift
func applyWatermark(
    to sourceImage: CIImage,
    watermark: CIImage,
    position: WatermarkPosition,
    scale: CGFloat
) -> CIImage {
    let sourceExtent = sourceImage.extent
    let scaledWatermark = watermark.transformed(
        by: CGAffineTransform(scaleX: scale, y: scale)
    )
    let positionedWatermark = scaledWatermark.transformed(
        by: PositionCalculator.transform(for: position, baseExtent: sourceExtent, watermarkExtent: scaledWatermark.extent)
    )
    let composite = CIFilter.sourceOverCompositing()
    composite.inputImage = positionedWatermark
    composite.backgroundImage = sourceImage
    return composite.outputImage!.cropped(to: sourceExtent)
}
```

### Pattern 3: Extension-as-Thin-Shell

**What:** Extensions contain only entry-point view controllers, target-specific plist configuration, and a thin SwiftUI view. All shared logic, models, and processing are in the `WatermarkCore` Swift Package.

**When to use:** Both the Share Extension and Photo Edit Extension. Extensions have strict memory limits (~120MB) and cold-start latency requirements — keeping them thin is non-negotiable.

**Trade-offs:** The main app and extensions share state through App Group containers (file-based, not memory). This means passing media requires writing to a shared temp directory and reading from it — adds I/O overhead but is the only option across process boundaries.

**Example:**
```swift
// ShareViewController.swift — the ONLY code directly in the extension target
class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let viewModel = WatermarkViewModel() // from WatermarkCore
        let contentView = ShareExtensionView(viewModel: viewModel)
        let host = UIHostingController(rootView: contentView)
        addChild(host)
        view.addSubview(host.view)
        host.view.frame = view.bounds
        // Load media from extensionContext into viewModel...
    }
}
```

### Pattern 4: Async Processing Pipeline

**What:** Processing operations run on background queues via Swift Concurrency (`async`/`await`). The ViewModel awaits results and publishes progress updates. The UI never blocks.

**When to use:** Both photo and video processing. Video processing is especially long-running (seconds to minutes) and must never block the main thread.

**Trade-offs:** Requires careful cancellation support (Swift `Task` cancellation, `checkCancellation()` calls in processing loops). Video export cancellation is particularly nuanced — `AVAssetExportSession.cancelExport()` must be called.

## Data Flow

### Primary Flow: Main App (In-App Picker)

```
User taps "+" button
    ↓
PHPickerViewController (or UIImagePickerController)
    ↓ returns URL/Data
MediaInputVM.loadMedia(from: url)
    ↓ determines photo vs video, generates thumbnail
WatermarkViewModel.mediaSource = .photo(url) | .video(url)
    ↓
User configures position, style, text via UI
    ↓ updates config properties (auto-bound by @Observable)
WatermarkConfigViewModel.config = updated
    ↓ triggers preview regeneration
PreviewViewModel.generatePreview(config, source)
    ↓ calls ProcessingEngine.preview(config, source)
PhotoProcessor.generatePreview() → CIImage chain → CGImage
    ↓ rendered on background queue, published to @MainActor
previewImage published → SwiftUI redraws preview
    ↓
User taps "Share"
    ↓
ShareCoordinatorVM.share(watermarkedResult)
    ↓
ProcessingEngine.process(source, config) [full quality]
    ↓ PhotoProcessor or VideoProcessor
    ↓ writes to temp file (cachesDirectory)
ProcessingState = .complete(ProcessingResult(tempURL, mediaType))
    ↓
ShareCoordinator presents UIActivityViewController with tempURL
    ↓ user shares to Messages, Instagram, TikTok, etc.
ShareCoordinator schedules temp file cleanup (after 60s delay)
```

### Secondary Flow: Share Extension

```
User taps "Share" in another app (Photos, Safari, Files)
    ↓ iOS presents share sheet, user selects Watermark
ShareViewController.viewDidLoad()
    ↓
extensionContext.inputItems → NSExtensionItem → NSItemProvider
    ↓ loadFileRepresentation(for: .image) or loadItem(for: .movie)
MediaSource created from file URL
    ↓ saved to App Group container (so main app can access history)
WatermarkViewModel.mediaSource = source
    ↓
[Same config/preview/process flow as main app]
    ↓
User taps "Share" in extension → UIActivityViewController
    ↓ OR
User taps "Open in Watermark" → opens main app via URL scheme
    ↓ main app loads media from App Group container
Share extension calls extensionContext.completeRequest()
    ↓ extension terminated by system
```

### Tertiary Flow: Photos Edit Extension

```
User opens photo/video in Photos app → taps Edit → taps "..." → selects Watermark
    ↓
PhotoEditViewController.startContentEditing(with: input, placeholderImage:)
    ↓ input.fullSizeImageURL (photo) or input.audiovisualAsset (video)
    ↓ input.adjustmentData? (previous edits from this extension, if any)
WatermarkViewModel loads media from PHContentEditingInput
    ↓
[Same config/preview flow as main app]
    ↓
User taps "Done"
    ↓
PhotoEditViewController.finishContentEditing { completionHandler in
    ↓
    let output = PHContentEditingOutput(contentEditingInput: input)
    ↓
    ProcessingEngine.process(source, config, outputURL: output.renderedContentURL)
    ↓
    output.adjustmentData = PHAdjustmentData(
        formatIdentifier: "com.watermark.app",
        formatVersion: "1.0",
        data: config.serialized()  // JSON-encoded WatermarkConfiguration
    )
    ↓
    completionHandler(output)  // Photos app saves non-destructively
}
```

### State Management

```
WatermarkConfiguration (@Observable, shared model)
    ├── selectedPosition: WatermarkPosition
    ├── overlayStyle: OverlayStyle (.watermark | .whiteFrame)
    ├── customText: String
    ├── watermarkScale: CGFloat
    └── watermarkImageData: Data?  // custom watermark image

WatermarkViewModel (@Observable, main coordinator)
    ├── config: WatermarkConfiguration
    ├── mediaSource: MediaSource?
    ├── processingState: ProcessingState { idle, processing(progress), complete(result), error(Error) }
    ├── previewImage: UIImage?
    └── thumbnailImage: UIImage?

UserDefaults(suiteName: "group.com.watermark.app") — cross-process persistence
    ├── "lastUsedPosition" → WatermarkPosition.rawValue
    ├── "lastUsedStyle" → OverlayStyle.rawValue
    ├── "defaultText" → String
    └── "customWatermarkData" → Data?

AppGroupContainer (file-based, cross-process)
    └── Shared/Inbox/  — share extension drops media here
    └── Shared/Temp/   — temp processing outputs accessible by both
```

### Key Data Flows

1. **Media Ingestion Flow:** External source (picker/share/Photos) → URL/Data → MediaSource enum → ViewModel.mediaSource. The ViewModel immediately generates a low-res thumbnail for preview while the full asset URL is retained for processing.

2. **Preview Flow:** Config change (user taps position) → ViewModel.config updates → triggers `generatePreview()` → core processing chain runs at preview resolution (max 1920px) → CGImage → UIImage → published to SwiftUI. This happens on a `.utility` queue, not main.

3. **Processing Flow:** User taps share → engine runs at full resolution → PhotoProcessor (CIImage → CGImageDestination with metadata dict) or VideoProcessor (AVVideoComposition → AVAssetExportSession) → writes to temp file → result URL published → share sheet presented.

4. **Metadata Passthrough Flow:** Source → CGImageSourceCopyProperties (photo) or AVAsset.metadata + AVAssetTrack (video) → MetadataPreserver extracts → output's CGImageDestinationAddImage(properties:) or AVAssetExportSession.metadata = extracted → metadata intact in output.

## Scaling Considerations

This is a local-only, on-device processing app. Traditional "scaling to N users" doesn't apply. Instead, scale concerns are about media size and processing volume.

| Concern | Small media (12MP photo, 30s 1080p video) | Large media (48MP ProRAW, 10min 4K HDR) | Extreme (ProRes 4K, 1hr) |
|---------|-------------------------------------------|-----------------------------------------|---------------------------|
| Photo processing | In-memory CIImage, <1s | In-memory still fine, 2-5s | Downscale for preview, process at full res on background |
| Video processing | AVAssetExportSession with preset, 10-30s | AVAssetWriter for HDR control, 2-5 min | Stream with AVAssetReader → AVAssetWriter, 10min+ |
| Memory pressure | Negligible | CIContext reuse prevents spikes | Must use tile-based rendering for photos >100MP |
| Extension memory limit | Well within 120MB | Risk of termination — offload to main app | Extension only for config, main app for processing |
| Preview responsiveness | Instant | Slight delay acceptable | Always use downscaled preview source |

### Scaling Priorities

1. **First bottleneck:** Large video processing time. Mitigation: show progress bar, allow background processing (iOS background task), use `AVAssetExportSession` with `presetName: AVAssetExportPresetHEVCHighestQuality` for hardware-accelerated encoding.

2. **Second bottleneck:** Extension memory limits on large photos. Mitigation: extensions generate a low-res preview only; tapping "Process" opens the main app to complete full-quality processing.

## Anti-Patterns

### Anti-Pattern 1: Massive ViewModel

**What people do:** Put image processing logic, AVFoundation setup, file I/O, and UI state all in one ViewModel class that grows to 1000+ lines.

**Why it's wrong:** Untestable, unreadable, and blocks the main thread when processing methods are accidentally called synchronously. Extensions can't share any of it.

**Do this instead:** Separate into WatermarkViewModel (UI state), ProcessingEngine (pipeline lifecycle), PhotoProcessor/VideoProcessor (media-specific logic), and pure Rendering functions. Keep ViewModels under 200 lines. ProcessingEngine lives in the shared WatermarkCore package.

### Anti-Pattern 2: Creating CIContext Per Frame

**What people do:** `let context = CIContext()` inside a video frame processing closure or inside every preview generation call.

**Why it's wrong:** `CIContext` initialization is extremely expensive — it allocates GPU resources and compiles shader programs. Creating one per frame (30fps × 60s = 1800 allocations) will cause frame drops and memory churn.

**Do this instead:** Create one `CIContext` instance with `.cacheIntermediates = false` (for video) and reuse it for the lifetime of the processing session. Store it as a property on the processor.

```swift
// WRONG: In every frame callback
func processFrame(_ image: CIImage) -> CGImage? {
    let ctx = CIContext()  // DO NOT DO THIS
    return ctx.createCGImage(image, from: image.extent)
}

// RIGHT: One context, reused
final class PhotoProcessor {
    private let context: CIContext = {
        var opts = CIContextOptions()
        opts.cacheIntermediates = false  // Important for video
        return CIContext(options: opts)
    }()
    
    func processFrame(_ image: CIImage) -> CGImage? {
        context.createCGImage(image, from: image.extent)
    }
}
```

### Anti-Pattern 3: Saving Output to Camera Roll by Default

**What people do:** Process media → call `PHPhotoLibrary.shared().performChanges` to save the watermarked copy automatically.

**Why it's wrong:** The core value proposition is "watermark and share without cluttering the camera roll." Auto-saving violates this. Plus, Photos extensions already handle non-destructive storage — you return rendered content to the Photos app; you don't save separately.

**Do this instead:** Write output to a temp file in `cachesDirectory`. Present `UIActivityViewController` with that temp URL for sharing. Schedule cleanup of temp files after the share completes. Only save to camera roll if the user explicitly chooses "Save Image/Video" from the share sheet.

### Anti-Pattern 4: Not Preserving HDR During Custom Video Composition

**What people do:** Use `AVVideoComposition` with a CIFilter handler but don't configure color properties on the `AVAssetExportSession`, relying on defaults.

**Why it's wrong:** Default color properties assume SDR (BT.709). HDR content (HLG, Dolby Vision, HDR10) gets tone-mapped down to SDR, losing brightness range and color fidelity. The output looks flat and washed out.

**Do this instead:** For SDR videos, `AVAssetExportSession` with standard presets is fine. For HDR videos (detected via `AVAssetTrack.hasMediaCharacteristic(.containsHDRVideo)`), use `AVAssetWriter` with explicit 10-bit color properties (BT.2020 primaries, HLG/PQ transfer function, `kVTCompressionPropertyKey_HDRMetadataInsertionMode: kVTHDRMetadataInsertionMode_Auto`). Fall back to export session with warning if HDR preservation isn't critical for v1.

## Integration Points

### External Services

None. This is an entirely on-device app with no network dependencies.

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| App ↔ Share Extension | App Group file container + `UserDefaults(suiteName:)` | Extensions write media to shared inbox; main app reads it. No direct memory sharing. |
| App ↔ Photo Edit Extension | `PHContentEditingController` protocol (input/output contracts) | Photos framework mediates; extension receives `PHContentEditingInput`, returns `PHContentEditingOutput` |
| ViewModel ↔ Processing Engine | Async method calls (`async throws`) | ViewModel calls `engine.process()`, engine publishes progress via callback or async stream |
| Processing Engine ↔ Renderers | Synchronous function calls | Renderers are pure functions: receive config + source → return CIImage |
| All targets ↔ WatermarkCore | Direct framework linking | All three targets link the same local Swift Package; no IPC needed for shared code |

## Suggested Build Order (Dependency Graph)

```
                        ┌─────────────────────┐
                        │   WatermarkCore      │  ← PHASE 1: Foundation
                        │   Swift Package      │
                        │  - Models            │
                        │  - PositionCalc      │
                        │  - Renderers         │
                        │  - TempFileMgr       │
                        │  - AppGroupContainer │
                        └──────────┬──────────┘
                                   │
              ┌────────────────────┼────────────────────┐
              │                    │                    │
     ┌────────┴────────┐  ┌───────┴────────┐  ┌────────┴────────┐
     │  PhotoProcessor │  │ VideoProcessor │  │ MetadataPreserv.│
     │  (CIImage chain)│  │ (AVVideoComp)  │  │ (EXIF/AVMeta)  │
     └────────┬────────┘  └───────┬────────┘  └────────┬────────┘
              │                    │                    │
              └────────────────────┼────────────────────┘
                                   │
                        ┌──────────┴──────────┐
                        │  ProcessingEngine    │  ← PHASE 2: Core Pipeline
                        │  (Router + Progress) │
                        └──────────┬──────────┘
                                   │
              ┌────────────────────┼────────────────────┐
              │                    │                    │
     ┌────────┴────────┐  ┌───────┴────────┐  ┌────────┴────────┐
     │ Main App UI     │  │ Share Ext UI   │  │ PhotoEdit UI    │
     │ - Picker        │  │ - ShareVC      │  │ - PHContentEdit │
     │ - Config views  │  │ - SwiftUI host │  │ - SwiftUI host  │
     │ - Preview       │  │                │  │                 │
     │ - Share coord.  │  │                │  │                 │
     └────────┬────────┘  └───────┬────────┘  └────────┬────────┘
              │                    │                    │
              └────────────────────┼────────────────────┘
                                   │
                        ┌──────────┴──────────┐
                        │  Polish + Testing    │  ← PHASE 3: Integration
                        │  - HDR validation    │
                        │  - Metadata tests    │
                        │  - Edge cases        │
                        └─────────────────────┘
```

**Phase ordering rationale:**

- **Phase 1 (WatermarkCore + Models):** Everything depends on shared models and rendering functions. Build PositionCalculator, renderers, and temp file management first. These are pure logic, testable in isolation, and have zero UI dependencies.

- **Phase 2 (Processing Pipeline):** PhotoProcessor and VideoProcessor depend on renderers from Phase 1. MetadataPreserver depends on ImageIO/AVFoundation knowledge. ProcessingEngine ties them together. Once this phase is done, the app CAN process media end-to-end (testable via unit tests and command-line tools).

- **Phase 3 (UI + Extensions):** All three UI targets depend on Phase 2's ProcessingEngine. Main app should be built first (has the most UI complexity and the in-app picker). Share extension next (simpler UI, same engine). Photos edit extension last (most constrained environment, requires PHContentEditingController integration).

**Research flags for phases:**
- Phase 2 (VideoProcessor): HIGH risk — HDR preservation is complex and may need offline investigation with sample HDR footage. Flag for deeper research during planning.
- Phase 3 (Photo Edit Extension): MEDIUM risk — PHContentEditingController has strict lifecycle requirements (cancelContentEditing, shouldShowCancelConfirmation). These are well-documented but easy to miss.
- Phase 1 (Renderers): LOW risk — Core Image filter chaining is well-understood, pure functions, highly testable.

## Sources

- Apple Developer Documentation — AVFoundation: AVVideoComposition, AVAssetExportSession, AVAssetWriter (developer.apple.com). HIGH confidence.
- Apple Developer Documentation — Photos: PHContentEditingController, PHContentEditingInput, PHContentEditingOutput (developer.apple.com). HIGH confidence.
- Apple Developer Documentation — Core Image: CIFilter, CIContext, CIAttributedTextImageGenerator, CISourceOverCompositing (developer.apple.com). HIGH confidence.
- Apple Developer Documentation — ImageIO: CGImageSource, CGImageDestination, metadata preservation (developer.apple.com). HIGH confidence.
- Apple Developer Documentation — App Extension Programming Guide: Share Extensions, Photo Editing Extensions, App Groups (developer.apple.com). HIGH confidence.
- Swift Evolution — SE-0395: Observation Framework (@Observable macro, iOS 17+). HIGH confidence.
- Multiple community sources (Medium, Stack Overflow, dev.to) — project structure patterns, extension architecture, Core Image performance. MEDIUM confidence (community consensus, verified against official docs).
- Community reports on HDR metadata preservation challenges during custom AVVideoComposition (forasoft.com, nonstrict.eu). MEDIUM confidence (practical experience reports, consistent across multiple sources).

---

*Architecture research for: iOS Photo/Video Watermarking App*
*Researched: 2026-06-17*
*Confidence: HIGH*
