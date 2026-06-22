# Phase 16: Redesigned Controls - Pattern Map

**Mapped:** 2026-06-21
**Files analyzed:** 9 new/modified files (7 refactored, 1 replaced, 1 extension)
**Analogs found:** 9 / 9

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `Packages/WatermarkCore/Sources/WatermarkCore/UI/ControlsView.swift` | component | request-response (binding + event-driven) | `MarkepiScrollEdgeProtection.swift` usage pattern + current `ControlsView.swift` | exact |
| `Packages/WatermarkCore/Sources/WatermarkCore/UI/TextWatermarkInputView.swift` | component | request-response (binding) | Current `TextWatermarkInputView.swift` | exact (self-refactor) |
| `Packages/WatermarkCore/Sources/WatermarkCore/UI/ScaleStepperView.swift` | component | request-response (binding) | Current `ScaleStepperView.swift` | exact (self-refactor) |
| `Packages/WatermarkCore/Sources/WatermarkCore/UI/LogoPickerView.swift` | component | request-response (binding + file picker) | Current `LogoPickerView.swift` + `SignatureCaptureView.swift` (add/selected/remove pattern) | exact (self-refactor) |
| `Packages/WatermarkCore/Sources/WatermarkCore/UI/SignatureCaptureView.swift` | component | request-response (binding + modal sheet) | Current `SignatureCaptureView.swift` | exact (self-refactor) |
| `Packages/WatermarkCore/Sources/WatermarkCore/UI/WhiteFrameToggleView.swift` | component | request-response (binding) | Current `WhiteFrameToggleView.swift` | exact (self-refactor) |
| `Packages/WatermarkCore/Sources/WatermarkCore/UI/LayerListView.swift` | component | request-response (binding) | Current `LayerListView.swift` | exact (self-refactor) |
| `Packages/WatermarkCore/Sources/WatermarkCore/UI/PositionGridView.swift` | component | request-response (binding) | **REPLACED** — inline Menu in ControlsView (Pattern 1 from RESEARCH.md) | N/A (replaced) |
| `Packages/WatermarkCore/Sources/WatermarkCore/Models/WatermarkPosition.swift` | model | static data (no flow) | Current `WatermarkPosition.swift` | exact (extension only) |

## Pattern Assignments

---

### `ControlsView.swift` (component, request-response + event-driven)

**Analog:** Current `ControlsView.swift` lines 1-280 + `MarkepiScrollEdgeProtection.swift` lines 42-83 + `MarkepiPillBar.swift` lines 1-86

**Imports pattern** (lines 1-2 of current):
```swift
import SwiftUI
import WatermarkCore
```
No change needed — imports stay the same.

**Generic signature and struct declaration** (lines 12-13 of current):
```swift
/// Composite view combining all watermarking controls...
/// Generic over any `WatermarkConfigurable & Observable` ViewModel...
public struct ControlsView<ViewModel: WatermarkConfigurable & Observable>: View {
    @State var viewModel: ViewModel
```
**FROZEN** — stays the same. Add `@Environment(\.accessibilityReduceTransparency)` alongside existing `@Environment(\.accessibilityReduceMotion)`.

**Section state and pill bar insertion** — NEW pattern from `MarkepiPillBar.swift` lines 45-86:
```swift
    @State private var section: ControlsSection = .watermark
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
```
Replace the current `ScrollView(.vertical)` wrapper (lines 34-62) with `MarkepiScrollEdgeProtection`:
```swift
    public var body: some View {
        VStack(spacing: 0) {  // ← NO ScrollView here — MarkepiScrollEdgeProtection creates its own
            switch section {
            case .watermark:
                watermarkSectionContent
            case .style:
                styleSectionContent
            case .output:
                outputSectionContent
            }
        }
        .markepiScrollEdgeProtection {  // ← from MarkepiScrollEdgeProtection.swift lines 87-103
            MarkepiPillBar(selection: $section)  // ← from MarkepiPillBar.swift lines 45-86
        }
    }
```

**HDR→JPEG alert** (lines 115-125 of current — MUST BE PRESERVED):
```swift
        .alert("HDR Will Be Lost", isPresented: $showHDRLossWarning) {
            Button("Convert to JPEG") {
                pendingFormatSelection = .preserveSource
            }
            Button("Cancel", role: .cancel) {
                viewModel.config.outputFormat = .preserveSource
            }
        } message: {
            Text("JPEG does not support HDR. The image will be converted to standard dynamic range.")
        }
```
Attach this `.alert(...)` to the output section container, NOT the old DisclosureGroup (which is being removed).

**Share button state machine** (lines 128-264 of current):
```swift
    private var shareButton: some View {
        Group {
            switch viewModel.renderingState {
            case .idle:
                Button { Task { await viewModel.renderAndPrepareShare() } } label: {
                    Label(isBatchMode ? "Watermark All" : "Share",
                          systemImage: isBatchMode ? "square.and.arrow.up.on.square.fill" : "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.markepiPrimary())  // ← was .borderedProminent

            case .rendering:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.regular)
                    Text("Rendering...").markepiTypography(.controlLabel)
                }
                .frame(maxWidth: .infinity).frame(height: 50)
                .markepiGlass(shape: RoundedRectangle(cornerRadius: 12, style: .continuous),
                              isEnabled: !reduceTransparency)
                .disabled(true)

            case .renderingVideo(let progress, let eta):
                // Keep existing video progress UI structure; restyle:
                // - .progressViewStyle(.linear) + .tint(.blue) → stays
                // - Cancel button uses .markepiSecondary() per D-10
                // - Cancel label: Text("Cancel") — text-only per D-11 secondary

            case .batchProcessing(let current, let total, let eta):
                // Keep existing batch progress UI structure; restyle:
                // - Cancel button uses .markepiSecondary() per D-10
                // - Cancel label: Text("Stop Processing") — text-only per D-11 secondary

            case .done:
                Button { viewModel.presentShareSheet() } label: {
                    Label(isBatchMode ? "Ready to Share All" : "Ready to Share",
                          systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.markepiPrimary())  // ← was .borderedProminent .tint(.green)

            case .error:
                Button { Task { await viewModel.renderAndPrepareShare() } } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.markepiSecondary())  // ← was .bordered .tint(.orange)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: viewModel.renderingState)
    }
```

**Save-as-template button** (lines 266-279 of current):
```swift
    private var saveTemplateButton: some View {
        Button { viewModel.showSaveTemplateAlert = true } label: {
            Label("Save as Template", systemImage: "square.and.arrow.down.on.square")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.markepiSecondary())  // ← was .bordered .tint(.accentColor)
    }
```

**Error handling pattern** (from `WatermarkConfigurable.swift` lines 79-92 for invalid inputs):
No central error handler in ControlsView — errors are surfaced through the ViewModel's `errorMessage`/`showError` properties. Preserve this pattern. The existing `.alert("HDR Will Be Lost"...)` is the only alert; no try/catch in ControlsView — all async work is in the ViewModel.

---

### `TextWatermarkInputView.swift` (component, request-response binding)

**Analog:** Current `TextWatermarkInputView.swift` lines 1-95

**Imports pattern** (lines 1-5):
```swift
import SwiftUI
import WatermarkCore
#if canImport(UIKit)
import UIKit
#endif
```
Keep all imports.

**Generic signature and struct declaration** (lines 11-16):
```swift
public struct TextWatermarkInputView<ViewModel: WatermarkConfigurable & Observable>: View {
    @Bindable var viewModel: ViewModel

    public init(viewModel: ViewModel) {
        self.viewModel = viewModel
    }
```
**FROZEN** — stays the same.

**Current body** (lines 36-63) — the old style:
```swift
    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Watermark Text")
                .font(.title3.weight(.semibold))  // ← replace with .markepiTypography(.sectionHeader)
            ...
        }
    }
```

**New inset grouped row pattern** (D-06, D-08):
```swift
    public var body: some View {
        VStack(spacing: 0) {
            // Header
            Text("Text")
                .markepiTypography(.sectionHeader)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

            // Row container with glass backing
            VStack(spacing: 0) {
                // Text input row — control label + text editor
                VStack(alignment: .leading, spacing: 4) {
                    Text("Watermark Text")
                        .markepiTypography(.controlLabel)
                    ZStack(alignment: .topLeading) {
                        if currentText.isEmpty {
                            Text("Type your watermark...")
                                .foregroundColor(placeholderColor)
                                .markepiTypography(.metadata)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 8)
                        }
                        TextEditor(text: textBinding)
                            .font(.body)
                            .frame(minHeight: 80, maxHeight: 120)
                            .scrollContentBackground(.hidden)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .markepiGlass(
                shape: RoundedRectangle(cornerRadius: 12, style: .continuous),
                isEnabled: !reduceTransparency
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 16)
        }
    }
```
Add `@Environment(\.accessibilityReduceTransparency) private var reduceTransparency` to the struct.

**Core binding pattern** (lines 73-94) — **FROZEN**, unchanged:
```swift
    private var textBinding: Binding<String> {
        Binding(
            get: { currentText },
            set: { newValue in
                guard var layer = viewModel.config.watermarks.first,
                      case let .text(input, position, scale, opacity, isVisible) = layer else { return }
                let truncated = String(newValue.prefix(500))
                viewModel.config.watermarks[0] = .text(
                    TextWatermarkInput(text: truncated, fontSize: input.fontSize,
                                       color: input.color, opacity: input.opacity),
                    position: position, scale: scale, opacity: opacity, isVisible: isVisible
                )
            }
        )
    }
```

**Accessibility preservation (Pitfall 4):** Current has no explicit accessibility labels on TextEditor itself. Keep text-related VoiceOver implicit behavior. The label "Text" / "Watermark Text" is implicit.

---

### `ScaleStepperView.swift` (component, request-response binding)

**Analog:** Current `ScaleStepperView.swift` lines 1-56

**Imports pattern** (lines 1-2):
```swift
import SwiftUI
import WatermarkCore
```
Keep.

**Generic signature** (lines 7-12) — **FROZEN**.

**Current body** (lines 20-43) — old style with raw `.font()` and `.foregroundStyle(.secondary)`:
```swift
    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Scale")
                .font(.title3.weight(.semibold))  // ← replace with .markepiTypography(.sectionHeader)

            HStack {
                Text("Scale: \(Int(currentScale * 100))%")
                    .font(.body)                        // ← replace
                    .foregroundStyle(.secondary)       // ← replace
                Spacer()
                Stepper("", value: scaleBinding, in: 0.01...0.90, step: 0.05)
                    .labelsHidden()
            }
        }
        .accessibilityLabel("Watermark scale")
        .accessibilityHint("Adjust watermark size. Current value: \(Int(currentScale * 100)) percent")
    }
```

**New inset grouped row pattern** (D-06, D-08):
```swift
    public var body: some View {
        // Single row inside the parent section container
        HStack {
            Text("Scale")
                .markepiTypography(.controlLabel)
            Spacer()
            Text("\(Int(currentScale * 100))%")
                .markepiTypography(.value)  // monospacedDigit automatically
            Stepper("", value: scaleBinding, in: 0.01...0.90, step: 0.05)
                .labelsHidden()
                .frame(width: 100)  // Compact stepper
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityLabel("Watermark scale")
        .accessibilityHint("Adjust watermark size. Current value: \(Int(currentScale * 100)) percent")
    }
```
Note: The ScaleStepperView no longer wraps itself in a glass container — it's a single row that will be placed inside a `ControlSection` by the parent ControlsView.

**Core binding pattern** (lines 50-55) — **FROZEN**:
```swift
    private var scaleBinding: Binding<CGFloat> {
        Binding(
            get: { currentScale },
            set: { viewModel.updateLayerScale(at: layerIndex, scale: $0) }
        )
    }
```

---

### `LogoPickerView.swift` (component, request-response binding + file picker)

**Analog:** Current `LogoPickerView.swift` lines 1-120

**Imports pattern** (lines 1-5):
```swift
import CoreImage
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import WatermarkCore
```
Keep all imports.

**Two-state body pattern** (lines 21-31): Add logo button vs. selected logo view. **FROZEN** pattern — only restyle buttons.

**Current buttons (lines 84-96 and 98-119):**
```swift
    // Add logo — currently .buttonStyle(.bordered)
    private var addLogoButton: some View {
        Button { showConfirmationDialog = true } label: {
            HStack {
                Image(systemName: "photo.badge.plus")
                Text("Add Logo")
            }
        }
        .buttonStyle(.bordered)  // ← replace with .markepiPrimary()
    }

    // Logo selected state:
    private var logoSelectedView: some View {
        HStack {
            Image(systemName: "photo").foregroundStyle(.secondary)
            Text("Logo").font(.body).foregroundStyle(.primary)
            Spacer()
            Button {
                if let index = logoLayerIndex { viewModel.removeLayer(at: index) }
            } label: {
                Text("Remove").font(.body).foregroundStyle(.red)  // ← text-only, destructive
            }
        }
    }
```

**New button styling per D-10/D-11:**
```swift
    // D-10: Add Logo = .primary role
    // D-11: .primary = icon + text (SF Symbol + label)
    private var addLogoButton: some View {
        Button { showConfirmationDialog = true } label: {
            Label("Add Logo", systemImage: "photo.badge.plus")
        }
        .buttonStyle(.markepiPrimary())  // ← was .bordered
        .accessibilityLabel("Add logo watermark")
        .accessibilityHint("Choose a logo image from your photo library or files")
    }

    // D-10: Remove = .destructive role
    // D-11: .destructive = text-only
    private var logoSelectedView: some View {
        HStack {
            Image(systemName: "photo").foregroundStyle(.secondary).frame(width: 24)
            Text("Logo").markepiTypography(.controlLabel)
            Spacer()
            Button {
                if let index = logoLayerIndex { viewModel.removeLayer(at: index) }
            } label: {
                Text("Remove").font(.body)  // text-only, destructive color applied by .markepiDestructive()
            }
            .buttonStyle(.markepiDestructive())  // ← was .foregroundStyle(.red)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
```

**PhotosPicker + fileImporter flow** (lines 41-67) — **FROZEN**, no changes. Only restyle the presentation buttons.

**Accessibility preservation:** Keep lines 94-95 (add button labels) and preserve the add/remove button semantics.

---

### `SignatureCaptureView.swift` (component, request-response binding + modal sheet)

**Analog:** Current `SignatureCaptureView.swift` lines 1-279

**Imports pattern** (lines 1-7) — **FROZEN**.

**Two-state body pattern** (lines 30-44): Add signature button vs. selected signature view. **FROZEN** — restyle only.

**Current buttons (lines 64-76 and 78-108):**
```swift
    // Add signature — currently .buttonStyle(.bordered)
    private var addSignatureButton: some View {
        Button { showCaptureSheet = true } label: {
            HStack {
                Image(systemName: "signature")
                Text("Add Signature")
            }
        }
        .buttonStyle(.bordered)  // ← replace with .markepiPrimary()
    }

    // Signature selected: Edit (.blue) + Remove (.red)
    private var signatureSelectedView: some View {
        HStack {
            Image(systemName: "signature").foregroundStyle(.secondary)
            Text("Signature").font(.body).foregroundStyle(.primary)
            Spacer()
            Button { showCaptureSheet = true } label: {
                Text("Edit").font(.body).foregroundStyle(.blue)  // ← replace
            }
            Button {
                if let index = signatureLayerIndex {
                    withAnimation(.easeOut(duration: 0.25)) { viewModel.removeLayer(at: index) }
                }
            } label: {
                Text("Remove").font(.body).foregroundStyle(.red)  // ← replace
            }
        }
    }
```

**New button styling per D-10/D-11:**
```swift
    // D-10: Add Signature = .primary role
    // D-11: .primary = icon + text
    private var addSignatureButton: some View {
        Button { showCaptureSheet = true } label: {
            Label("Add Signature", systemImage: "signature")
        }
        .buttonStyle(.markepiPrimary())  // ← was .bordered
        .accessibilityLabel("Add signature watermark")
        .accessibilityHint("Open the signature capture canvas to draw your signature")
    }

    // D-10: Edit Signature = .primary role
    // D-11: .primary = icon + text
    private var signatureSelectedView: some View {
        HStack {
            Image(systemName: "signature").foregroundStyle(.secondary).frame(width: 24)
            Text("Signature").markepiTypography(.controlLabel)
            Spacer()
            Button { showCaptureSheet = true } label: {
                Label("Edit", systemImage: "pencil")
            }
            .buttonStyle(.markepiPrimary())  // ← was .foregroundStyle(.blue)
            .labelStyle(.iconAndText)

            Button {
                if let index = signatureLayerIndex {
                    withAnimation(.easeOut(duration: 0.25)) { viewModel.removeLayer(at: index) }
                }
            } label: {
                Text("Remove")  // text-only per D-11 destructive
            }
            .buttonStyle(.markepiDestructive())  // ← was .foregroundStyle(.red)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
```

**Signature capture sheet** (lines 113-186) — **FROZEN**. The PencilKit canvas and toolbar are not restyled in this phase.

**Accessibility preservation:** Keep lines 74-75 (add button) and the PencilKit canvas implicit accessibility.

---

### `WhiteFrameToggleView.swift` (component, request-response binding)

**Analog:** Current `WhiteFrameToggleView.swift` lines 1-34

**Imports pattern** (lines 1-2) — **FROZEN**.

**Generic signature** (lines 7-12) — **FROZEN**.

**Current body** (lines 14-33) — has its own VStack with raw fonts:
```swift
    public var body: some View {
        let isEnabled = viewModel.whiteFrameEnabled
        return VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: Binding(
                get: { isEnabled },
                set: { viewModel.setWhiteFrameEnabled($0) }
            )) {
                Text("White Frame")
                    .font(.title3.weight(.semibold))  // ← replace with .markepiTypography(.controlLabel)
            }
            Text("Adds a white border with device name")
                .font(.caption)              // ← replace with .markepiTypography(.metadata)
                .foregroundStyle(.secondary) // ← metadata already applies .secondary foreground
        }
        .accessibilityLabel("White frame")
        .accessibilityHint("Add a white border with device model text to your photo")
    }
```

**New inset grouped row pattern** (D-06, D-08):
```swift
    public var body: some View {
        let isEnabled = viewModel.whiteFrameEnabled
        // Single row — placed inside parent ControlSection container
        VStack(spacing: 0) {
            Toggle(isOn: Binding(
                get: { isEnabled },
                set: { viewModel.setWhiteFrameEnabled($0) }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("White Frame")
                        .markepiTypography(.controlLabel)     // ← was .font(.title3.weight(.semibold))
                    Text("Adds a white border with device name")
                        .markepiTypography(.metadata)         // ← was .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .accessibilityLabel("White frame")
        .accessibilityHint("Add a white border with device model text to your photo")
    }
```

**Core toggle logic** (lines 19-25) — **FROZEN**. Uses `setWhiteFrameEnabled(_:)` idempotent setter (from `WatermarkConfigurable.swift` lines 145-155).

**Accessibility preservation:** Keep lines 31-32.

---

### `LayerListView.swift` (component, request-response binding)

**Analog:** Current `LayerListView.swift` lines 1-91

**Imports pattern** (lines 1-2) — **FROZEN**.

**Generic signature** (lines 7-12) — **FROZEN**.

**Current body** (lines 14-35) — has `.background(.regularMaterial)` and raw fonts:
```swift
    public var body: some View {
        if viewModel.config.watermarks.isEmpty { EmptyView() }
        else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Watermark Layers")
                    .font(.title3.weight(.semibold))  // ← replace with .markepiTypography(.sectionHeader)

                VStack(spacing: 0) {
                    ForEach(Array(viewModel.config.watermarks.enumerated()), id: \.offset) { index, layer in
                        layerRow(index: index, layer: layer)
                            .transition(.opacity.combined(with: .move(edge: .trailing)))
                        if index < viewModel.config.watermarks.count - 1 {
                            Divider()
                        }
                    }
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))  // ← replace with .markepiGlass
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }
```

**New styling** (D-06, D-08):
```swift
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public var body: some View {
        if viewModel.config.watermarks.isEmpty { EmptyView() }
        else {
            VStack(spacing: 0) {
                // Section header
                Text("Layers")
                    .markepiTypography(.sectionHeader)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)

                // Row container with glass backing
                VStack(spacing: 0) {
                    ForEach(Array(viewModel.config.watermarks.enumerated()), id: \.offset) { index, layer in
                        layerRow(index: index, layer: layer)
                            .transition(.opacity.combined(with: .move(edge: .trailing)))
                        if index < viewModel.config.watermarks.count - 1 {
                            Divider()
                                .padding(.leading, 52)  // align with text after icon (Pitfall 2)
                        }
                    }
                }
                .markepiGlass(
                    shape: RoundedRectangle(cornerRadius: 12, style: .continuous),
                    isEnabled: !reduceTransparency
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 16)
            }
        }
    }
```

**Layer row with active-layer highlight** (lines 37-70) — refactored for D-06 row styling:
```swift
    @ViewBuilder
    private func layerRow(index: Int, layer: WatermarkLayer) -> some View {
        Button {
            viewModel.activeLayerIndex = index
        } label: {
            HStack(spacing: 12) {
                Image(systemName: layerIcon(for: layer))
                    .foregroundStyle(viewModel.activeLayerIndex == index ? .accentColor : .secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(layerTypeName(for: layer))
                        .markepiTypography(.controlLabel)
                    Text(layerSubtitle(for: layer))
                        .markepiTypography(.metadata)
                        .lineLimit(1)
                }

                Spacer()

                // D-10: Remove Layer = .destructive, icon-only (red X) per D-11
                Button {
                    withAnimation(.easeOut(duration: 0.25)) {
                        viewModel.removeLayer(at: index)
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.markepiDestructive())  // ← was .foregroundStyle(.red)
                .frame(width: 44, height: 44)
                .accessibilityLabel("Remove layer: \(layerDescription(for: layer))")
                .accessibilityHint("Double tap to remove this watermark layer")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                viewModel.activeLayerIndex == index
                    ? Color.accentColor.opacity(0.08)
                    : Color.clear
            )
        }
        .buttonStyle(.plain)  // The main row button should be plain (not Markepi styled)
    }
```

**Accessibility preservation (Pitfall 4):** Keep lines 64-65 (remove button accessibility labels).

---

### `PositionGridView.swift` — REPLACED (component, request-response binding)

**Status:** **DELETED** — Entire file replaced by inline `Menu` in ControlsView.

**Analog:** RESEARCH.md Pattern 1 (lines 200-247) + `WatermarkPosition.swift` (all 9 case names).

**Replacement code** (goes inside ControlsView as a `private var positionMenuRow`):
```swift
    /// Inline position picker Menu replacing PositionGridView.
    /// D-01: Single button showing current position name with disclosure arrow.
    /// D-02: Menu lists all 9 position names as plain text items.
    /// D-03: Underlying `updateLayerPosition(at:position:)` behavior unchanged.
    private var positionMenuRow: some View {
        let idx = max(0, min(viewModel.activeLayerIndex, viewModel.config.watermarks.count - 1))
        let currentPos = viewModel.config.watermarks.indices.contains(idx)
            ? viewModel.config.watermarks[idx].position : WatermarkPosition.center

        return HStack {
            Text("Position")
                .markepiTypography(.controlLabel)
            Spacer()
            Menu {
                ForEach(WatermarkPosition.allCases, id: \.rawValue) { position in
                    Button(position.displayName) {
                        viewModel.updateLayerPosition(at: idx, position: position)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(currentPos.displayName)
                        .markepiTypography(.value)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityLabel("Watermark position, currently \(currentPos.displayName)")
            .accessibilityHint("Double tap to choose a different position")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
```

**Required `displayName` extension** (added to WatermarkPosition.swift):
```swift
// Located at the end of WatermarkPosition.swift (after line 80)
extension WatermarkPosition {
    /// Human-readable display name for the 9-position picker Menu.
    /// Maps rawValue enum cases to natural language labels.
    var displayName: String {
        switch self {
        case .topLeft: return "Top Left"
        case .topCenter: return "Top Center"
        case .topRight: return "Top Right"
        case .middleLeft: return "Middle Left"
        case .center: return "Center"
        case .middleRight: return "Middle Right"
        case .bottomLeft: return "Bottom Left"
        case .bottomCenter: return "Bottom Center"
        case .bottomRight: return "Bottom Right"
        }
    }
}
```

---

### `WatermarkPosition.swift` (model, static data — extension only)

**Analog:** Current `WatermarkPosition.swift` lines 1-80

**Addition only** — append the `displayName` extension (shown above) after line 80. No existing code is modified.

**Existing pattern reference:** The enum already conforms to `CaseIterable` (line 13), which the Menu `ForEach` iterates over. The `rawValue: String` is used as the `id` in the ForEach.

---

## Shared Patterns

### ViewModel Binding Pattern (all sub-views)
**Source:** All current sub-view files (e.g., `TextWatermarkInputView.swift` lines 11-16, `ScaleStepperView.swift` lines 7-12, `LogoPickerView.swift` lines 10-19)
**Apply to:** All 7 sub-view files
```swift
public struct SomeView<ViewModel: WatermarkConfigurable & Observable>: View {
    @Bindable var viewModel: ViewModel

    public init(viewModel: ViewModel) {
        self.viewModel = viewModel
    }
```
**FROZEN** — no changes to this pattern. All sub-views are generic over `WatermarkConfigurable & Observable` with `@Bindable var viewModel`.

### Inset Grouped Row Container (D-06)
**Source:** RESEARCH.md Pattern 2 (lines 295-341) + `LayerListView.swift` lines 31-33 (existing `.background(.regularMaterial, in: RoundedRectangle)` pattern)
**Apply to:** ControlsView section content builders (watermarkSectionContent, styleSectionContent, outputSectionContent)
```swift
/// A reusable section container with glass backing.
private struct ControlSection<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .markepiGlass(
            shape: RoundedRectangle(cornerRadius: 12, style: .continuous),
            isEnabled: !reduceTransparency
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 16)
    }
}
```

### MarkepiButtonStyle Application (CTL-08, D-09/D-10/D-11)
**Source:** `MarkepiButtonStyle.swift` lines 1-126
**Apply to:** Every Button in ControlsView and all sub-views
```swift
// Primary: icon + text       (Label or HStack{Image+Text})
// Secondary: text-only or icon+text per context
// Destructive: text-only     (Text("Remove"))
// Layer remove: icon-only    (Image(systemName: "xmark.circle.fill"))
```

| Button | Old Style | New Style | Label Pattern |
|--------|-----------|-----------|---------------|
| Share / Watermark All (.idle) | `.borderedProminent` | `.markepiPrimary()` | icon + text |
| Ready to Share (.done) | `.borderedProminent .tint(.green)` | `.markepiPrimary()` | icon + text |
| Retry (.error) | `.bordered .tint(.orange)` | `.markepiSecondary()` | icon + text |
| Cancel (.renderingVideo) | `Button(role:.destructive) + .bordered .tint(.red)` | `.markepiSecondary()` | text-only |
| Stop Processing (.batch) | `Button(role:.destructive) + .bordered .tint(.red)` | `.markepiSecondary()` | text-only |
| Add Logo | `.bordered` | `.markepiPrimary()` | icon + text |
| Add Signature | `.bordered` | `.markepiPrimary()` | icon + text |
| Edit Signature | `.foregroundStyle(.blue)` | `.markepiPrimary()` | icon + text |
| Remove Logo | `.foregroundStyle(.red)` | `.markepiDestructive()` | text-only |
| Remove Signature | `.foregroundStyle(.red)` | `.markepiDestructive()` | text-only |
| Remove Layer (X) | `.foregroundStyle(.red)` | `.markepiDestructive()` | icon-only |
| Save as Template | `.bordered .tint(.accentColor)` | `.markepiSecondary()` | icon + text |

### MarkepiTypography Application (D-08)
**Source:** `MarkepiTypography.swift` lines 1-108
**Apply to:** All Text views in ControlsView and all sub-views
```swift
// Replace:
//   .font(.title3.weight(.semibold))  → .markepiTypography(.sectionHeader)
//   .font(.body)                      → .markepiTypography(.controlLabel)
//   .font(.body) + .monospacedDigit() → .markepiTypography(.value)
//   .font(.caption)                   → .markepiTypography(.metadata)
//   (no existing pill label usage)    → .markepiTypography(.pillLabel) — handled by MarkepiPillBar
```
`.markepiTypography()` applies BOTH `.font()` and `.foregroundStyle()` — no need for separate `.foregroundStyle(.secondary)` calls on typography-styled Text.

### MarkepiGlass Application (D-06, D-13)
**Source:** `MarkepiGlassModifier.swift` lines 1-76
**Apply to:** Section containers in ControlsView, the pill bar (already applied in MarkepiPillBar)
```swift
// Each glass consumer reads its own @Environment:
@Environment(\.accessibilityReduceTransparency) private var reduceTransparency

// Section container:
.someContainer
    .markepiGlass(
        shape: RoundedRectangle(cornerRadius: 12, style: .continuous),
        isEnabled: !reduceTransparency
    )

// Progress state (rendering):
ProgressView(...)
    .markepiGlass(
        shape: RoundedRectangle(cornerRadius: 12, style: .continuous),
        isEnabled: !reduceTransparency
    )
```

### Section Content Switching (D-04, D-05)
**Source:** `MarkepiPillBar.swift` lines 13-19 (ControlsSection enum) + RESEARCH.md Pattern 3 (lines 349-378)
**Apply to:** ControlsView body structure
```swift
@State private var section: ControlsSection = .watermark

var body: some View {
    VStack(spacing: 0) {
        switch section {
        case .watermark:  watermarkSectionContent
        case .style:      styleSectionContent
        case .output:     outputSectionContent
        }
    }
    .markepiScrollEdgeProtection {
        MarkepiPillBar(selection: $section)
    }
}
```

### RenderingState State Machine (FROZEN)
**Source:** `ControlsView.swift` lines 128-264 + `ProcessingResult.swift` lines 50-93
**Apply to:** ControlsView share button — logic unchanged, only button styling changes
```swift
// State machine: .idle → .rendering → .done → .error
// .renderingVideo / .batchProcessing for extended progress
// Present share sheet in .done; retry in .error
```
**No logic changes** — only replace `.buttonStyle(...)` and `.tint(...)` with Markepi equivalents.

### Export Format + HDR Warning (FROZEN logic, restyled UI)
**Source:** Current `ControlsView.swift` lines 65-126
**Apply to:** ControlsView output section — the `showHDRLossWarning` state and alert MUST be preserved (Pitfall 5)
```swift
@State private var showHDRLossWarning = false
@State private var pendingFormatSelection: OutputFormat = .preserveSource

// Export format: DisclosureGroup → tap-to-open Menu row (D-07)
// Quality slider: separate row below format row
// HDR→JPEG warning: alert attached to output section container
```

### Export Format Menu (new pattern — replaces DisclosureGroup)
**Source:** RESEARCH.md lines 250-286 (Pattern 1: Menu-Based Picker)
**Apply to:** ControlsView output section
```swift
private var exportFormatRow: some View {
    HStack {
        Text("Format")
            .markepiTypography(.controlLabel)
        Spacer()
        Menu {
            Button("HEIC") { viewModel.config.outputFormat = .heic }
            Button("JPEG") {
                if viewModel.sourceHasHDR {
                    pendingFormatSelection = .jpeg
                    showHDRLossWarning = true
                }
                viewModel.config.outputFormat = .jpeg
            }
            Button("PNG") { viewModel.config.outputFormat = .png }
            Button("TIFF") { viewModel.config.outputFormat = .tiff }
            Button("Match Source\(sourceFormatLabel.map { " (\($0))" } ?? "")") {
                viewModel.config.outputFormat = .preserveSource
            }
        } label: {
            HStack(spacing: 4) {
                Text(currentFormatLabel)
                    .markepiTypography(.value)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
}
```

### Divider Alignment (Pitfall 2)
**Source:** LayerListView.swift lines 26-27 (existing) + RESEARCH.md Pitfall 2 (lines 462-477)
**Apply to:** Any section container mixing icon-prefixed rows with non-icon rows
```swift
// For sections with mixed icon/no-icon rows:
Divider()
    .padding(.leading, 52)  // 24pt icon + 12pt spacing + 16pt internal padding

// For sections where all rows have uniform leading alignment:
Divider()  // full-width
```

## No Analog Found

None — all files have exact or role-match analogs in the codebase. The Menu-based picker pattern is new to ControlsView but is a standard SwiftUI Menu API with code examples provided in RESEARCH.md.

## Metadata

**Analog search scope:** `Packages/WatermarkCore/Sources/WatermarkCore/UI/`, `Packages/WatermarkCore/Sources/WatermarkCore/DesignSystem/`, `Packages/WatermarkCore/Sources/WatermarkCore/Models/`
**Files scanned:** 18 source files + 6 design system primitive files
**Pattern extraction date:** 2026-06-21
**Design system version:** Phase 15 (Markepi primitives — delivered)
**Key constraint:** `WatermarkConfigurable` protocol FROZEN — zero changes to protocol surface
