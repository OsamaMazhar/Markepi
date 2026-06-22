# Phase 17: Inspector Bottom-Sheet Shell - Pattern Map

**Mapped:** 2026-06-22
**Files analyzed:** 5 (2 new, 3 modified)
**Analogs found:** 5 / 5

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `Packages/WatermarkCore/Sources/WatermarkCore/DesignSystem/ShareActionButton.swift` | component | event-driven | `Packages/WatermarkCore/Sources/WatermarkCore/UI/ControlsView.swift` (lines 239-358) | exact — this is the extraction source |
| `Packages/WatermarkCore/Sources/WatermarkCore/UI/InspectorSheetView.swift` | component | event-driven | `Packages/WatermarkCore/Sources/WatermarkCore/DesignSystem/ScrollEdge/MarkepiScrollEdgeProtection.swift` | good — same glass+`if #available` pattern, DragGesture is novel |
| `App/Views/ContentView.swift` | controller | event-driven | `App/Views/ContentView.swift` (lines 127-171, `previewArea` ZStack) | exact — extending existing ZStack layering pattern to full screen |
| `App/Views/PreviewArea/PreviewView.swift` | component | request-response | `App/Views/PreviewArea/PreviewView.swift` (line 94) | exact — single-line safe-area change |
| `Packages/WatermarkCore/Sources/WatermarkCore/UI/ControlsView.swift` | component | request-response | `Packages/WatermarkCore/Sources/WatermarkCore/UI/ControlsView.swift` (lines 152-153, 239-358) | exact — extraction of shareButton reference |

---

## Pattern Assignments

### 1. `Packages/WatermarkCore/Sources/WatermarkCore/DesignSystem/ShareActionButton.swift` (component, event-driven)

**Analog:** `Packages/WatermarkCore/Sources/WatermarkCore/UI/ControlsView.swift` lines 239-358 (the `shareButton` computed property being extracted)

This is the **exact extraction source** — the new file copies the rendering state machine verbatim from ControlsView. The surrounding ControlsView file also provides the structural pattern for how the component is declared (public struct, generic over ViewModel, @State viewModel, @Environment for accessibility).

**Imports pattern** (ControlsView.swift lines 1-2):
```swift
import SwiftUI
import WatermarkCore
```

**Struct declaration pattern** (ControlsView.swift lines 4-15):
```swift
/// public struct with generic constraint on `WatermarkConfigurable & Observable`
public struct ShareActionButton<ViewModel: WatermarkConfigurable & Observable>: View {
    @State var viewModel: ViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public init(viewModel: ViewModel) {
        self.viewModel = viewModel
    }
```

**Core state machine pattern** (ControlsView.swift lines 239-357) — extract this ENTIRE `shareButton` computed property into `body`:
```swift
public var body: some View {
    Group {
        switch viewModel.renderingState {
        case .idle:
            Button {
                Task { await viewModel.renderAndPrepareShare() }
            } label: {
                Label(
                    viewModel.hasMultiplePhotos ? "Watermark All" : "Share",
                    systemImage: viewModel.hasMultiplePhotos ? "square.and.arrow.up.on.square.fill" : "square.and.arrow.up"
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
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .markepiGlass(shape: RoundedRectangle(cornerRadius: 12, style: .continuous),
                          isEnabled: !reduceTransparency)
            .disabled(true)
            .transition(.opacity.combined(with: .scale))

        case .renderingVideo(let progress, let eta):
            // [EXACT lines 268-330 from ControlsView.swift]
            videoRenderingView(progress: progress, eta: eta)

        case .batchProcessing(let current, let total, let eta):
            // [EXACT lines 300-330 from ControlsView.swift]
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
    .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: viewModel.renderingState)
}
```

**Private helper methods** (extracted from ControlsView.swift lines 268-330) — `.renderingVideo` and `.batchProcessing` cases become private methods:
```swift
// Extract lines 268-298 into private method:
private func videoRenderingView(progress: Double, eta: TimeInterval?) -> some View {
    VStack(spacing: 8) {
        HStack(spacing: 12) {
            ProgressView(value: progress, total: 1.0)
                .progressViewStyle(.linear)
                .tint(.blue)
            Text("\(Int(progress * 100))%")
                .font(.caption.weight(.medium))
                .monospacedDigit()
                .frame(width: 36, alignment: .trailing)
        }
        if let eta = eta {
            Text("~\(Int(eta))s remaining")
                .font(.caption2)
                .foregroundStyle(.secondary)
        } else {
            Text("--")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        Button {
            viewModel.cancelProcessing()
        } label: {
            Text("Cancel")
                .frame(maxWidth: .infinity)
                .frame(height: 36)
        }
        .buttonStyle(.markepiSecondary())
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 4)
}

// Extract lines 300-330 into private method:
private func batchProcessingView(current: Int, total: Int, eta: TimeInterval?) -> some View {
    VStack(spacing: 8) {
        HStack(spacing: 12) {
            ProgressView(value: total > 0 ? Double(current) / Double(total) : 0, total: 1.0)
                .progressViewStyle(.linear)
                .tint(.blue)
            Text("\(current)/\(total)")
                .font(.caption.weight(.medium))
                .monospacedDigit()
                .frame(width: 56, alignment: .trailing)
        }
        if let eta = eta, eta > 0 {
            Text("ETA: \(Int(eta / 60)) min")
                .font(.caption2)
                .foregroundStyle(.secondary)
        } else {
            Text("--")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        Button {
            viewModel.cancelProcessing()
        } label: {
            Text("Stop Processing")
                .frame(maxWidth: .infinity)
                .frame(height: 36)
        }
        .buttonStyle(.markepiSecondary())
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 4)
}
```

**DesignSystem component file structure pattern** (PreviewCatalog.swift lines 1-15):
```swift
import SwiftUI

/// Doc comment describing the component's purpose and placement-agnostic contract.
///
/// Generic over `WatermarkConfigurable & Observable` so all three targets can
/// consume it: main app pinned bar, ControlsView inline, extension shells via ControlsView.
public struct ShareActionButton<ViewModel: WatermarkConfigurable & Observable>: View {
    // ...
}
```

**Protocol surface consumed** (WatermarkConfigurable.swift lines 46-66):
```swift
// Methods called by ShareActionButton:
func renderAndPrepareShare() async      // line 48
func presentShareSheet()                // line 51
func cancelProcessing()                 // line 66
// Properties read by ShareActionButton:
var renderingState: RenderingState { get }  // line 20
var hasMultiplePhotos: Bool { get }         // line 33
```

**RenderingState enum** (ProcessingResult.swift lines 55-77) — all cases consumed by the state machine:
```swift
case idle
case rendering
case renderingVideo(progress: Double, estimatedTimeRemaining: TimeInterval?)
case batchProcessing(current: Int, total: Int, eta: TimeInterval?)
case done
case error(Error)
```

---

### 2. `Packages/WatermarkCore/Sources/WatermarkCore/UI/InspectorSheetView.swift` (component, event-driven)

**Analog A (glass + `if #available` pattern):** `MarkepiScrollEdgeProtection.swift` lines 42-78
**Analog B (DragGesture):** No existing DragGesture on view containers in the codebase — greenfield
**Analog C (view-with-ViewModel generic pattern):** `ControlsView.swift` lines 12-35

**Imports pattern** (ControlsView.swift lines 1-2):
```swift
import SwiftUI
import WatermarkCore
```

**Struct declaration + generic constraint** (ControlsView.swift lines 12-14):
```swift
public struct InspectorSheetView<ViewModel: WatermarkConfigurable & Observable>: View {
    @State var viewModel: ViewModel
```

**Detent enum pattern** — define at file scope, matching the project's use of public enums in DesignSystem (ControlsSection in MarkepiPillBar.swift lines 13-19):
```swift
public enum SheetDetent: Equatable {
    case peek      // pill bar + drag indicator only (~60pt)
    case expanded  // half-screen ControlsView
}
```

**Environment accessibility reducers** (ControlsView.swift lines 14-15, MarkepiScrollEdgeProtection.swift line 44):
```swift
@Environment(\.accessibilityReduceMotion) private var reduceMotion
@Environment(\.accessibilityReduceTransparency) private var reduceTransparency
```

**Core glass sheet body pattern** (MarkepiScrollEdgeProtection.swift lines 54-77 for ZStack+glass, MarkepiPillBar.swift lines 77-85 for `.markepiGlass()` usage):
```swift
public var body: some View {
    VStack(spacing: 0) {
        // Drag indicator (D-10)
        RoundedRectangle(cornerRadius: 2.5)
            .fill(Color.secondary.opacity(0.4))
            .frame(width: 36, height: 5)
            .padding(.top, 8)
            .padding(.bottom, 4)
            .gesture(dragGesture)
            .accessibilityLabel("Resize controls")
            .accessibilityHint("Drag up to show all controls, down to minimize")

        // ControlsView unchanged (D-14)
        ControlsView(viewModel: viewModel)
    }
    .frame(maxWidth: .infinity)
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
}
```

**Glass effect API signature** (MarkepiGlassModifier.swift lines 53-75):
```swift
// Call pattern:
.markepiGlass(
    shape: UnevenRoundedRectangle(...),
    isEnabled: !reduceTransparency
)
```

**Drag gesture pattern** — greenfield for this project. Standard SwiftUI DragGesture with snap:
```swift
@State private var dragOffset: CGFloat = 0
@State private var lastDragPosition: CGFloat = 0

private var dragGesture: some Gesture {
    DragGesture()
        .onChanged { value in
            let translation = lastDragPosition + value.translation.height
            if detent == .peek && translation < -10 {
                let progress = min(abs(translation) / (expandedHeight - peekHeight), 1.0)
                dragOffset = -progress * (expandedHeight - peekHeight)
            } else if detent == .expanded && translation > 10 {
                let progress = min(translation / (expandedHeight - peekHeight), 1.0)
                dragOffset = -progress * (expandedHeight - peekHeight)
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
```

**Spring animation pattern** — matching project conventions (MarkepiPillBar.swift line 58):
```swift
withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { ... }  // PillBar uses this
// InspectorSheet uses slightly slower:
.animation(.spring(response: 0.4, dampingFraction: 0.85), value: detent)
```

**`@State` + `@Binding` ownership pattern** (MarkepiPillBar.swift lines 45-52):
```swift
// Bindings for state owned by parent (detent) + local state (dragOffset, lastDragPosition):
public struct InspectorSheetView<ViewModel: WatermarkConfigurable & Observable>: View {
    @Binding var detent: SheetDetent       // owned by ContentView
    let peekHeight: CGFloat                 // constant from parent
    @State var viewModel: ViewModel
    @State private var dragOffset: CGFloat = 0
    @State private var lastDragPosition: CGFloat = 0
```

---

### 3. `App/Views/ContentView.swift` (controller, event-driven)

**Analog for ZStack layering:** `ContentView.swift` lines 127-171 (`previewArea` ZStack already demonstrates multi-layer ZStack with conditional children)

**Analog for the restructured layout:** The existing ContentView provides the complete pattern for state management, toolbar, modifier groups, and sheet presentations — all of which are preserved. Only the `mainLayout` function and related computed properties change.

**Existing imports** (ContentView.swift lines 1-4) — unchanged:
```swift
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import WatermarkCore
```

**Existing @State properties** (ContentView.swift lines 13-20) — add new detent/drag state, keep existing:
```swift
struct ContentView: View {
    @State var viewModel: WatermarkViewModel
    @State private var showFileImporter = false

    // Batch processing UI state — KEEP ALL EXISTING
    @State private var selectedItemForOverride: IdentifiableIndex? = nil
    @State private var showBatchCancelConfirmation: Bool = false
    @State private var showResetOverridesConfirmation: Bool = false
    @State private var showBatchResultAlert: Bool = false

    // NEW: Sheet detent state
    @State private var detent: SheetDetent = .peek
    @State private var sheetDragOffset: CGFloat = 0
    @State private var lastSheetDragPosition: CGFloat = 0

    // Derived constant
    private let peekDetentHeight: CGFloat = 60
```

**ZStack layering pattern** — extending the existing `previewArea` ZStack (lines 127-171) to the full screen. The existing ZStack already shows the pattern of:
- Base content (preview) at z=0
- Conditional overlays (thumbnail strip, batch progress) on top
- Decorative elements (plus button) at highest z-index

```swift
// NEW mainLayout replacing lines 69-93:
private func mainLayout(_ geometry: GeometryProxy) -> some View {
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
    .task(id: viewModel.previewIdentifier) { ... }  // KEEP existing task/onChange
    .onChange(of: viewModel.currentIndex) { ... }    // KEEP existing
    .onChange(of: viewModel.renderingState) { ... }   // KEEP existing
}
```

**Existing previewArea ZStack** (lines 127-171) — preserved with preview only (batch overlays move to root ZStack):
```swift
private var previewArea: some View {
    ZStack(alignment: .bottom) {
        PreviewView(viewModel: viewModel)

        // Batch overlays REMOVED from here — moved to root ZStack z=1

        // Plus button — KEEP in previewArea
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
```

**Existing toolbar pattern** (lines 97-123) — KEEP ENTIRELY UNCHANGED:
```swift
@ToolbarContentBuilder
private var toolbarContent: some ToolbarContent { ... }
```

**Existing modifier groups** (lines 180-331) — KEEP ALL THREE ENTIRELY UNCHANGED:
```swift
private struct AlertModifiers: ViewModifier { ... }      // lines 183-210
private struct BatchAlertModifiers: ViewModifier { ... }  // lines 213-257
private struct SheetModifiers: ViewModifier { ... }        // lines 261-331
```

**Existing body structure** (lines 22-64) — preserves NavigationStack wrapper, GeometryReader, all modifiers:
```swift
var body: some View {
    NavigationStack {
        GeometryReader { geometry in
            mainLayout(geometry)         // CHANGED: now ZStack-based
                .toolbar { toolbarContent }
                .photosPicker(...)       // KEEP
                .fileImporter(...)       // KEEP
                .onAppear { ... }        // KEEP
        }
        .modifier(AlertModifiers(...))       // KEEP
        .modifier(BatchAlertModifiers(...))  // KEEP
        .modifier(SheetModifiers(...))       // KEEP
    }
}
```

**REMOVED:** The `controlsArea` computed property (lines 175-177) — ControlsView now lives inside the inspector sheet.

---

### 4. `App/Views/PreviewArea/PreviewView.swift` (component, request-response)

**Analog:** The file itself at line 94 — single-line safe-area change.

**Existing pattern** (PreviewView.swift lines 93-94):
```swift
.frame(maxWidth: .infinity, maxHeight: .infinity)
.edgesIgnoringSafeArea(.top)
```

**Change to:**
```swift
.frame(maxWidth: .infinity, maxHeight: .infinity)
.ignoresSafeArea()
```

The rest of PreviewView.swift (lines 1-143) is unchanged — all gesture handling, comparison overlay, zoom accessibility, and picker button remain intact.

---

### 5. `Packages/WatermarkCore/Sources/WatermarkCore/UI/ControlsView.swift` (component, request-response)

**Analog:** The file itself at lines 152-153 — replace `shareButton` reference with `ShareActionButton`.

**Existing pattern** (ControlsView.swift lines 148-153):
```swift
ControlSection {
    saveTemplateButton
}

shareButton
    .padding(.horizontal, 16)
```

**Change to:**
```swift
ControlSection {
    saveTemplateButton
}

ShareActionButton(viewModel: viewModel)
    .padding(.horizontal, 16)
```

The `shareButton` computed property (lines 239-358) is REMOVED entirely — its logic now lives in `ShareActionButton.swift`.

The rest of ControlsView.swift (lines 1-237, 359-390) is unchanged — the shell-agnostic mandate (D-14) is strictly preserved. The struct declaration, section content, ControlSection, and all other computed properties remain as-is.

---

## Shared Patterns

### ViewModel Generic Constraint
**Source:** `ControlsView.swift` lines 12-13
**Apply to:** `ShareActionButton.swift`, `InspectorSheetView.swift`
```swift
public struct ComponentName<ViewModel: WatermarkConfigurable & Observable>: View {
    @State var viewModel: ViewModel
```

### Liquid Glass + iOS 26 Fallback
**Source:** `MarkepiGlassModifier.swift` lines 36-50, `MarkepiScrollEdgeProtection.swift` lines 67-75
**Apply to:** `InspectorSheetView.swift`, `ContentView.swift` (pinned share bar)
```swift
.markepiGlass(
    shape: <some Shape>,
    isEnabled: !reduceTransparency
)
```
The modifier internally handles `if #available(iOS 26, *)` — no availability checks needed at call sites.

### Accessibility: Reduce Transparency / Reduce Motion
**Source:** `ControlsView.swift` lines 14-15, `MarkepiPillBar.swift` line 48
**Apply to:** `ShareActionButton.swift`, `InspectorSheetView.swift`
```swift
@Environment(\.accessibilityReduceMotion) private var reduceMotion
@Environment(\.accessibilityReduceTransparency) private var reduceTransparency
```

### System-Adaptive Colors
**Source:** `MarkepiButtonStyle.swift` lines 77-87
**Apply to:** All new views (drag indicator, sheet chrome, pinned bar)
```swift
// D-13: All colors use system-adaptive semantic colors:
.foregroundStyle(.primary)    // or .secondary, .accentColor
// Never hardcode: no Color(hex:), no Color.white/black
```

### Spring Animation Convention
**Source:** `MarkepiPillBar.swift` line 58
**Apply to:** `InspectorSheetView.swift` detent snap animation
```swift
withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
// InspectorSheet uses slightly slower: response: 0.4, dampingFraction: 0.85
```

### Button Style Extensions
**Source:** `MarkepiButtonStyle.swift` lines 91-125
**Apply to:** `ShareActionButton.swift` button states
```swift
.buttonStyle(.markepiPrimary())      // idle + done states
.buttonStyle(.markepiSecondary())    // error + cancel buttons
```

### Typography
**Source:** `MarkepiTypography.swift` lines 100-107
**Apply to:** Any new text labels in InspectorSheetView or ShareActionButton
```swift
.markepiTypography(.controlLabel)
.markepiTypography(.value)
```

---

## No Analog Found

None — all files have strong analogs in the existing codebase.

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| — | — | — | All files have exact or strong analogs. The DragGesture in InspectorSheetView is greenfield, but the glass effect and generic ViewModel patterns are well-established. |

---

## Metadata

**Analog search scope:** `App/Views/`, `Packages/WatermarkCore/Sources/WatermarkCore/DesignSystem/`, `Packages/WatermarkCore/Sources/WatermarkCore/UI/`, `ShareExtension/`
**Files scanned:** 12
**Pattern extraction date:** 2026-06-22
**Key insights:**
1. **ShareActionButton** is a pure extraction — copy ControlsView lines 239-358 verbatim, wrap in public struct with ViewModel generic constraint. Zero behavioral changes.
2. **InspectorSheetView** combines patterns from ControlsView (generic ViewModel), MarkepiScrollEdgeProtection (glass+`if #available`), and MarkepiPillBar (spring animation). DragGesture is greenfield but follows standard SwiftUI conventions.
3. **ContentView** restructuring extends the existing `previewArea` ZStack pattern to the full screen — the codebase already demonstrates multi-layer ZStack with conditional children.
4. **PreviewView** and **ControlsView** modifications are single-line changes — no new patterns needed.
