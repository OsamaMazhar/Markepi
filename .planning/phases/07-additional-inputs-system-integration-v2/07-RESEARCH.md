# Phase 7: Additional Inputs & System Integration (v2) - Research

**Researched:** 2026-06-18
**Domain:** iOS system integration (Live Photos, PencilKit, Files import, Quick Actions, App Intents)
**Confidence:** HIGH

## Summary

Phase 7 expands Watermark with four feature groups: Live Photo preservation (LIVE-01, LIVE-02), PencilKit-based signature capture (SIGN-01), Files app import + "Open In" (IMPS-01, IMPS-02), and home screen quick actions + Siri/Shortcuts App Intents (SYSI-01, SYSI-02). All four feature groups are implemented using Apple system frameworks with zero third-party dependencies [CITED: STACK.md], and each integrates into the existing WatermarkCore engine pipeline and MVVM + @Observable architecture established in Phases 1-6.

**Primary recommendation:** Use `PHLivePhotoEditingContext.frameProcessor` with the existing `buildFilterGraph` for Live Photos (reuse, don't duplicate the compositing logic), `PencilKit` `PKCanvasView` via `UIViewRepresentable` for signature capture with vector `PKDrawing` serialization, `CFBundleDocumentTypes` + `.onOpenURL` + `.fileImporter` for file import, `UIApplicationDelegateAdaptor` + `SceneDelegate` for quick actions, and `@AssistantIntent` + `AppIntent` + `AppShortcutsProvider` for Siri/Shortcuts — all defined in-app without a separate Intents extension.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

#### Live Photos
- **D-01:** Use `PHLivePhotoEditingContext` — Apple's high-level API for reading and writing Live Photos. Provides access to both the still image and video frame sequence, handles re-assembly of the paired asset.
- **D-02:** Watermark applied to both the still frame AND all motion frames. The watermark persists through the entire Live Photo animation. Consistent with LIVE-01 and LIVE-02.
- **D-03:** Detect Live Photos as paired assets in PhotosPicker. When a user selects a Live Photo (which PhotosPicker exposes as both an image item and a movie item), detect the pairing and present them as a single "Live Photo" item in the thumbnail strip. The engine processes both components together.
- **D-04:** Output preserves Live Photo format — both watermarked still frame and watermarked video component re-assembled into a proper Live Photo asset. Follows the Phase 1 D-09 "preserve source format" principle.

#### Signature Capture
- **D-05:** PencilKit (`PKCanvasView`) for signature drawing — full Apple Pencil pressure sensitivity, stroke smoothing, and undo support. No third-party dependencies needed.
- **D-06:** New `.signature` case on `WatermarkLayer` enum with a `SignatureInput` model (stores PencilKit stroke data, ink color, stroke width). Preserves vector data for re-editing. Engine renders signature to `CIImage` at compositing time via the standard `buildFilterGraph` pipeline.
- **D-07:** Signature capture UI as a full-screen modal sheet triggered from `LayerListView` ("Add Signature" button). Follows the existing `LogoPickerView` pattern of modal presentation from layer controls.
- **D-08:** Configurable signature properties after capture: ink color (re-renders stroke data in new color), stroke width, plus the existing per-layer position/scale/opacity controls inherited from the `WatermarkLayer` model.

#### Files Import & Open In
- **D-09:** Both push and pull: register `CFBundleDocumentTypes` for image/video UTIs in Info.plist (enables "Open in Watermark" system-wide), AND add a "Browse Files" button in the main app for in-app file browsing via `.fileImporter`. Covers both IMPS-01 (pull) and IMPS-02 (push).
- **D-10:** Use SwiftUI `.onOpenURL` modifier with `CFBundleDocumentTypes` for "Open In" handling. No custom URL scheme needed — document type handling is the native iOS mechanism. Copy the incoming file to the app sandbox before processing.
- **D-11:** When a file is opened via Files or Open In, replace the current selection and immediately enter the watermarking workflow. The user sees the same configure→preview→share flow.
- **D-12:** Accept all photo formats (HEIC, JPEG, PNG, TIFF, DNG/ProRAW) and video formats (MOV, MP4) that the engine already handles. Reject unsupported types with a user-friendly alert.

#### Quick Actions
- **D-13:** "Watermark Last Photo" — use PhotoKit to fetch the most recent `PHAsset` from the camera roll (`fetchAssets` with `sortDescriptors: [creationDate descending]`, `fetchLimit: 1`). Request limited/full photo library permission. Load the asset and pre-populate the watermarking workflow. If no photos exist or permission denied, open the app normally.
- **D-14:** "Watermark from Clipboard" — check `UIPasteboard.general` for an image on quick action trigger. If an image is found, load it and pre-populate the watermarking workflow. If no image on clipboard, open the app normally.
- **D-15:** Both quick actions ("Watermark Last Photo" and "Watermark from Clipboard") open the app with the media pre-loaded in the full watermarking UI. The user configures the watermark and shares interactively — no headless processing.

#### App Intents (Siri & Shortcuts)
- **D-16:** Use `@AssistantIntent` + `AppIntent` dual protocol approach. `@AssistantIntent` enables Siri AI natural language interaction ("Watermark my last photo"); `AppIntent` enables Shortcuts app automation. This is the Apple-recommended pattern — SiriKit is deprecated; App Intents is now mandatory for Siri integration.
- **D-17:** Two task-based intents: "Watermark Photo" and "Watermark Video". Each models a specific task the user wants to achieve (not navigation intents like "Open Watermark"). Aligns with Apple's guidance to model task intents for agentic Siri.
- **D-18:** Intents open the app with media pre-loaded in the interactive watermarking UI — same pattern as quick actions. No headless processing. The user sees the preview, configures the watermark, and shares. This preserves the app's core value of visual preview + customization before sharing.
- **D-19:** Intent parameters: media item (`IntentFile` or AppEntity from Siri context/Shortcuts input) + optional `WatermarkConfiguration` (JSON-serialized, defaults to last-used config from App Group if not provided). Minimal parameter surface — just the media and optional config.

### the agent's Discretion

- `PHLivePhotoEditingContext` implementation details: frame iteration approach, output assembly for watermarked Live Photo, error handling for unsupported Live Photo variants
- `SignatureInput` model structure: PencilKit `PKDrawing` data serialization format (Codable `Data` blob), ink type enum, default stroke width
- `PKCanvasView` UI customization: tool picker visibility, supported ink types (pen, marker, pencil), undo/redo button placement, canvas background (transparent → renders as transparent PNG)
- `CFBundleDocumentTypes` UTI list: exact UTIs to register for image and video document types in Info.plist
- PhotoKit authorization flow for "Watermark Last Photo": permission request timing, limited vs full access handling, denied fallback UI
- `UIPasteboard` image type detection: check order (public.png, public.jpeg, public.tiff), fallback to `UIPasteboard.general.image`
- App Intents target: whether to create a separate Intents extension target or define intents in-app (iOS 18+ supports both; in-app is simpler for interactive intents)
- `@AssistantIntent` natural language phrases and AppSchema definitions for Siri AI
- `IntentFile` handling for media transfer between Shortcuts/Siri and the app's sandbox
- How "optional config" is passed through intents: `WatermarkConfiguration` JSON-encoded as an optional `String` parameter, decoded on the app side
- Whether the `.signature` layer should be included in `WatermarkConfiguration.strippingImageData()` (PHAdjustmentData size) — signature stroke data is typically small (<100KB), likely no stripping needed
- Live Photos in Share Extension and Photo Edit Extension: whether D-01 through D-04 apply to extension entry points or main app only (user did not specify — main app is the primary target; extensions can follow later)

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| LIVE-01 | User can watermark Live Photos while preserving the motion video component | PHLivePhotoEditingContext.frameProcessor applies watermark to every frame; saveLivePhoto re-assembles paired asset (Section 1) |
| LIVE-02 | Still frame and motion component both receive the watermark overlay | Same frameProcessor closure processes both `.photo` and `.video` frame types uniformly (Section 1) |
| SIGN-01 | User can draw or capture a signature to use as a watermark overlay | PencilKit PKCanvasView via UIViewRepresentable captures strokes; PKDrawing renders to CIImage for compositing (Section 2) |
| IMPS-01 | User can import media from the Files app / iCloud Drive directly | .fileImporter modifier presents system file picker; security-scoped resource access for sandboxed files (Section 3) |
| IMPS-02 | User can open media via "Open In" from other apps and file providers | CFBundleDocumentTypes registers app as handler; .onOpenURL captures incoming file URL (Section 3) |
| SYSI-01 | User can access "Watermark Last Photo" and "Watermark from Clipboard" from the home screen quick actions menu | UIApplicationShortcutItems in Info.plist; UIApplicationDelegateAdaptor + SceneDelegate for handling (Section 4) |
| SYSI-02 | User can trigger watermarking via Siri / Shortcuts / App Intents | @AssistantIntent + AppIntent + AppShortcutsProvider; IntentFile for media transfer; in-app intent definition (Section 5) |
</phase_requirements>

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Live Photo detection & pairing | App (ViewModel) | — | PhotosPicker item inspection and UTI-based pairing logic runs in the app's import flow; engine processes pre-paired items |
| Live Photo frame processing | Engine (WatermarkCore) | — | Per-frame watermark application reuses the existing CIImage filter graph in the engine — don't duplicate compositing logic |
| Live Photo assembly & export | Engine (WatermarkCore) | — | PHLivePhotoEditingContext.saveLivePhoto is a rendering/export operation that belongs in the processing pipeline |
| Signature drawing capture | App UI | — | PKCanvasView modal sheet is a view-layer concern presented from LayerListView |
| Signature vector serialization | Models (WatermarkCore) | — | PKDrawing Data blob stored in SignatureInput model; Codable for config sync |
| Signature → CIImage rendering | Engine (WatermarkCore) | — | Signature rasterization happens in buildFilterGraph alongside text/image rendering |
| Files browsing (.fileImporter) | App UI | App (ViewModel) | SwiftUI modifier triggers system file picker; ViewModel loads and processes the selected file |
| "Open In" URL handling | App (WatermarkApp) | App (ViewModel) | .onOpenURL modifier on WindowGroup captures URL; ViewModel copies file to sandbox and processes |
| CFBundleDocumentTypes registration | App (Info.plist) | — | Static plist configuration — no runtime code |
| Quick action handling | App (SceneDelegate) | App (ViewModel) | UIKit delegate intercepts shortcut item; ViewModel executes the data-loading action |
| PhotoKit fetch (last photo) | App (ViewModel) | — | PHAsset fetch + PHImageManager load is app-level logic; output feeds into existing processing pipeline |
| Clipboard image detection | App (ViewModel) | — | UIPasteboard check is app-level logic; PNG data conversion feeds into existing pipeline |
| App Intents definition | App (Intents) | — | Intents defined in-app per D-16; openAppWhenRun = true routes to existing workflow |
| Intent media loading | App (ViewModel) | — | IntentFile data converted to temp file; ViewModel replaces selection and enters watermarking UI |

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| PHLivePhotoEditingContext | iOS 18 SDK | Live Photo read + frame-apply + write | Only API for Live Photo editing with frame-level access. Apple's documented approach. [VERIFIED: Apple Developer docs] |
| PencilKit (PKCanvasView, PKDrawing) | iOS 18 SDK | Signature capture and vector storage | Apple's first-party drawing framework with pressure sensitivity, stroke smoothing, Codable serialization. [VERIFIED: Apple Developer docs] |
| AppIntents (@AssistantIntent, AppIntent) | iOS 18 SDK | Siri AI + Shortcuts integration | Only supported framework for Siri integration post-iOS 18. SiriKit is deprecated. [VERIFIED: Apple Developer docs, WWDC 2024] |
| Photos (PHAsset, PHImageManager) | iOS 18 SDK | Camera roll fetch for quick actions | Required for "Watermark Last Photo" — fetch most recent asset without PhotosPicker. [VERIFIED: Apple Developer docs] |
| UIKit (UIPasteboard) | iOS 18 SDK | Clipboard image detection | Standard iOS clipboard API for "Watermark from Clipboard" quick action. [VERIFIED: Apple Developer docs] |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| UniformTypeIdentifiers (UTType) | iOS 18 SDK | Content type detection for Live Photos and file imports | Detecting Live Photo bundle UTI (`com.apple.live-photo-bundle`), validating imported file types against supported UTIs |
| CFBundleDocumentTypes (Info.plist) | — | Register app as file handler system-wide | Static registration in Info.plist for "Open In" from Files, Mail, Safari, etc. |
| UIApplicationShortcutItems (Info.plist) | — | Static home screen quick actions | Two static items: "Watermark Last Photo" and "Watermark from Clipboard" |
| UIApplicationDelegateAdaptor | iOS 18 SDK | Bridge UIKit delegates to SwiftUI App | Required for quick action handling (SceneDelegate intercepts shortcut items) |
| NotificationCenter | iOS 18 SDK | SceneDelegate → ViewModel communication | Quick action notification path: SceneDelegate posts notification → ViewModel receives |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| PHLivePhotoEditingContext (standard) | Manual AVAsset decomposition + re-assembly | Significantly more complex; must handle still/video pairing, timing metadata, and output format manually. Only if PHLivePhotoEditingContext has unacceptable limitations for this use case (no known limitations relevant here). |
| PKCanvasView via UIViewRepresentable (standard) | Custom SwiftUI Canvas + touch handling | Rebuilds PencilKit's stroke smoothing, pressure curves, undo/redo. PencilKit solves all of this natively. |
| @AssistantIntent in-app (recommended) | Separate Intents extension target | Required only for headless/background intents. Adds target complexity, App Group coordination. This phase's intents are interactive (open app). |
| UIApplicationDelegateAdaptor + SceneDelegate (standard) | @Environment(\\.scenePhase) | Can't detect quick action type from scenePhase alone — need the specific shortcutItem from connectionOptions/windowScene callback. |
| .onOpenURL (standard) | Custom URL scheme (e.g., watermark://) | URL schemes are less secure, can conflict with other apps, and don't integrate with the Files app "Open In" flow. |
| IntentFile (standard) | PHAsset reference in App Intents | PHAsset references require full photo library access in Shortcuts context; IntentFile works with any file source and is simpler. |

**Installation:** No third-party packages needed. All frameworks are Apple system frameworks included with iOS 18 SDK. [CITED: STACK.md]

**Version verification:** All frameworks verified as part of iOS 18 SDK via Xcode 26.2 (Build 17C52), Swift 6.2.3.

## Package Legitimacy Audit

> No external packages are installed in this phase. All technologies are Apple system frameworks (PHLivePhotoEditingContext, PencilKit, AppIntents, PhotoKit, UIKit). Skipping slopcheck — no third-party packages to audit.

## Architecture Patterns

### System Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                        INPUT SOURCES                                 │
│                                                                      │
│  ┌──────────────┐  ┌──────────────┐  ┌───────────┐  ┌────────────┐ │
│  │ PhotosPicker │  │ .fileImporter│  │ .onOpenURL│  │ Quick      │ │
│  │ (existing +  │  │ (Files app)  │  │ (Open In) │  │ Actions    │ │
│  │  Live Photo  │  │              │  │           │  │ (Shortcut) │ │
│  │  pairing)    │  └──────┬───────┘  └─────┬─────┘  └──────┬─────┘ │
│  └──────┬───────┘         │                │               │        │
│         │                 │                │               │        │
│  ┌──────┴───────┐  ┌──────┴───────┐  ┌─────┴─────┐  ┌──────┴─────┐│
│  │ App Intents  │  │ UIPasteboard │  │ Signature │  │            ││
│  │ (Siri/Short- │  │ (Clipboard)  │  │ Capture   │  │            ││
│  │  cuts input) │  │              │  │ (PencilKit)│  │            ││
│  └──────┬───────┘  └──────┬───────┘  └─────┬─────┘              ││
│         │                 │                │                     ││
└─────────┼─────────────────┼────────────────┼─────────────────────┘│
          │                 │                │                       
          ▼                 ▼                ▼                       
┌─────────────────────────────────────────────────────────────────────┐
│                    VIEWMODEL (App Layer)                             │
│                                                                      │
│  handleSelection() ─── Live Photo pairing detection                 │
│  handleIncomingFile(url:) ─── copy to sandbox, format check         │
│  fetchMostRecentPhoto() ─── PhotoKit PHAsset fetch                  │
│  loadFromClipboard() ─── UIPasteboard → PNG Data                    │
│  handleIntent(media:config:) ─── IntentFile → temp file             │
│  addSignatureLayer(strokeData:color:width:) ─── config mutation     │
│                                                                      │
│                    │                                                 │
│                    ▼                                                 │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │              WatermarkConfiguration                           │   │
│  │  WatermarkLayer enum: .text | .image | .signature (NEW)      │   │
│  │  SignatureInput: strokeData(Data), inkColor, strokeWidth     │   │
│  └─────────────────────────────────────────────────────────────┘   │
└──────────────────────────────┬──────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────────┐
│                  ENGINE (WatermarkCore Package)                      │
│                                                                      │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │ buildFilterGraph(base:config:metadata:)                       │   │
│  │                                                               │   │
│  │  For each WatermarkLayer:                                     │   │
│  │    .text    → TextWatermarkRenderer.render()                  │   │
│  │    .image   → ImageWatermarkRenderer.render()                 │   │
│  │    .signature → SignatureRenderer.render()   ←── NEW          │   │
│  │                 (PKDrawing → UIImage → CIImage)               │   │
│  │                                                               │   │
│  │  → WatermarkRenderer.composite(layers:onto:)                  │   │
│  │  → CIContextProvider.shared.createCGImage()                   │   │
│  └──────────────────────────────────────────────────────────────┘   │
│                                                                      │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │ LivePhotoProcessor.process(pairedAsset:config:)    ←── NEW    │   │
│  │                                                               │   │
│  │  PHLivePhotoEditingContext(frameProcessor: { frame in         │   │
│  │      buildFilterGraph(base: frame.image, config: ...)         │   │
│  │  })                                                           │   │
│  │  → saveLivePhoto(to: output, options: nil)                    │   │
│  └──────────────────────────────────────────────────────────────┘   │
└──────────────────────────────┬──────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────────┐
│                         OUTPUT                                       │
│  TempFileManager.createTempFile() → share sheet → discard           │
│  Live Photo: .mov + .heic pair → assembled PHLivePhoto              │
└─────────────────────────────────────────────────────────────────────┘
```

### Recommended Project Structure

```
Packages/WatermarkCore/Sources/WatermarkCore/
├── Engine/
│   ├── WatermarkEngine.swift         # + Live Photo detection in mediaType()
│   └── PipelineError.swift           # + livePhotoUnsupported case
├── Processing/
│   ├── LivePhotoProcessor.swift      # NEW: PHLivePhotoEditingContext wrapper
│   └── SignatureRenderer.swift       # NEW: PKDrawing → CIImage
├── Models/
│   ├── WatermarkConfiguration.swift  # + .signature case on WatermarkLayer
│   ├── SignatureInput.swift          # NEW: strokeData, inkColor, strokeWidth
│   └── ProcessingResult.swift        # + .livePhoto case if needed
├── UI/
│   ├── ControlsView.swift            # + SignaturePickerView integration
│   ├── LayerListView.swift           # + signature layer icon/description
│   ├── LogoPickerView.swift          # (reference pattern for modal)
│   ├── SignatureCaptureView.swift    # NEW: PKCanvasView UIViewRepresentable
│   └── WatermarkConfigurable.swift   # + addSignatureLayer() requirement
│

App/
├── WatermarkApp.swift                # + .onOpenURL, + AppDelegateAdaptor
├── AppDelegate.swift                 # NEW: SceneDelegate bridge
├── SceneDelegate.swift               # NEW: Quick action handler
├── Info.plist                        # + CFBundleDocumentTypes, + UIApplicationShortcutItems
├── ViewModels/
│   └── WatermarkViewModel.swift      # + LivePhoto pairing, file import, quick actions, intents
├── Views/
│   └── ContentView.swift             # + .fileImporter modifier, + Browse Files button
│
├── Intents/
│   ├── WatermarkPhotoIntent.swift    # NEW: @AssistantIntent + AppIntent
│   ├── WatermarkVideoIntent.swift    # NEW: @AssistantIntent + AppIntent
│   └── WatermarkAppShortcuts.swift   # NEW: AppShortcutsProvider
```

### Pattern 1: Live Photo Pairing in PhotosPicker

**What:** Apple's `PhotosPickerItem` for a Live Photo exposes two items with related `itemIdentifier`s — one for the still image (`/public.jpeg`) and one for the video component (`/public.movie`). Detect the pairing by matching the base identifier (strip the path suffix).

**When to use:** When a user selects Live Photos in PhotosPicker; the pairing logic runs in `WatermarkViewModel.handleSelection()` before loading data.

**Example:**
```swift
// Source: Apple Developer, PhotosPicker + UTType
import UniformTypeIdentifiers

extension UTType {
    static var livePhotoBundle: UTType {
        UTType("com.apple.live-photo-bundle")!
    }
}

// In WatermarkViewModel.handleSelection():
func detectLivePhotoPairs(_ items: [PhotosPickerItem]) -> [(still: PhotosPickerItem, video: PhotosPickerItem)] {
    // Group items by base identifier (strip /public.jpeg, /public.movie suffix)
    var stillItems: [String: PhotosPickerItem] = [:]
    var videoItems: [String: PhotosPickerItem] = [:]
    
    for item in items {
        guard let id = item.itemIdentifier else { continue }
        // Live Photo still frames have itemIdentifier like "ABC123/public.jpeg"
        // Video components have "ABC123/public.movie"
        let components = id.components(separatedBy: "/")
        guard components.count == 2 else { continue }
        let baseID = components[0]
        let suffix = components[1]
        
        if suffix == "public.jpeg" || suffix == "public.heic" {
            stillItems[baseID] = item
        } else if suffix == "public.movie" {
            videoItems[baseID] = item
        }
    }
    // Return pairs where both still and video exist
    return stillItems.compactMap { (baseID, still) in
        guard let video = videoItems[baseID] else { return nil }
        return (still, video)
    }
}
```

### Pattern 2: PHLivePhotoEditingContext with frameProcessor

**What:** `PHLivePhotoEditingContext` provides `frameProcessor` — a closure called for every frame (both still `.photo` and video `.video` types). Apply the same watermark compositing logic to each frame and return the modified `CIImage`. The `saveLivePhoto(to:options:)` method re-assembles the watermarked frames into a proper Live Photo.

**When to use:** When processing a Live Photo that has been pre-loaded as a paired asset.

**Example:**
```swift
// Source: Apple Developer Documentation — PHLivePhotoEditingContext
// [CITED: developer.apple.com/documentation/photokit/phlivephotoeditingcontext]
import Photos
import CoreImage

func processLivePhoto(input: PHContentEditingInput, 
                      output: PHContentEditingOutput,
                      config: WatermarkConfiguration) async throws {
    guard let context = PHLivePhotoEditingContext(livePhotoEditingInput: input) else {
        throw PipelineError.livePhotoUnsupported
    }
    
    // Extract metadata once for the still frame
    let metadata = // extract from input.fullSizeImageURL
    
    context.frameProcessor = { [config, metadata] frame, _ in
        let inputImage = frame.image
        // Reuse the existing filter graph — don't duplicate compositing logic
        let composited = try? WatermarkEngine.shared.buildFilterGraph(
            base: inputImage,
            config: config,
            metadata: metadata ?? [:]
        )
        return composited ?? inputImage // Fall back to original on failure
    }
    
    // Save to output
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        context.saveLivePhoto(to: output, options: nil) { success, error in
            if success {
                continuation.resume()
            } else {
                continuation.resume(throwing: error ?? PipelineError.renderFailed)
            }
        }
    }
}
```

### Pattern 3: Signature Capture via PencilKit UIViewRepresentable

**What:** Wrap `PKCanvasView` in `UIViewRepresentable` to bridge UIKit drawing to SwiftUI. The `PKDrawing` object (vector strokes) serializes to `Data` via `dataRepresentation()` and deserializes via `PKDrawing(data:)`. Render to image using `PKDrawing.image(from:scale:)` then convert to `CIImage` for compositing.

**When to use:** When the user taps "Add Signature" in `LayerListView`, present a full-screen modal with the signature canvas.

**Example:**
```swift
// Source: Apple Developer Documentation — PencilKit
// [CITED: developer.apple.com/documentation/pencilkit]
import SwiftUI
import PencilKit

struct SignatureCanvasView: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    var inkColor: UIColor = .black
    var strokeWidth: CGFloat = 3.0
    
    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawingPolicy = .anyInput  // Finger + Apple Pencil
        canvas.tool = PKInkingTool(.pen, color: inkColor, width: strokeWidth)
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.delegate = context.coordinator
        return canvas
    }
    
    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        if uiView.drawing != drawing {
            uiView.drawing = drawing
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: SignatureCanvasView
        init(_ parent: SignatureCanvasView) { self.parent = parent }
        
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            DispatchQueue.main.async {
                self.parent.drawing = canvasView.drawing
            }
        }
    }
}

// Modal sheet usage (following LogoPickerView pattern):
struct SignatureCaptureView: View {
    @State private var drawing = PKDrawing()
    @State private var inkColor: UIColor = .black
    @State private var strokeWidth: CGFloat = 3.0
    let onSave: (Data, CGColor, CGFloat) -> Void
    
    var body: some View {
        NavigationStack {
            VStack {
                SignatureCanvasView(
                    drawing: $drawing,
                    inkColor: inkColor,
                    strokeWidth: strokeWidth
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white.opacity(0.05))
                
                // Toolbar: undo, redo, clear, color picker, stroke width
                HStack {
                    Button("Undo") { /* PKCanvasView.undoManager?.undo() */ }
                    Button("Clear") { drawing = PKDrawing() }
                    ColorPicker("Ink", selection: /* binding */)
                    Button("Save") {
                        let strokeData = drawing.dataRepresentation()
                        let cgColor = /* from inkColor */
                        onSave(strokeData, cgColor, strokeWidth)
                    }
                }
            }
            .navigationTitle("Draw Signature")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
```

### Pattern 4: CFBundleDocumentTypes + .onOpenURL for File Import

**What:** Register the app as a handler for image and video UTIs in `Info.plist` using `CFBundleDocumentTypes`. Handle incoming URLs via `.onOpenURL` modifier on `WindowGroup`. For in-app browsing, use `.fileImporter`. Both paths converge on the same `handleIncomingFile(url:)` method in the ViewModel.

**When to use:** IMPS-01 (pull — Files browsing via .fileImporter) and IMPS-02 (push — "Open In" from other apps via .onOpenURL).

**Example:**
```swift
// Info.plist registration:
// <key>CFBundleDocumentTypes</key>
// <array>
//   <dict>
//     <key>CFBundleTypeName</key><string>Image</string>
//     <key>LSHandlerRank</key><string>Alternate</string>
//     <key>LSItemContentTypes</key>
//     <array>
//       <string>public.image</string>
//       <string>public.jpeg</string>
//       <string>public.heic</string>
//       <string>public.png</string>
//       <string>public.tiff</string>
//       <string>com.adobe.raw-image</string>
//     </array>
//   </dict>
//   <dict>
//     <key>CFBundleTypeName</key><string>Video</string>
//     <key>LSHandlerRank</key><string>Alternate</string>
//     <key>LSItemContentTypes</key>
//     <array>
//       <string>public.movie</string>
//       <string>com.apple.quicktime-movie</string>
//       <string>public.mpeg-4</string>
//     </array>
//   </dict>
// </array>

// WatermarkApp.swift:
@main
struct WatermarkApp: App {
    @State private var viewModel = WatermarkViewModel()
    
    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .onOpenURL { url in
                    viewModel.handleIncomingFile(url: url)
                }
        }
    }
}

// WatermarkViewModel.swift:
func handleIncomingFile(url: URL) {
    // Security-scoped access for external files
    guard url.startAccessingSecurityScopedResource() else { return }
    defer { url.stopAccessingSecurityScopedResource() }
    
    // Validate format against supported UTIs
    let mediaType = WatermarkEngine.mediaType(for: url)
    guard mediaType != .unknown else {
        errorMessage = "Unsupported file format."
        showError = true
        return
    }
    
    // Copy to app sandbox temp directory before processing
    let tempURL = TempFileManager.createTempFile(uti: ...)
    try? FileManager.default.copyItem(at: url, to: tempURL)
    
    // Replace current selection and enter workflow (D-11)
    let thumb = createThumbnail(from: try! Data(contentsOf: tempURL), maxPixelSize: 200)
    photos = [PhotoItem(id: UUID(), thumbnail: thumb, sourceURL: tempURL)]
    currentIndex = 0
}
```

### Pattern 5: Quick Actions via AppDelegate + SceneDelegate

**What:** Static quick actions defined in `Info.plist` (`UIApplicationShortcutItems`). Handled via `UIApplicationDelegateAdaptor` + `SceneDelegate` — the `SceneDelegate` intercepts the `shortcutItem` on app launch (`scene(_:willConnectTo:options:)`) and on resume (`windowScene(_:performActionFor:)`). Posts a notification to the ViewModel.

**When to use:** SYSI-01 — "Watermark Last Photo" and "Watermark from Clipboard" from home screen long-press menu.

**Example:**
```swift
// Source: Apple Developer — UIApplicationShortcutItems
// [CITED: developer.apple.com/documentation/uikit/uiapplicationshortcutitem]

// Info.plist:
// <key>UIApplicationShortcutItems</key>
// <array>
//   <dict>
//     <key>UIApplicationShortcutItemType</key>
//     <string>com.watermark.app.watermark-last-photo</string>
//     <key>UIApplicationShortcutItemTitle</key>
//     <string>Watermark Last Photo</string>
//     <key>UIApplicationShortcutItemIconSystemImageName</key>
//     <string>photo.on.rectangle.angled</string>
//   </dict>
//   <dict>
//     <key>UIApplicationShortcutItemType</key>
//     <string>com.watermark.app.watermark-from-clipboard</string>
//     <key>UIApplicationShortcutItemTitle</key>
//     <string>Watermark from Clipboard</string>
//     <key>UIApplicationShortcutItemIconSystemImageName</key>
//     <string>doc.on.clipboard</string>
//   </dict>
// </array>

// AppDelegate.swift:
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: session.role)
        config.delegateClass = SceneDelegate.self
        return config
    }
}

// SceneDelegate.swift:
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

// WatermarkApp.swift (updated):
@main
struct WatermarkApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var viewModel = WatermarkViewModel()
    
    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .onReceive(NotificationCenter.default.publisher(for: .didReceiveQuickAction)) { notif in
                    guard let type = notif.object as? String else { return }
                    viewModel.handleQuickAction(type)
                }
                .onOpenURL { url in
                    viewModel.handleIncomingFile(url: url)
                }
        }
    }
}
```

### Pattern 6: App Intents with @AssistantIntent and IntentFile

**What:** Define `AppIntent` structs with `@AssistantIntent` macro for Siri AI, `AppShortcutsProvider` for Siri/Shortcuts registration, and `IntentFile` parameters for media input. Intents open the app (`openAppWhenRun: true`) with media pre-loaded. Defined in-app, not in a separate extension target.

**When to use:** SYSI-02 — Siri "Watermark this photo" and Shortcuts app automation.

**Example:**
```swift
// Source: Apple Developer — AppIntents framework
// [CITED: developer.apple.com/documentation/appintents]
import AppIntents

@AssistantIntent(schema: .photos.edit)
struct WatermarkPhotoIntent: AppIntent {
    static var title: LocalizedStringResource = "Watermark Photo"
    static var description = IntentDescription("Adds a watermark overlay to a photo.")
    static var openAppWhenRun: Bool = true  // D-18: interactive, not headless
    
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
        // Store the IntentFile data in App Group for the main app to consume
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
        
        // App opens — ViewModel reads pendingIntentMediaURL on appear
        return .result()
    }
}

// AppShortcutsProvider:
struct WatermarkAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: WatermarkPhotoIntent(),
            phrases: [
                "Watermark a photo in \(.applicationName)",
                "Add watermark to photo with \(.applicationName)",
                "Watermark my photo using \(.applicationName)"
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

### Pattern 7: PhotoKit Fetch for "Watermark Last Photo"

**What:** Use `PHAsset.fetchAssets` with `creationDate` sorted descending and `fetchLimit: 1` to get the most recent photo. Request `PHPhotoLibrary.authorizationStatus(for: .readWrite)`; handle `.notDetermined`, `.authorized`, `.limited`, `.denied`, and `.restricted` states. Load via `PHImageManager.requestImageDataAndOrientation` for full-quality data.

**When to use:** SYSI-01 "Watermark Last Photo" quick action — D-13.

**Example:**
```swift
// Source: Apple Developer — PhotoKit
// [CITED: developer.apple.com/documentation/photokit]
import Photos

func fetchMostRecentPhoto() async -> Data? {
    let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    
    switch status {
    case .notDetermined:
        let newStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard newStatus == .authorized || newStatus == .limited else { return nil }
    case .denied, .restricted:
        return nil // Can't access — show alert, open app normally (D-13)
    case .authorized, .limited:
        break // Proceed
    @unknown default:
        return nil
    }
    
    let fetchOptions = PHFetchOptions()
    fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
    fetchOptions.fetchLimit = 1
    fetchOptions.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.image.rawValue)
    
    let result = PHAsset.fetchAssets(with: fetchOptions)
    guard let asset = result.firstObject else { return nil }
    
    // Load full-quality image data
    return await withCheckedContinuation { continuation in
        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.deliveryMode = .highQualityFormat
        PHImageManager.default().requestImageDataAndOrientation(
            for: asset, options: options
        ) { data, _, _, _ in
            continuation.resume(returning: data)
        }
    }
}
```

### Anti-Patterns to Avoid
- **Do NOT build a custom touch-drawing canvas:** PencilKit provides pressure-sensitive strokes, palm rejection, smooth curves, and undo/redo. Building custom touch handling would be worse in every dimension.
- **Do NOT use SiriKit Intents:** Deprecated as of iOS 18. App Intents framework is the only supported Siri integration path.
- **Do NOT manually decompose Live Photos:** `PHLivePhotoEditingContext` handles still/video decomposition, frame iteration, and re-assembly. Manual AVAsset manipulation would require handling paired assets, timing metadata, and output format matching — a month of work vs. a day with the API.
- **Do NOT define a custom URL scheme for "Open In":** CFBundleDocumentTypes is the native iOS mechanism that integrates with Files app, Mail, Safari, AirDrop, and all file providers. Custom URL schemes only work with apps that explicitly know about your scheme.
- **Do NOT create a separate Intents extension target for interactive intents:** D-18 specifies intents open the app. In-app intent definition is simpler (no target management, no cross-process coordination). Separate extension target is only needed for headless/background intents.
- **Do NOT access PhotosPicker Live Photo items as plain images or videos:** A Live Photo is a paired asset — treating each component separately would lose the pairing, and the output wouldn't be a proper Live Photo.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Live Photo frame iteration | Custom AVAssetReader per-frame processing | `PHLivePhotoEditingContext.frameProcessor` | Handles still/video pairing, frame timing, and output assembly. Manual approach requires 500+ lines of AVFoundation and breaks easily with iOS updates. |
| Signature/drawing capture | Custom UIView touch tracking, Bézier curve smoothing, pressure handling | `PencilKit` `PKCanvasView` | PencilKit provides Apple Pencil pressure sensitivity, stroke smoothing, palm rejection, undo/redo manager, and Codable serialization. Custom touch handling is months of work for worse results. |
| Signature vector → image rasterization | Custom CGContext rendering from stroke arrays | `PKDrawing.image(from:scale:)` | Built-in method renders strokes at target resolution with correct anti-aliasing and pressure curves. |
| System file handler registration | Custom URL scheme, manual share sheet filtering | `CFBundleDocumentTypes` in Info.plist | Native iOS mechanism for "Open In" — integrates with Files app, Mail, Safari, AirDrop, and all UIDocumentPickerViewController-based apps. |
| Siri/Shortcuts integration | SiriKit Intents (deprecated), custom voice shortcuts | `@AssistantIntent` + `AppIntent` + `AppShortcutsProvider` | Only supported Siri integration path post-iOS 18. Automatically surfaces in Shortcuts app, Spotlight, and Siri suggestions. |
| Home screen quick action handling | Custom app lifecycle observation, @Environment scenePhase hacking | `UIApplicationDelegateAdaptor` + `SceneDelegate` | SceneDelegate callbacks are the designated interception point for `UIApplicationShortcutItem`. scenePhase can't identify which shortcut was triggered. |
| Camera roll asset fetch | Raw `PHAsset.fetchAssets` with complex predicates | `PHFetchOptions` with `sortDescriptors` + `fetchLimit` | Standard PhotoKit pattern with `creationDate` sort and `fetchLimit: 1` — simplest correct approach for "most recent photo". |
| Clipboard image detection | Manual UTI inspection of pasteboard items | `UIPasteboard.general.hasImages` + `.image` | Lightweight property check (avoids privacy banner for data inspection), then standard `UIImage` → PNG `Data` conversion. |

**Key insight:** This phase is about iOS system integration — every feature group maps to a specific Apple framework designed for exactly that purpose. The implementation risk is not in "how to do X" (the APIs are well-documented and stable) but in correctly wiring each integration point into the existing WatermarkCore pipeline. The mantra for this phase: **integrate, don't recreate**.

## Runtime State Inventory

> This is NOT a rename/refactor/migration phase — it's a greenfield feature expansion. No runtime state migration needed.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | None — existing App Group UserDefaults and config serialization unchanged | None |
| Live service config | None | None |
| OS-registered state | None | New static registrations added (CFBundleDocumentTypes, UIApplicationShortcutItems in Info.plist) — no migration |
| Secrets/env vars | None | None |
| Build artifacts | None | New source files added; no existing artifacts to update |

## Common Pitfalls

### Pitfall 1: Live Photo Detection via itemIdentifier String Parsing

**What goes wrong:** PhotosPicker item identifiers can change format between iOS versions. Relying on string parsing of `/public.jpeg` and `/public.movie` suffixes could break if Apple changes the identifier format.

**Why it happens:** The `PhotosPickerItem.itemIdentifier` is not documented as a stable API surface — it's an implementation detail exposed through the public interface.

**How to avoid:** 
1. Use multiple detection strategies: check `UTType.livePhotoBundle` via `supportedContentTypes`, AND fall back to itemIdentifier suffix matching.
2. If detection fails, fall back to treating items as separate photo + video — the user can still watermark them individually.
3. Test on actual device with Live Photos captured by iPhone Camera (most reliable source of correct identifiers).

**Warning signs:** Live Photo pairing fails silently → items appear as separate photo + video in the thumbnail strip.

### Pitfall 2: PHLivePhotoEditingContext Initialization Failure

**What goes wrong:** `PHLivePhotoEditingContext(livePhotoEditingInput:)` returns nil for Live Photos that are not in the expected format — e.g., Live Photos synced from iCloud with missing local assets, or Live Photos captured by third-party camera apps with non-standard encoding.

**Why it happens:** The initializer requires both the still image and video components to be locally available and in a format the Photos framework can process.

**How to avoid:**
1. Always nil-check the context initializer. 
2. On failure, fall back to watermarking only the still image (the user loses the motion component but gets a watermarked photo).
3. Log the failure with `os_log` for diagnostics.
4. Request `PHImageRequestOptions.isNetworkAccessAllowed = true` when loading assets to handle iCloud-stored Live Photos.

**Warning signs:** Context init returns nil; `PipelineError.livePhotoUnsupported` thrown; user sees "Live Photo not supported" alert.

### Pitfall 3: Security-Scoped URL Access for "Open In" Files

**What goes wrong:** Files received via `.onOpenURL` from other apps are security-scoped. Failing to call `startAccessingSecurityScopedResource()` before reading, or calling `stopAccessingSecurityScopedResource()` too early (before the file is fully copied to the sandbox), causes data access failures with cryptic errors.

**Why it happens:** iOS sandboxing prevents direct access to files from other apps. Security-scoped bookmarks grant temporary access that must be explicitly started and stopped.

**How to avoid:**
1. Always wrap file access in `url.startAccessingSecurityScopedResource()` / `defer { url.stopAccessingSecurityScopedResource() }`.
2. **Copy the file to the app's temp directory before stopping access** — the copy is in the app sandbox and doesn't need security-scoped access for subsequent reads.
3. Validate the copy succeeded before proceeding to the watermarking workflow.

**Warning signs:** `Data(contentsOf: url)` throws permission error; file appears in sandbox but is empty or corrupted.

### Pitfall 4: App Intents Not Appearing in Shortcuts App

**What goes wrong:** After defining `AppShortcutsProvider`, the intents don't appear in the Shortcuts app or are not available to Siri.

**Why it happens:** The system indexes intents at app install/first launch. During development, cached indexes from previous builds can prevent new intents from surfacing.

**How to avoid:**
1. Delete the app from the device/simulator, do a clean build (Shift+Cmd+K), and reinstall.
2. Verify `AppShortcutsProvider` is included in the app target (not only in WatermarkCore).
3. Check that `openAppWhenRun: true` is set — some intent types default to background-only.
4. Ensure `IntentFile` parameter has `supportedTypeIdentifiers` matching the UTI the Shortcuts app can provide.
5. Test on physical device — Simulator Siri behavior differs from device.

**Warning signs:** Intents defined but not visible in Shortcuts app; Siri says "I can't do that in Watermark"; intent appears in Xcode's intent inspector but not at runtime.

### Pitfall 5: CGColor Codable in SignatureInput

**What goes wrong:** `SignatureInput` stores `inkColor: CGColor`. `CGColor` is not natively Codable — the existing codebase uses an RGBA `[CGFloat]` array encoding pattern in `TextWatermarkInput.color`. The same pattern must be used in `SignatureInput`.

**Why it happens:** `CGColor` is a Core Foundation type without Codable conformance. Custom encoding/decoding is required.

**How to avoid:** Copy the exact same CGColor Codable pattern from `TextWatermarkInput`:
- Encode: extract `color.components` → RGBA `[CGFloat]` array
- Decode: decode `[CGFloat]` array → `CGColor(colorSpace: sRGB, components:)`
- Use `decodeIfPresent` with default black for backward compatibility

**Warning signs:** Encoding failure at config sync time; crash on CGColor decode with old JSON payloads.

### Pitfall 6: PencilKit Drawing Size Mismatch

**What goes wrong:** `PKDrawing.image(from:scale:)` produces an image at a fixed pixel size determined by the canvas bounds. If the canvas is small (e.g., 300×200 on a compact device), the signature renders pixelated when composited onto a 48MP ProRAW image.

**Why it happens:** The canvas view size (screen points) doesn't match the target render resolution (source image dimensions).

**How to avoid:**
1. Set the `PKCanvasView` frame to a generous size (e.g., full screen width × 300pt height) for capture.
2. When rendering to `CIImage` for compositing, use a larger `scale` parameter in `PKDrawing.image(from:scale:)` — e.g., `scale: 3.0` for Retina-quality output.
3. The resulting `UIImage` → `CIImage` will be at the desired resolution regardless of the captured canvas pixel dimensions.
4. Consider saving the canvas size metadata alongside stroke data if re-editing is important.

**Warning signs:** Signature looks crisp in preview but pixelated in full-resolution output; jagged edges on signature strokes at 100% zoom.

## Code Examples

### Live Photo Processing (LIVE-01, LIVE-02)

```swift
// Source: Apple Developer — PHLivePhotoEditingContext
// [CITED: developer.apple.com/documentation/photokit/phlivephotoeditingcontext]
// Reuses existing buildFilterGraph from WatermarkEngine

func processLivePhoto(
    input: PHContentEditingInput,
    output: PHContentEditingOutput,
    config: WatermarkConfiguration
) async throws {
    guard let editingContext = PHLivePhotoEditingContext(livePhotoEditingInput: input) else {
        throw PipelineError.livePhotoUnsupported
    }
    
    // Extract metadata from the still frame for EXIF token support
    var frameMetadata: [String: Any] = [:]
    if let imageURL = input.fullSizeImageURL,
       let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
       let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] {
        frameMetadata = props
    }
    
    editingContext.frameProcessor = { frame, _ in
        let baseImage = frame.image
        do {
            let composited = try WatermarkEngine.shared.buildFilterGraph(
                base: baseImage,
                config: config,
                metadata: frameMetadata
            )
            return composited
        } catch {
            return baseImage // Graceful fallback
        }
    }
    
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        editingContext.saveLivePhoto(to: output, options: nil) { success, error in
            if success {
                continuation.resume()
            } else {
                continuation.resume(throwing: error ?? PipelineError.renderFailed)
            }
        }
    }
}
```

### SignatureInput Model (SIGN-01)

```swift
// Source: Derived from existing TextWatermarkInput CGColor Codable pattern
public struct SignatureInput: Sendable, Codable {
    /// Raw PKDrawing stroke data (vector format)
    public let strokeData: Data
    /// Ink color for re-rendering
    public let inkColor: CGColor
    /// Stroke width in points (default: 3.0)
    public let strokeWidth: CGFloat
    
    public init(strokeData: Data, inkColor: CGColor = CGColor(gray: 0, alpha: 1), strokeWidth: CGFloat = 3.0) {
        self.strokeData = strokeData
        self.inkColor = inkColor
        self.strokeWidth = strokeWidth
    }
    
    enum CodingKeys: String, CodingKey {
        case strokeData, colorRGBA, strokeWidth
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        strokeData = try container.decode(Data.self, forKey: .strokeData)
        strokeWidth = try container.decodeIfPresent(CGFloat.self, forKey: .strokeWidth) ?? 3.0
        let rgba = try container.decode([CGFloat].self, forKey: .colorRGBA)
        guard rgba.count == 4,
              let cgColor = CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    components: rgba) else {
            throw DecodingError.dataCorruptedError(forKey: .colorRGBA, in: container,
                debugDescription: "Invalid RGBA components")
        }
        inkColor = cgColor
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(strokeData, forKey: .strokeData)
        try container.encode(strokeWidth, forKey: .strokeWidth)
        let components = inkColor.components ?? [0, 0, 0, 1]
        let rgba: [CGFloat] = components.count >= 4
            ? [components[0], components[1], components[2], components[3]]
            : [0, 0, 0, 1]
        try container.encode(rgba, forKey: .colorRGBA)
    }
}
```

### Signature Rendering in buildFilterGraph

```swift
// Source: To be integrated into WatermarkEngine.buildFilterGraph()
// Inside the for-loop over config.watermarks:

case .signature(let signatureInput, _, _, _, _):
    // Reconstruct PKDrawing from stored stroke data
    guard let drawing = try? PKDrawing(data: signatureInput.strokeData) else {
        continue // Skip if data corruption
    }
    // Render at 3x scale for Retina-quality output on high-res source images
    let signatureImage = drawing.image(from: drawing.bounds, scale: 3.0)
    // Convert to CIImage with correct color
    guard let cgImage = signatureImage.cgImage else { continue }
    let ciSignature = CIImage(cgImage: cgImage)
    // Apply ink color via CIFilter (respects signatureInput.inkColor)
    let colorFilter = CIFilter.colorMatrix()
    colorFilter.inputImage = ciSignature
    // ... apply ink color tint
    watermarkImage = colorFilter.outputImage ?? ciSignature
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| SiriKit Intents (INIntent) | App Intents framework (@AssistantIntent, AppIntent) | iOS 18 (WWDC 2024) | SiriKit deprecated; any Siri integration MUST use App Intents. @AssistantIntent macro enables Apple Intelligence awareness without custom vocabulary. |
| Manual AVAsset Live Photo editing | PHLivePhotoEditingContext | iOS 10 (stable since) | Frame-level access via frameProcessor block. Eliminates manual paired asset handling. |
| Custom drawing/touch handling | PencilKit (PKCanvasView) | iOS 13 (stable since) | Pressure-sensitive strokes, palm rejection, undo/redo — all built in. |
| Custom file handler registration | CFBundleDocumentTypes | iOS 2 (stable since) | Unchanged since iOS 2. Still the standard mechanism for "Open In" registration. |
| UIApplicationDelegate for everything | UIApplicationDelegateAdaptor + SceneDelegate | iOS 13 (Scenes) | SwiftUI apps use @UIApplicationDelegateAdaptor to bridge only necessary UIKit delegate methods. |

**Deprecated/outdated:**
- **SiriKit (`INIntent`, `INExtension`):** Fully deprecated for new development. AppIntents is the only path forward. [CITED: WWDC 2024 — "What's new in App Intents"]
- **`UIImagePickerController`:** Already avoided per STACK.md. Not relevant to this phase but worth noting for any clipboard-to-image flow — prefer Core Graphics pipeline for processing.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `@AssistantIntent` macro is available on iOS 18.0 deployment target with Xcode 26.2 | App Intents | If the macro syntax or availability changed between iOS 18 and Xcode 26's SDK, the implementation pattern needs adjustment. Plausible but unlikely — the macro was announced at WWDC 2024 and is a compile-time feature. |
| A2 | Live Photo itemIdentifier format (`baseID/public.jpeg`, `baseID/public.movie`) is stable across iOS 18+ | Live Photos | If Apple changes the identifier format in a future iOS version, Live Photo pairing detection will break. Mitigated by fallback to individual photo+video treatment. Test on device before release. |
| A3 | `PHLivePhotoEditingContext.saveLivePhoto(to:options:)` completion handler bridge via `withCheckedThrowingContinuation` is safe (single-call guarantee) | Live Photos | If Apple's completion handler can be called multiple times (unlikely per docs), the continuation would crash. Docs indicate single-call; verified by community usage. |
| A4 | `PKDrawing.dataRepresentation()` produces a Codable `Data` blob that round-trips correctly | Signature | If Apple changes the PKDrawing serialization format in a future iOS version, stored signature data from older versions may not decode. Test with saved configs across iOS version upgrades. |
| A5 | App Intents defined in-app (not separate extension) work correctly for `openAppWhenRun: true` intents | App Intents | If Apple requires a separate Intents extension for certain intent types in a future iOS version, the architecture would need a refactor. Currently documented as supported in iOS 18+. |
| A6 | `NotificationCenter` is the appropriate mechanism for SceneDelegate → ViewModel communication in a `@Observable` SwiftUI app | Quick Actions | Alternative approaches (Combine publisher, callback closure on AppDelegate, @Environment injection) might be more idiomatic. NotificationCenter is chosen for simplicity and zero additional state. |

## Open Questions

1. **Live Photos in Share Extension and Photo Edit Extension**
   - What we know: CONTEXT.md leaves this at the agent's discretion. Main app is the primary target.
   - What's unclear: Whether `PHLivePhotoEditingContext` works within the Photos edit extension (PHContentEditingController) context — the extension receives `PHContentEditingInput` which may or may not contain Live Photo data.
   - Recommendation: Implement Live Photo processing in the main app only for this phase. Extensions can receive Live Photo support in a follow-up phase after testing on device.

2. **PKDrawing Rendering Scale for High-Resolution ProRAW**
   - What we know: `PKDrawing.image(from:scale:)` takes a `scale` parameter. A 3× scale on a 300pt canvas produces ~900px output — fine for most use cases but potentially soft on 48MP ProRAW.
   - What's unclear: Optimal scale factor for 48MP sources. The signature is inherently a vector/raster hybrid — scaling up the rasterization may show interpolation artifacts.
   - Recommendation: Default to `scale: 3.0` (3× display scale, produces clean output up to ~12MP equivalent). If quality is insufficient in testing, increase to `scale: 6.0` or use `PKDrawing.image(from:scale:)` with the source image's pixel dimensions divided by the drawing's point size.

3. **App Intent config JSON round-trip with SignatureInput Data**
   - What we know: `SignatureInput.strokeData` is a `Data` blob (typically <100KB). `WatermarkConfiguration` encodes to JSON for App Group sync and intent parameter passing.
   - What's unclear: Whether the JSON-encoded config with embedded `strokeData` (base64 in JSON) exceeds any undocumented App Intent parameter size limits.
   - Recommendation: Keep intent config parameter optional and lightweight. If the full config with signature data exceeds a practical limit, pass only the media and use the App Group's last-saved config on the app side. Test with a full config (text + image + signature layers) serialized to JSON.

4. **PhotoKit Authorization UX for "Watermark Last Photo"**
   - What we know: D-13 specifies requesting permission on quick action trigger. If denied, open app normally. `PHPhotoLibrary.authorizationStatus(for: .readWrite)` returns `.notDetermined`, `.authorized`, `.limited`, `.denied`, `.restricted`.
   - What's unclear: Whether the system allows presenting the permission dialog from within the quick action handling flow (app may not be fully foregrounded when SceneDelegate receives the shortcut item).
   - Recommendation: If `.notDetermined`, defer the permission request to when the app is fully foregrounded (use `Task { @MainActor in ... }` with a small delay). Show a brief loading indicator during the permission flow.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Xcode | All Swift compilation | ✓ | 26.2 (Build 17C52) | — |
| Swift | All source code | ✓ | 6.2.3 | — |
| iOS SDK | All framework APIs | ✓ | Included in Xcode 26.2 | — |
| iOS Deployment Target | Minimum API availability | ✓ | 18.0 (verified in project.pbxproj) | — |
| Photos Framework (PHLivePhotoEditingContext) | Live Photos | ✓ | iOS 10+ (stable) | Fall back to still-only watermarking on context init failure |
| PencilKit | Signature capture | ✓ | iOS 13+ (stable) | — |
| AppIntents Framework | Siri/Shortcuts | ✓ | iOS 18+ (iOS 18 min target) | — |
| PhotoKit (PHAsset) | "Watermark Last Photo" | ✓ | iOS 8+ (stable) | — |
| UIKit (UIPasteboard) | "Watermark from Clipboard" | ✓ | iOS 2+ (stable) | — |
| UniformTypeIdentifiers | UTI detection | ✓ | iOS 14+ (stable) | — |

**Missing dependencies with no fallback:** None — all required frameworks are Apple system frameworks included in the iOS 18 SDK and are available on the target platform.

**Missing dependencies with fallback:** None.

## Security Domain

> `security_enforcement` is not explicitly set to `false` in `.planning/config.json`. Defaulting to enabled.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | No | Not applicable — no user accounts |
| V3 Session Management | No | Not applicable — no sessions |
| V4 Access Control | No (partial — file access) | Security-scoped resource access for "Open In" files (startAccessingSecurityScopedResource/stopAccessingSecurityScopedResource) |
| V5 Input Validation | Yes | UTI-based format validation before processing imported files; unsupported format rejection with user alert (D-12) |
| V6 Cryptography | No | Not applicable — no cryptographic operations |
| V7 Error Handling | Yes | Graceful fallback for Live Photo context init failure; clear user-facing error messages without stack traces |
| V8 Data Protection | No (partial — sandbox) | Files imported from "Open In" copied to app sandbox before processing — no persistent storage outside sandbox |

### Known Threat Patterns for iOS 18 SwiftUI

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Malicious file via "Open In" (crafted image/video exploiting parser bugs) | Tampering / Elevation of Privilege | UTI check before processing; copy to sandbox temp; rely on Apple's hardened system image/video parsers (CGImageSource, AVAsset) |
| Clipboard image from untrusted source | Tampering | `UIPasteboard.general.hasImages` is lightweight check; `UIImage(data:)` validation catches corrupted data; PNG conversion normalizes input |
| Large clipboard image exhausting memory | Denial of Service | Check image size before loading; apply max dimension cap consistent with existing engine limits |
| IntentFile from Shortcuts with unexpected format | Tampering | Validate `IntentFile.data` is non-nil; check UTI against supported types; reject with error result (not crash) |
| Signature stroke data tampering in config JSON | Tampering | Validate `PKDrawing(data:)` initializer doesn't throw; fall back to ignoring corrupted signature layers |

## Sources

### Primary (HIGH confidence)
- Apple Developer Documentation — PHLivePhotoEditingContext: frameProcessor, saveLivePhoto(to:options:) [CITED: developer.apple.com/documentation/photokit/phlivephotoeditingcontext]
- Apple Developer Documentation — PencilKit: PKCanvasView, PKDrawing, PKToolPicker, PKInkingTool [CITED: developer.apple.com/documentation/pencilkit]
- Apple Developer Documentation — AppIntents: AppIntent, @AssistantIntent, AppShortcutsProvider, IntentFile [CITED: developer.apple.com/documentation/appintents]
- Apple Developer Documentation — PhotoKit: PHAsset.fetchAssets, PHImageManager [CITED: developer.apple.com/documentation/photokit]
- Apple Developer Documentation — CFBundleDocumentTypes, UIApplicationShortcutItems [CITED: developer.apple.com/documentation/bundleresources/information_property_list]
- Apple Developer Documentation — UIPasteboard (hasImages, image) [CITED: developer.apple.com/documentation/uikit/uipasteboard]
- WWDC 2024 — "What's new in App Intents": @AssistantIntent macro, task-based intents, SiriKit deprecation [CITED: developer.apple.com/videos/]
- Project codebase: WatermarkCore package, WatermarkViewModel, WatermarkConfiguration, LogoPickerView pattern [VERIFIED: local codebase]

### Secondary (MEDIUM confidence)
- PhotosPicker Live Photo pairing: itemIdentifier format (`baseID/public.jpeg`, `baseID/public.movie`) — observed behavior confirmed by community [CITED: stackoverflow.com, Apple Developer Forums]
- .onOpenURL + CFBundleDocumentTypes pattern for SwiftUI apps [CITED: multiple community sources, consistent pattern]
- UIApplicationDelegateAdaptor + SceneDelegate for quick actions in SwiftUI [CITED: multiple community sources, consistent with Apple docs]
- PKDrawing.image(from:scale:) as the recommended rasterization method (not ImageRenderer) [CITED: community best practices, confirmed by testing reports]

### Tertiary (LOW confidence)
- PhotosPicker item identifier suffix stability across iOS versions [ASSUMED] — needs device testing
- PHLivePhotoEditingContext completion handler single-call guarantee [ASSUMED] — consistent with Apple's standard callback pattern but not explicitly documented

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — All frameworks are Apple first-party system frameworks included in iOS 18 SDK. Zero third-party dependencies. Framework choices are mandated by the problem domain (no alternatives exist for Live Photo editing, PencilKit drawing, or App Intents Siri integration).
- Architecture: HIGH — Architecture patterns follow the existing MVVM + @Observable + WatermarkCore engine architecture established in Phases 1-6. Each feature group integrates into established extension points (buildFilterGraph for signature rendering, handleSelection for Live Photo pairing, WatermarkConfigurable protocol for UI).
- Pitfalls: HIGH — Pitfalls identified from Apple documentation limitations, community experience reports, and existing codebase patterns (CGColor Codable, security-scoped resources, intent indexing).

**Research date:** 2026-06-18
**Valid until:** 2026-07-18 (30 days — all APIs are stable Apple system frameworks; no fast-moving third-party dependencies)
