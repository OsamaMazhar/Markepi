# Phase 16: Redesigned Controls - Research

**Researched:** 2026-06-21
**Domain:** SwiftUI control reskinning — rebuilding UI only on a frozen data model
**Confidence:** HIGH

## Summary

Phase 16 is a pure presentation-layer reskin of every control inside the shared `ControlsView` onto the Phase 15 Markepi design system primitives. Zero behavior changes — all 8 CTL requirements (CTL-01 through CTL-08) are observable look-and-feel changes to existing functionality. The `WatermarkConfigurable` protocol surface, all ViewModel logic, the `RenderingState` state machine, `WatermarkPosition` enum, `OutputFormat` enum, and all watermark rendering are frozen.

The current `ControlsView` (~280 lines) is a flat `ScrollView > VStack(spacing: 20)` with 7 sub-views stacked linearly plus divider-separated share/template/export buttons. The redesign replaces this with a 3-section pill bar (`MarkepiPillBar`), each section containing iOS Settings-style inset grouped rows with `.markepiGlass()` backing, all buttons restyled to `MarkepiButtonStyle`, the position picker converted from a 3x3 grid to a `Menu` button, and the export `DisclosureGroup` replaced by plain tap-to-open Menu rows.

All work lives inside `Packages/WatermarkCore/Sources/WatermarkCore/UI/` (the shared WatermarkCore package) and is consumed identically by all 3 targets (App, ShareExtension, PhotoEditExtension). ControlsView MUST remain shell-agnostic (no bottom-sheet assumptions).

**Primary recommendation:** Rebuild ControlsView from scratch using the Phase 15 primitives already in the codebase — replace the current flat `ScrollView` with `MarkepiScrollEdgeProtection` + `MarkepiPillBar` + section-switched content, convert each sub-view to inset grouped row pattern, and apply `MarkepiButtonStyle` everywhere. Keep all existing protocol calls (`updateLayerPosition`, `addLogoLayer`, etc.) unchanged.

## User Constraints (from CONTEXT.md)

### Locked Decisions

#### 9-Position Picker (CTL-01)
- **D-01:** The current `PositionGridView` 3x3 grid of text-labeled buttons is replaced by a single button showing the currently selected position name (e.g., "Center") with a disclosure arrow.
- **D-02:** Tapping the button presents a Menu listing all 9 position names as plain text items. No directional icons, no thumbnails, no image rendering. Items show position names only.
- **D-03:** The underlying 9 `WatermarkPosition` values and `updateLayerPosition(at:position:)` behavior are unchanged — this is UI-only.

#### Section Grouping (Pill Bar)
- **D-04:** Controls are grouped into the 3 `MarkepiPillBar` sections: Watermark (text input + position picker + scale stepper), Style (logo picker + signature capture + white frame toggle + layer list), Output (export options + save as template).
- **D-05:** The `ControlsSection` enum in `MarkepiPillBar.swift` is the source of truth for pill bar segment identity.

#### Row Presentation
- **D-06:** Controls are presented as iOS Settings-style inset grouped rows with `.markepiGlass()` backing on the section container. Clean, minimal, professional — Lightroom/Adobe-style control panel aesthetic.
- **D-07:** Current `DisclosureGroup("Export Options")` is replaced by a plain tap-to-open row that presents a `Menu` with format options, plus a separate quality row. No inline expand/collapse.
- **D-08:** Section headers use `MarkepiTypography.sectionHeader`. Control labels use `.controlLabel`. Values use `.value` (monospacedDigit for numbers). Metadata uses `.metadata`. No raw `.font()` calls.

#### MarkepiButtonStyle Application (CTL-08)
- **D-09:** All buttons in ControlsView must use `MarkepiButtonStyle` or the convenience `.markepiPrimary()`, `.markepiSecondary()`, `.markepiDestructive()` modifiers. No `.bordered`, `.borderedProminent`, or raw `.tint()` calls.
- **D-10:** Button role mapping: `.primary` → Share / Watermark All (idle), Ready to Share (done), Add Logo, Add Signature, Edit Signature; `.secondary` → Cancel (rendering), Retry (error), Save as Template; `.destructive` → Remove Logo, Remove Signature, Remove Layer (red X).
- **D-11:** Label conventions: Primary = icon + text (SF Symbol + label); Secondary = text-only or icon+text per context; Destructive = text-only; Layer remove = icon-only (red X).

#### Scroll & Surface
- **D-12:** Each pill section scrolls vertically within its pill view. The pill bar sits above the scroll area with `.markepiScrollEdgeProtection()`.
- **D-13:** The pill bar itself gets `.markepiGlass()` — content scrolling beneath is blurred by the glass backing. Already built in Phase 15.

### Agent's Discretion
- Exact layout metrics (padding, spacing, corner radii, separator placement) within the inset grouped rows — follow iOS HIG grouped list conventions.
- The Menu presentation style for the position picker and export format — use native `.menu` picker style.
- Transition between the 3 pill sections — `MarkepiPillBar` already handles the matched-geometry sliding indicator; ControlsView only needs to switch content via `ControlsSection`.
- How to handle the "Ready to Share" state transitioned from the primary button — keep the existing `RenderingState` enum driving the button state machine; only restyle the button look, not the state logic.

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope.

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| CTL-01 | A visual 9-position picker replaces the TL/TC/TR text grid, showing placement glanceably | Menu-based picker (Pattern 1), `WatermarkPosition.allCases` provides names, D-01/D-02/D-03 |
| CTL-02 | The text watermark input is redesigned with a cleaner field and inline affordances | Inset grouped row pattern + `.controlLabel` typography (Pattern 2), existing `TextWatermarkInputView` reused |
| CTL-03 | The scale control is redesigned with a live value readout | Inset grouped row + `.value` typography (monospacedDigit), existing `ScaleStepperView` stepper reused |
| CTL-04 | The Logo and Signature pickers share consistent add / preview / remove affordances | Inset grouped rows, MarkepiButtonStyle (.primary add, .destructive remove, .primary edit) |
| CTL-05 | White Frame is presented as an integrated grouped row within the controls | Inset grouped row with Toggle, `.controlLabel` + `.metadata` typography |
| CTL-06 | The layer list is redesigned with clear active-layer selection and remove controls | Inset grouped rows, active-layer highlight, icon-only .destructive remove (red X) |
| CTL-07 | Export Options are redesigned using native Menus/pickers | Menu-based format picker + inline quality row (D-07), HDR→JPEG warning preserved |
| CTL-08 | The Save-as-Template action conforms to the new button language | `.markepiSecondary()` — D-10 maps template to secondary; D-11 secondary = text-only or icon+text |

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Position picker (CTL-01) | UI View (ControlsView/PositionPickerView) | ViewModel protocol | View renders position names, ViewModel provides `updateLayerPosition(at:position:)` call — called from Menu button tap |
| Text watermark input (CTL-02) | UI View (TextWatermarkInputView) | ViewModel protocol | View renders editable TextEditor, ViewModel provides config binding — raw `.font()` calls replaced with `.markepiTypography()` |
| Scale stepper (CTL-03) | UI View (ScaleStepperView) | ViewModel protocol | View renders Stepper + value readout, ViewModel provides `updateLayerScale(at:scale:)` |
| Logo/Signature pickers (CTL-04) | UI View (LogoPickerView/SignatureCaptureView) | ViewModel protocol | View handles picker/import UI, ViewModel provides `addLogoLayer`/`addSignatureLayer`/`removeLayer` |
| White frame toggle (CTL-05) | UI View (WhiteFrameToggleView) | ViewModel protocol | Toggle binds to `whiteFrameEnabled` + `setWhiteFrameEnabled(_:)` |
| Layer list (CTL-06) | UI View (LayerListView) | ViewModel protocol | View renders sorted layers with selection highlight, ViewModel tracks `activeLayerIndex` |
| Export options (CTL-07) | UI View (ControlsView export section) | ViewModel protocol | View renders Menu + quality slider, ViewModel provides `config.outputFormat`/`config.outputQuality` |
| Share / render button | UI View (ControlsView shareButton) | ViewModel protocol | View reads `renderingState` to pick button variant, ViewModel implements `renderAndPrepareShare()` |
| Save-as-template (CTL-08) | UI View (ControlsView template button) | ViewModel protocol | Button calls `showSaveTemplateAlert = true`, ViewModel handles alert logic |

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| SwiftUI | iOS 18 SDK (Xcode 26.2) | UI framework for all control views | Declarative, system-native, no third-party UI libs needed |
| Markepi Design System (Phase 15) | Delivered | Glass effect, pill bar, button styles, typography, scroll-edge | Project's own design primitives — all controls consume these |
| WatermarkConfigurable protocol | Frozen (v1.0+) | ViewModel interface for all control sub-views | Generic protocol enables code sharing across 3 targets |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| — _(none)_ | — | — | No third-party libraries are needed. All UI is built with SwiftUI + Phase 15 design primitives. |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Custom pill bar (Phase 15) | `Picker(.segmented)` | Native segmented picker can't do per-segment glass-effect styling — already decided in Phase 15 D-04 |
| Form/List for inset grouped | Custom VStack containers | Form/List would fight MarkepiScrollEdgeProtection (which wraps its own ScrollView) and wouldn't allow `.markepiGlass()` on individual sections easily |
| `Picker(.menu)` for position picker | Custom Menu with disclosure arrow | Menu gives full label control (custom disclosure arrow, no double-arrow artifact). D-01/D-02 explicitly choose Menu over grid — `Picker(.menu)` could work too but Menu with custom label is more flexible for custom button styling |
| Keep `DisclosureGroup` for Export | Menu-based format row | D-07 explicitly replaces DisclosureGroup with Menu — DisclosureGroup has inline expand/collapse that doesn't match the clean row aesthetic |

**Installation:**
```bash
# No package manager needed. All dependencies are either:
# 1. Apple system frameworks (SwiftUI — included with iOS SDK)
# 2. Phase 15 design system primitives (already in WatermarkCore package)
```

**Version verification:** All primitives verified present in the codebase — `MarkepiButtonStyle`, `MarkepiPillBar`, `MarkepiTypography`, `MarkepiGlassModifier`, `MarkepiScrollEdgeProtection`, `MarkepiUtilities` confirmed by file reads at research time.

## Package Legitimacy Audit

> No external packages are installed in this phase. All dependencies are either Apple system frameworks or the project's own Phase 15 design system primitives within the WatermarkCore Swift Package. Audit is not applicable.

**Packages removed due to slopcheck [SLOP] verdict:** N/A (no external packages)
**Packages flagged as suspicious [SUS]:** N/A (no external packages)

## Architecture Patterns

### System Architecture Diagram

```
┌────────────────────────────────────────────────────────────────────┐
│  ControlsView<ViewModel: WatermarkConfigurable & Observable>        │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │  @State var section: ControlsSection = .watermark            │   │
│  │                                                              │   │
│  │  NavigationStack-independent — no NavigationLink assumptions  │   │
│  │  Shell-agnostic — no bottom-sheet assumptions                │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │  MarkepiScrollEdgeProtection {                                │   │
│  │    header: MarkepiPillBar(selection: $section)                │   │
│  │      .markepiGlass() ← already built in pill bar             │   │
│  │    content: switch section { ... }                            │   │
│  │  }                                                            │   │
│  └───────────────┬─────────────────────────────────────────────┘   │
│                  │                                                  │
│     ┌────────────┼────────────┬──────────────┐                     │
│     ▼            ▼            ▼              ▼                     │
│  .watermark  .style       .output        (pill bar switches)       │
│     │            │            │                                     │
│     ├─ TextInput ├─ LogoPicker ├─ ExportMenu                       │
│     ├─ PosMenu  ├─ SigCapture ├─ QualitySlider                     │
│     └─ ScaleStp ├─ WFrameTgl  └─ TemplateBtn                       │
│                 └─ LayerList                                       │
│                                                                     │
│  Each section: VStack of inset grouped rows                        │
│  ┌───────────────────────────────────────────┐                     │
│  │  Section container {                       │                     │
│  │    .markepiGlass(shape: RoundedRectangle)  │                     │
│  │    .clipShape(RoundedRectangle(corner:)    │                     │
│  │    VStack(spacing: 0) {                    │                     │
│  │      [row 1]                               │                     │
│  │      Divider()                             │                     │
│  │      [row 2]                               │                     │
│  │    }                                       │                     │
│  │  }                                         │                     │
│  │  .padding(.horizontal, 16)                 │                     │
│  └───────────────────────────────────────────┘                     │
└────────────────────────────────────────────────────────────────────┘
         │                  │                  │
         ▼                  ▼                  ▼
    WatermarkConfigurable protocol (frozen)
         │
         ├── updateLayerPosition(at:position:)
         ├── updateLayerScale(at:scale:)
         ├── addLogoLayer(pngData:)
         ├── addSignatureLayer(...)
         ├── removeLayer(at:)
         ├── setWhiteFrameEnabled(_:)
         ├── config.outputFormat / outputQuality
         ├── renderAndPrepareShare()
         ├── presentShareSheet()
         └── cancelProcessing()
```

### Recommended Project Structure
```
Packages/WatermarkCore/Sources/WatermarkCore/UI/
├── ControlsView.swift                  # [REWRITE] Main control hub — pill bar + section switching
├── WatermarkConfigurable.swift         # [FROZEN] Protocol surface — do not modify
├── TextWatermarkInputView.swift        # [REFACTOR] Restyle with inset row + typography
├── ScaleStepperView.swift             # [REFACTOR] Add live value readout + row pattern
├── LogoPickerView.swift               # [REFACTOR] Consistent add/preview/remove affordances
├── SignatureCaptureView.swift         # [REFACTOR] Consistent add/preview/remove affordances
├── WhiteFrameToggleView.swift         # [REFACTOR] Inset grouped row with Toggle
├── LayerListView.swift                # [REFACTOR] Active-layer highlight, icon-only remove
├── PositionGridView.swift             # [REPLACE] → inline Menu in ControlsView or new PositionMenuView
```

### Pattern 1: Menu-Based Picker (CTL-01, CTL-07)

**What:** A `Menu` component with a custom button label showing the current selection and a disclosure arrow. The menu items are plain text action buttons.

**When to use:** When a picker needs custom label styling (beyond what `Picker(.menu)` provides) — for the position picker (CTL-01) and export format picker (CTL-07).

**Example — Position Picker (CTL-01, D-01/D-02):**
```swift
// Source: SwiftUI Menu API — verified in ControlsView redesign context
// Replaces PositionGridView entirely
@ViewBuilder
private var positionPickerRow: some View {
    HStack {
        Text("Position")
            .markepiTypography(.controlLabel)
        Spacer()
        Menu {
            ForEach(WatermarkPosition.allCases, id: \.rawValue) { position in
                Button(position.displayName) {
                    viewModel.updateLayerPosition(at: layerIndex, position: position)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(currentPosition?.displayName ?? "Center")
                    .markepiTypography(.value)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
}

// Display name extension on WatermarkPosition (D-02: plain text names only)
// Source: WatermarkPosition.swift — enum already has CaseIterable
extension WatermarkPosition {
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
[CITED: Apple Developer Documentation — Menu, verified via WebSearch + standard SwiftUI API]

**Example — Export Format Menu (CTL-07, D-07):**
```swift
// Replaces DisclosureGroup("Export Options") { ... }
@ViewBuilder
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
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
}
```
[CITED: Apple Developer Documentation — Menu, verified via WebSearch + standard SwiftUI API]

### Pattern 2: Inset Grouped Row (D-06)

**What:** A custom section container mimicking iOS Settings-style inset grouped rows — a `VStack` inside a `RoundedRectangle` clip shape with `.markepiGlass()` backing.

**When to use:** For ALL control rows inside each pill section. The glass-backed container groups related rows with dividers between them.

**Example:**
```swift
// Source: iOS HIG grouped list conventions + Phase 15 .markepiGlass() modifier
// Verified: MarkepiGlassModifier accepts any Shape including RoundedRectangle

struct ControlSection<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .markepiGlass(
            shape: RoundedRectangle(cornerRadius: 12, style: .continuous),
            fallbackMaterial: .ultraThinMaterial,
            isEnabled: !reduceTransparency
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 16)
    }
}

// Usage inside a pill section:
// Watermark section
Group {
    ControlSection {
        TextWatermarkInputView(viewModel: viewModel)
        // Divider handled internally or as part of row
    }
    
    ControlSection {
        positionPickerRow       // Menu-based
        Divider()
            .padding(.leading, 52)  // align with text after icon
        scaleStepperRow
    }
}
```
[CITED: MarkepiGlassModifier.swift (verified — supports generic `<S: Shape>`), iOS HIG Grouped Lists convention]

**Key layout metrics (Agent's Discretion — follow iOS HIG):**
- Section container corner radius: 12pt (`.continuous` style)
- External horizontal padding: 16pt (inset from screen edges)
- Internal row padding: `.horizontal: 16, .vertical: 12`
- Divider between rows inside same container
- Section-to-section spacing: 16-20pt vertical gap

### Pattern 3: Section Content Switching (D-04, D-05)

**What:** ControlsView uses `@State var section: ControlsSection` to switch the displayed content via `switch section { case .watermark: ... case .style: ... case .output: ... }`. The pill bar's `selection` binding drives the switch.

**When to use:** This is the core ControlsView architecture — each pill section is a separate scrollable content area.

**Example:**
```swift
// Source: MarkepiPillBar.swift ControlsSection enum — D-05
public struct ControlsView<ViewModel: WatermarkConfigurable & Observable>: View {
    @State var viewModel: ViewModel
    @State private var section: ControlsSection = .watermark
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    
    public var body: some View {
        // D-12: markepiScrollEdgeProtection wraps everything —
        // it creates its own ScrollView and overlays the pill bar header
        VStack(spacing: 0) {
            // Section content — scrolled inside MarkepiScrollEdgeProtection's ScrollView
            switch section {
            case .watermark:
                watermarkSectionContent
            case .style:
                styleSectionContent
            case .output:
                outputSectionContent
            }
        }
        .markepiScrollEdgeProtection {
            MarkepiPillBar(selection: $section)
        }
    }
}
```
[CITED: MarkepiScrollEdgeProtection.swift (verified — creates internal ScrollView wrapping content), MarkepiPillBar.swift (verified — uses `@Binding var selection: ControlsSection`)]

### Anti-Patterns to Avoid

- **Wrapping MarkepiScrollEdgeProtection in another ScrollView:** `MarkepiScrollEdgeProtection` already creates its own `ScrollView(.vertical)`. Nesting a second ScrollView creates conflicting scroll gestures. ControlsView must NOT have its own `ScrollView` — the outer shell (Phase 17) will handle any additional scrolling needs.

- **Using Form/List inside ControlsView:** Form and List have built-in scroll behaviors and styling that conflict with custom glass-backed containers and the MarkepiScrollEdgeProtection wrapper. Use raw VStack containers with explicit glass + clipShape modifiers.

- **Reading `@Environment(\.accessibilityReduceTransparency)` inside Child Views:** Each glass-backed component needs its own `@Environment` read — don't pass `isEnabled` as a parameter down through multiple view levels. The pattern from Phase 15 (read in the view that applies the glass modifier) should be followed.

- **Modifying WatermarkConfigurable protocol:** The protocol surface is frozen per the v2.1 scope. Do not add new methods, properties, or change signatures. All 8 CTL requirements are UI-only.

- **Adding target-specific code to ControlsView:** ControlsView is consumed by all 3 targets identically. No `#if targetEnvironment(simulator)`, no extension-specific layout assumptions. The host view (ContentView, ShareExtensionRootView, PhotosExtensionRootView) provides the shell — ControlsView only provides the control content.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Glass/blur background on section containers | Custom BlurView wrapper, UIVisualEffectView bridge | `.markepiGlass(shape: RoundedRectangle(...))` | Already built in Phase 15 — handles iOS 26 Liquid Glass + iOS 18 material fallback + Reduce Transparency automatically |
| Position picker dropdown | Custom popover, context menu, or sheet | SwiftUI `Menu` with custom label | Menu is the standard iOS pattern for selection from a list — handles accessibility, keyboard navigation, and platform adaptation |
| Export format picker with disclosure arrow | Custom overlay or re-implemented Picker UI | SwiftUI `Menu` with custom label | Menu provides built-in presentation, accessibility, and the standard iOS interaction model (D-07) |
| Capsule-shaped buttons with glass treatment | Custom ButtonStyle from scratch | `.buttonStyle(.markepiPrimary())` etc. | Phase 15 already built 3-role capsule button style with glass, pressed-state feedback, and Reduce Transparency respect |
| Semantic typography (section headers, labels, values) | Raw `.font(.title3.weight(.semibold))` calls | `.markepiTypography(.sectionHeader)` etc. | Phase 15 typography system provides consistent scale, automatic uncapped Dynamic Type, and semantic foreground colors (D-08) |
| Scroll-edge blur for pill bar | Custom gradient overlay, manual scroll offset tracking | `.markepiScrollEdgeProtection { MarkepiPillBar(...) }` | Phase 15 already implemented ZStack + scrollClipDisabled + glass-backed header (D-12, D-13) |
| Inline expand/collapse for export options | DisclosureGroup | Tap-to-open Menu row | D-07 explicitly replaces DisclosureGroup — Menu is cleaner, avoids inline layout jumps, and matches the section's row aesthetic |

**Key insight:** The Phase 15 primitives were purpose-built for this phase. Every visual concern (glass, buttons, typography, scroll-edge, pill bar) already has a production-ready implementation. This phase is about **consuming** those primitives correctly, not building new ones.

## Runtime State Inventory

> Phase 16 is a pure UI redesign / refactor phase. It rewrites SwiftUI view files within WatermarkCore — no data model changes, no stored state changes, no service reconfiguration. However, since it's a significant restyling of ControlsView, we check the 5 categories:

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | None — all watermark config lives in `WatermarkConfiguration` (Codable, in-memory). No database, no CoreData, no UserDefaults keys change. | None |
| Live service config | None — no external services (this is a fully offline, on-device app). | None |
| OS-registered state | None — no Task Scheduler, pm2, launchd, or systemd registrations exist for this iOS app. | None |
| Secrets/env vars | None — no API keys, no SOPS, no .env. The only App Group identifier is `group.com.[bundle].watermark` and does not change. | None |
| Build artifacts | None requiring migration — the WatermarkCore Swift Package will recompile when sources change. No pip/egg-info, no npm global installs, no Docker images. The Xcode project structure (target membership, package dependencies) is not changing. | None |

**Nothing found in any category:** Verified by reading all 5 source categories — this is a pure SwiftUI view-file reskin with zero impact on runtime state, stored data, or external service configuration.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Xcode | Building WatermarkCore + all 3 targets | ✓ | 26.2 (17C52) | — |
| Swift compiler | Compiling SwiftUI views | ✓ | 6.2.3 (swiftlang-6.2.3.3.21) | — |
| iOS 18 SDK | Deployment target | ✓ | Included with Xcode 26.2 | — |
| git | Version control for commits | ✓ | 2.50.1 | — |
| Phase 15 primitives | All Markepi components | ✓ | Delivered (verified in codebase) | — |

**Missing dependencies with no fallback:** None
**Missing dependencies with fallback:** None

## Common Pitfalls

### Pitfall 1: Double ScrollView Nesting

**What goes wrong:** ControlsView currently wraps its content in `ScrollView(.vertical)`. MarkepiScrollEdgeProtection internally creates its own `ScrollView(.vertical)`. If ControlsView keeps its existing ScrollView inside the MarkepiScrollEdgeProtection content, two nested vertical ScrollViews fight for gesture recognition — scrolling becomes broken/unpredictable.

**Why it happens:** MarkepiScrollEdgeProtection is a ViewModifier whose `body` includes a `ScrollView(.vertical) { content }` layer. When content already contains a ScrollView, SwiftUI creates competing scroll gesture recognizers.

**How to avoid:** Strip the `ScrollView(.vertical)` wrapper from ControlsView.body entirely. The body should return the raw content (section-switched VStack of ControlSections) without any additional scrolling wrapper. MarkepiScrollEdgeProtection provides the scrolling container.

**Warning signs:** Scrolling feels sticky, jumps, or doesn't respond; two scroll indicators visible; "Unable to simultaneously satisfy constraints" Auto Layout warnings.

### Pitfall 2: Divider Alignment with SF Symbol Rows

**What goes wrong:** When a section container has rows with SF Symbol icons (e.g., logo picker with `photo` icon) mixed with rows without icons, a full-width `Divider()` creates visual misalignment — the divider spans edge-to-edge while the text labels are offset by icon width.

**Why it happens:** The default `Divider()` spans the full width of its container. Rows with icon+label have content starting ~52pt from the leading edge (24pt icon + 12pt spacing + 16pt internal padding), while rows without icons start at ~16pt.

**How to avoid:** For sections with mixed icon/no-icon rows, use `.padding(.leading, 52)` on `Divider()` to align with the text portion of the labeled rows. For sections where all rows have uniform leading alignment, a full-width Divider is fine. Follow iOS HIG grouped list conventions — dividers typically inset to align with text, not with icons.

**Warning signs:** Dividers start at different horizontal positions in different sections; visual inconsistency between Lightroom/Adobe-style reference designs and implementation.

### Pitfall 3: MarkepiButtonStyle Label Content Mismatch (D-11)

**What goes wrong:** Applying `.markepiPrimary()` to a button with text-only label, or `.markepiDestructive()` to a button with icon+text label — violating the label conventions from D-11.

**Why it happens:** `MarkepiButtonStyle` renders whatever `configuration.label` the caller provides — it does not enforce label conventions. It's the caller's responsibility to follow D-11.

**How to avoid:**
- `.primary` buttons: Use `Label("Share", systemImage: "square.and.arrow.up")` or `HStack { Image + Text }`
- `.secondary` buttons: Text-only or icon+text per context
- `.destructive` buttons: Text-only (e.g., `Text("Remove")`)
- Layer remove (destructive, icon-only): `Image(systemName: "xmark.circle.fill")` with NO text
- Do NOT wrap icons in `Label` for destructive/icon-only cases

**Warning signs:** Destructive button showing an icon (should be text-only per D-11); primary button showing text-only (should be icon+text per D-11); visual weight mismatches between same-role buttons.

### Pitfall 4: VoiceOver Labels Lost During Reskin

**What goes wrong:** The current sub-views have `.accessibilityLabel()` and `.accessibilityHint()` modifiers. During full restructuring (e.g., replacing 9 grid buttons with 1 Menu button), existing accessibility annotations are dropped.

**Why it happens:** When replacing a sub-view entirely (PositionGridView → inline Menu), the new code doesn't inherit the old view's accessibility modifiers. The developer may forget to re-add them.

**How to avoid:** For each sub-view being restyled or replaced, audit the current accessibility modifiers and preserve/improve them. Specifically:
- Position picker: The old grid had per-button `accessibilityLabel("Position: Top Left")` — the new Menu button should have `accessibilityLabel("Watermark position, currently \(currentPosition.displayName)")` and the menu items should maintain per-position labels
- Scale stepper: Preserve `accessibilityLabel("Watermark scale")` and `accessibilityHint`
- Logo/Signature: Preserve add/remove button labels
- Layer list: Preserve `accessibilityLabel("Remove layer: \(description)")`

**Warning signs:** VoiceOver reads "Button" instead of "Watermark position, currently Bottom Right"; VoiceOver reads generic labels for re-styled controls.

### Pitfall 5: HDR→JPEG Warning Lost in Export Redesign

**What goes wrong:** The current `DisclosureGroup("Export Options")` contains the HDR→JPEG warning alert logic (`showHDRLossWarning` state). When replacing DisclosureGroup with a Menu-based format row, the warning alert can be accidentally dropped.

**Why it happens:** The alert modifier is currently on the `DisclosureGroup` sub-view. When that sub-view is removed and replaced with a `Menu`, the `.alert(...)` modifier may not be carried over.

**How to avoid:** Keep the `@State private var showHDRLossWarning = false` and `@State private var pendingFormatSelection` state on ControlsView. Apply the `.alert("HDR Will Be Lost", ...)` modifier to the section container or the Menu itself. The Menu button's JPEG action should still check `viewModel.sourceHasHDR` and set `showHDRLossWarning = true` before changing the format.

**Warning signs:** Selecting JPEG when source has HDR shows no warning; EXIF verification shows HDR gain map stripped without user confirmation.

## Code Examples

Verified patterns from official sources and Phase 15 primitives:

### Position Menu Picker replacing PositionGridView (CTL-01, D-01/D-02/D-03)
```swift
// Source: SwiftUI Menu API + WatermarkPosition.allCases (verified in codebase)
// Replaces: PositionGridView.swift (entire file — 94 lines)

// Display name extension (add to WatermarkPosition.swift or ControlsView.swift)
// [CITED: WatermarkPosition.swift — rawValue enum, CaseIterable confirmed]
extension WatermarkPosition {
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

// Usage inside ControlsView watermark section
// [CITED: D-01, D-02, D-03 from CONTEXT.md]
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

### Button Restyling — RenderingState Machine (CTL-08, D-09/D-10/D-11)
```swift
// Source: CONTEXT.md D-09/D-10/D-11 + MarkepiButtonStyle.swift (verified)
// Replace all .buttonStyle(.borderedProminent), .buttonStyle(.bordered), .tint() calls

private var shareButton: some View {
    Group {
        switch viewModel.renderingState {
        case .idle:
            Button {
                Task { await viewModel.renderAndPrepareShare() }
            } label: {
                Label(
                    isBatchMode ? "Watermark All" : "Share",
                    systemImage: isBatchMode ? "square.and.arrow.up.on.square.fill" : "square.and.arrow.up"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.markepiPrimary())  // ← was .borderedProminent with no tint

        case .rendering:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.regular)
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
            renderingVideoStateView(progress: progress, eta: eta)

        case .batchProcessing(let current, let total, let eta):
            batchProcessingStateView(current: current, total: total, eta: eta)

        case .done:
            Button {
                if !reduceMotion {
                    withAnimation(.easeOut(duration: 0.3)) {}
                }
                viewModel.presentShareSheet()
            } label: {
                Label(
                    isBatchMode ? "Ready to Share All" : "Ready to Share",
                    systemImage: "checkmark.circle.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.markepiPrimary())  // ← was .borderedProminent .tint(.green)

        case .error:
            Button {
                Task { await viewModel.renderAndPrepareShare() }
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.markepiSecondary())  // ← was .bordered .tint(.orange)
        }
    }
    .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: viewModel.renderingState)
}
```

### Save-as-Template Button (CTL-08, D-10 secondary)
```swift
// Source: CONTEXT.md D-10/D-11 — template = secondary, secondary = text-only or icon+text
// Replaces: current .buttonStyle(.bordered) .tint(.accentColor)

private var saveTemplateButton: some View {
    Button {
        viewModel.showSaveTemplateAlert = true
    } label: {
        Label("Save as Template", systemImage: "square.and.arrow.down.on.square")
            .frame(maxWidth: .infinity)
    }
    .buttonStyle(.markepiSecondary())  // ← was .bordered .tint(.accentColor)
}
```

### Cancel Button during Rendering (D-10 secondary)
```swift
// Source: CONTEXT.md D-10 — Cancel = secondary role
// Replaces: current .buttonStyle(.bordered) .tint(.red) with Button(role: .destructive)

// In renderingVideo state:
Button {
    viewModel.cancelProcessing()
} label: {
    Text("Cancel")
        .frame(maxWidth: .infinity)
}
.buttonStyle(.markepiSecondary())  // ← D-10: Cancel = secondary, NOT destructive
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Flat `VStack(spacing: 20)` with `Divider()` separators | Pill bar with 3 sections + inset grouped rows with `.markepiGlass()` | Phase 16 | All 7 control sections reorganized into 3 pill sections |
| `PositionGridView` 3x3 grid of text-labeled buttons | Menu button showing current position + chevron | Phase 16 (D-01/D-02) | 94 lines of grid code replaced by ~25 line Menu implementation |
| `DisclosureGroup("Export Options")` inline expand/collapse | Tap-to-open Menu row + separate quality row | Phase 16 (D-07) | No inline layout jumps; consistent row aesthetic |
| `.buttonStyle(.borderedProminent)` / `.bordered` / `.tint()` | `.buttonStyle(.markepiPrimary())` / `.markepiSecondary()` / `.markepiDestructive()` | Phase 16 (D-09) | All buttons get capsule shape + glass treatment + semantic roles |
| Raw `.font(.title3.weight(.semibold))` | `.markepiTypography(.sectionHeader)` | Phase 16 (D-08) | Uncapped Dynamic Type, consistent typographic hierarchy |
| `ScrollView(.vertical)` wrapping all controls | `MarkepiScrollEdgeProtection` (built-in ScrollView + glass pill bar header) | Phase 16 (D-12/D-13) | Content scrolls beneath glass pill bar; no double-scroll nesting |

**Deprecated/outdated:**
- `PositionGridView.swift` — entire file replaced by inline Menu in ControlsView (D-01/D-02)
- `DisclosureGroup` for Export Options — replaced by Menu-based row (D-07)
- All raw `.font()` calls — replaced by `.markepiTypography()` (D-08)
- All `.buttonStyle(.borderedProminent)` / `.buttonStyle(.bordered)` / `.tint()` — replaced by MarkepiButtonStyle (D-09)

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | The 9 `WatermarkPosition` display names ("Top Left" etc.) are user-facing labels — no localization needed for v2.1 | Pattern 1: Menu-Based Picker | Non-English users see English position names; low risk for photo utility app |
| A2 | `MarkepiScrollEdgeProtection`'s internal header height (44pt) correctly accounts for `MarkepiPillBar` with `.padding(4)` outer + segment `.padding(.vertical, 8)` | Pattern 3: Section Content Switching | Content top padding is off — pill bar overlaps first row or leaves excess gap |
| A3 | `WatermarkConfigurable` protocol's `addSignatureLayer` default implementation is a no-op — the main app ViewModel override handles signature capture, and extensions don't need it | CTL-04 | Logo/SignaturePickerView code compiles in extensions but signature capture sheet does nothing |
| A4 | The pillar header height constant (44pt) in MarkepiScrollEdgeProtection is sufficient for Safe Area + pill bar height on all iPhone models (notch, Dynamic Island, no-notch) | Pattern 3: Section Content Switching | Content padding too small on certain devices, pill bar overlaps first section row |

## Open Questions

1. **Should `WatermarkPosition.displayName` be added to `WatermarkPosition.swift` (the model file) or kept as a private extension in `ControlsView.swift`?**
   - What we know: `WatermarkPosition.swift` is in `WatermarkCore/Models/` — it's a pure data model. Adding UI-specific display names blurs the model/view boundary. But D-02 says "plain text items" — simple display names are arguably model-level, not view-level.
   - What's unclear: Conventions for this specific project — does the team prefer model-layer display names or view-layer?
   - Recommendation: Add as an internal extension in ControlsView.swift (keeps model clean) since PositionGridView.swift is being removed and ControlsView is the only consumer. If multiple views need it later, promote to the model file.

2. **Should the sub-view refactors (TextWatermarkInputView, ScaleStepperView, etc.) be in separate files or inlined into ControlsView?**
   - What we know: Current sub-views are each in separate files (7 files, 50-280 lines each). The pill-bar section switching means these sub-views are conditionally rendered. The `@ViewBuilder` pattern supports file-per-subview or inline approaches.
   - What's unclear: Whether file-per-subview (easier to read/navigate) or inline-everything-in-ControlsView (fewer files, easier to see the whole layout) is preferred.
   - Recommendation: Keep separate files per sub-view for maintainability — each file gets the inset grouped row treatment independently. ControlsView becomes thinner (~100-150 lines) — just the pill bar + section switching + share/template buttons. The sub-views don't change their `@Bindable var viewModel` pattern, only their styling.

3. **Should `PositionGridView.swift` be deleted or left as unreferenced code?**
   - What we know: It's 94 lines, currently the position picker. D-01/D-02 replace it entirely with a Menu. No other view references it.
   - What's unclear: Whether the project prefers clean deletion or soft deprecation (file kept, unreferenced).
   - Recommendation: Delete `PositionGridView.swift` — it's fully replaced. Git history preserves the code if needed. Add a comment in the commit message noting the replacement.

4. **Layout of the `Output` section — export format row vs quality row vs template button: one container or separate?**
   - What we know: D-06 says "iOS Settings-style inset grouped rows". In iOS Settings, related controls share a container (with dividers), unrelated groups get separate containers.
   - What's unclear: Whether Export Format + Quality are "related" (same container) or "separate concerns" (different containers). Save-as-Template is clearly separate.
   - Recommendation: Put Export Format + Quality in one container (they're both export settings). Put Save-as-Template in its own container (it's a template management action, not an export setting). This matches iOS Settings grouping conventions.

## Sources

### Primary (HIGH confidence)
- `Packages/WatermarkCore/Sources/WatermarkCore/DesignSystem/MarkepiPillBar.swift` — ControlsSection enum, pill bar with glass backing and matched-geometry indicator (verified at research time)
- `Packages/WatermarkCore/Sources/WatermarkCore/DesignSystem/ButtonStyles/MarkepiButtonStyle.swift` — 3-role button style, convenience modifiers, tint mapping (verified at research time)
- `Packages/WatermarkCore/Sources/WatermarkCore/DesignSystem/Typography/MarkepiTypography.swift` — 5 semantic typography styles (verified at research time)
- `Packages/WatermarkCore/Sources/WatermarkCore/DesignSystem/GlassEffect/MarkepiGlassModifier.swift` — `.markepiGlass()` modifier with generic Shape constraint (verified at research time)
- `Packages/WatermarkCore/Sources/WatermarkCore/DesignSystem/ScrollEdge/MarkepiScrollEdgeProtection.swift` — ScrollView + ZStack + glass header pattern (verified at research time)
- `Packages/WatermarkCore/Sources/WatermarkCore/DesignSystem/MarkepiUtilities.swift` — `.modify()` conditional helper (verified at research time)
- `Packages/WatermarkCore/Sources/WatermarkCore/UI/ControlsView.swift` — Current implementation (280 lines), all 7 sub-views consumed, RenderingState machine (verified at research time)
- `Packages/WatermarkCore/Sources/WatermarkCore/UI/PositionGridView.swift` — 3x3 grid being replaced (verified at research time)
- `Packages/WatermarkCore/Sources/WatermarkCore/Models/WatermarkPosition.swift` — 9-case enum with CaseIterable, display names needed for Menu (verified at research time)
- `Packages/WatermarkCore/Sources/WatermarkCore/Models/ProcessingResult.swift` — RenderingState enum (idle/rendering/renderingVideo/batchProcessing/done/error) (verified at research time)
- `Packages/WatermarkCore/Sources/WatermarkCore/Models/WatermarkConfiguration.swift` — OutputFormat enum (preserveSource/heic/jpeg/png/tiff) (verified at research time)
- `Packages/WatermarkCore/Sources/WatermarkCore/UI/WatermarkConfigurable.swift` — Protocol surface (FROZEN) (verified at research time)
- Phase 16 CONTEXT.md — All D-01 through D-13 locked decisions (verified at research time)
- Phase 15 plan summaries (15-01, 15-02, 15-03) — Delivered primitives list, patterns established (verified at research time)

### Secondary (MEDIUM confidence)
- Apple Developer Documentation — SwiftUI Menu API: standard pattern for selection-from-list UI, custom label support, built-in accessibility
  [CITED: developer.apple.com/documentation/swiftui/menu]
- iOS HIG — Grouped Lists conventions: inset grouped style, divider alignment, padding standards
  [CITED: developer.apple.com/design/human-interface-guidelines/lists]
- Apple Developer Documentation — SwiftUI Label: standard icon+text pattern for primary action buttons
  [CITED: developer.apple.com/documentation/swiftui/label]

### Tertiary (LOW confidence)
- WebSearch: Custom inset grouped rows in ScrollView pattern — multiple community sources confirm VStack + RoundedRectangle + material background approach as standard when Form/List can't be used [ASSUMED]
- WebSearch: Menu vs Picker(.menu) tradeoff — community consensus that Menu gives more label control, Picker(.menu) has system-default styling [ASSUMED]

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all dependencies are either Apple system frameworks or already-delivered Phase 15 primitives verified in the codebase
- Architecture: HIGH — architecture is dictated by Phase 15 primitives (MarkepiScrollEdgeProtection controls the scroll container, MarkepiPillBar controls section switching) plus locked decisions D-01 through D-13
- Pitfalls: HIGH — pitfalls derived from reading actual source files and understanding the interaction between Phase 15 primitives and current ControlsView architecture

**Research date:** 2026-06-21
**Valid until:** 2026-07-21 (30 days — design system primitives are stable, no iOS SDK changes expected that would affect UI view structure)
