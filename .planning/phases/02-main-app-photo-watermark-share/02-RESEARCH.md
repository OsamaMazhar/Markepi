# Phase 2: Main App (Photo Watermark & Share) - Research

**Researched:** 2026-06-17
**Domain:** iOS SwiftUI photo import, real-time CIImage preview, share sheet integration
**Confidence:** HIGH

## Summary

Phase 2 delivers the main SwiftUI app — photo import via PhotosPicker, real-time watermark preview via Core Image pipeline, watermark configuration UI, multi-photo sequential navigation, and instant share without camera roll save. The app consumes Phase 1's WatermarkCore Swift Package (`WatermarkEngine.shared.process(sourceURL:config:)`) for all rendering.

The technical core is a reactive preview pipeline: user config changes (text, position, scale) debounced at 300-500ms → low-res CIImage render via shared CIContext → CGImage → UIImage → SwiftUI display. The share flow uses UIActivityViewController via UIViewControllerRepresentable because the two-tap flow (render → confirm → share) requires programmatic control over when the share sheet appears, and `completionWithItemsHandler` is needed for temp file cleanup.

All state management uses the `@Observable` macro (iOS 17+), consistent with Phase 1's MVVM pattern. No third-party libraries — Apple system frameworks provide complete coverage.

**Primary recommendation:** Build the UI as a single `@Observable` ViewModel coordinating PhotosPicker selection, WatermarkConfiguration mutation, debounced preview rendering, and share sheet presentation. Use `.task(id:)` for debounce (not Combine — simpler, works with `@Observable`). Use `UIViewControllerRepresentable` for share sheet (not `ShareLink` — cannot support two-tap flow or completion callbacks).

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| MEDI-01 | User can import photos from in-app picker (PhotosPicker) | See §PhotosPicker Integration — `.photosPicker(isPresented:selection:)` modifier, multi-select `[PhotosPickerItem]`, auto-open on launch |
| WMRK-04 | User can see real-time preview of watermarked result before sharing | See §Preview Rendering — low-res CIImage pipeline via shared CIContext, debounce via `.task(id:)`, GPU-accelerated display |
| SHAR-01 | User can share watermarked media via share sheet without output being saved to camera roll | See §Share Sheet Bridging — UIActivityViewController via UIViewControllerRepresentable, temp file lifecycle via completionWithItemsHandler, TempFileManager.cleanup |
</phase_requirements>

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** PhotosPicker opens immediately on first launch — direct-to-picker
- **D-02:** Multi-select — user picks N photos, configures each sequentially with prev/next navigation
- **D-03:** Thumbnail-first loading strategy — show low-res thumbnail immediately, load full-res in background
- **D-04:** Logo/watermark image picker offers "From Photos" + "From Files" choice
- **D-05:** Real-time preview uses low-res engine render, debounced 0.3–0.5s, true WYSIWYG
- **D-06:** Two-tap share flow: tap Share → render full-res → preview updates → confirm → share sheet
- **D-07:** Share button animates to ProgressView spinner during render
- **D-08:** Watermark scale via pinch-to-resize on preview; accessibility stepper fallback ±5%
- **D-09:** Split layout — preview top 60%, controls bottom 40%
- **D-10:** PhotosPicker trigger is large "+" / photo icon button
- **D-11:** Multi-line text input for watermark text
- **D-12:** X button per watermark layer for removal
- **D-13:** Horizontal scrollable thumbnail strip below preview for navigation
- **D-14:** Config persists across photos within session, resets only on explicit clear or app restart
- **D-15:** Multi-photo cancel shows confirmation alert, returns to picker/single-photo mode
- **D-16:** Temp files cleaned up immediately after share sheet dismisses
- **D-17:** Engine failures display as UIAlertController modal with error + OK dismiss
- **D-18:** Accessibility: pinch-to-resize has stepper fallback for VoiceOver/assistive touch

### the agent's Discretion
- Debounce implementation details (Combine throttle vs Task.sleep, exact interval tuning)
- Thumbnail loading approach (PhotosPickerItem.loadTransferable vs CGImageSourceCreateThumbnail)
- Low-res preview resolution (e.g., max 1200px on longest side)
- Multi-photo state management pattern (@Observable model holding [PhotoItem] + currentIndex)
- Pinch gesture implementation (MagnifyGesture + simultaneous gesture coordination with scroll)
- Share sheet presentation (UIViewControllerRepresentable wrapping UIActivityViewController)
- TempFileManager integration (reuse from Phase 1 WatermarkCore)
- SwiftUI view hierarchy and component decomposition

### Deferred Ideas (OUT OF SCOPE)
- None — discussion stayed within phase scope
</user_constraints>

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Photo import & selection | Browser/Client (SwiftUI) | — | PhotosPicker is a UI-level component; no backend involved |
| Watermark configuration state | Browser/Client (SwiftUI) | — | @Observable ViewModel holds mutable config; no persistence layer needed |
| Real-time preview rendering | Browser/Client (SwiftUI) | API/Backend (WatermarkCore) | ViewModel triggers engine render; engine runs on background actor |
| Full-resolution render | API/Backend (WatermarkCore) | — | WatermarkEngine actor handles all CIImage processing |
| Share sheet presentation | Browser/Client (SwiftUI) | — | UIActivityViewController via UIViewControllerRepresentable |
| Temp file lifecycle | API/Backend (WatermarkCore) | Browser/Client | TempFileManager creates; share dismiss triggers cleanup |
| Pinch gesture handling | Browser/Client (SwiftUI) | — | MagnifyGesture applied to rendered UIImage display view |
| Thumbnail generation | Browser/Client (SwiftUI) | — | CGImageSourceCreateThumbnail from PhotosPickerItem Data |

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| SwiftUI | iOS 18 SDK | Full UI layer | Declarative, Apple's definitive UI framework; required for @Observable |
| PhotosUI (PhotosPicker) | iOS 18 SDK | Photo import | Privacy-first, no permission prompt, async Transferable loading |
| Core Image | iOS 18 SDK | GPU-accelerated preview | Shared CIContext from WatermarkCore; CIImage → CGImage → UIImage |
| ImageIO | iOS 18 SDK | Thumbnail downsampling | CGImageSourceCreateThumbnailAtIndex for memory-efficient thumbnails |
| UIKit (bridging only) | iOS 18 SDK | UIActivityViewController | UIViewControllerRepresentable bridge; completionWithItemsHandler for cleanup |
| WatermarkCore | local Swift Pkg | Full-res rendering | Phase 1; WatermarkEngine.process(), TempFileManager, WatermarkConfiguration |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| — _(none)_ | — | — | No third-party libraries needed. Apple system frameworks provide complete coverage. |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| UIActivityViewController (UIViewControllerRepresentable) | ShareLink | ShareLink cannot support two-tap flow (render first, share second) or provide completion callbacks for temp file cleanup |
| Task.sleep debounce (`.task(id:)`) | Combine `.debounce()` | Combine requires ObservableObject/@Published; Task.sleep works with @Observable, simpler, auto-cancellation |
| CGImageSource thumbnail loading | loadTransferable(type: Image.self) | Image.self loads full-res into memory; CGImageSource downsampling prevents memory pressure |
| MagnifyGesture + scaleEffect on view | CIImage transform re-render on gesture | Re-rendering on every gesture frame is too expensive; scaleEffect on the rendered UIImage is GPU-accelerated |

**Installation:**
```bash
# No package manager needed. Apple frameworks included with iOS SDK.
# Phase 2 creates main app target and links existing WatermarkCore package.
```

## Architecture Patterns

### System Architecture Diagram

```
┌──────────────────────────────────────────────────────────────────────────┐
│                         MAIN APP (iOS)                                     │
│                                                                            │
│  ┌──────────────────────────────────────────────────────────────────┐    │
│  │                    ContentView (Root)                               │    │
│  │  ┌──────────────────────────────┐  ┌───────────────────────────┐  │    │
│  │  │     Preview Area (60%)       │  │   Controls Area (40%)     │  │    │
│  │  │                              │  │                           │  │    │
│  │  │  ┌────────────────────────┐  │  │  TextField (multi-line)   │  │    │
│  │  │  │  Watermarked Preview   │  │  │  Position Grid (8 btns)   │  │    │
│  │  │  │  + MagnifyGesture      │  │  │  Scale: Stepper ±5%      │  │    │
│  │  │  │  + Pinch Scale Label   │  │  │  Logo Picker (dual)      │  │    │
│  │  │  └────────────────────────┘  │  │  Layer List (X remove)    │  │    │
│  │  │                              │  │  White Frame Toggle       │  │    │
│  │  │  ┌────────────────────────┐  │  │                           │  │    │
│  │  │  │  Thumbnail Strip       │  │  │  [Share Button → Spinner] │  │    │
│  │  │  │  ◄ prev · [■■□] · next►│  │  │                           │  │    │
│  │  │  └────────────────────────┘  │  └───────────────────────────┘  │    │
│  │  └──────────────────────────────┘                                  │    │
│  │                                                                     │    │
│  │  ┌─ PhotosPicker (.photosPicker modifier) ─┐                       │    │
│  │  │  Auto-presented on first launch          │                       │    │
│  │  │  Multi-select: [PhotosPickerItem]         │                       │    │
│  │  └──────────────────────────────────────────┘                       │    │
│  └──────────────────────────────────────────────────────────────────────┘    │
│         │                                                                     │
│         │  @Observable ViewModel coordinates state                            │
│         ▼                                                                     │
│  ┌──────────────────────────────────────────────────────────────────────┐    │
│  │              WatermarkViewModel (@Observable, @MainActor)             │    │
│  │                                                                       │    │
│  │  selectedItems: [PhotosPickerItem]    → triggers async loading        │    │
│  │  photos: [PhotoItem]                  → loaded photos with thumbnails  │    │
│  │  currentIndex: Int                    → which photo is active          │    │
│  │  config: WatermarkConfiguration       → mutable watermark setup        │    │
│  │  previewImage: UIImage?               → low-res preview for display    │    │
│  │  renderingState: RenderingState       → idle/rendering/done/error      │    │
│  │  fullResURL: URL?                     → output temp file for sharing   │    │
│  │  showShareSheet: Bool                 → triggers UIActivityViewController│
│  │  showPicker: Bool                     → triggers PhotosPicker          │    │
│  │  showCancelAlert: Bool               → confirmation for cancel        │    │
│  │  errorMessage: String?                → triggers UIAlertController     │    │
│  └──────────┬────────────────────────────────────────────────────────────┘    │
│             │                                                                  │
│             │  async calls to engine (background actor)                         │
│             ▼                                                                  │
│  ┌──────────────────────────────────────────────────────────────────────┐    │
│  │              WatermarkEngine (actor, from WatermarkCore)              │    │
│  │                                                                       │    │
│  │  process(sourceURL: URL, config: WatermarkConfiguration)               │    │
│  │    → async throws ProcessingResult                                    │    │
│  │    → writes to temp file (TempFileManager)                             │    │
│  └──────────────────────────────────────────────────────────────────────┘    │
│                                                                               │
│  ┌──────────────────────────────────────────────────────────────────────┐    │
│  │              Share Sheet Bridge                                        │    │
│  │                                                                       │    │
│  │  ActivityViewController (UIViewControllerRepresentable)                │    │
│  │    ← activityItems: [tempFileURL]                                      │    │
│  │    ← completionWithItemsHandler → TempFileManager.cleanup(url:)        │    │
│  └──────────────────────────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────────────────────┘
```

### Recommended Project Structure
```
App/
├── WatermarkApp.swift              # @main App entry, inject ViewModel
├── Views/
│   ├── ContentView.swift           # Root: split layout, picker trigger, share
│   ├── PreviewArea/
│   │   ├── PreviewView.swift       # Rendered watermark preview + pinch gesture
│   │   └── ScaleLabelView.swift    # Overlay showing scale % during pinch
│   ├── Controls/
│   │   ├── ControlsView.swift      # ScrollView container for all controls
│   │   ├── TextWatermarkInputView.swift  # Multi-line TextField
│   │   ├── PositionGridView.swift  # 8-position button grid
│   │   ├── ScaleStepperView.swift  # Stepper ±5% (accessibility fallback)
│   │   ├── LogoPickerView.swift    # Dual-source: PhotosPicker + file picker
│   │   ├── LayerListView.swift     # Per-layer X removal buttons
│   │   └── WhiteFrameToggleView.swift # Toggle + padding slider
│   ├── Navigation/
│   │   └── ThumbnailStripView.swift # Horizontal LazyHStack of thumbnails
│   ├── Share/
│   │   └── ShareSheetView.swift    # UIViewControllerRepresentable for UIActivityVC
│   └── Common/
│       ├── AsyncButton.swift       # Button with ProgressView spinner
│       └── ErrorAlertModifier.swift # UIAlertController bridging
├── ViewModels/
│   └── WatermarkViewModel.swift    # @Observable, @MainActor state coordinator
└── Models/
    └── PhotoItem.swift             # Hashable struct: id, thumbnail, fullResURL
```

### Pattern 1: @Observable ViewModel with .task(id:) Debounce

**What:** The ViewModel holds all mutable state. View uses `.task(id:)` on a combined config identifier to trigger debounced preview rendering. SwiftUI auto-cancels the previous task when config changes again before the sleep completes.

**When to use:** All config-driven preview updates. Replaces Combine `.debounce()` with simpler Swift Concurrency pattern that works with `@Observable` (no `@Published`/`ObservableObject` bridge needed).

**Example:**
```swift
// Source: Apple Developer Documentation .task(id:) + WebSearch verification
@Observable @MainActor
final class WatermarkViewModel {
    var config = WatermarkConfiguration()
    var previewImage: UIImage?
    // ... other state
    
    // Called from View via .task(id: config.changeIdentifier)
    func generatePreview(for sourceURL: URL) async {
        // Debounce is handled by .task(id:) auto-cancellation
        // The Task.sleep here is the debounce window
        try? await Task.sleep(for: .milliseconds(350))
        
        // Render low-res preview on background
        let previewConfig = config.withDownsampledWatermarks(maxDimension: 1200)
        let result = try? await engine.process(sourceURL: sourceURL, config: previewConfig)
        
        if let data = result?.data ?? (try? Data(contentsOf: result?.url ?? URL(fileURLWithPath: ""))),
           let uiImage = UIImage(data: data) {
            previewImage = uiImage
        }
    }
}

// In View:
// .task(id: viewModel.config.previewIdentifier) {
//     await viewModel.generatePreview(for: currentPhotoURL)
// }
```

### Pattern 2: PhotosPicker Auto-Open + Multi-Select

**What:** Use `.photosPicker(isPresented:selection:maxSelectionCount:matching:)` modifier. Set `isPresented = true` in `.onAppear` for auto-open. Bind `selection` to `[PhotosPickerItem]` for multi-select.

**When to use:** On first launch and whenever user taps the "+" button to add more photos.

**Example:**
```swift
// Source: Apple Developer Documentation PhotosPicker + WebSearch verification
struct ContentView: View {
    @State var viewModel: WatermarkViewModel
    
    var body: some View {
        VStack {
            // ... main content
        }
        .photosPicker(
            isPresented: Binding(
                get: { viewModel.showPicker },
                set: { viewModel.showPicker = $0 }
            ),
            selection: Binding(
                get: { viewModel.selectedItems },
                set: { viewModel.handleSelection($0) }
            ),
            maxSelectionCount: 20,  // reasonable limit
            matching: .images
        )
        .onAppear {
            if viewModel.photos.isEmpty {
                viewModel.showPicker = true  // auto-open on first launch
            }
        }
    }
}
```

### Pattern 3: CIImage → SwiftUI Image Preview Pipeline

**What:** Render CIImage to CGImage via shared CIContext on background task, wrap in UIImage, display in SwiftUI `Image(uiImage:)`. Apply `.drawingGroup()` for Metal-backed rendering.

**When to use:** Every preview update. Never render CIImage on the main actor.

**Example:**
```swift
// Source: Apple CIContext docs + SwiftUI Image docs (verified via WebSearch)
func renderPreview(_ ciImage: CIImage, context: CIContext) async -> UIImage? {
    return await Task.detached(priority: .userInitiated) {
        guard let cgImage = context.createCGImage(
            ciImage,
            from: ciImage.extent,
            format: .RGBAh,
            colorSpace: ciImage.colorSpace ?? CGColorSpace(name: CGColorSpace.displayP3)
        ) else { return nil }
        return UIImage(cgImage: cgImage)
    }.value
}

// In View:
// Image(uiImage: previewUIImage)
//     .resizable()
//     .aspectRatio(contentMode: .fit)
//     .drawingGroup()  // Metal-backed, improves animation smoothness
```

### Pattern 4: MagnifyGesture for Watermark Scale

**What:** Use `@GestureState` for live ("in-flight") scale during pinch, `@State` for committed scale. Apply `scaleEffect` to the rendered UIImage view (GPU-accelerated), not to the CIImage pipeline. Update engine's scale config only in `.onEnded`.

**When to use:** Pinch-to-resize on the preview. Keeps UI fluid during gesture; only re-renders after gesture ends.

**Example:**
```swift
// Source: Apple SwiftUI Gesture docs + WebSearch community patterns (verified)
struct PreviewView: View {
    @GestureState private var pinchScale: CGFloat = 1.0
    @State private var committedScale: CGFloat = 1.0
    @Binding var viewModel: WatermarkViewModel
    
    var effectiveScale: CGFloat { committedScale * pinchScale }
    
    var body: some View {
        let magnification = MagnifyGesture()
            .updating($pinchScale) { value, state, _ in
                state = value.magnification
            }
            .onEnded { value in
                committedScale *= value.magnification
                // Clamp and update engine config after gesture ends
                let clamped = min(max(committedScale, 0.01), 0.90)
                committedScale = clamped
                viewModel.config.watermarks[0].scale = clamped
            }
        
        if let preview = viewModel.previewImage {
            Image(uiImage: preview)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .scaleEffect(effectiveScale)
                .gesture(magnification)
                .overlay(alignment: .topTrailing) {
                    if pinchScale != 1.0 {
                        Text("\(Int(effectiveScale * 100))%")
                            .font(.caption)
                            .padding(4)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
        }
    }
}
```

### Pattern 5: UIActivityViewController via UIViewControllerRepresentable

**What:** Wrap `UIActivityViewController` in `UIViewControllerRepresentable`. Present via `.sheet(isPresented:)`. Use `completionWithItemsHandler` for temp file cleanup on dismiss.

**When to use:** The two-tap share flow. Not `ShareLink` — that presents immediately and has no completion callback.

**Example:**
```swift
// Source: Apple UIActivityViewController docs + WebSearch community patterns (verified)
struct ShareSheetView: UIViewControllerRepresentable {
    let activityItems: [Any]
    let onDismiss: () -> Void  // cleanup closure
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
        controller.completionWithItemsHandler = { _, completed, _, error in
            // Always cleanup, whether shared or cancelled
            onDismiss()
        }
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// Usage in View:
// .sheet(isPresented: $viewModel.showShareSheet) {
//     ShareSheetView(
//         activityItems: [viewModel.fullResURL].compactMap { $0 },
//         onDismiss: { viewModel.cleanupTempFile() }
//     )
// }
```

### Pattern 6: Thumbnail Strip with Current Photo Highlight

**What:** Horizontal `ScrollView(.horizontal)` with `LazyHStack` of thumbnail images. Current index has accent border. Tap to switch current photo.

**When to use:** Multi-photo navigation (D-13). Only shown when 2+ photos selected.

**Example:**
```swift
// Source: Apple ScrollView/LazyHStack docs + WebSearch community patterns (verified)
struct ThumbnailStripView: View {
    let photos: [PhotoItem]
    @Binding var currentIndex: Int
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            ScrollViewReader { proxy in
                LazyHStack(spacing: 8) {
                    ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                        if let thumb = photo.thumbnail {
                            Image(uiImage: thumb)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 60, height: 60)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(index == currentIndex ? Color.accentColor : Color.clear, lineWidth: 3)
                                )
                                .onTapGesture { currentIndex = index }
                        }
                    }
                }
                .padding(.horizontal)
                .onChange(of: currentIndex) { _, newIndex in
                    withAnimation {
                        proxy.scrollTo(photos[newIndex].id, anchor: .center)
                    }
                }
            }
        }
        .frame(height: 72)
    }
}
```

### Pattern 7: AsyncButton with ProgressView Spinner

**What:** Custom button component that shows a ProgressView spinner during async work. Disables itself to prevent double-tap.

**When to use:** Share button during full-res render (D-07).

**Example:**
```swift
// Source: WebSearch community consensus pattern (verified across multiple sources)
struct AsyncButton<Label: View>: View {
    var action: () async -> Void
    @ViewBuilder var label: () -> Label
    
    @State private var isPerformingTask = false
    
    var body: some View {
        Button {
            guard !isPerformingTask else { return }
            Task {
                isPerformingTask = true
                await action()
                isPerformingTask = false
            }
        } label: {
            HStack(spacing: 8) {
                if isPerformingTask {
                    ProgressView()
                        .controlSize(.small)
                }
                label()
            }
        }
        .disabled(isPerformingTask)
    }
}
```

### Anti-Patterns to Avoid

- **Anti-pattern: Loading PhotosPickerItem as `Image.self` for thumbnails** — decodes full-resolution bitmap into memory. Use `Data.self` + `CGImageSourceCreateThumbnailAtIndex` with `maxPixelSize`.
- **Anti-pattern: Re-rendering CIImage on every MagnifyGesture frame** — too expensive. Apply `scaleEffect` to the rendered UIImage view; only trigger engine re-render in `.onEnded`.
- **Anti-pattern: Creating new CIContext for preview** — Phase 1 already provides `CIContextProvider.shared`. Reuse it.
- **Anti-pattern: Using ShareLink for two-tap flow** — ShareLink presents immediately on tap. Use UIActivityViewController for programmatic control.
- **Anti-pattern: Calling engine.process() on MainActor** — freezes UI. Always call from `.task {}` or `Task.detached`.
- **Anti-pattern: Storing full-res UIImages in array** — 48MP photos consume ~75MB each. Store URLs, generate thumbnails for display.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Debounce | Custom timer/throttle logic, `DispatchWorkItem` | `.task(id:)` with `Task.sleep` | Automatic cancellation when value changes; native Swift Concurrency; no cleanup code |
| Share sheet | Custom share UI, manual file export to other apps | `UIActivityViewController` via `UIViewControllerRepresentable` | System share sheet handles all destinations (Messages, Instagram, AirDrop, etc.), completion callback for cleanup |
| Thumbnail downsampling | Manual pixel scaling on GPU/CPU | `CGImageSourceCreateThumbnailAtIndex` with `kCGImageSourceThumbnailMaxPixelSize` | Single-call, respects EXIF orientation, memory-efficient, hardware-accelerated |
| Pinch gesture state | Manual `UIPanGestureRecognizer` + math | `MagnifyGesture` + `@GestureState` + `scaleEffect` | Built-in, automatically resets gesture state, GPU-accelerated scale transform on view |
| Temp file cleanup | FileManager polling, timer-based cleanup | `TempFileManager.cleanup(url:)` + `completionWithItemsHandler` | Phase 1 API; deterministic cleanup on share dismiss |
| Watermark rendering on preview | Custom rendering code | `WatermarkEngine.process()` from WatermarkCore | Same pipeline as full-res output; true WYSIWYG |

**Key insight:** The preview pipeline should pass through the SAME WatermarkEngine as the final output (just at lower resolution). This ensures true WYSIWYG — what the user sees is exactly what gets shared. Building a separate preview renderer creates divergence risk.

## Runtime State Inventory

*Omitted — this is a greenfield phase (no rename/refactor/migration).*

## Common Pitfalls

### Pitfall 1: Memory Pressure from Loading Full-Resolution Photos into Array

**What goes wrong:** Selecting 10+ photos and loading them all as full-resolution `UIImage` objects consumes hundreds of MB, triggering jetsam termination on device.

**Why it happens:** `PhotosPickerItem.loadTransferable(type: Image.self)` or `UIImage(data:)` decodes the entire pixel buffer. A 12MP photo is ~48MB uncompressed; 10 photos = 480MB, exceeding iOS memory limits.

**How to avoid:** Load thumbnails via `Data.self` → `CGImageSourceCreateThumbnailAtIndex(maxPixelSize: 200)`. Store source URLs (not images) for the full-res render. Only one full-resolution image is loaded at a time during processing. Never store full-res `UIImage` instances in arrays.

**Warning signs:** App crashes silently on device (works in Simulator), Xcode Organizer shows jetsam events with memory pressure.

### Pitfall 2: CIImage Coordinate System Mismatch in MagnifyGesture

**What goes wrong:** Applying gesture coordinates directly to CIImage transforms produces incorrect scaling because the gesture operates in SwiftUI's view coordinate space (top-left origin), while CIImage uses bottom-left origin.

**Why it happens:** This is well-documented in Pitfall 5 of the project's PITFALLS.md. The solution applied here is different: apply `scaleEffect` to the SwiftUI view hosting the rendered UIImage, not to the CIImage. The view-level transform is GPU-accelerated and coordinate-system-agnostic. The engine scale config is only updated in `.onEnded` with the final numeric scale value (0.01–0.90).

**How to avoid:** Keep gesture → view transform and engine → config update separate. View transform for live feedback (GPU, no re-render). Config update for persistence (triggers debounced re-render).

### Pitfall 3: ShareLink Presents Immediately, Blocking Two-Tap Flow

**What goes wrong:** Using `ShareLink` for the two-tap flow causes the share sheet to appear before the full-res render completes.

**Why it happens:** `ShareLink` is a button that presents the share sheet immediately on tap. It cannot be programmatically controlled. The two-tap flow requires: tap 1 → render → preview update → tap 2 (confirm) → share sheet.

**How to avoid:** Use `UIActivityViewController` via `UIViewControllerRepresentable`, presented via `.sheet(isPresented: $showShareSheet)`. Set `showShareSheet = true` only after render completes.

### Pitfall 4: Debounce Timer Not Cancelled on Rapid Config Changes

**What goes wrong:** Rapid text entry or scale changes queue multiple render operations that all execute, causing UI jank and wasted GPU work.

**Why it happens:** Manual `DispatchQueue.asyncAfter` or `Task { sleep; render }` without cancellation creates orphaned tasks that still execute.

**How to avoid:** Use `.task(id: config.previewIdentifier)` — SwiftUI automatically cancels the previous task when the identifier changes. The `Task.sleep` inside will throw `CancellationError` if cancelled, preventing the render from executing.

### Pitfall 5: UIActivityViewController Dismiss Detection Failure

**What goes wrong:** Temp files accumulate because share sheet dismiss is not detected, or cleanup fires while share sheet is still active.

**Why it happens:** `.sheet(onDismiss:)` fires when the sheet is dismissed from SwiftUI's perspective, which may not align with UIActivityViewController's actual lifecycle.

**How to avoid:** Use `completionWithItemsHandler` on UIActivityViewController — this is guaranteed to fire when the share sheet completes, regardless of whether the user shared, saved, or cancelled. Pair with `TempFileManager.cleanup(url:)` from Phase 1.

## Code Examples

### Full ViewModel Structure
```swift
// Source: Apple @Observable docs + project ARCHITECTURE.md patterns (verified)
import SwiftUI
import PhotosUI
import WatermarkCore
import Observation

@Observable @MainActor
final class WatermarkViewModel {
    // MARK: - Photo Selection
    var selectedItems: [PhotosPickerItem] = []
    var photos: [PhotoItem] = []
    var currentIndex: Int = 0
    var showPicker: Bool = false
    
    // MARK: - Watermark Configuration
    var config = WatermarkConfiguration(watermarks: [
        .text(TextWatermarkInput(text: "", fontSize: 48, color: .white, opacity: 1.0),
              position: .bottomRight,
              scale: 0.15)
    ])
    
    // MARK: - Preview State
    var previewImage: UIImage?
    var isGeneratingPreview: Bool = false
    
    // MARK: - Render & Share State
    var renderingState: RenderingState = .idle
    var fullResResult: ProcessingResult?
    var showShareSheet: Bool = false
    var showCancelAlert: Bool = false
    var errorMessage: String?
    var showError: Bool = false
    
    // MARK: - Engine
    private let engine = WatermarkEngine.shared
    
    // MARK: - Derived
    var currentPhoto: PhotoItem? {
        guard !photos.isEmpty, currentIndex >= 0, currentIndex < photos.count else { return nil }
        return photos[currentIndex]
    }
    
    var hasMultiplePhotos: Bool { photos.count > 1 }
    
    var previewIdentifier: String {
        // Changing any config property creates a new identifier,
        // triggering .task(id:) cancellation of previous preview render
        "\(currentIndex)-\(config.hashValue)"
    }
    
    // MARK: - Photo Loading
    func handleSelection(_ items: [PhotosPickerItem]) {
        Task {
            var loaded: [PhotoItem] = []
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    let thumb = createThumbnail(from: data, maxPixelSize: 200)
                    let sourceURL = await copyToTemp(data: data, item: item)
                    loaded.append(PhotoItem(
                        id: UUID(),
                        thumbnail: thumb,
                        sourceURL: sourceURL
                    ))
                }
            }
            photos = loaded
            currentIndex = 0
        }
    }
    
    // MARK: - Navigation
    func goToNext() {
        guard currentIndex < photos.count - 1 else { return }
        currentIndex += 1
    }
    
    func goToPrev() {
        guard currentIndex > 0 else { return }
        currentIndex -= 1
    }
    
    // MARK: - Preview Rendering (debounced via .task(id:))
    func generatePreview() async {
        guard let sourceURL = currentPhoto?.sourceURL else { return }
        isGeneratingPreview = true
        defer { isGeneratingPreview = false }
        
        // Task.sleep here is the debounce — .task(id:) cancels if config changes
        try? await Task.sleep(for: .milliseconds(350))
        
        let result = try? await engine.process(sourceURL: sourceURL, config: config)
        if let url = result?.url,
           let data = try? Data(contentsOf: url),
           let uiImage = UIImage(data: data) {
            previewImage = uiImage
        }
    }
    
    // MARK: - Full-Res Render & Share
    func renderAndPrepareShare() async {
        guard let sourceURL = currentPhoto?.sourceURL else { return }
        renderingState = .rendering
        
        do {
            let result = try await engine.process(sourceURL: sourceURL, config: config)
            fullResResult = result
            renderingState = .done
            // Update preview to show full-res result
            if let url = result.url,
               let data = try? Data(contentsOf: url),
               let uiImage = UIImage(data: data) {
                previewImage = uiImage
            }
        } catch {
            renderingState = .error(error)
            errorMessage = error.localizedDescription
            showError = true
        }
    }
    
    func presentShareSheet() {
        guard renderingState == .done else { return }
        showShareSheet = true
    }
    
    func cleanupTempFile() {
        if let url = fullResResult?.url {
            try? TempFileManager.cleanup(url: url)
        }
        fullResResult = nil
        renderingState = .idle
    }
    
    // MARK: - Cancel
    func requestCancel() {
        showCancelAlert = true
    }
    
    func confirmCancel() {
        photos = []
        currentIndex = 0
        fullResResult = nil
        renderingState = .idle
        showPicker = true
    }
}

// MARK: - Supporting Types
struct PhotoItem: Identifiable, Hashable {
    let id: UUID
    let thumbnail: UIImage?
    let sourceURL: URL
    
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: PhotoItem, rhs: PhotoItem) -> Bool { lhs.id == rhs.id }
}

enum RenderingState: Equatable {
    case idle
    case rendering
    case done
    case error(Error)
    
    static func == (lhs: RenderingState, rhs: RenderingState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.rendering, .rendering), (.done, .done): return true
        case (.error, .error): return true
        default: return false
        }
    }
}

// Thumbnail helper
func createThumbnail(from data: Data, maxPixelSize: CGFloat) -> UIImage? {
    let options = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,  // respect EXIF orientation
        kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
    ] as CFDictionary
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
        return nil
    }
    return UIImage(cgImage: cgImage)
}
```

### Split Layout Structure
```swift
// Source: Apple SwiftUI Layout docs + CONTEXT.md D-09 (verified)
struct ContentView: View {
    @State var viewModel: WatermarkViewModel
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Preview: top 60%
                PreviewAreaView(viewModel: viewModel)
                    .frame(height: geometry.size.height * 0.60)
                
                Divider()
                
                // Controls: bottom 40%
                ControlsView(viewModel: viewModel)
                    .frame(height: geometry.size.height * 0.40)
            }
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "Unknown error")
        }
        .confirmationDialog(
            "Discard changes to remaining photos?",
            isPresented: $viewModel.showCancelAlert
        ) {
            Button("Discard", role: .destructive) { viewModel.confirmCancel() }
            Button("Keep Editing", role: .cancel) {}
        }
        .sheet(isPresented: $viewModel.showShareSheet) {
            if let url = viewModel.fullResResult?.url {
                ShareSheetView(
                    activityItems: [url],
                    onDismiss: { viewModel.cleanupTempFile() }
                )
            }
        }
    }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `UIImagePickerController` | `PhotosPicker` (PhotosUI) | iOS 16 | No permission prompt, async Transferable, privacy-first |
| `ObservableObject` + `@Published` | `@Observable` macro | iOS 17 | Property-level granularity, fewer redraws, simpler syntax |
| `NavigationView` / `NavigationLink` | `NavigationStack` + `.navigationDestination` | iOS 16 | Programmatic navigation, type-safe destinations |
| Combine `.debounce()` for UI | `.task(id:)` + `Task.sleep` | iOS 17+ | No Combine dependency, auto-cancellation, simpler |
| `ShareLink` for sharing | `UIActivityViewController` via representable | Always (for complex needs) | Completion callbacks, programmatic control |
| `UIImage` for processing | `CGImageSource` → `CIImage` pipeline | Phase 1 standard | Metadata + HDR preservation |

**Deprecated/outdated:**
- `UIImagePickerController`: Replaced by PhotosPicker. Requires full library permission, no async support.
- `ObservableObject`/`@Published`: Replaced by `@Observable`. Phase 1 already uses `@Observable`.
- `ShareLink` for this use case: Cannot support two-tap flow or provide completion callbacks. Use UIActivityViewController.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `.task(id:)` auto-cancellation works reliably with `Task.sleep` debounce in iOS 18 | Preview Rendering | Medium — if cancellation edge cases exist, preview updates may lag or render stale config. Fallback: switch to explicit `Task` reference + `.cancel()` |
| A2 | CIContextProvider.shared from Phase 1 is safe to call from non-isolated Tasks (it's an actor) | Preview Rendering | Low — Phase 1 already designed for this; confirmed by Phase 1 tests |
| A3 | UIActivityViewController `completionWithItemsHandler` fires reliably on iOS 18 for all dismiss paths (share, save, cancel) | Share Sheet Bridging | Low — Apple has maintained this behavior since iOS 8 |
| A4 | `kCGImageSourceCreateThumbnailWithTransform: true` correctly handles all EXIF orientations | Thumbnail Navigation | Low — documented ImageIO behavior, well-tested across Apple ecosystem |
| A5 | `.photosPicker(isPresented:)` modifier presents immediately when set true in `.onAppear` | PhotosPicker | Medium — some edge cases where system delays presentation during initial load. Fallback: add explicit button as backup trigger |
| A6 | 20 photo maxSelectionCount is reasonable for a sequential (non-batch) flow | PhotosPicker | Low — sequential flow means user configures each individually; 20 is generous |
| A7 | `WatermarkConfiguration` will be Hashable (or provide a change identifier) for `.task(id:)` | Preview Rendering | Medium — if config can't produce stable identifier, debounce won't work. Need to add computed `previewIdentifier` property |

## Open Questions

1. **Preview resolution tradeoff**
   - What we know: Low-res preview (1200px max) is fast, but might not show fine watermark text details. Full-res preview is slow.
   - What's unclear: Optimal max dimension for responsive yet detailed preview. 1200px is recommended based on iPhone screen resolution (1179px for Pro Max).
   - Recommendation: Start with 1200px on longest side; test with small text watermarks; increase to 1800px if quality insufficient, decrease to 900px if performance laggy.

2. **PhotosPicker auto-open UX**
   - What we know: Setting `showPicker = true` in `.onAppear` presents the picker. The system may show a brief flash of the empty UI before the picker animates in.
   - What's unclear: Whether this flash is noticeable or jarring. Apple discourages auto-presenting sheets without user intent.
   - Recommendation: Add a brief splash/welcome state that transitions to picker. Or use `.photosPicker` modifier (not sheet) which may be less jarring. Test on device.

3. **Two-tap share flow interaction design**
   - What we know: D-06 specifies: tap Share → render → result in preview → confirm → share sheet. D-07 says Share button becomes ProgressView spinner during render.
   - What's unclear: Does the user see a separate "Confirm" button after render, or does the Share button transition from spinner → active share trigger? D-07 suggests the latter (single button, state transitions).
   - Recommendation: Single Share button with 3 states: idle → spinning (rendering) → enabled (tap to share). After render completes, brief highlight animation to signal readiness. Second tap opens share sheet.

4. **MagnifyGesture + thumbnail scroll gesture conflict**
   - What we know: The preview area has MagnifyGesture for scale; the thumbnail strip has a horizontal ScrollView with tap gesture. These are in different views.
   - What's unclear: If user tries to pinch near the bottom of the preview, could the gesture be captured by the thumbnail scroll? Unlikely due to view hierarchy separation.
   - Recommendation: No special coordination needed if thumbnail strip is in a separate view hierarchy below the preview. Verify on device.

## Environment Availability

> Phase 2 has no external tool/service dependencies beyond the iOS SDK and Xcode toolchain, both confirmed available by Phase 1 execution.

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Xcode | Build & run | ✓ | 18.x (Phase 1 confirmed) | — |
| iOS Simulator / Device | Testing | ✓ | iOS 18 (Phase 1 confirmed) | — |
| WatermarkCore Swift Pkg | Rendering engine | ✓ | Phase 1 complete | — |
| exiftool (CLI) | Metadata validation (optional QA) | ✗ | — | Xcode Previews visual comparison |

**Missing dependencies with no fallback:** None — all core dependencies are available.
**Missing dependencies with fallback:** exiftool (optional QA only — visual comparison sufficient for Phase 2).

## Security Domain

*Security domain deferred — no network calls, all on-device processing, no user authentication, no data storage. Phase 2 UI only passes data to WatermarkCore (Phase 1, already verified). No new threat vectors introduced.*

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | No | — |
| V3 Session Management | No | — |
| V4 Access Control | No | — |
| V5 Input Validation | Yes | WatermarkConfiguration validation (Phase 1); text input sanitization (max length, empty string handling) |
| V6 Cryptography | No | — |

### Known Threat Patterns for SwiftUI/iOS

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Temp file path traversal | Tampering | UUID-based filenames (Phase 1 TempFileManager) |
| Overly long text input crashing engine | Denial of Service | Max text length validation before passing to engine |
| Share sheet sending unintended data | Information Disclosure | Only the temp file URL is shared; no metadata leak beyond what's in the watermarked output |

## Sources

### Primary (HIGH confidence)
- Apple Developer Documentation — `PhotosPicker`: `.photosPicker(isPresented:selection:)` modifier, `PhotosPickerItem`, `Transferable`, `maxSelectionCount`, programmatic presentation. [developer.apple.com/documentation/photokit/photospicker]
- Apple Developer Documentation — `UIActivityViewController`: `completionWithItemsHandler`, activity items, dismissal lifecycle. [developer.apple.com/documentation/uikit/uiactivityviewcontroller]
- Apple Developer Documentation — `MagnifyGesture`: `updating(_:body:)`, `onEnded(_:)`, `@GestureState`. [developer.apple.com/documentation/swiftui/magnifygesture]
- Apple Developer Documentation — `.task(id:)`: auto-cancellation, async lifecycle, Equatable trigger. [developer.apple.com/documentation/swiftui/view/task(id:_:)]
- Apple Developer Documentation — `@Observable` macro: Observation framework, property-level tracking. [developer.apple.com/documentation/observation]
- Apple Developer Documentation — `CIContext`: `createCGImage(_:from:format:colorSpace:)`, reuse strategy. [developer.apple.com/documentation/coreimage/cicontext]
- Apple Developer Documentation — `CGImageSourceCreateThumbnailAtIndex`: downsampling options, `kCGImageSourceThumbnailMaxPixelSize`. [developer.apple.com/documentation/imageio/cgimagesource]
- Phase 1 WatermarkCore codebase — `WatermarkEngine`, `TempFileManager`, `WatermarkConfiguration`, `CIContextProvider.shared`

### Secondary (MEDIUM confidence)
- WebSearch — PhotosPicker multi-select Transferable patterns: community consensus on `.task(id:)` + `loadTransferable(type: Data.self)` approach. Verified against Apple docs.
- WebSearch — CIImage → SwiftUI Image pipeline: community-verified pattern of background Task + CIContext + UIImage conversion. Verified against Apple docs.
- WebSearch — Debounce patterns: `.task(id:)` with `Task.sleep` vs Combine `.debounce()`. Community consensus on `.task(id:)` for @Observable projects. Verified against Apple docs.
- WebSearch — AsyncButton with ProgressView: community pattern for loading state in buttons. Verified against SwiftUI Button docs.

### Tertiary (LOW confidence)
- None — all findings cross-verified with Apple documentation or Phase 1 codebase.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all Apple system frameworks, no third-party dependencies, stack decisions inherited from STACK.md
- Architecture: HIGH — @Observable MVVM pattern established in Phase 1; PhotosPicker patterns well-documented by Apple; share sheet bridging is standard UIKit-SwiftUI interop
- Pitfalls: HIGH — memory management, gesture coordination, share sheet lifecycle all verified against multiple sources and Apple docs
- Validation: SKIPPED — nyquist_validation: false in config.json

**Research date:** 2026-06-17
**Valid until:** 2026-07-17 (stable domain — Apple SDK APIs change only at WWDC)

**No Package Legitimacy Audit required** — Phase 2 installs no external packages (Apple system frameworks only).
