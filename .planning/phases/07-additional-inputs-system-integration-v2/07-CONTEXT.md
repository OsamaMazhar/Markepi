# Phase 7: Additional Inputs & System Integration (v2) - Context

**Gathered:** 2026-06-18
**Status:** Ready for planning

## Phase Boundary

This phase expands how users get media INTO Watermark and how they TRIGGER the app from iOS system surfaces. Four feature groups: (1) Live Photos preservation with watermarking on both still and motion components, (2) PencilKit-based signature capture as a new watermark layer type, (3) Files app import and "Open In" from other apps, and (4) home screen quick actions and Siri/Shortcuts App Intents.

**In scope:** Live Photos decomposition + re-assembly via PHLivePhotoEditingContext, signature drawing via PencilKit integrated as a new `.signature` WatermarkLayer case, CFBundleDocumentTypes registration + in-app file browser + `.onOpenURL` handler for Files/Open In, two home screen quick actions, `@AssistantIntent` + `AppIntent` for Siri AI and Shortcuts

**Out of scope:** Batch processing (v2), watermark templates (v2), rotating watermarks (v2), custom frame colors (v2), additional metadata frame types (v2), Android, cloud sync

## Implementation Decisions

### Live Photos
- **D-01:** Use `PHLivePhotoEditingContext` — Apple's high-level API for reading and writing Live Photos. Provides access to both the still image and video frame sequence, handles re-assembly of the paired asset.
- **D-02:** Watermark applied to both the still frame AND all motion frames. The watermark persists through the entire Live Photo animation. Consistent with LIVE-01 and LIVE-02.
- **D-03:** Detect Live Photos as paired assets in PhotosPicker. When a user selects a Live Photo (which PhotosPicker exposes as both an image item and a movie item), detect the pairing and present them as a single "Live Photo" item in the thumbnail strip. The engine processes both components together.
- **D-04:** Output preserves Live Photo format — both watermarked still frame and watermarked video component re-assembled into a proper Live Photo asset. Follows the Phase 1 D-09 "preserve source format" principle.

### Signature Capture
- **D-05:** PencilKit (`PKCanvasView`) for signature drawing — full Apple Pencil pressure sensitivity, stroke smoothing, and undo support. No third-party dependencies needed.
- **D-06:** New `.signature` case on `WatermarkLayer` enum with a `SignatureInput` model (stores PencilKit stroke data, ink color, stroke width). Preserves vector data for re-editing. Engine renders signature to `CIImage` at compositing time via the standard `buildFilterGraph` pipeline.
- **D-07:** Signature capture UI as a full-screen modal sheet triggered from `LayerListView` ("Add Signature" button). Follows the existing `LogoPickerView` pattern of modal presentation from layer controls.
- **D-08:** Configurable signature properties after capture: ink color (re-renders stroke data in new color), stroke width, plus the existing per-layer position/scale/opacity controls inherited from the `WatermarkLayer` model.

### Files Import & Open In
- **D-09:** Both push and pull: register `CFBundleDocumentTypes` for image/video UTIs in Info.plist (enables "Open in Watermark" system-wide), AND add a "Browse Files" button in the main app for in-app file browsing via `.fileImporter`. Covers both IMPS-01 (pull) and IMPS-02 (push).
- **D-10:** Use SwiftUI `.onOpenURL` modifier with `CFBundleDocumentTypes` for "Open In" handling. No custom URL scheme needed — document type handling is the native iOS mechanism. Copy the incoming file to the app sandbox before processing.
- **D-11:** When a file is opened via Files or Open In, replace the current selection and immediately enter the watermarking workflow. The user sees the same configure→preview→share flow.
- **D-12:** Accept all photo formats (HEIC, JPEG, PNG, TIFF, DNG/ProRAW) and video formats (MOV, MP4) that the engine already handles. Reject unsupported types with a user-friendly alert.

### Quick Actions
- **D-13:** "Watermark Last Photo" — use PhotoKit to fetch the most recent `PHAsset` from the camera roll (`fetchAssets` with `sortDescriptors: [creationDate descending]`, `fetchLimit: 1`). Request limited/full photo library permission. Load the asset and pre-populate the watermarking workflow. If no photos exist or permission denied, open the app normally.
- **D-14:** "Watermark from Clipboard" — check `UIPasteboard.general` for an image on quick action trigger. If an image is found, load it and pre-populate the watermarking workflow. If no image on clipboard, open the app normally.
- **D-15:** Both quick actions ("Watermark Last Photo" and "Watermark from Clipboard") open the app with the media pre-loaded in the full watermarking UI. The user configures the watermark and shares interactively — no headless processing.

### App Intents (Siri & Shortcuts)
- **D-16:** Use `@AssistantIntent` + `AppIntent` dual protocol approach. `@AssistantIntent` enables Siri AI natural language interaction ("Watermark my last photo"); `AppIntent` enables Shortcuts app automation. This is the Apple-recommended iOS 27+ pattern — SiriKit is deprecated; App Intents is now mandatory for Siri integration.
- **D-17:** Two task-based intents: "Watermark Photo" and "Watermark Video". Each models a specific task the user wants to achieve (not navigation intents like "Open Watermark"). Aligns with Apple's WWDC 2026 guidance to model task intents for agentic Siri.
- **D-18:** Intents open the app with media pre-loaded in the interactive watermarking UI — same pattern as quick actions. No headless processing. The user sees the preview, configures the watermark, and shares. This preserves the app's core value of visual preview + customization before sharing.
- **D-19:** Intent parameters: media item (`IntentFile` or AppEntity from Siri context/Shortcuts input) + optional `WatermarkConfiguration` (JSON-serialized, defaults to last-used config from App Group if not provided). Minimal parameter surface — just the media and optional config.

### Claude's Discretion

- PHLivePhotoEditingContext implementation details: frame iteration approach, output assembly for watermarked Live Photo, error handling for unsupported Live Photo variants
- `SignatureInput` model structure: PencilKit `PKDrawing` data serialization format (Codable `Data` blob), ink type enum, default stroke width
- PKCanvasView UI customization: tool picker visibility, supported ink types (pen, marker, pencil), undo/redo button placement, canvas background (transparent → renders as transparent PNG)
- `CFBundleDocumentTypes` UTI list: exact UTIs to register for image and video document types in Info.plist
- PhotoKit authorization flow for "Watermark Last Photo": permission request timing, limited vs full access handling, denied fallback UI
- `UIPasteboard` image type detection: check order (public.png, public.jpeg, public.tiff), fallback to `UIPasteboard.general.image`
- App Intents target: whether to create a separate Intents extension target or define intents in-app (iOS 18+ supports both; in-app is simpler for interactive intents)
- `@AssistantIntent` natural language phrases and AppSchema definitions for Siri AI
- `IntentFile` handling for media transfer between Shortcuts/Siri and the app's sandbox
- How "optional config" is passed through intents: `WatermarkConfiguration` JSON-encoded as an optional `String` parameter, decoded on the app side
- Whether the `.signature` layer should be included in `WatermarkConfiguration.strippingImageData()` (PHAdjustmentData size) — signature stroke data is typically small (<100KB), likely no stripping needed
- Live Photos in Share Extension and Photo Edit Extension: whether D-01 through D-04 apply to extension entry points or main app only (user did not specify — main app is the primary target; extensions can follow later)

## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project Foundation
- `.planning/PROJECT.md` — Core value, constraints, key decisions
- `.planning/REQUIREMENTS.md` — v2 requirements: LIVE-01, LIVE-02, SIGN-01, IMPS-01, IMPS-02, SYSI-01, SYSI-02
- `.planning/STATE.md` — Current position, Phase 7 blocker notes (App Intents iOS 18+, Live Photos compositing)

### Phase 1-6 Context (Dependencies)
- `.planning/phases/01-core-engine-photo-pipeline/01-CONTEXT.md` — Phase 1 D-09 (format preservation), D-10 (metadata handling), HDR pipeline, watermark compositing
- `.planning/phases/03-video-processing-share-extension/03-CONTEXT.md` — Phase 3 D-01 through D-04 (video compositing), D-05 through D-08 (share extension pattern), D-09 through D-12 (HDR preservation)
- `.planning/phases/04-photos-edit-extension-polish/04-CONTEXT.md` — Phase 4 D-01 through D-03 (extension UI pattern), D-04 through D-05 (PHAdjustmentData), D-06 through D-08 (photo + video in extension)
- `.planning/phases/05-extended-engine-proraw-exif-tokens-multi-layer/05-CONTEXT.md` — Phase 5 D-12 (compositing order), D-13 through D-15 (WatermarkLayer model, per-layer controls)
- `.planning/phases/06-export-control-ux-polish/06-CONTEXT.md` — Phase 6 D-15 (ControlsView structure), D-06 through D-09 (comparison view patterns)

### Engine API (WatermarkCore)
- `Packages/WatermarkCore/Sources/WatermarkCore/Engine/WatermarkEngine.swift` — `process()`, `processVideo()`, `buildFilterGraph()`, `mediaType(for:)` — core rendering pipeline and media type detection
- `Packages/WatermarkCore/Sources/WatermarkCore/Models/WatermarkConfiguration.swift` — `WatermarkLayer` enum (`.text`, `.image` — must add `.signature`), `OutputFormat`, config serialization
- `Packages/WatermarkCore/Sources/WatermarkCore/Models/TextWatermarkInput.swift` — Text watermark input model (reference for SignatureInput design)
- `Packages/WatermarkCore/Sources/WatermarkCore/Models/ImageWatermarkInput.swift` — Image watermark input model (reference for SignatureInput design)
- `Packages/WatermarkCore/Sources/WatermarkCore/Models/ProcessingResult.swift` — `ProcessingResult`, `RenderingState` enum (may need Live Photo case)
- `Packages/WatermarkCore/Sources/WatermarkCore/Processing/VideoProcessor.swift` — `VideoProcessor.process()`, `AVAssetExportSession` usage (relevant for Live Photo video component)
- `Packages/WatermarkCore/Sources/WatermarkCore/Input/ImageLoader.swift` — CGImageSource loading, HDR options (may need Live Photo image extraction)
- `Packages/WatermarkCore/Sources/WatermarkCore/Input/FormatDetector.swift` — UTI detection, DNG signatures (may need Live Photo UTI detection)
- `Packages/WatermarkCore/Sources/WatermarkCore/UI/WatermarkConfigurable.swift` — Shared ViewModel protocol (may need signature layer accessors)
- `Packages/WatermarkCore/Sources/WatermarkCore/UI/ControlsView.swift` — Shared controls container
- `Packages/WatermarkCore/Sources/WatermarkCore/UI/LayerListView.swift` — Layer list with add/remove (add "Add Signature" action)
- `Packages/WatermarkCore/Sources/WatermarkCore/Storage/AppGroupConfigSync.swift` — App Group UserDefaults sync for config

### Main App
- `App/WatermarkApp.swift` — `@main` app entry point, `WindowGroup` with `.onOpenURL` (to add)
- `App/Views/ContentView.swift` — Main layout, PhotosPicker integration, toolbar
- `App/ViewModels/WatermarkViewModel.swift` — `@Observable` ViewModel, `handleSelection()`, `renderAndPrepareShare()`, import flows
- `App/Views/Share/ShareSheetView.swift` — `UIActivityViewController` bridge
- `App/Info.plist` — Currently empty; must add `CFBundleDocumentTypes`, `UIApplicationShortcutItems`

### Extensions (Pattern References)
- `ShareExtension/ShareViewController.swift` — UIKit + UIHostingController pattern for extensions
- `ShareExtension/ShareExtensionViewModel.swift` — `WatermarkConfigurable` conformance in extension
- `ShareExtension/Info.plist` — `NSExtensionActivationRule` pattern
- `PhotoEditExtension/PhotoEditingViewController.swift` — `PHContentEditingController` pattern
- `PhotoEditExtension/PhotosExtensionViewModel.swift` — `PHContentEditingInput` handling

### Research
- `.planning/research/STACK.md` — Technology stack: PHLivePhotoEditingContext, PencilKit, PhotoKit, App Intents, UserNotifications
- `.planning/research/ARCHITECTURE.md` — MVVM + @Observable, shared WatermarkCore package across targets
- `.planning/research/PITFALLS.md` — Critical pitfalls for metadata and quality preservation

### Phase Tracking
- `.planning/ROADMAP.md` Phase 7 — Goal, requirements, success criteria

### Apple Documentation (for implementation reference)
- `PHLivePhotoEditingContext` — `frameProcessor` block for per-frame watermark application, `saveLivePhoto(to:options:)`
- `PencilKit` — `PKCanvasView`, `PKDrawing`, `PKToolPicker`, `PKInkingTool`
- `CFBundleDocumentTypes` — Info.plist keys for document type registration (`LSItemContentTypes`, `CFBundleTypeRole`)
- `UIApplicationShortcutItem` — `UIApplicationShortcutItemType`, `UIApplicationShortcutItemTitle`, `UIApplicationShortcutItemIconType`
- `AppIntents` framework — `@AssistantIntent` macro, `AppIntent` protocol, `IntentFile`, `AppEntity`
- WWDC 2026: SiriKit deprecated; App Intents mandatory for Siri AI integration; task-based intents recommended over navigation intents

## Existing Code Insights

### Reusable Assets
- **WatermarkLayer enum** — Currently `.text` and `.image`. New `.signature` case extends the same pattern with independent position/scale/opacity/visibility controls.
- **WatermarkEngine.buildFilterGraph()** — Ordered layer compositing already handles multiple layers. A `.signature` layer renders to CIImage and composits in array order via the existing `CIFilter.sourceOverCompositing` chain.
- **LogoPickerView** — Modal presentation pattern from layer controls. Signature capture follows the same "add from modal" UX pattern.
- **WatermarkConfigurable protocol** — Shared across all three targets. May need `addSignatureLayer()` and signature property accessors. Existing `addLogoLayer(pngData:)` is the closest analog.
- **ControlsView<VM: WatermarkConfigurable>** — Generic over ViewModel. Any new layer type controls added here automatically work in main app, share extension, and photo extension.
- **PhotosPicker import flow** — `WatermarkViewModel.handleSelection()` iterates `PhotosPickerItem`s, detects media type. Live Photo pairing logic extends this flow.
- **AppGroupConfigSync** — Already syncs `WatermarkConfiguration` via App Group UserDefaults. Signature layer config serialization follows the same Codable pattern with `decodeIfPresent` defaults for backward compatibility.
- **TempFileManager** — File lifecycle management. Files imported from Files app follow the same create→use→cleanup pattern.

### Established Patterns
- **Config serialization** — `WatermarkConfiguration` is Codable with `decodeIfPresent` defaults for backward compatibility. New `SignatureInput` model and `.signature` layer case must support old JSON payloads that don't include signature layers.
- **PHAdjustmentData stripping** — `strippingImageData()` removes large PNG blobs for Photos extension. Signature stroke data is compact (<100KB) — likely no stripping needed, but the method should be extended to handle `.signature` layers.
- **Modal sheet for creation** — `LogoPickerView` uses a modal sheet triggered from `LayerListView`. Signature capture follows the same pattern.
- **Generic ControlsView<VM>** — All UI components are generic over `WatermarkConfigurable & Observable`. Any UI added for signature layer properties works across all three targets automatically.
- **@Observable + @MainActor ViewModel** — All state management follows this. PhotoKit asset loading and UIPasteboard checks must be `@MainActor`.
- **Replace-on-import flow** — When new media arrives (PhotosPicker selection, share extension item, extension input), it replaces the current selection. Files/Open In follows this same pattern.
- **SwiftUI app lifecycle** — Pure SwiftUI `@main App` with `WindowGroup`. `.onOpenURL` modifier handles incoming files. No UIKit app delegate.

### Integration Points
- **WatermarkLayer enum** — Add `.signature(SignatureInput, position:, scale:, opacity:, isVisible:)` case. Update all switch statements that exhaust over `.text` and `.image`.
- **WatermarkEngine.buildFilterGraph()** — Add `.signature` case to the filter graph builder. Render `PKDrawing` → `UIImage` → `CIImage` → apply scale → apply opacity → position → composite.
- **WatermarkConfiguration Codable** — Add signature layer encoding/decoding with `decodeIfPresent` for backward compatibility.
- **LayerListView** — Add "Add Signature" button alongside existing "Add Logo" button. The signature layer shows an icon + "Signature" label in the layer list.
- **WatermarkViewModel.handleSelection()** — Add Live Photo detection: when a PhotosPickerItem pair matches (same localIdentifier prefix), merge into a LivePhotoItem.
- **App/Info.plist** — Add `CFBundleDocumentTypes` for image and video UTIs. Add `UIApplicationShortcutItems` with two entries.
- **WatermarkApp.swift** — Add `.onOpenURL { url in ... }` modifier to `WindowGroup`. Handle incoming file URLs: copy to sandbox, detect format, set as current source, enter watermarking workflow.
- **WatermarkViewModel** — Add methods: `handleIncomingFile(url:)`, `handleQuickAction(_:)`, `fetchMostRecentPhoto()`, `loadFromClipboard()`.
- **App Group** — `group.com.watermark.app` already configured. No new entitlements needed unless a separate Intents extension target is created.

## Specific Ideas

- Live Photo pairing in PhotosPicker: Apple's `PhotosPickerItem` exposes Live Photos as two items with related `itemIdentifier`s. Pair them by matching the base identifier (strip the `/public.jpeg` or `/public.movie` suffix).
- PHLivePhotoEditingContext's `frameProcessor` block receives each frame as a `CIImage`. Apply the same `buildFilterGraph` compositing logic to each frame — reuse the engine, don't duplicate.
- Signature stroke data from `PKDrawing` serializes to/from `Data` via `PKDrawing.dataRepresentation()` and `PKDrawing(data:)`. Store this in `SignatureInput` for Codable round-tripping.
- `SignatureInput` model: `strokeData: Data`, `inkColor: CGColor` (default black), `strokeWidth: CGFloat` (default 3.0). CGColor encoded as RGBA `[CGFloat]` array — same pattern as `TextWatermarkInput.color`.
- The signature canvas background should be transparent so the signature composites cleanly — use `PKCanvasView.backgroundColor = .clear` and `isOpaque = false`.
- "Watermark Last Photo" quick action: request `PHPhotoLibrary.readWrite` authorization on first use. If denied, show an alert and open the app normally. Use `PHImageManager.requestImageDataAndOrientation` for full-quality asset data.
- "Watermark from Clipboard" quick action: check `UIPasteboard.general.hasImages` first. Load via `UIPasteboard.general.image` (returns `UIImage`). Convert to PNG `Data` for the engine pipeline.
- `CFBundleDocumentTypes` UTI list: `public.image`, `public.jpeg`, `public.heic`, `public.png`, `public.tiff`, `com.adobe.raw-image`, `public.mpeg-4`, `com.apple.quicktime-movie`.
- `@AssistantIntent` phrases should be natural: "Watermark this photo", "Add my signature to this photo", "Watermark my last photo". Use `@Parameter` with `IntentFile` for the media input.
- App Intents should be defined in-app (not a separate extension target) since they open the app for interactive configuration. Separate Intents extension is only needed for headless/background intents.
- The `.signature` layer should render as a transparent-background `CIImage` using `UIGraphicsImageRenderer` or direct `CIImage` from `PKDrawing.image(from:scale:)` — then composited via the existing `CIFilter.sourceOverCompositing` chain.
- PhotoKit authorization for quick actions: use `PHPhotoLibrary.authorizationStatus(for: .readWrite)`. Request if `.notDetermined`, show limited picker fallback if `.denied` or `.restricted`.

## Deferred Ideas

None — discussion stayed within phase scope.

---

*Phase: 7-Additional Inputs & System Integration (v2)*
*Context gathered: 2026-06-18*
