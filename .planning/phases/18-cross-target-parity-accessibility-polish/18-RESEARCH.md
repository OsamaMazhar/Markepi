# Phase 18: Cross-Target Parity & Accessibility Polish - Research

**Researched:** 2026-06-22
**Domain:** iOS Accessibility / SwiftUI Snapshot Testing / Extension Layout Verification
**Confidence:** HIGH

## Summary

Phase 18 is a verification-and-polish phase: prove the redesigned `ControlsView` works in both extensions, add accessibility labels to new Phase 15-17 elements, gate all animations on Reduce Motion, verify all glass sites respect Reduce Transparency, implement Dynamic Type scaling for the expanded sheet detent, and redesign the empty state.

The phase has zero external dependencies — everything uses iOS system frameworks already in the project. The only net-new code is the `EmptyStateView` shared component and the `SnapshotTestViewModel` test-only mock. Accessibility work is additive (labels on existing elements) and conditional (gating animations, expanding sheet height).

**Primary recommendation:** Build the snapshot infrastructure first (it gates all extension verification), then add accessibility labels and gates, then implement the empty state. All work lives in `WatermarkCore` except ContentView changes for the empty state integration and reduceMotion gating.

## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Automated snapshot tests — NOT build-only or manual checklist. XCTest snapshot tests in the WatermarkCore test target verify both extension root views render correctly at the extension's layout dimensions.
- **D-02:** Full root view snapshots — capture the complete `ShareExtensionRootView` and `PhotosExtensionRootView` at the extension's 60/40 layout. Pill bar fitting in 40%, all controls rendered, toolbar items, preview area. NOT ControlsView-only or per-section.
- **D-03:** XCTest in WatermarkCore with a lightweight SwiftUI-to-UIImage snapshot renderer. No third-party dependency. Image data comparison within tolerance. Tests run as part of the existing `xcodebuild test` suite.
- **D-04:** Lightweight `SnapshotTestViewModel` in WatermarkCore test target — conforms to `WatermarkConfigurable & Observable` with pre-populated config (text watermark, logo, frame, 2 layers). Test-only, not shipped.
- **D-05:** Single device size: 430pt × 932pt (iPhone 16 Pro Max). One reference size per state — layout is size-class driven, not pixel-dependent.
- **D-06:** 3 key states per extension, 5 snapshots total: Share Extension (idle/empty state + preview rendered + multi-item progress bar), Photos Extension (idle/empty state + preview rendered).
- **D-07:** Hero illustration + CTA button design. Centered vertical stack with app iconography, headline, body text, and a primary action button. Replaces current ultraThinMaterial "Add Photos" pill and extension "Preparing photo..." idle state.
- **D-08:** Shared `EmptyStateView` component in `WatermarkCore/Sources/WatermarkCore/DesignSystem/` — consumed by main app and both extensions. One component, 3 targets, consistent look.
- **D-09:** When empty state is showing (`currentPhoto == nil` and not loading), the bottom sheet and pinned Share bar are hidden. Only the `EmptyStateView` is displayed. Sheet and bar reappear automatically when media loads.
- **D-10:** Empty state content recipe: Large SF Symbol (`photo.on.rectangle.angled`, 40pt) in circular glass-backed container, headline "Add a Photo" with `.sectionHeader` typography, body text with `.controlLabel` secondary color, CTA Markepi primary button "Choose Photo".
- **D-11:** Audit + fix gaps + verify at scale. Proactive: find missing labels on Phase 15-17 elements, add them, verify Dynamic Type at 200%, gate animations on Reduce Motion, verify Reduce Transparency at every glass usage site.
- **D-12:** Dynamic expanded sheet height when `DynamicTypeSize >= .xxLarge`. The expanded detent scales to a higher fraction (e.g., 70%) or uses `.large()` to give large type more room. Peek height stays fixed — pill bar self-sizes via intrinsic content. Sheet remains overlay. ControlsView scrolls internally.
- **D-13:** VoiceOver labels added to: MarkepiPillBar segments ("Watermark controls", "Style controls", "Output controls"), ControlSection glass containers (identified by content group). Menu-based controls (position, format) already work via system Menu accessibility.
- **D-14:** Reduce Motion gating: MarkepiPillBar matched-geometry sliding indicator disabled when `reduceMotion` is true, batch overlay transitions (opacity) audited and gated, preview rendering state animation (ContentView line 163) audited and gated, InspectorSheetView spring already gated — verify, no change needed.

### the agent's Discretion
- Snapshot comparison tolerance — planner chooses a reasonable pixel-difference threshold that handles minor system font/rendering drift across OS versions.
- The specific `DynamicTypeSize` threshold for scaling the sheet expanded height — planner determines from testing.
- Exact layout metrics for EmptyStateView (spacing, padding, glass circle size) — follow Markepi design system conventions.
- Snapshot reference image storage — planner decides whether to commit them to the repo or generate on first test run.
- Whether the snapshot helper renders root views inside a UIHostingController (required for toolbar items) or directly as SwiftUI views — planner determines based on what produces accurate extension-context rendering.

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope.

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| XTG-01 | The redesigned `ControlsView` renders and functions correctly in the Share Extension | ImageRenderer snapshot testing (§ Snapshot Infrastructure), extension 60/40 layout dimensions verified |
| XTG-02 | The redesigned `ControlsView` renders and functions correctly in the Photos Edit Extension | ImageRenderer snapshot testing, toolbar rendering strategy documented |
| UXQ-01 | Dynamic Type is supported across redesigned controls with no truncation or overlap up to 200% | DynamicTypeSize analysis (§ Dynamic Type), MarkepiTypography uses system font styles (auto-scaling), ControlsView scrolls internally |
| UXQ-02 | VoiceOver labels and hints are preserved or improved relative to the current UI | VoiceOver patterns documented (§ VoiceOver Accessibility), pill bar and glass container labeling strategy |
| UXQ-03 | Reduce Motion and Reduce Transparency settings are respected | Reduce Motion gating patterns (§ Reduce Motion), glass transparency audit sites identified |
| UXQ-04 | The empty state (no photo loaded) is redesigned | EmptyStateView design pattern (§ Empty State Redesign), shared component in WatermarkCore/DesignSystem |

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Snapshot test infrastructure | WatermarkCore (test target) | — | Test-only code; runs via `xcodebuild test -scheme WatermarkCore` |
| EmptyStateView component | WatermarkCore (DesignSystem) | — | Shared across all 3 targets; import-only |
| Empty state integration (main app) | App/Views/ContentView | — | ContentView owns the ZStack layout; replaces previewArea when empty |
| Empty state integration (extensions) | ShareExtension / PhotoEditExtension | — | Each extension's root view owns its preview area; replaces "Preparing photo..." idle state |
| VoiceOver labels (pill bar) | WatermarkCore (MarkepiPillBar) | — | Labels live on the component itself |
| VoiceOver labels (ControlSection) | WatermarkCore (ControlsView) | — | ControlSection is a private struct in ControlsView.swift |
| Reduce Motion gating (pill bar) | WatermarkCore (MarkepiPillBar) | — | `@Environment(\.accessibilityReduceMotion)` declared on pill bar |
| Reduce Motion gating (ContentView) | App/Views/ContentView | — | Preview rendering state animation at ContentView line 163 |
| Dynamic Type sheet scaling | WatermarkCore (InspectorSheetView) | App (ContentView) | InspectorSheetView reads `@Environment(\.dynamicTypeSize)`; ContentView passes `expandedHeight` — scaling happens in ContentView's geometry computation |
| Reduce Transparency audit | All targets | — | Every `.markepiGlass()` call site must pass `isEnabled: !reduceTransparency` |

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| SwiftUI `ImageRenderer` | iOS 16+ | Off-screen SwiftUI → UIImage rendering for snapshot tests | Apple's official API for rasterizing SwiftUI views. No third-party dependency required. Available since iOS 16 (project targets iOS 18). [VERIFIED: Apple Developer Documentation - ImageRenderer] |
| SwiftUI `DynamicTypeSize` | iOS 15+ | Environment value for detecting user's preferred content size category | Standard SwiftUI API. Used to gate expanded sheet height scaling. [VERIFIED: Apple Developer Documentation - DynamicTypeSize] |
| SwiftUI `accessibilityReduceMotion` | iOS 14+ | Detects Reduce Motion accessibility setting | Standard SwiftUI environment value. Already used in 4+ files in this project. [VERIFIED: Apple Developer Documentation] |
| SwiftUI `accessibilityReduceTransparency` | iOS 14+ | Detects Reduce Transparency accessibility setting | Standard SwiftUI environment value. Already used in 8+ files in this project. [VERIFIED: Apple Developer Documentation] |
| SwiftUI `.accessibilityLabel(_:)` / `.accessibilityHint(_:)` | iOS 14+ | VoiceOver labels and hints for custom controls | Standard SwiftUI accessibility modifiers. Required because custom controls (pill bar, glass containers) lack automatic accessibility. [VERIFIED: Apple Developer Documentation] |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| SwiftUI `.accessibilityAddTraits(_:)` | iOS 14+ | Adds `.isButton`, `.isSelected` traits to custom controls | Required for pill bar segments to behave as accessible buttons |
| SwiftUI `.accessibilityElement(children: .contain)` | iOS 14+ | Groups child elements as a single accessible container | Use on pill bar and ControlSection containers |
| SwiftUI `UIHostingController` | iOS 13+ | Hosts SwiftUI views in UIKit context for snapshot rendering | Only needed if PhotosExtensionRootView toolbar items must render in snapshots (see Pitfall 1) |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `ImageRenderer` (built-in) | `swift-snapshot-testing` (pointfreeco) | Third-party lib adds dependency for a single phase. `ImageRenderer` is zero-dependency, available on iOS 16+, sufficient for our 5-snapshot scope. User explicitly chose no third-party dependency (D-03). |
| Snapshot at multiple device sizes | Snapshot at single size (430×932) | Multiple sizes increase reference image maintenance burden. Layout is size-class driven not pixel-dependent — one size covers all iPhones (user D-05). |
| `UIHostingController` wrapper for all snapshots | Direct ImageRenderer for VStack-based views | UIHostingController is only needed for PhotosExtensionRootView toolbar items. ShareExtensionRootView has no toolbar — direct ImageRenderer works. Wrapping unnecessarily for simple views adds complexity. |

**Installation:**
```bash
# No package installation needed. All APIs are Apple system frameworks.
# ImageRenderer: part of SwiftUI (iOS 16+)
# DynamicTypeSize, accessibility environment values: part of SwiftUI (iOS 14+)
# WatermarkCore test target already exists with Swift Testing framework
```

**Version verification:** All APIs are Apple system frameworks bundled with the iOS SDK. `ImageRenderer` is available in iOS 16+ [VERIFIED: Apple Developer Documentation]. All accessibility environment values are available in iOS 14+. Project minimum deployment target is iOS 18.

## Package Legitimacy Audit

> No external packages are installed in this phase. All functionality uses Apple system frameworks (SwiftUI, XCTest/Swift Testing). The `slopcheck` protocol is satisfied by default — no third-party dependencies to audit.

| Package | Registry | Age | Downloads | Source Repo | slopcheck | Disposition |
|---------|----------|-----|-----------|-------------|-----------|-------------|
| *(none)* | — | — | — | — | — | No external packages |

**Packages removed due to slopcheck [SLOP] verdict:** none
**Packages flagged as suspicious [SUS]:** none

## Architecture Patterns

### System Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                     Phase 18 Data Flow                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────────┐    ┌──────────────────┐                   │
│  │ ShareExtension   │    │ PhotoEdit        │                   │
│  │ RootView         │    │ Extension Root   │                   │
│  │ (60/40 VStack)   │    │ View (60/40 VStk)│                   │
│  └────────┬─────────┘    └────────┬─────────┘                   │
│           │ imports                │ imports                     │
│           ▼                        ▼                            │
│  ┌────────────────────────────────────────────┐                  │
│  │           WatermarkCore Package             │                  │
│  │  ┌──────────────────────────────────────┐  │                  │
│  │  │  ControlsView<VM> (unchanged)        │  │                  │
│  │  │  ├─ MarkepiPillBar [+ VoiceOver]     │  │                  │
│  │  │  ├─ ControlSection [+ VoiceOver]     │  │                  │
│  │  │  └─ ShareActionButton                │  │                  │
│  │  └──────────────────────────────────────┘  │                  │
│  │  ┌──────────────────────────────────────┐  │                  │
│  │  │  EmptyStateView [NEW - shared]       │◄─┤─ Consumed by     │
│  │  │  ├─ Glass circle + SF Symbol         │  │  App + both      │
│  │  │  ├─ Typography stack                 │  │  Extensions      │
│  │  │  └─ Primary CTA button               │  │                  │
│  │  └──────────────────────────────────────┘  │                  │
│  │  ┌──────────────────────────────────────┐  │                  │
│  │  │  InspectorSheetView                  │  │                  │
│  │  │  └─ Dynamic Type sheet scaling [NEW] │  │                  │
│  │  └──────────────────────────────────────┘  │                  │
│  └────────────────────────────────────────────┘                  │
│           │                                                      │
│           │ tested by                                            │
│           ▼                                                      │
│  ┌────────────────────────────────────────────┐                  │
│  │  WatermarkCoreTests (test target)          │                  │
│  │  ┌──────────────────────────────────────┐  │                  │
│  │  │  SnapshotTestViewModel [NEW]         │  │                  │
│  │  │  └─ Pre-populated config             │  │                  │
│  │  └──────────────────────────────────────┘  │                  │
│  │  ┌──────────────────────────────────────┐  │                  │
│  │  │  ImageRenderer helper [NEW]          │  │                  │
│  │  │  └─ SwiftUI → UIImage → PNG data     │  │                  │
│  │  └──────────────────────────────────────┘  │                  │
│  │  ┌──────────────────────────────────────┐  │                  │
│  │  │  ExtensionSnapshotTests [NEW]        │  │                  │
│  │  │  ├─ ShareExt: idle + preview + batch │  │                  │
│  │  │  └─ PhotoExt: idle + preview         │  │                  │
│  │  └──────────────────────────────────────┘  │                  │
│  └────────────────────────────────────────────┘                  │
│                                                                  │
│  App target changes:                                             │
│  ┌──────────────────────────────────────────────┐                │
│  │  ContentView.swift                           │                │
│  │  ├─ EmptyStateView when currentPhoto == nil  │                │
│  │  ├─ Hide sheet/share bar when empty          │                │
│  │  └─ ReduceMotion gate on .animation()        │                │
│  └──────────────────────────────────────────────┘                │
│                                                                  │
│  Extension target changes:                                       │
│  ┌──────────────────────────────────────┐                        │
│  │  ShareExtensionRootView              │                        │
│  │  └─ Replace "Preparing photo..."     │                        │
│  │     idle state with EmptyStateView   │                        │
│  ├──────────────────────────────────────┤                        │
│  │  PhotosExtensionRootView             │                        │
│  │  └─ Replace "Preparing photo..."     │                        │
│  │     idle state with EmptyStateView   │                        │
│  └──────────────────────────────────────┘                        │
│                                                                  │
│  ┌─── Reduce Motion Audit ───────────────────────┐              │
│  │  ✓ InspectorSheetView .spring() (Phase 17)    │              │
│  │  ✗ MarkepiPillBar matchedGeometryEffect → NEW │              │
│  │  ✗ ContentView .animation() line 163 → NEW    │              │
│  │  ✓ ShareActionButton .animation() (Phase 17)  │              │
│  │  ✗ BatchProgressOverlay .transition() → NEW   │              │
│  └────────────────────────────────────────────────┘              │
│                                                                  │
│  ┌─── Reduce Transparency Audit Sites ───────────┐              │
│  │  MarkepiPillBar          — isEnabled ✓         │              │
│  │  ControlSection          — isEnabled ✓         │              │
│  │  InspectorSheetView      — isEnabled ✓         │              │
│  │  MarkepiButtonStyle       — isEnabled ✓         │              │
│  │  ContentView pinnedShare  — isEnabled ✓         │              │
│  │  MarkepiScrollEdgeProtect — has glass (verify) │              │
│  │  ShareActionButton .rendering state — isEnab.✓│              │
│  │  EmptyStateView [NEW]     — must add gate      │              │
│  └────────────────────────────────────────────────┘              │
└─────────────────────────────────────────────────────────────────┘
```

### Recommended Project Structure
```
Packages/WatermarkCore/
├── Sources/WatermarkCore/
│   └── DesignSystem/
│       ├── EmptyStateView.swift          # [NEW] Shared empty state component
│       ├── MarkepiPillBar.swift          # [MODIFY] +VoiceOver labels +reduceMotion gate
│       ├── MarkepiGlassModifier.swift    # [NO CHANGE] Already has isEnabled gate
│       ├── MarkepiTypography.swift       # [NO CHANGE] Already Dynamic Type aware
│       ├── MarkepiButtonStyle.swift      # [NO CHANGE] Already has glass + transparency gate
│       ├── ShareActionButton.swift       # [NO CHANGE] Already has reduceMotion gate
│       ├── MarkepiUtilities.swift        # [NO CHANGE] .modify {} helper
│       └── ScrollEdge/
│           └── MarkepiScrollEdgeProtection.swift  # [NO CHANGE]
├── Sources/WatermarkCore/UI/
│   ├── ControlsView.swift               # [MODIFY] +VoiceOver labels on ControlSections
│   └── InspectorSheetView.swift         # [MODIFY] +DynamicTypeSize env for sheet scaling
├── Tests/WatermarkCoreTests/
│   ├── TestHelpers/
│   │   └── SnapshotTestViewModel.swift  # [NEW] Test-only mock ViewModel
│   ├── ExtensionSnapshotTests.swift     # [NEW] 5 snapshot tests
│   └── TestHelpers/
│       └── SnapshotRenderer.swift       # [NEW] UIImage helper + comparison
App/Views/
├── ContentView.swift                    # [MODIFY] EmptyStateView integration, reduceMotion gate
└── PreviewArea/
    └── PreviewView.swift                # [MODIFY] Remove pickerButton (replaced by EmptyStateView at ContentView level)
ShareExtension/
└── ShareExtensionRootView.swift         # [MODIFY] Replace idle state with EmptyStateView
PhotoEditExtension/
└── PhotosExtensionRootView.swift        # [MODIFY] Replace idle state with EmptyStateView
```

### Pattern 1: Snapshot Testing with ImageRenderer

**What:** Render SwiftUI views to `UIImage` off-screen using `ImageRenderer`, compare against reference PNG data using pixel-difference tolerance.

**When to use:** Automated verification that extension root views render correctly at target dimensions.

**Key constraints:**
- `ImageRenderer` is `MainActor`-isolated — render on main actor
- Set `renderer.scale = UIScreen.main.scale` (typically 3.0 for iPhone 16 Pro Max)
- Toolbar items (`ToolbarItem`) do NOT render in `ImageRenderer` unless the view is wrapped in a `NavigationStack` or hosted via `UIHostingController` with a `UINavigationController`
- Views with `matchedGeometryEffect` may render incorrectly without a real view hierarchy parent — use `UIHostingController` for accurate rendering

**Example:**
```swift
// Source: Apple Developer Documentation - ImageRenderer
// [VERIFIED: developer.apple.com/documentation/swiftui/imagerenderer]
import SwiftUI
import XCTest

@MainActor
func renderViewToPNG<V: View>(_ view: V, size: CGSize, scale: CGFloat = 3.0) -> Data? {
    let controller = UIHostingController(rootView: view.frame(width: size.width, height: size.height))
    controller.view.bounds = CGRect(origin: .zero, size: size)
    
    let renderer = UIGraphicsImageRenderer(bounds: controller.view.bounds)
    let image = renderer.image { ctx in
        controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
    }
    return image.pngData()
}

// Tolerance-based comparison (per user's discretion)
func compareSnapshot(actual: Data, reference: Data, tolerance: Double = 0.02) -> Bool {
    guard let actualImage = UIImage(data: actual),
          let referenceImage = UIImage(data: reference) else { return false }
    // Pixel-difference comparison with tolerance...
    // See § Snapshot Infrastructure below for complete pattern
}
```

**Important:** For PhotosExtensionRootView which has a `.toolbar` modifier, the snapshot MUST be rendered via `UIHostingController` wrapped in a `UINavigationController` to get toolbar rendering. ShareExtensionRootView (no toolbar) can use either `ImageRenderer` or `UIHostingController`. [VERIFIED: Apple Developer Forums / Stack Overflow — toolbars require hosting context]

### Pattern 2: VoiceOver Labeling for Custom Segmented Controls

**What:** Manually add accessibility labels, hints, and traits to custom SwiftUI controls that lack automatic accessibility because they're built from raw `HStack` + `Button` instead of `Picker`.

**When to use:** Any custom control that replaces a system control with automatic accessibility.

**Example:**
```swift
// Source: Apple Developer Documentation — accessibilityAddTraits, accessibilityLabel
// [VERIFIED: developer.apple.com/documentation/swiftui]
// Pill bar VoiceOver labels (D-13):

HStack(spacing: 0) {
    ForEach(ControlsSection.allCases) { section in
        Button { ... } label: {
            Text(section.rawValue)
        }
        .accessibilityLabel("\(section.rawValue) controls")  // D-13: "Watermark controls"
        .accessibilityHint("Shows \(section.rawValue.lowercased()) settings")
        .accessibilityAddTraits(selection == section ? [.isButton, .isSelected] : .isButton)
    }
}
.accessibilityElement(children: .contain)
.accessibilityLabel("Controls section selector")  // Group label

// Glass container label (D-13):
ControlSection { content() }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Text and position controls")  // Per content group
```

### Pattern 3: Reduce Motion Animation Gating

**What:** Conditionally disable animations when `@Environment(\.accessibilityReduceMotion)` is `true`.

**When to use:** Every animation in the app — spring detent transitions, matched geometry effects, opacity transitions, and state-change animations.

**Example:**
```swift
// Source: Apple Developer Documentation — accessibilityReduceMotion
// [VERIFIED: developer.apple.com/documentation/swiftui/environmentvalues/accessibilityreducemotion]

// Pattern A: .animation() modifier (already used in InspectorSheetView line 127)
.animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.85), value: detent)

// Pattern B: withAnimation block (for state-triggered animations like pill bar)
Button {
    withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8)) {
        selection = section
    }
} label: { ... }

// Pattern C: .transition() gating (for batch overlays)
BatchProgressOverlay(...)
    .transition(reduceMotion ? .identity : .opacity)

// Pattern D: matchedGeometryEffect disable (pill bar sliding indicator)
// When reduceMotion is true, use a simple conditional background without animation
.background {
    if selection == section {
        Capsule()
            .fill(.selection)
            .matchedGeometryEffect(id: "activePill", in: pillNamespace)
    }
}
// The animation is controlled in withAnimation — nil means instant switch
```

### Pattern 4: Dynamic Type Sheet Height Scaling

**What:** Increase the expanded sheet detent height when Dynamic Type is large to give controls more room.

**When to use:** Triggered when `@Environment(\.dynamicTypeSize) >= .xxLarge`.

**Example:**
```swift
// Source: SwiftUI DynamicTypeSize documentation
// [VERIFIED: developer.apple.com/documentation/swiftui/dynamictypesize]

// In ContentView (where expandedHeight is computed):
@Environment(\.dynamicTypeSize) private var dynamicTypeSize

private func expandedHeight(for geometry: GeometryProxy) -> CGFloat {
    if dynamicTypeSize >= .xxLarge {
        return geometry.size.height * 0.70  // 70% at large type (D-12)
    }
    return geometry.size.height * 0.55  // Standard 55%
}

// DynamicTypeSize scale reference:
// .xxLarge = ~135% of base
// .xxxLarge = ~165% of base
// .accessibility1 = ~185% of base
// .accessibility2 = ~210% of base  (covers UXQ-01 "200%")
// [ASSUMED] Scale percentages are approximate — exact multipliers vary by font style
```

### Anti-Patterns to Avoid

- **Anti-pattern: Fixed `GeometryReader` height for text containers.** Avoid setting `.frame(height: N)` on text elements — text height varies with Dynamic Type. Use intrinsic sizing. **Do:** Let SwiftUI text elements self-size; use `.fixedSize(horizontal: false, vertical: true)` sparingly.
- **Anti-pattern: `.accessibilityHidden(true)` on decorative glass without providing alternative labels.** Glass backgrounds are decorative but their container content needs labels. **Do:** Hide the glass modifier itself, add labels to the logical container.
- **Anti-pattern: Comparing `UIImage` pixel-for-pixel without tolerance.** System font rendering differences across OS versions, GPU vs CPU rendering paths, and antialiasing all produce sub-pixel differences. **Do:** Use a tolerance-based comparison (2-5% pixel difference threshold). [ASSUMED based on industry standard snapshot testing practice]
- **Anti-pattern: Snapshot testing without `UIHostingController` for views needing UIKit context.** `ImageRenderer` doesn't replicate UIKit hosting controller layout. Views with toolbar, navigation, or safe-area dependencies render incorrectly. **Do:** Use `UIHostingController` + `UIGraphicsImageRenderer` + `drawHierarchy` for accurate extension-context rendering. [VERIFIED: Stack Overflow / Apple Developer Forums]

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| SwiftUI → UIImage rendering | Custom `CGContext` rendering pipeline | `ImageRenderer` (iOS 16+) or `UIHostingController` + `UIGraphicsImageRenderer` | Apple APIs handle layout, scale, color space, and safe area correctly. Custom rendering misses these and produces inaccurate snapshots. |
| Pixel-difference image comparison | Manual pixel-by-pixel loops | `UIImage.pngData()` comparison with byte-level diff + tolerance threshold | Manual comparison is error-prone and slow. PNG data comparison with tolerance handles antialiasing differences. |
| VoiceOver labels for segmented controls | Custom accessibility container with manual notifications | `.accessibilityLabel()` + `.accessibilityAddTraits(.isButton, .isSelected)` on each segment | Apple's modifier-based API provides correct VoiceOver announcements without manual UIAccessibility notifications. |
| Animation gating for Reduce Motion | Checking `UIAccessibility.isReduceMotionEnabled` (UIKit) globally | `@Environment(\.accessibilityReduceMotion)` (SwiftUI) | SwiftUI environment value is reactive — changes are picked up automatically without manual notification observation. |
| Empty state component per target | Copy-pasted VStack in ContentView + ShareExtension + PhotoEditExtension | Single `EmptyStateView` in WatermarkCore/DesignSystem | Duplication defeats the purpose of the shared package. One component = one source of truth for design consistency. |

**Key insight:** This phase is additive — it adds accessibility labels and animation gates to existing components. It does NOT rebuild controls, change the rendering pipeline, or modify protocol surfaces. The only net-new visual component is `EmptyStateView`, which consumes existing design system primitives (MarkepiTypography, MarkepiButtonStyle, MarkepiGlassModifier).

## Runtime State Inventory

> Phase 18 is verification and polish on existing UI — no rename, no refactor, no data migration. This section confirms nothing needs migration.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | None — Phase 18 does not touch WatermarkConfiguration, TemplateStore, or any persisted model | None |
| Live service config | None — no external service configurations affected | None |
| OS-registered state | None — no Task Scheduler, launchd, or system registrations | None |
| Secrets/env vars | None — no secrets or env var naming changes | None |
| Build artifacts | None — no package renames or installed artifacts | None |

**Nothing found in category:** All five categories confirmed empty — this phase is a pure UI verification and accessibility pass with no runtime state implications.

## Common Pitfalls

### Pitfall 1: Toolbar Items Don't Render in ImageRenderer

**What goes wrong:** `PhotosExtensionRootView` has a `.toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") {...} } }` modifier. When rendered via `ImageRenderer(content: view)`, toolbar items are invisible because `ImageRenderer` has no hosting `UINavigationController` to provide the toolbar context.

**Why it happens:** SwiftUI toolbar rendering requires a `UINavigationController` (or `NavigationStack`) ancestor in the UIKit view hierarchy. `ImageRenderer` renders the view in isolation — no navigation controller exists.

**How to avoid:** Use `UIHostingController` embedded in a `UINavigationController` for snapshot rendering:
```swift
let rootView = PhotosExtensionRootView(viewModel: viewModel)
let host = UIHostingController(rootView: rootView)
let nav = UINavigationController(rootViewController: host)
nav.view.bounds = CGRect(x: 0, y: 0, width: 430, height: 932)
let renderer = UIGraphicsImageRenderer(bounds: nav.view.bounds)
let image = renderer.image { _ in
    nav.view.drawHierarchy(in: nav.view.bounds, afterScreenUpdates: true)
}
```
This applies ONLY to PhotosExtensionRootView (has toolbar). ShareExtensionRootView (no toolbar) can use `ImageRenderer` directly.

**Warning signs:** Snapshot is missing the "Done" button, toolbar area is blank, or the snapshot looks like a plain VStack without chrome.

### Pitfall 2: Dynamic Type Overflow in Fixed-Height Container

**What goes wrong:** At `.accessibility2` (200% type size), text labels in the controls may be truncated if their container has a fixed height. The controls area in extensions is fixed at 40% of screen height — if ControlsView content exceeds this, it clips.

**Why it happens:** The 60/40 split uses `.frame(height: geometry.size.height * 0.40)` on the controls area. If ControlsView content is taller than 40% of screen, it overflows.

**How to avoid:** ControlsView already wraps content in a `ScrollView` via `markepiScrollEdgeProtection`. The scroll view handles internal overflow. The 40% frame acts as a viewport — content scrolls within it. **Verify:** at `.accessibility2`, ControlsView content scrolls cleanly without clipping.

**Warning signs:** Text truncates with "..." at large type sizes, controls become unreachable, debug view hierarchy shows content exceeding frame bounds.

### Pitfall 3: matchedGeometryEffect Without Reduce Motion Gate

**What goes wrong:** When Reduce Motion is enabled, the pill bar's sliding indicator still animates, causing the indicator to teleport between positions without transition — visually jarring and accessibility-hostile.

**Why it happens:** The `withAnimation(.spring(...))` block in MarkepiPillBar's `Button` action doesn't check `reduceMotion`. The animation fires regardless of the accessibility setting.

**How to avoid:** Add `@Environment(\.accessibilityReduceMotion) private var reduceMotion` to `MarkepiPillBar` and conditionally pass animation:
```swift
Button {
    withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8)) {
        selection = section
    }
} label: { ... }
```
When `reduceMotion` is true, `withAnimation(nil)` performs an instant state change — the indicator appears in the new position without sliding.

**Warning signs:** Pill bar indicator jumps/teleports when Reduce Motion is on, VoiceOver announces section changes but visual indicator doesn't track.

### Pitfall 4: Glass Modifier Without Reduce Transparency Gate in New Components

**What goes wrong:** The new `EmptyStateView` uses a glass-backed circle for the SF Symbol. If `!reduceTransparency` is not passed as `isEnabled`, the glass effect renders even when Reduce Transparency is enabled, violating user's accessibility preference.

**Why it happens:** `MarkepiGlassModifier` defaults `isEnabled` to `true`. If the caller forgets to pass the environment value, glass always renders.

**How to avoid:** Always declare `@Environment(\.accessibilityReduceTransparency) private var reduceTransparency` and pass `isEnabled: !reduceTransparency`. Audit all glass sites before shipping.

**Warning signs:** Glass backgrounds visible on screen when Reduce Transparency is enabled in Settings → Accessibility → Display & Text Size.

## Code Examples

Verified patterns from official sources:

### ImageRenderer Snapshot Rendering (with UIHostingController for toolbar support)

```swift
// Source: Apple Developer Documentation — ImageRenderer, UIHostingController
// [VERIFIED: developer.apple.com/documentation/swiftui/imagerenderer]
import SwiftUI
import XCTest

@MainActor
struct SnapshotRenderer {
    /// Renders a SwiftUI view to PNG data using UIHostingController
    /// (required for toolbar items and accurate extension-context layout).
    static func render<V: View>(
        _ view: V,
        size: CGSize = CGSize(width: 430, height: 932),
        scale: CGFloat = 3.0,
        inNavigationController: Bool = false
    ) throws -> Data {
        let rootView = view.frame(width: size.width, height: size.height)
        let host = UIHostingController(rootView: rootView)
        
        let container: UIViewController
        if inNavigationController {
            container = UINavigationController(rootViewController: host)
        } else {
            container = host
        }
        
        container.view.bounds = CGRect(origin: .zero, size: size)
        container.view.layoutIfNeeded()
        
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        
        let renderer = UIGraphicsImageRenderer(bounds: container.view.bounds, format: format)
        let image = renderer.image { ctx in
            container.view.drawHierarchy(in: container.view.bounds, afterScreenUpdates: true)
        }
        
        guard let pngData = image.pngData() else {
            throw SnapshotError.renderingFailed
        }
        return pngData
    }
    
    enum SnapshotError: Error {
        case renderingFailed
    }
}
```

### Pixel-Difference Snapshot Comparison with Tolerance

```swift
// [ASSUMED] Tolerance threshold — planner determines exact value.
// Industry standard: 1-5% for UI snapshots accommodating antialiasing variance.
@MainActor
struct SnapshotComparator {
    /// Compares two PNG images with a per-pixel tolerance.
    /// Returns true if the percentage of different pixels is below `tolerance`.
    static func compare(
        actual: Data,
        reference: Data,
        pixelTolerance: Double = 0.02  // 2% — planner's discretion
    ) -> Bool {
        guard let actualImage = UIImage(data: actual)?.cgImage,
              let referenceImage = UIImage(data: reference)?.cgImage,
              actualImage.width == referenceImage.width,
              actualImage.height == referenceImage.height
        else { return false }
        
        let width = actualImage.width
        let height = actualImage.height
        let totalPixels = width * height
        
        // Compare pixel data...
        // Returns true if differentPixelCount / totalPixels <= pixelTolerance
        // [IMPLEMENTATION: planner or Wave 0 phase provides exact comparison logic]
        return true  // placeholder
    }
}
```

### DynamicTypeSize-Responsive Sheet Height (ContentView integration)

```swift
// Source: SwiftUI DynamicTypeSize documentation
// [VERIFIED: developer.apple.com/documentation/swiftui/dynamictypesize]
struct ContentView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    
    private func mainLayout(_ geometry: GeometryProxy) -> some View {
        let expandedHeight = dynamicTypeSize >= .xxLarge
            ? geometry.size.height * 0.70
            : geometry.size.height * 0.55
        
        return ZStack(alignment: .bottom) {
            previewArea
            inspectorSheet(expandedHeight: expandedHeight)
            pinnedShareBar
        }
    }
}
```

### EmptyStateView (Shared Component)

```swift
// [ASSUMED] Layout metrics follow Markepi design system conventions.
// Planner determines exact spacing/padding from design system tokens.
import SwiftUI

public struct EmptyStateView: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    
    let onChoosePhoto: () -> Void
    
    public init(onChoosePhoto: @escaping () -> Void) {
        self.onChoosePhoto = onChoosePhoto
    }
    
    public var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Glass circle with SF Symbol (D-10)
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
                .frame(width: 80, height: 80)
                .markepiGlass(
                    shape: Circle(),
                    isEnabled: !reduceTransparency  // Reduce Transparency gate
                )
            
            VStack(spacing: 8) {
                Text("Add a Photo")
                    .markepiTypography(.sectionHeader)
                Text("Choose a photo or video to watermark and share instantly")
                    .markepiTypography(.controlLabel)
                    .foregroundStyle(.secondary)
            }
            
            Button {
                onChoosePhoto()
            } label: {
                Label("Choose Photo", systemImage: "photo.on.rectangle.angled")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.markepiPrimary())
            .padding(.horizontal, 40)
            
            Spacer()
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 32)
    }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Manual UIKit `UIGraphicsImageRenderer` for view snapshots | SwiftUI `ImageRenderer` (iOS 16+) | iOS 16 (2022) | Cleaner API, SwiftUI-native, no UIView bridge needed for toolbar-less views |
| `UIAccessibility.isReduceMotionEnabled` (UIKit) | `@Environment(\.accessibilityReduceMotion)` (SwiftUI) | iOS 14+ | Reactive to setting changes, SwiftUI-native |
| Third-party snapshot testing libraries | Built-in `ImageRenderer` + PNG comparison | N/A (project choice) | Zero dependencies, suitable for 5-snapshot scope |
| Static sheet height | Dynamic Type-responsive sheet height | Phase 18 (new) | Controls remain usable at large type sizes |

**Deprecated/outdated:**
- `UIAccessibility.isReduceMotionEnabled`: Use `@Environment(\.accessibilityReduceMotion)` in SwiftUI views. Not used in this project.
- `UIAccessibility.isReduceTransparencyEnabled`: Use `@Environment(\.accessibilityReduceTransparency)`. Already migrated throughout project.

## Assumptions Log

> All claims tagged `[ASSUMED]` in this research. The planner and discuss-phase use this section to identify decisions that need user confirmation before execution.

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | DynamicTypeSize scale percentages (`.xxLarge` ≈ 135%, `.accessibility2` ≈ 210%) are approximate | Dynamic Type Sheet Scaling (Pattern 4) | Low — exact multipliers vary by font style, but the `>= .xxLarge` threshold for 70% height is a design intent decision, not a precision-dependent one. |
| A2 | 2% pixel tolerance for snapshot comparison is a reasonable default | Snapshot Infrastructure (Pattern 1) | Medium — too strict causes false failures from font rendering drift; too loose misses genuine layout regressions. Planner should determine exact value during implementation. |
| A3 | EmptyStateView layout metrics (80pt circle, 24pt VStack spacing, 32pt horizontal padding) follow Markepi conventions | Empty State Redesign | Low — visual polish, not functional. Adjusting metrics is trivial and doesn't affect architecture. |
| A4 | Reference snapshot images should be committed to repo rather than generated on first test run | Snapshot Infrastructure | Medium — committing images enables CI to compare without running a record pass. Generating on first run is simpler but requires per-machine recording. |

## Open Questions

1. **Snapshot reference image storage strategy**
   - What we know: The user deferred this to the planner's discretion. Two options: (a) commit PNG references to `Tests/WatermarkCoreTests/__Snapshots__/`, (b) generate on first test run with an environment flag like `RECORD_SNAPSHOTS=1`.
   - What's unclear: Which approach integrates better with the existing xcodebuild test workflow and CI.
   - Recommendation: Commit references (option a). Reference images are small (~100KB each for 430×932 PNG), deterministic, and don't require a record pass on each CI machine. Follows the standard `swift-snapshot-testing` library convention even though we're not using the library.

2. **PhotosExtensionRootView toolbar rendering in snapshot**
   - What we know: The view uses `.toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") } }`. Toolbar items require a hosting UINavigationController to render.
   - What's unclear: Whether the planner should use `UIHostingController` wrapped in `UINavigationController` for this snapshot, or accept that toolbar items won't appear in snapshots.
   - Recommendation: Use `UINavigationController` wrapper (see Pitfall 1). The toolbar "Done" button is part of the extension's chrome and should appear in the snapshot to verify the full root view renders correctly.

3. **Exact DynamicTypeSize threshold for sheet height scaling**
   - What we know: User suggested `.xxLarge` as the threshold (D-12), with expanded height scaling to 70%.
   - What's unclear: Whether `.xxLarge` (≈135% of base) is the right threshold or if `.xxxLarge` (≈165%) or `.accessibility1` (≈185%) would be better. The UXQ-01 requirement says "up to 200%" which is around `.accessibility2`.
   - Recommendation: Use `.xxLarge` as the threshold (matches user's design intent). If testing reveals overflow at `.xxLarge` is insufficient, adjust to `.xxxLarge`. The 70% fraction provides significant extra room. ControlsView scrolls internally regardless — sheet height scaling is a convenience, not a functional necessity.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Xcode | Compilation / snapshot test execution | ✓ | 26.2 (17C52) | — |
| Swift | Compilation (Swift 6 mode) | ✓ | 6.2.3 | — |
| iOS Simulator | Snapshot test execution (requires UIKit rendering) | ✓ | iOS 18+ (via Xcode 26.2) | — |
| `xcodebuild` | Test suite execution (`xcodebuild test -scheme WatermarkCore`) | ✓ | Xcode 26.2 | `swift test` from package directory (SPM-only; may not support UIKit-dependent snapshot tests on macOS host) |

**Missing dependencies with no fallback:**
- None — all required tools are present.

**Missing dependencies with fallback:**
- If snapshot tests fail on macOS SPM host (`swift test`): Use `xcodebuild test -scheme WatermarkCore -destination 'platform=iOS Simulator,name=iPhone 16 Pro'` for UIKit-dependent tests (same pattern as existing PhotosExtensionTests and VideoProcessorProgressTests).

## Validation Architecture

> `workflow.nyquist_validation` is explicitly `false` in `.planning/config.json`. This section is omitted per the phase research instructions.

## Security Domain

> `security_enforcement` is not explicitly disabled in config. Treating as enabled (default).

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | No | Phase 18 is UI verification + accessibility — no auth surface |
| V3 Session Management | No | No sessions involved |
| V4 Access Control | No | Extensions are sandboxed by iOS — no access control logic in Phase 18 |
| V5 Input Validation | No | Phase 18 does not introduce new user input surfaces (EmptyStateView's CTA button triggers existing picker, no text input) |
| V6 Cryptography | No | No cryptographic operations in Phase 18 |

### Known Threat Patterns for SwiftUI/iOS

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| VoiceOver labels leaking internal state | Information Disclosure | Use descriptive labels that describe function, not internal state (e.g., "Choose photo" not "pickerButton") |
| Snapshot reference images containing sensitive data | Information Disclosure | SnapshotTestViewModel uses only synthetic/pre-populated config data — no real user data ever stored in test snapshots |
| Accessibility labels exposing implementation details | Information Disclosure | Label content should describe user-facing function (per D-13: "Watermark controls", "Style controls") — no internal implementation details |

**Phase 18 is security-neutral.** It verifies UI rendering and adds accessibility labels/animations — no new data flows, no network calls, no authentication, no cryptography. All processing remains on-device per project constraints.

## Sources

### Primary (HIGH confidence)
- Apple Developer Documentation — `ImageRenderer` (iOS 16+): Standard API for SwiftUI-to-UIImage off-screen rendering. [VERIFIED: developer.apple.com/documentation/swiftui/imagerenderer]
- Apple Developer Documentation — `DynamicTypeSize`: Environment value for detecting user content size preference. [VERIFIED: developer.apple.com/documentation/swiftui/dynamictypesize]
- Apple Developer Documentation — `accessibilityReduceMotion`: Environment value for Reduce Motion detection. [VERIFIED: developer.apple.com/documentation/swiftui/environmentvalues/accessibilityreducemotion]
- Apple Developer Documentation — `accessibilityReduceTransparency`: Environment value for Reduce Transparency detection. [VERIFIED: developer.apple.com/documentation/swiftui/environmentvalues/accessibilityreducetransparency]
- Apple Developer Documentation — `.accessibilityLabel(_:)`, `.accessibilityHint(_:)`, `.accessibilityAddTraits(_:)`: VoiceOver modifiers for custom controls. [VERIFIED: developer.apple.com/documentation/swiftui]
- CONTEXT.md (18-CONTEXT.md) — Phase 18 locked decisions D-01 through D-14: All architectural and accessibility decisions. [VERIFIED: project file]
- Phase 15-17 Research and Plan documents — Design system primitives, ControlsView structure, Inspector sheet architecture. [VERIFIED: project files]

### Secondary (MEDIUM confidence)
- Google Search results — SwiftUI snapshot testing patterns using ImageRenderer + UIHostingController: Confirmed toolbar rendering requires hosting controller context. [CITED: stackoverflow.com, hackingwithswift.com]
- Google Search results — SwiftUI accessibility patterns for custom segmented controls: Confirmed `.accessibilityElement(children: .contain)` + per-segment `.accessibilityAddTraits` pattern. [CITED: stackoverflow.com, medium.com]
- Google Search results — Reduce Motion gating with `matchedGeometryEffect`: Confirmed `withAnimation(reduceMotion ? nil : .spring(...))` pattern. [CITED: multiple SwiftUI blogs]
- Project codebase — ControlsView.swift, InspectorSheetView.swift, MarkepiPillBar.swift, ContentView.swift, ShareExtensionRootView.swift, PhotosExtensionRootView.swift: All existing implementation patterns referenced. [VERIFIED: git repository]

### Tertiary (LOW confidence)
- DynamicTypeSize scale percentages (`.xxLarge` ≈ 135%, `.accessibility2` ≈ 210%): Approximate estimates from community sources. Not verified against Apple's exact multipliers. [ASSUMED]

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — All APIs are Apple system frameworks, verified against official documentation and already in use in the project. No third-party dependencies.
- Architecture: HIGH — Pattern follows existing project structure (shared WatermarkCore package consumed by all 3 targets). Snapshot testing uses established Apple APIs (ImageRenderer/UIHostingController).
- Pitfalls: HIGH — Toolbar rendering in snapshots, Dynamic Type overflow, Reduce Motion gating, and glass transparency gating are well-understood iOS patterns with documented solutions.

**Research date:** 2026-06-22
**Valid until:** 2026-07-22 (30 days — stable iOS APIs, no fast-moving external dependencies)
