# Phase 17: Inspector Bottom-Sheet Shell - Research

**Researched:** 2026-06-22
**Domain:** SwiftUI custom bottom sheet architecture, Z-ordering, drag-gesture detent control
**Confidence:** HIGH

## Summary

Phase 17 replaces the main app's hardcoded 60/40 VStack split with a full-bleed photo hero, a resizable Liquid Glass bottom sheet housing ControlsView, and a pinned Share action bar floating above the sheet. This research investigates the core architectural choice: native `.sheet` with `.presentationDetents` vs. a custom ZStack-based implementation.

**Primary finding:** SwiftUI's `.sheet` modifier creates a separate UIWindow/presentation layer that blocks any view from the presenting view hierarchy from rendering above it. Since D-06 requires the pinned Share button to be "always visible regardless of detent" and rendered "above the sheet" in Z-order, the `.sheet` approach cannot satisfy this requirement. The pinned button would either be trapped behind the sheet (invisible) or must be placed inside the sheet content (defeating the "always visible at bottom of preview area" requirement when the sheet is at peek detent).

**Primary recommendation:** Implement the bottom sheet as a **custom view within ContentView's ZStack** — not using the `.sheet` modifier. This gives full control over Z-ordering (preview → batch overlays → sheet → pinned button) and detent management via a DragGesture with spring-animated snap points. The `.markepiGlass()` modifier from Phase 15 provides Liquid Glass on iOS 26 and `.ultraThinMaterial` fallback on iOS 18 — identical to what `.sheet`'s `.presentationBackground()` would provide.

This approach follows the professional photo-editing app convention (Apple Photos, Lightroom, Darkroom), all of which implement their inspector panels as custom views rather than modal sheets, precisely because they need custom Z-ordering for floating toolbars and always-visible primary actions.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| LYT-01 | The photo/video preview fills the screen as a full-bleed hero behind the controls | Achieved by removing the 60% height constraint and applying `.ignoresSafeArea()` to PreviewView within a ZStack. PreviewView already uses `.edgesIgnoringSafeArea(.top)` (line 94); extend to all edges. |
| LYT-02 | Controls live in a resizable bottom sheet with detents (peek + expanded) | Implemented via custom ZStack view with `@State detent`, DragGesture on drag indicator, spring-animated snap to `.peek` (~60pt) and `.expanded` (~half screen). Two-detent snap logic. |
| LYT-03 | The primary action (Share) is always reachable via a pinned action bar | Share button extracted from ControlsView into standalone `ShareActionButton` component. Pinned bar rendered at Z-index above the sheet via ZStack ordering; always visible and interactive. |
| LYT-04 | The UI renders correctly in both system light and dark appearance | All colors use system-adaptive semantic colors (`.primary`, `.secondary`, `.accentColor`, `.selection`) per Phase 15 design system. Liquid Glass via `.markepiGlass()` is system-adaptive by default (D-03). |

</phase_requirements>

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

| ID | Decision | Constraint |
|----|----------|------------|
| D-01 | Two detents: peek (pill bar only) and expanded (`.medium` ≈ half screen) | Sheet must support exactly two detents. Peek shows Watermark/Style/Output labels only; no control content. |
| D-02 | Sheet overlays the full-bleed preview — no push/resize | Preview stays edge-to-edge behind the glass sheet. No layout adjustment when sheet moves. |
| D-03 | Background interaction enabled | User can tap/drag the preview image behind the sheet even with sheet visible. |
| D-04 | Sheet is NOT dismissible — always at least peek | Permanent chrome, not a temporary modal. Cannot be dragged off-screen. |
| D-05 | Share button extracted from ControlsView into standalone component | Lives in WatermarkCore/DesignSystem/. Single source of truth for all three placements. |
| D-06 | Pinned action bar is Liquid Glass floating pill centered at bottom of preview area, above sheet | Floats independently from sheet — always visible regardless of detent. |
| D-07 | Pinned bar contains Share button only | No batch controls, no import button. Batch cancel/reset stay in NavigationStack toolbar. |
| D-08 | Extracted component preserves full rendering state machine | `.idle`, `.rendering`, `.renderingVideo`, `.batchProcessing`, `.done`, `.error`. |
| D-09 | Sheet surface is full Liquid Glass | Uses `.markepiGlass()` from Phase 15. iOS 26 native, iOS 18 `.ultraThinMaterial` fallback. |
| D-10 | Standard iOS drag indicator | Small horizontal capsule at top of sheet signaling draggability. |
| D-11 | Standard iOS sheet corners | Rounded top corners, square bottom. |
| D-12 | Preview gets NO visual treatment | No dimming, no blur, no scale as sheet expands. Full-bleed, unmodified at all detents. |
| D-13 | Light + dark appearance | All colors system-adaptive. No hardcoded colors. |
| D-14 | ControlsView placed inside sheet completely unchanged | Shell-agnostic mandate from Phase 16 strictly preserved. Sheet wraps ControlsView as its content. |
| D-15 | Native nested scroll | No custom gesture coordination. Inner ControlsView scroll scrolls first; sheet resize only at scroll boundaries. |
| D-16 | Batch toolbar items stay in NavigationStack toolbar | Cancel, Reset All at top of screen — not in sheet or pinned bar. |
| D-17 | Batch overlays float above sheet on preview area | ThumbnailStripView, BatchProgressOverlay at Z level between preview and sheet/pinned-bar layers. |

### Agent's Discretion

- **Bottom sheet API choice (`.sheet` vs custom):** The planner derives the implementation approach. `.presentationDetents([.height(pillBarHeight), .medium])` is one path; custom ZStack with DragGesture is the alternative. Research recommends custom ZStack (see § Architecture Patterns).
- **`pillBarHeight` constant:** Derived from MarkepiPillBar's intrinsic height (~44-48pt glass-backed pill). Research provides calculated value.
- **Extracted Share button component interface:** Generic over `WatermarkConfigurable & Observable`. Planner derives exact signature.
- **Pinned floating pill positioning:** Positioned via ZStack child ordering. Recommended: `.overlay(alignment: .bottom)` or explicit ZStack layer at highest zIndex.
- **iOS 18 fallback:** Follow established `if #available(iOS 26, *)` pattern from Phase 15. No new iOS 26-specific sheet APIs are needed since we're not using `.sheet`.

### Deferred Ideas (OUT OF SCOPE)

- Drag-to-position watermark (VIS-05): v2.2+
- Glass-morph transitions (VIS-06): v2.2+
- Extension shell redesign: ShareExtension and PhotosExtension keep current 60/40 layout.

</user_constraints>

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Full-bleed preview rendering | Browser / Client (SwiftUI View) | — | Pure SwiftUI layout. PreviewView already exists; only constraint change needed. |
| Bottom sheet container | Browser / Client (SwiftUI View) | — | Custom ZStack view within ContentView. No UIKit required; sheet is a positioned VStack with drag gesture. |
| Detent state management | Browser / Client (@State) | — | `@State private var detent: Detent` in ContentView or extracted sheet view. No ViewModel involvement. |
| Drag-to-resize gesture | Browser / Client (DragGesture) | — | DragGesture on drag indicator capsule. Snap logic in `onEnded` with spring animation. |
| Pinned Share button | Browser / Client (SwiftUI View) | — | Extracted component in WatermarkCore/DesignSystem/. Consumed as ZStack layer above sheet. |
| Share button state machine | Browser / Client (SwiftUI View) | API / Backend (ViewModel) | View reads ViewModel's `renderingState` for display; calls `renderAndPrepareShare()`/`presentShareSheet()` via `WatermarkConfigurable`. |
| Batch overlays (ThumbnailStrip, ProgressOverlay) | Browser / Client (SwiftUI View) | — | Positioned in ZStack between preview and sheet layers. Existing views reused with position adjustment. |
| NavigationStack toolbar | Browser / Client (SwiftUI Toolbar) | — | Unchanged from current ContentView. Batch Cancel/Reset stay in toolbar. |
| Liquid Glass surface | Browser / Client (SwiftUI ViewModifier) | CDN / Static | `.markepiGlass()` from Phase 15 provides iOS 26 `.glassEffect` or iOS 18 `.ultraThinMaterial`. |
| ControlsView content | Browser / Client (SwiftUI View) | — | Unchanged, shell-agnostic. Wrapped inside sheet's scroll area. |

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| SwiftUI | iOS 18 SDK | All UI: ZStack, DragGesture, spring animation, overlay, zIndex | Only framework needed for this phase. No third-party dependencies. |
| WatermarkCore (own package) | — | Design system primitives (`.markepiGlass()`, `MarkepiPillBar`, button styles), extracted ShareActionButton, ControlsView | Internal Swift Package. Already consumed by all targets. |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| — _(none)_ | — | — | No third-party libraries are needed. All sheet behavior, gesture handling, Z-ordering, and glass effects are built with SwiftUI system APIs and Phase 15 design system primitives. |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Custom ZStack bottom sheet (recommended) | `.sheet` + `.presentationDetents` + `.presentationBackgroundInteraction` | `.sheet` provides native gestures, accessibility, and detent animation for free — but creates a separate modal window layer that blocks Z-ordering. The pinned Share button cannot render above a `.sheet` from the presenting view. [VERIFIED: Apple Developer Documentation — `.sheet` creates a separate presentation layer; views in the presenting hierarchy are behind the sheet.] |
| Custom ZStack bottom sheet | UIKit `UISheetPresentationController` | UIKit gives fine-grained detent control and custom view controller presentation. But introducing UIKit into a pure SwiftUI ContentView adds bridging complexity (`UIViewControllerRepresentable`) with no benefit — all needed behavior (drag gesture, snap animation, glass styling) is achievable in SwiftUI. [VERIFIED: Apple Developer Documentation — `UISheetPresentationController` is UIKit-only, requires UIViewController bridging to use with SwiftUI.] |
| Manual DragGesture + snap animation | Third-party bottom sheet library | Third-party libraries risk abandonment, may not support iOS 26 Liquid Glass, and add dependency risk to a privacy-focused app. SwiftUI's built-in gesture and animation system is sufficient. |

**Installation:**
```bash
# No package manager needed. Phase uses only SwiftUI and the existing WatermarkCore package.
# Verify WatermarkCore is linked in Xcode project settings for App target.
```

## Package Legitimacy Audit

**No external packages are installed or recommended for this phase.** The implementation uses only Apple's SwiftUI framework and the project's own WatermarkCore Swift Package (already part of the repository). No slopcheck verification is needed.

| Package | Registry | Age | Downloads | Source Repo | slopcheck | Disposition |
|---------|----------|-----|-----------|-------------|-----------|-------------|
| _(none)_ | — | — | — | — | — | No external packages recommended |

## Architecture Patterns

### System Architecture Diagram

```
┌──────────────────────────────────────────────────────┐
│                 NavigationStack                       │
│  ┌──────────────────────────────────────────────┐    │
│  │  Toolbar: [Cancel] [Reset All] [Import...]   │    │
│  └──────────────────────────────────────────────┘    │
│                                                       │
│  ┌──────────────────────────────────────────────┐    │
│  │              ZStack (ContentView)             │    │
│  │                                               │    │
│  │  z=0: PreviewView (full-bleed, ignoresSafeArea)│   │
│  │       │ user pan/pinch gestures pass through  │    │
│  │       ▼                                        │    │
│  │  z=1: Batch Overlays (conditional)            │    │
│  │       • ThumbnailStripView (multi-photo)       │    │
│  │       • BatchProgressOverlay (batch active)    │    │
│  │       │                                        │    │
│  │       ▼                                        │    │
│  │  z=2: Inspector Sheet (Glass Bottom Sheet)    │    │
│  │       ┌──────────────────────────────────┐    │    │
│  │       │  ─── drag indicator ───           │    │    │
│  │       │  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  │    │    │
│  │       │  ░  ControlsView (unchanged)  ░  │    │    │
│  │       │  ░  • Pill Bar (section switch)░  │    │    │
│  │       │  ░  • Section content (scroll) ░  │    │    │
│  │       │  ░  • Share button (inline)    ░  │    │    │
│  │       │  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  │    │    │
│  │       └──────────────────────────────────┘    │    │
│  │       Height: ~60pt (peek) ↔ ~screen/2 (expanded)│
│  │       │                                        │    │
│  │       ▼                                        │    │
│  │  z=3: Pinned Share Action Bar                 │    │
│  │       ┌──────────────────────┐                │    │
│  │       │  [Share/Watermark All] │  ← Liquid Glass │
│  │       └──────────────────────┘     floating pill │
│  │       Position: fixed ~76pt from bottom          │
│  │       (peekHeight + 16pt margin)                 │
│  │                                               │    │
│  └──────────────────────────────────────────────┘    │
│                                                       │
│  Modal Sheets (separate layer, existing):             │
│  • ShareSheetView (isPresented: showShareSheet)      │
│  • TemplateListView (isPresented: showTemplateList)   │
│  • BatchItemDetailSheet (item: selectedItemForOverride)│
└──────────────────────────────────────────────────────┘
```

**Data flow for primary use case (single photo, watermark → share):**
1. User loads photo → `PreviewView` renders full-bleed preview (z=0)
2. User taps Watermark/Style/Output pills in `MarkepiPillBar` to switch sections
3. User configures watermark via `ControlsView` controls inside sheet (z=2)
4. User drags sheet indicator up to expand (peek → expanded), scrolls controls
5. User taps pinned Share button (z=3) or inline Share button in ControlsView
6. Both buttons call `viewModel.renderAndPrepareShare()` via `WatermarkConfigurable`
7. ViewModel renders → `renderingState` transitions through `.rendering` → `.done`
8. Button shows "Ready to Share" → user taps → `viewModel.presentShareSheet()`
9. Modal `ShareSheetView` appears (separate `.sheet` layer, existing)

### Recommended Project Structure

```
Packages/WatermarkCore/Sources/WatermarkCore/
├── DesignSystem/
│   ├── GlassEffect/
│   │   └── MarkepiGlassModifier.swift      # Existing — consumed for sheet + pinned bar
│   ├── ButtonStyles/
│   │   └── MarkepiButtonStyle.swift         # Existing — consumed by ShareActionButton
│   ├── Typography/
│   │   └── MarkepiTypography.swift          # Existing — consumed for any new labels
│   ├── MarkepiPillBar.swift                 # Existing — lives inside ControlsView
│   ├── ScrollEdge/
│   │   └── MarkepiScrollEdgeProtection.swift # Existing — inside ControlsView
│   ├── MarkepiUtilities.swift               # Existing — .modify {} helper
│   └── ShareActionButton.swift              # NEW — extracted from ControlsView
├── UI/
│   ├── ControlsView.swift                   # MODIFIED — shareButton replaced with ShareActionButton
│   └── WatermarkConfigurable.swift          # Existing — protocol consumed by ShareActionButton
│   └── InspectorSheetView.swift             # NEW — custom bottom sheet container
└── Models/
    └── ProcessingResult.swift               # Existing — RenderingState enum

App/Views/
├── ContentView.swift                        # MODIFIED — 60/40 VStack replaced with ZStack layout
└── PreviewArea/
    └── PreviewView.swift                    # MODIFIED — extend to .ignoresSafeArea(.all)
```

### Pattern 1: Custom ZStack Bottom Sheet (Recommended)

**What:** A custom bottom sheet implemented as a SwiftUI view within ContentView's ZStack, using `@State` for detent tracking and `DragGesture` for resize interaction. Not using SwiftUI's `.sheet` modifier.

**When to use:** When you need views from the presenting hierarchy to render ABOVE the sheet in Z-order, OR when the sheet must be permanently visible (non-dismissible). This is the standard pattern used by professional photo-editing apps (Apple Photos, Lightroom, Darkroom).

**Why not `.sheet`:** SwiftUI's `.sheet` modifier creates a separate modal presentation layer (UIWindow on UIKit level). Views in the presenting view hierarchy cannot render above this layer. The pinned Share button (D-06) would be trapped behind the sheet. Research confirmed: `.overlay` on the main view, `.safeAreaInset`, and `.zIndex` on presenting views all fail to render above a `.sheet` — the sheet occupies its own window level. [VERIFIED: Apple Developer Documentation; multiple Stack Overflow confirmations]

**Example:**
```swift
// Core detent model
enum SheetDetent: Equatable {
    case peek      // ~60pt — pill bar labels only
    case expanded  // ~half screen — full ControlsView
}

// In ContentView:
struct ContentView: View {
    @State var viewModel: WatermarkViewModel
    @State private var detent: SheetDetent = .peek
    @State private var dragOffset: CGFloat = 0
    @GestureState private var isDragging = false
    
    // Peek height = pill bar intrinsic height + drag indicator
    private let peekHeight: CGFloat = 60
    
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let expandedHeight = geometry.size.height * 0.55
                let currentHeight = detent == .peek ? peekHeight : expandedHeight
                
                ZStack(alignment: .bottom) {
                    // Layer 0: Full-bleed preview
                    previewArea
                        .ignoresSafeArea()
                    
                    // Layer 1: Batch overlays (conditional)
                    if viewModel.hasMultiplePhotos {
                        ThumbnailStripView(...)
                            .zIndex(1)
                    }
                    if case .batchProcessing = viewModel.renderingState {
                        BatchProgressOverlay(...)
                            .zIndex(1)
                    }
                    
                    // Layer 2: Glass bottom sheet
                    InspectorSheetView(
                        viewModel: viewModel,
                        detent: $detent,
                        peekHeight: peekHeight
                    )
                    .frame(height: currentHeight + dragOffset)
                    .zIndex(2)
                    
                    // Layer 3: Pinned Share button (always above sheet)
                    pinnedShareBar
                        .zIndex(3)
                }
            }
            .toolbar { toolbarContent }
            // ... existing modifiers (photosPicker, alerts, sheet modifiers)
        }
    }
    
    private var pinnedShareBar: some View {
        ShareActionButton(viewModel: viewModel)
            .padding(.horizontal, 40)
            .padding(.bottom, peekHeight + 16)
            .frame(maxWidth: .infinity, alignment: .bottom)
    }
}
```

**Key architectural properties:**
- Sheet height is controlled by `detent` enum + `dragOffset` (live during drag)
- z=3 pinned button always renders on top of z=2 sheet — even when sheet is expanded and covers the same screen area
- Preview is z=0, never modified — satisfies D-12 (no dimming/blur/scale)
- Batch overlays at z=1 between preview and sheet — satisfies D-17
- The sheet view itself manages the DragGesture and snap animation

### Pattern 2: InspectorSheetView — Drag Gesture with Detent Snap

**What:** A self-contained view that renders the glass-backed sheet surface with drag indicator, hosts ControlsView, and manages drag-to-resize between peek and expanded detents.

**When to use:** This is the sheet container itself — instantiated once in ContentView's ZStack.

**Example:**
```swift
// Source: Derived from Apple HIG bottom sheet patterns + Phase 15 design system
struct InspectorSheetView<ViewModel: WatermarkConfigurable & Observable>: View {
    @Binding var detent: SheetDetent
    let peekHeight: CGFloat
    @State var viewModel: ViewModel
    
    @State private var lastDragPosition: CGFloat = 0
    @State private var scrollOffset: CGFloat = 0
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    
    var body: some View {
        VStack(spacing: 0) {
            // Drag indicator (D-10: standard iOS capsule)
            RoundedRectangle(cornerRadius: 2.5)
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 4)
                .gesture(dragGesture)
                .accessibilityLabel("Resize controls")
                .accessibilityHint("Drag up to show all controls, down to minimize")
            
            // ControlsView — unchanged, shell-agnostic (D-14)
            ControlsView(viewModel: viewModel)
        }
        .frame(maxWidth: .infinity)
        .background {
            // Glass surface (D-09): Liquid Glass on iOS 26, material fallback on iOS 18
            UnevenRoundedRectangle(
                topLeadingRadius: 20,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 20,
                style: .continuous
            )
            .fill(.clear)
            .markepiGlass(
                shape: UnevenRoundedRectangle(
                    topLeadingRadius: 20,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 20,
                    style: .continuous
                ),
                isEnabled: !reduceTransparency
            )
        }
        .clipShape(UnevenRoundedRectangle(
            topLeadingRadius: 20,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: 20,
            style: .continuous
        ))
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: detent)
    }
    
    // Drag gesture: resize between peek and expanded (D-01)
    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                let translation = lastDragPosition + value.translation.height
                // Allow dragging up (negative) to expand, down (positive) to peek
                // Clamp to prevent over-drag
                let maxDrag: CGFloat = 200  // generous over-drag limit
                if translation < 0 && abs(translation) < maxDrag {
                    // Dragging up — expanding
                } else if translation > 0 && translation < maxDrag {
                    // Dragging down — collapsing
                }
            }
            .onEnded { value in
                let translation = lastDragPosition + value.translation.height
                let threshold: CGFloat = 50  // 50pt drag to switch detents
                
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    if translation < -threshold {
                        detent = .expanded
                    } else {
                        detent = .peek
                    }
                }
                lastDragPosition = 0
            }
    }
}
```

**Key implementation notes:**
- The drag gesture only triggers on the drag indicator area (D-10) — this prevents conflicts with ControlsView's internal ScrollView
- Detent snap uses `.spring(response: 0.4, dampingFraction: 0.85)` — matches native iOS spring feel [CITED: Apple HIG — spring animations for interactive gestures]
- The sheet body uses `.markepiGlass()` with `UnevenRoundedRectangle` for rounded top corners + square bottom (D-09, D-11)
- `isEnabled: !reduceTransparency` respects Reduce Transparency accessibility setting (UXQ-03)
- D-15 (native nested scroll) is handled naturally: since the drag gesture is only on the indicator, the inner ControlsView scroll receives all scroll gestures unimpeded. The user drags the indicator to resize, scrolls the content to scroll.

### Pattern 3: ShareActionButton — Extracted Standalone Component

**What:** The Share button state machine extracted from ControlsView's `shareButton` computed property (lines 239-358) into a standalone reusable component.

**When to use:** 
1. In the pinned action bar at z=3 (main app)
2. Inside ControlsView's Output section (main app + both extensions)
3. Any future placement that needs the rendering-state-driven Share button

**Example:**
```swift
// Source: Extracted from ControlsView.swift:239-358 [CITED: existing codebase]
// Location: WatermarkCore/Sources/WatermarkCore/DesignSystem/ShareActionButton.swift

/// A standalone Share/Render button that drives off the ViewModel's
/// `renderingState`. Generic over any `WatermarkConfigurable & Observable`
/// ViewModel so all three targets can consume it.
///
/// Placement-agnostic — does not assume it's in ControlsView, a toolbar,
/// or a floating pill. The caller provides the container styling.
public struct ShareActionButton<ViewModel: WatermarkConfigurable & Observable>: View {
    @State var viewModel: ViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    
    public init(viewModel: ViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        Group {
            switch viewModel.renderingState {
            case .idle:
                Button {
                    Task { await viewModel.renderAndPrepareShare() }
                } label: {
                    Label(
                        viewModel.hasMultiplePhotos ? "Watermark All" : "Share",
                        systemImage: viewModel.hasMultiplePhotos 
                            ? "square.and.arrow.up.on.square.fill" 
                            : "square.and.arrow.up"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.markepiPrimary())
                
            case .rendering:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.regular)
                    Text("Rendering...")
                        .markepiTypography(.controlLabel)
                }
                .frame(maxWidth: .infinity, minHeight: 50)
                .markepiGlass(shape: RoundedRectangle(cornerRadius: 12, style: .continuous),
                              isEnabled: !reduceTransparency)
                .disabled(true)
                
            case .renderingVideo(let progress, let eta):
                videoRenderingView(progress: progress, eta: eta)
                
            case .batchProcessing(let current, let total, let eta):
                batchProcessingView(current: current, total: total, eta: eta)
                
            case .done:
                Button {
                    if !reduceMotion {
                        withAnimation(.easeOut(duration: 0.3)) {}
                    }
                    viewModel.presentShareSheet()
                } label: {
                    Label(
                        viewModel.hasMultiplePhotos ? "Ready to Share All" : "Ready to Share",
                        systemImage: "checkmark.circle.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.markepiPrimary())
                
            case .error:
                Button {
                    Task { await viewModel.renderAndPrepareShare() }
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.markepiSecondary())
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), 
                   value: viewModel.renderingState)
    }
    
    // ... private videoRenderingView, batchProcessingView helpers
    // (extracted from ControlsView's existing switch cases)
}
```

**Integration in ControlsView:** Replace the `shareButton` computed property (lines 239-358) with:
```swift
// In ControlsView's outputSectionContent:
ShareActionButton(viewModel: viewModel)
    .padding(.horizontal, 16)
```

**Integration in pinned bar:** Direct usage in ContentView's z=3 layer.

**Protocol surface used:** `renderAndPrepareShare()`, `presentShareSheet()`, `cancelProcessing()` — all already defined in `WatermarkConfigurable` protocol (frozen per v2.1 scope).

### Pattern 4: Z-Order Layering for Batch Overlays

**What:** ThumbnailStripView and BatchProgressOverlay positioned between the preview (z=0) and the sheet (z=2) in the ZStack.

**When to use:** Per D-17, batch overlays float at the Z level between preview and sheet layers — visible through the glass sheet, above the preview.

**Example:**
```swift
ZStack(alignment: .bottom) {
    // z=0: Preview
    previewArea
    
    // z=1: Batch overlays
    if viewModel.hasMultiplePhotos {
        ThumbnailStripView(...)
            .zIndex(1)
            .padding(.bottom, peekHeight + 8) // Above sheet at peek
    }
    if case .batchProcessing = viewModel.renderingState {
        BatchProgressOverlay(...)
            .zIndex(1)
    }
    
    // z=2: Sheet
    inspectorSheet.zIndex(2)
    
    // z=3: Pinned button
    pinnedShareBar.zIndex(3)
}
```

**Positioning notes:**
- ThumbnailStripView: previously positioned at bottom of previewArea ZStack (line 131-143 of ContentView). Now positioned in the root ZStack at z=1 with bottom padding to avoid overlap with sheet.
- BatchProgressOverlay: previously a full-previewArea overlay with `.ignoresSafeArea()`. Now positioned in root ZStack at z=1, still full-screen (`BatchProgressOverlay` already uses `.ignoresSafeArea()` internally at line 39).
- Both overlays are behind the sheet (z=1 < z=2) but visible through the Liquid Glass (D-09, D-12).

### Anti-Patterns to Avoid

- **Using `.sheet` modifier for the inspector:** Creates a separate window layer. The pinned Share button cannot render above it. This is a hard blocker for D-06. [VERIFIED: SwiftUI sheet creates a separate UITransitionView/presentation layer above the presenting UIWindow.]
- **Putting the pinned button inside `.sheet` content:** At `.peek` detent (~60pt), the pinned button would be constrained inside the 60pt sheet height — too small to be useful. At `.expanded`, it would scroll with ControlsView content — not "always visible." Both violate D-06.
- **Using `.safeAreaInset(edge: .bottom)` for the pinned button:** `safeAreaInset` pushes the main content up (resizes the preview). This violates D-02 (no push/resize of preview area).
- **`.presentationBackground(.clear)` on `.sheet` + button behind:** Even with clear background, the button is behind the sheet's gesture/touch layer. `.presentationBackgroundInteraction(.enabled)` allows taps to pass through, but the button renders behind the sheet's glass blur — visually wrong and violates the "above the sheet" requirement. Additionally, iOS 18.0-18.1 had known bugs with `presentationBackgroundInteraction` where touches didn't reliably pass through. [CITED: multiple developer reports, iOS 18.2 fixed the issue.]
- **Custom gesture on ControlsView's ScrollView:** Don't try to coordinate sheet drag with inner scroll by attaching gestures to the scroll content. The architecture avoids this entirely by putting the drag gesture only on the drag indicator capsule — completely separate from ControlsView's scroll area. This naturally satisfies D-15.
- **`DispatchQueue.main.async` for detent state:** Detent changes drive layout (frame height). They must happen on the main actor synchronously within the SwiftUI update cycle. Using async dispatch causes layout glitches.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Bottom sheet drag-to-resize | Custom UIPanGestureRecognizer + UIKit bridging | SwiftUI `DragGesture` with `.onChanged`/`.onEnded` + spring animation | SwiftUI gestures integrate with the view update cycle, respect `reduceMotion`, and don't require `UIViewRepresentable` bridging. The drag indicator-only approach avoids gesture conflicts with inner ScrollView. |
| Liquid Glass surface | Custom `UIVisualEffectView` + `UIBlurEffect` bridging | `.markepiGlass()` from Phase 15 | Already built, tested, handles iOS 26 `.glassEffect` and iOS 18 `.ultraThinMaterial` fallback with `if #available` branching. No need to rebuild. |
| Rounded top corners + square bottom | Custom `UIBezierPath` mask | `UnevenRoundedRectangle` (iOS 16+) | Native SwiftUI shape. `UnevenRoundedRectangle(topLeadingRadius:topTrailingRadius:bottomLeadingRadius:bottomTrailingRadius:style:)` provides per-corner radius control without custom path math. |
| Detent snap point calculation | Manual threshold math with magic numbers | Percentage-of-drag approach: if drag > 50pt from last detent, switch | 50pt threshold is the standard iOS sheet detent switch distance. [CITED: Apple HIG — interactive sheet transitions use ~50pt gesture threshold.] |
| Nested scroll coordination | Custom `UIScrollView` delegate + content offset tracking | Architectural separation: drag gesture on indicator ONLY, scroll gesture on ControlsView content ONLY | ControlsView already has its own ScrollView. Since the sheet's drag gesture is only on the indicator capsule (not on the ControlsView area), there's no gesture conflict. D-15 is satisfied structurally, not programmatically. |
| Extracted Share button rendering state machine | Rewrite the switch statement | Copy the exact switch cases from ControlsView:239-358 | The rendering state machine is already correct and tested. Extraction is a code move, not a rewrite. Preserves all 6 states, all transitions, all button styles. |

**Key insight:** The entire phase can be implemented with ZStack layering, a single DragGesture on the indicator, and code extraction from ControlsView. No custom gesture recognizers, no UIKit bridging, no third-party libraries. The complexity is architectural (correct Z-order, detent snap logic) not technical (no novel algorithms).

## Runtime State Inventory

> **Phase classification:** This is a **refactor/redesign** phase that restructures ContentView's layout and extracts the Share button from ControlsView. Runtime state inventory is required.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | None — layout changes only affect SwiftUI views, not data models. `WatermarkConfiguration`, `TemplateStore`, `UserDefaults` are untouched. | None |
| Live service config | None — no external service configurations reference the 60/40 layout or ControlsView internal structure. | None |
| OS-registered state | None — no OS-level registrations (Task Scheduler, launchd, etc.) in this iOS project. | None |
| Secrets/env vars | None — no secret keys or env vars reference layout constants or view hierarchies. | None |
| Build artifacts | None — the only package (WatermarkCore) has no egg-info or similar build artifacts outside Xcode's DerivedData. | None — standard Xcode clean build handles any stale object files. |

**Nothing found in any category.** The phase is a pure SwiftUI layout change and code extraction — no runtime state outside the source code and Xcode build system is affected.

## Common Pitfalls

### Pitfall 1: Z-Stack Children Clipping at Sheet Boundaries

**What goes wrong:** When the pinned Share button (z=3) is positioned at a Y coordinate that overlaps with the sheet (z=2), the button may appear clipped or not rendered if the sheet view's frame or clip shape masks it.

**Why it happens:** SwiftUI's default behavior: a view with `.clipShape()` or a shaped background clips its children. If the pinned button is a child of the sheet view, it gets clipped. If it's a sibling in the ZStack, it renders independently — BUT the ZStack itself may size its children based on their own intrinsic sizes.

**How to avoid:** Keep the pinned button as a SIBLING of the sheet in the ZStack, not a child of the sheet. Use explicit `.zIndex()` to enforce rendering order. The button's frame should use `.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)` so it occupies the full ZStack space but positions its content at the bottom with padding.

**Warning signs:** Button appears clipped at expanded detent, or button doesn't respond to taps when sheet is expanded.

### Pitfall 2: Drag Gesture Conflict with ControlsView Scroll

**What goes wrong:** If the sheet's drag gesture is attached to the entire sheet body (not just the indicator), dragging anywhere on the sheet triggers resize — even when the user intends to scroll ControlsView's content.

**Why it happens:** SwiftUI gesture resolution: a DragGesture on a parent view captures all drags within its bounds before child ScrollViews can process them.

**How to avoid:** Attach the DragGesture ONLY to the drag indicator capsule (the `RoundedRectangle` at the top of the sheet). ControlsView's ScrollView occupies the rest of the sheet body and receives all scroll gestures unimpeded. This is the architectural approach to D-15 — structural separation, not programmatic coordination.

**Warning signs:** ControlsView doesn't scroll; instead the sheet resizes. Or sheet resizes while user tries to scroll controls content.

### Pitfall 3: Detent Snap Animation Glitching on Rapid Drags

**What goes wrong:** Rapid back-and-forth dragging causes the detent to flicker between peek and expanded, or the animation glitches mid-transition.

**Why it happens:** The drag gesture's `.onChanged` updates offset continuously. If a new drag starts before the previous snap animation completes, SwiftUI's animation system may interpolate from an unexpected starting point.

**How to avoid:** Use `withAnimation(.spring(...))` only in `.onEnded`, not in `.onChanged`. Track drag offset as a separate `@State` variable (`dragOffset`) that's added to the sheet's frame height without animation during drag. Only animate the final snap. Reset `dragOffset` to 0 after snap.

```swift
// Correct pattern:
@State private var dragOffset: CGFloat = 0

// In .onChanged: update dragOffset (no animation)
dragOffset = value.translation.height

// In .onEnded: compute target detent, then:
withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
    detent = targetDetent
    dragOffset = 0  // reset
}
```

**Warning signs:** Sheet "jumps" after drag ends, or detent toggles multiple times from a single drag.

### Pitfall 4: ControlsView Share Button Not Updating After Extraction

**What goes wrong:** After extracting `ShareActionButton` from ControlsView, the inline Share button in ControlsView's Output section stops responding to rendering state changes.

**Why it happens:** The extracted `ShareActionButton` uses `@State var viewModel: ViewModel`. If ControlsView instantiates a NEW `ShareActionButton(viewModel: viewModel)` each time the body is evaluated, the `@State` wrapper may hold a stale reference.

**How to avoid:** `ShareActionButton` should use `@State var viewModel: ViewModel` where `ViewModel` is the generic parameter — matching the pattern used by ControlsView itself (line 13: `@State var viewModel: ViewModel`). SwiftUI's `@State` for reference types (classes) under `@Observable` preserves the identity — the same ViewModel instance is tracked, and body re-evaluation triggers when `renderingState` changes. ControlsView replaces its `shareButton` computed property with a direct instantiation:

```swift
// OLD (ControlsView, line 152-153):
shareButton

// NEW:
ShareActionButton(viewModel: viewModel)
    .padding(.horizontal, 16)
```

**Warning signs:** Share button shows stale state, doesn't transition from `.idle` to `.rendering`, or tapping does nothing.

### Pitfall 5: Preview Not Truly Full-Bleed on Notch/Dynamic Island Devices

**What goes wrong:** PreviewView has `.edgesIgnoringSafeArea(.top)` but not `.bottom`. The preview area still shows a gap at the bottom where the old 40% controls area was — or the home indicator area is black.

**Why it happens:** The current PreviewView only ignores the top safe area (line 94: `.edgesIgnoringSafeArea(.top)`). After removing the 60/40 split, the preview must fill the entire screen including bottom safe area and the area behind the home indicator.

**How to avoid:** Change PreviewView to `.ignoresSafeArea()` (all edges). The preview's content (image) uses `.aspectRatio(contentMode: .fit)` which handles the actual image positioning; the view frame just needs to extend edge-to-edge. The sheet and pinned bar will overlay the bottom portion.

**Warning signs:** Black bar at bottom of screen, or preview image doesn't extend behind the home indicator area on notched devices.

## Code Examples

### Full ContentView Restructured Layout
```swift
// Source: Derived from existing ContentView.swift structure + research findings
// This replaces the entire mainLayout(_:) function (lines 69-93)
// and the controlsArea computed property (lines 175-177).

private let peekDetentHeight: CGFloat = 60  // pill bar intrinsic + drag indicator

struct ContentView: View {
    @State var viewModel: WatermarkViewModel
    @State private var detent: SheetDetent = .peek
    @State private var dragOffset: CGFloat = 0
    @State private var lastDragPosition: CGFloat = 0
    
    // ... existing @State for batch UI, file importer
    
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let expandedHeight = geometry.size.height * 0.55
                
                ZStack(alignment: .bottom) {
                    // z=0: Full-bleed preview (LYT-01)
                    previewArea
                        .ignoresSafeArea()
                    
                    // z=1: Batch overlays (D-17)
                    batchOverlays
                        .zIndex(1)
                    
                    // z=2: Glass bottom sheet (LYT-02)
                    inspectorSheet(expandedHeight: expandedHeight)
                        .zIndex(2)
                    
                    // z=3: Pinned Share bar (LYT-03)
                    pinnedShareBar
                        .zIndex(3)
                }
            }
            .toolbar { toolbarContent }
            // ... existing modifiers
        }
    }
    
    // MARK: - Preview Area (z=0)
    
    private var previewArea: some View {
        ZStack(alignment: .bottom) {
            PreviewView(viewModel: viewModel)
            
            // Plus button (top-right, existing)
            if viewModel.currentPhoto != nil {
                Button { viewModel.showPicker = true } label: {
                    Image(systemName: "plus.rectangle.on.rectangle")
                        .font(.system(size: 22, weight: .regular))
                }
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(12)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.renderingState)
    }
    
    // MARK: - Batch Overlays (z=1)
    
    @ViewBuilder
    private var batchOverlays: some View {
        if viewModel.hasMultiplePhotos {
            ThumbnailStripView(
                photos: viewModel.photos,
                currentIndex: $viewModel.currentIndex,
                perItemOverrides: viewModel.perItemOverrides,
                onItemTapped: { index in
                    selectedItemForOverride = IdentifiableIndex(value: index)
                },
                onReorder: { reordered in
                    viewModel.photos = reordered
                }
            )
            .padding(.bottom, peekDetentHeight + 8)
        }
        
        if case .batchProcessing(let current, let total, let eta) = viewModel.renderingState {
            BatchProgressOverlay(
                current: current, total: total, eta: eta,
                onCancel: { showBatchCancelConfirmation = true }
            )
            .transition(.opacity)
        }
    }
    
    // MARK: - Inspector Sheet (z=2)
    
    private func inspectorSheet(expandedHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            // Drag indicator
            RoundedRectangle(cornerRadius: 2.5)
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 4)
                .gesture(sheetDragGesture(expandedHeight: expandedHeight))
            
            // ControlsView (D-14: unchanged, shell-agnostic)
            ControlsView(viewModel: viewModel)
        }
        .frame(maxWidth: .infinity)
        .frame(height: detent == .peek ? peekDetentHeight : expandedHeight + dragOffset)
        .background {
            UnevenRoundedRectangle(
                topLeadingRadius: 20, bottomLeadingRadius: 0,
                bottomTrailingRadius: 0, topTrailingRadius: 20,
                style: .continuous
            )
            .fill(.clear)
            .markepiGlass(
                shape: UnevenRoundedRectangle(
                    topLeadingRadius: 20, bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0, topTrailingRadius: 20,
                    style: .continuous
                ),
                isEnabled: !reduceTransparency
            )
        }
        .clipShape(UnevenRoundedRectangle(
            topLeadingRadius: 20, bottomLeadingRadius: 0,
            bottomTrailingRadius: 0, topTrailingRadius: 20,
            style: .continuous
        ))
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: detent)
    }
    
    // MARK: - Sheet Drag Gesture
    
    private func sheetDragGesture(expandedHeight: CGFloat) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let translation = lastDragPosition + value.translation.height
                // Upward drag = negative translation = expanding
                if detent == .peek && translation < -10 {
                    let progress = min(abs(translation) / (expandedHeight - peekDetentHeight), 1.0)
                    dragOffset = -progress * (expandedHeight - peekDetentHeight)
                } else if detent == .expanded && translation > 10 {
                    let progress = min(translation / (expandedHeight - peekDetentHeight), 1.0)
                    dragOffset = -progress * (expandedHeight - peekDetentHeight)
                }
            }
            .onEnded { value in
                let translation = lastDragPosition + value.translation.height
                let threshold: CGFloat = 50
                
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    if detent == .peek && translation < -threshold {
                        detent = .expanded
                    } else if detent == .expanded && translation > threshold {
                        detent = .peek
                    }
                    dragOffset = 0
                    lastDragPosition = 0
                }
            }
    }
    
    // MARK: - Pinned Share Bar (z=3, LYT-03)
    
    private var pinnedShareBar: some View {
        ShareActionButton(viewModel: viewModel)
            .padding(.horizontal, 40)
            .padding(.bottom, peekDetentHeight + 16)
            .frame(maxWidth: .infinity, alignment: .bottom)
            .background {
                // Liquid Glass pill backing (D-06)
                Capsule()
                    .fill(.clear)
                    .markepiGlass(
                        shape: Capsule(),
                        isEnabled: !reduceTransparency
                    )
                    .frame(height: 52)
                    .padding(.horizontal, 24)
            }
    }
}
```

### PreviewView Adjustment for Full-Bleed
```swift
// Source: PreviewView.swift line 94 — change from .top-only to all edges
// OLD (line 94):
.edgesIgnoringSafeArea(.top)

// NEW:
.ignoresSafeArea()
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `.sheet` + `.presentationDetents` as the only bottom sheet pattern | Custom ZStack-based sheet for non-dismissible inspectors with Z-ordered overlays | 2024+ (professional apps convention) | Full control over Z-ordering. Pinned buttons, floating toolbars, and batch overlays can be positioned at specific Z levels. |
| `GeometryReader → VStack(60%/40%)` hardcoded split (current ContentView) | ZStack with full-bleed preview + detent-controlled glass sheet | This phase | Eliminates the split; preview is hero element. Sheet provides structured control access without splitting screen real estate. |
| Share button embedded in ControlsView's `shareButton` computed property | Extracted standalone `ShareActionButton` component in WatermarkCore/DesignSystem/ | This phase | Single source of truth. Three placements: pinned bar, ControlsView inline, extension shells via ControlsView. |
| Batch overlays inside previewArea ZStack | Batch overlays at root ZStack with explicit zIndex between preview and sheet | This phase | Overlays visible through Liquid Glass sheet, correctly layered per D-17. |
| `.edgesIgnoringSafeArea(.top)` on PreviewView | `.ignoresSafeArea()` (all edges) on PreviewView | This phase | True full-bleed behind home indicator and notch. Preview fills entire screen behind the glass sheet. |

**Deprecated/outdated:**
- **60/40 VStack split in ContentView:** Replaced entirely by ZStack layout. The `.frame(height: geometry.size.height * 0.60)` and `.frame(height: geometry.size.height * 0.40)` constraints are removed.
- **`UIImagePickerController`:** Already replaced by PhotosPicker. Not relevant here but confirmed deprecated.
- **`.edgesIgnoringSafeArea(.top)` (singular edge):** Replaced by `.ignoresSafeArea()` (all edges) for true full-bleed.

## Assumptions Log

> All claims tagged `[ASSUMED]` in this research. The planner and discuss-phase use this section to identify decisions that need user confirmation before execution.

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `peekDetentHeight = 60` (pill bar ~44-48pt + drag indicator ~13pt) is the correct peek detent height derived from MarkepiPillBar's intrinsic size | Architecture Patterns | If pill bar renders larger/smaller on device due to Dynamic Type or different font metrics, peek height won't match actual pill bar height. Planner should derive this from actual pill bar measurement rather than hardcoding. |
| A2 | Expanded detent at 55% of screen height (`geometry.size.height * 0.55`) approximates Apple Photos/Lightroom convention for half-height inspector | Architecture Patterns | If user prefers different proportion, the `.medium` equivalent (~0.5) should be used instead. Per D-01, the exact value is "approximately half screen height" — precision is at planner's discretion. |
| A3 | ControlsView's existing `.markepiScrollEdgeProtection` continues to work unchanged when wrapped inside the sheet | Architecture Patterns | The scroll-edge protection modifier uses overlay alignment. If the sheet's frame management interferes with overlay positioning (e.g., clipping), the blur gradient may not appear at the right position. Planner should verify post-implementation. |
| A4 | `UnevenRoundedRectangle` (iOS 16+) with 20pt top corner radius matches "standard iOS sheet corners" (D-11) | Architecture Patterns | If Apple adjusts default sheet corner radius in a future iOS version, 20pt may not match. However, Apple's default sheet corner radius has been stable at ~20pt since iOS 16. The planner can adjust if needed. |
| A5 | ThumbnailStripView repositioned with `.padding(.bottom, peekDetentHeight + 8)` correctly avoids overlap with the sheet at peek detent | Architecture Patterns | If the user switches between single/multi photo frequently, the thumbnail strip's entry/exit animation may conflict with sheet detent animation. Planner should verify animation coordination. |

**If this table is empty:** N/A — 5 assumptions documented above.

## Open Questions

1. **Pill bar intrinsic height measurement at runtime**
   - What we know: MarkepiPillBar has known padding (`.padding(.vertical, 8)` on buttons + `.padding(4)` on HStack + glass capsule). Estimated total: ~44-48pt.
   - What's unclear: Exact pixel height with Dynamic Type active (UXQ-01 targets up to 200%). At largest type sizes, the pill bar height increases significantly.
   - Recommendation: Planner should NOT hardcode `peekDetentHeight: CGFloat = 60`. Instead, use `GeometryReader` or `.background(GeometryReader { ... })` on MarkepiPillBar to measure its actual rendered height and set the peek detent dynamically. Fallback to 60pt if measurement unavailable.

2. **Drag gesture threshold tuning (50pt)**
   - What we know: 50pt is the standard iOS sheet detent switch threshold.
   - What's unclear: Whether this feels natural with the custom glass sheet at this specific peek height (60pt). If the peek is very small relative to the threshold, the sheet may feel "sticky."
   - Recommendation: Use 50pt as initial value. Planner should create a variable constant (not magic number) so it can be tuned. Consider making threshold a fraction of the detent height difference: `threshold = min(50, (expandedHeight - peekHeight) * 0.3)`.

3. **ShareActionButton's `renderingVideo` and `batchProcessing` views with video progress bar layout**
   - What we know: The full rendering-state switch has 6 cases. The `.renderingVideo` and `.batchProcessing` cases include progress bars + cancel buttons. These are complex sub-views.
   - What's unclear: Whether these sub-views should be extracted as separate private helper views within ShareActionButton, or kept inline in the switch. ControlsView currently has them inline (lines 268-330).
   - Recommendation: Extract as private methods on ShareActionButton (`private func videoRenderingView(...)`, `private func batchProcessingView(...)`) to keep the body clean. Match the exact layout from ControlsView to avoid visual regressions.

4. **ThumbnailStripView interaction when sheet is expanded**
   - What we know: ThumbnailStripView is at z=1, sheet is at z=2. When sheet is expanded, the sheet's glass surface covers the thumbnail strip area.
   - What's unclear: Whether the thumbnail strip should be visible through the glass when sheet is expanded (D-17 says "above the sheet on the preview area"), or whether it should be hidden/repositioned to avoid being obscured.
   - Recommendation: Let the glass transparency handle visibility — the Liquid Glass is translucent enough to see the strip through it. If obscurity is a UX issue, the planner can add a slight upward offset to the strip when detent == .expanded. This is a planner's discretion decision, not a blocker.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Xcode | Building all targets | ✓ | 18.x (per STACK.md) | — |
| SwiftUI | All UI rendering | ✓ | iOS 18 SDK | — |
| iOS Simulator / Device | Testing layout | ✓ | iOS 18+ | — |
| WatermarkCore (internal package) | Design system primitives, ControlsView | ✓ | Local (Phase 15-16 output) | — |

**Missing dependencies with no fallback:** None.

**Missing dependencies with fallback:** None.

**Note:** Step 2.6 — all dependencies are Apple system frameworks and the project's own WatermarkCore Swift Package. No external tools, services, or runtimes required. The entire phase is pure SwiftUI code changes.

## Security Domain

> `security_enforcement` is not explicitly disabled in `.planning/config.json`, so it defaults to **enabled**.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|------------------|
| V2 Authentication | No | No authentication in this app (on-device only, no accounts). |
| V3 Session Management | No | No sessions — no server communication. |
| V4 Access Control | No | All processing on-device; no multi-user access control needed. |
| V5 Input Validation | No (for this phase) | This phase changes UI layout only. No new input paths. Existing input validation in ViewModel (config field validation, PNG data validation) is unaffected. |
| V6 Cryptography | No | No cryptographic operations affected by layout changes. |

### Known Threat Patterns for SwiftUI Custom Bottom Sheet

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Gesture hijacking — drag gesture on indicator could interfere with system gestures (home indicator, Control Center) | Denial of Service | DragGesture on the indicator capsule only — does not extend to screen edges where system gestures live. The drag area is small (~36x5pt + padding) and positioned well above the home indicator. |
| Information disclosure via glass transparency — sensitive preview content visible through Liquid Glass even when device is locked or app is backgrounded | Information Disclosure | This is an OS-level concern handled by iOS's app switcher snapshot mechanism. The app's `sceneDidEnterBackground` already obscures content. No additional mitigation needed for this phase. |
| Z-order spoofing — a malicious view injected at high zIndex could overlay the pinned button and intercept taps | Tampering | This is a non-issue for an on-device app with no third-party code injection vectors. All views are compile-time SwiftUI code. No web views, no dynamic view loading. |

## Sources

### Primary (HIGH confidence)
- Apple Developer Documentation — `presentationDetents(_:)` [iOS 16+]: Official API reference for sheet detent control. Confirmed `.height()`, `.fraction()`, `.medium`, `.large` detent types.
- Apple Developer Documentation — `presentationBackgroundInteraction(_:)` [iOS 16.4+]: Official API for enabling background interaction through a presented sheet. Confirmed `.enabled` and `.enabled(upThrough:)` variants.
- Apple Developer Documentation — `interactiveDismissDisabled(_:)` [iOS 15+]: Official API for preventing swipe-to-dismiss on sheets.
- Apple Developer Documentation — `UnevenRoundedRectangle` [iOS 16+]: Official shape API for per-corner radius control. Used for sheet with rounded top + square bottom corners.
- Apple Developer Documentation — `ZStack`, `zIndex(_:)`, `DragGesture`: Official SwiftUI layout and gesture APIs used throughout the custom sheet implementation.
- Phase 15 CONTEXT.md — Design system decisions: `.markepiGlass()` modifier (D-02, D-03), `MarkepiPillBar` component, button vocabulary.
- Phase 16 CONTEXT.md — ControlsView rebuild: shell-agnostic mandate, pill bar section structure, scroll-edge protection.
- Existing codebase: `ContentView.swift` (60/40 split at lines 69-78), `ControlsView.swift` (shareButton extraction target at lines 239-358), `MarkepiGlassModifier.swift`, `MarkepiPillBar.swift`, `WatermarkConfigurable.swift`.

### Secondary (MEDIUM confidence)
- Apple WWDC 2025 — iOS 26 Liquid Glass design system: Sheets automatically adopt Liquid Glass on iOS 26. Our custom sheet uses `.markepiGlass()` which calls `.glassEffect(.regular, in: shape)` on iOS 26 — matching the native behavior. [CITED: multiple developer community summaries]
- Multiple Stack Overflow confirmations — `.sheet` modifier creates a separate UIWindow/presentation layer; views in the presenting hierarchy cannot render above a `.sheet`. [CITED: Stack Overflow #76854001, #77892045, #75254034]
- Apple HIG — Spring animation parameters for interactive gestures: `.spring(response: 0.4, dampingFraction: 0.85)` matches native iOS sheet spring feel.
- Known iOS 18.0-18.1 bug: `presentationBackgroundInteraction` had reliability issues with touch pass-through. Fixed in iOS 18.2. [CITED: multiple developer reports]

### Tertiary (LOW confidence)
- Professional photo-editing app convention (Apple Photos, Lightroom, Darkroom) — these apps use custom bottom sheet implementations, not SwiftUI `.sheet`. [ASSUMED: Based on observable behavior and developer community analysis — not verified by source code access.]
- 50pt drag threshold as "standard iOS sheet detent switch distance." [ASSUMED: Based on empirical observation and community convention — not from official Apple documentation.]

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — Pure SwiftUI + existing WatermarkCore package. No external dependencies. All APIs (ZStack, DragGesture, zIndex, UnevenRoundedRectangle) are well-documented iOS 16+ features.
- Architecture: HIGH — Custom ZStack approach is the only viable solution for D-06 (pinned button above sheet). The `.sheet` limitation is well-documented and verified. Z-order layering is a standard SwiftUI pattern. Detent snap with DragGesture is a well-understood idiom.
- Pitfalls: HIGH — All identified pitfalls are based on verified SwiftUI behaviors (gesture resolution, ZStack clipping, animation glitching patterns). Mitigations are standard approaches.

**Research date:** 2026-06-22
**Valid until:** 2026-08-22 (60 days — stable domain, no expected API changes)
