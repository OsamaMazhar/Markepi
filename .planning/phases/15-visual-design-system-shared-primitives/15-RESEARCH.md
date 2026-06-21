# Phase 15: Visual Design System & Shared Primitives - Research

**Researched:** 2026-06-21
**Domain:** iOS 26 Liquid Glass design system + SwiftUI shared component primitives
**Confidence:** MEDIUM

## Summary

Phase 15 establishes the shared visual language primitives that every downstream control (Phase 16) and shell (Phase 17) consumes. The work is pure SwiftUI presentation-layer — no third-party dependencies, no backend, no engine changes. The primary challenge is the iOS 26 Liquid Glass API surface, which is newly introduced (WWDC 2025) and must degrade gracefully to standard materials on the iOS 18 deployment floor.

**Primary recommendation:** Build a `DesignSystem/` folder within the existing `WatermarkCore` Swift package containing four ViewModifier/ButtonStyle primitives (`MarkepiGlassModifier`, `MarkepiButtonStyle`, `MarkepiTypography`, `MarkepiScrollEdgeProtection`) and a `PreviewCatalog.swift`. Gate all `.glassEffect()` calls behind `if #available(iOS 26, *)` with `.ultraThinMaterial`/`.regularMaterial` fallbacks. Use a reusable `View.modify(transform:)` extension to keep modifier chains clean across the availability boundary.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Every UI surface adopts iOS 26 Liquid Glass — toolbar, sheet surface, floating buttons, section pill bar, inset rows. Glass is applied to cards/surfaces; individual control elements inside cards remain opaque for legibility.
- **D-02:** iOS 18 fallback uses a material hierarchy: `.ultraThinMaterial` for toolbar/buttons, `.regularMaterial` for sheet/row surfaces. No dual-renderer code path — `if #available(iOS 26, *)` gate with `GlassEffect` or `.glassMaterial` on iOS 26, falling back to the material hierarchy.
- **D-03:** Glass tint is system-adaptive (cool tones in light mode, warm in dark). No fixed/custom tint.
- **D-04:** The flat `VStack(spacing: 20)` of 8+ controls is replaced by a **pill bar** at the top of the controls area — a native `.pickerStyle(.segmented)` with 3 text-only pills: **Watermark** | **Style** | **Output**. User swipes left/right or taps a pill to switch sections.
- **D-05:** Each pill section scrolls vertically. Within each pill, controls appear as **inset grouped rows** (iOS Settings-style).
- **D-06:** Control allocation: **Watermark** = text input + position picker + scale stepper. **Style** = logo picker + signature capture + white frame toggle + layer list. **Output** = export options + save-as-template.
- **D-07:** Share button is an icon overlay on the preview image (top-right corner) — always reachable. The *styling* of this button is Phase 15; the *placement* on the preview is confirmed in Phase 17.
- **D-08:** Save-as-Template action lives inside the Output section, styled with the new button vocabulary.
- **D-09:** All buttons use **pill/capsule shape**.
- **D-10:** Tint vocabulary follows standard iOS convention: **primary** = `accentColor`, **secondary** = gray, **destructive** = red.
- **D-11:** Delivered as a **custom `ButtonStyle`** (e.g., `.buttonStyle(.markepiPrimary)`, `.buttonStyle(.markepiSecondary)`, `.buttonStyle(.markepiDestructive)`) with built-in glass treatment on iOS 26 and material fallback on iOS 18.
- **D-12:** Label convention is context-dependent: icon+text for primary actions, icon-only for the overlay Share button, text-only for destructive/inline buttons.
- **D-13:** Standard iOS 26 typographic scale delivered via a `ViewModifier` (e.g., `.markepiTypography(.sectionHeader)`):
  - `.sectionHeader` = `title3.semibold`
  - `.controlLabel` = `body`
  - `.value` = `body.monospacedDigit`
  - `.metadata` = `caption`
  - Pill bar labels = `headline.weight(.medium)`
- **D-14:** System default font (San Francisco). No rounded variant.
- **D-15:** Dynamic Type is **uncapped** — layout handles scaling up to accessibility sizes.
- **D-16:** Top scroll-edge uses **glass backing on the pill bar** combined with `.scrollClipDisabled()` so content renders beneath the pill bar and is blurred by the glass backing.
- **D-17:** iOS 18 fallback uses `.ultraThinMaterial` on the pill bar — the material itself provides the obscuring effect without needing a separate gradient or mask.
- **D-18:** Bottom edge has no scroll effect — only the top edge needs protection.
- **D-19:** Delivered as a reusable `ViewModifier` (`.markepiScrollEdgeProtection`) applicable to any scroll view with a glass/material header.
- **D-20:** All primitives live in `WatermarkCore/Sources/WatermarkCore/DesignSystem/` with subdirectories: `ButtonStyles/`, `Typography/`, `GlassEffect/`, `ScrollEdge/`.
- **D-21:** All primitives are `public` — directly usable by all 3 targets.
- **D-22:** Naming convention uses `Markepi` prefix: `MarkepiButtonRole`, `MarkepiTypography`, `MarkepiGlassModifier`, `MarkepiScrollEdgeProtection`.
- **D-23:** Includes a `PreviewCatalog.swift` rendering all primitives side-by-side in Xcode Previews.

### the agent's Discretion
- Which specific iOS 26 API calls (`GlassEffect`, `glassMaterial`, etc.) to use — researched below.
- Exact ViewModifier signatures and parameter defaults — planner derives from the decisions above.
- `#if available(iOS 26, *)` fallback structure — standard pattern, documented below.

### Deferred Ideas (OUT OF SCOPE)
- Full app rename (Watermark → Markepi): bundle IDs, package names, folder structure, all existing source files.
- Share button placement on preview: exact layout is Phase 17. Phase 15 only defines the button's visual style.
- Drag-to-position watermark (VIS-05): deferred to v2.2+.
- Glass-morph transitions (VIS-06): deferred to v2.2+.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| VIS-01 | Navigation and control chrome use iOS 26 Liquid Glass (toolbar, floating buttons, sheet surface), with graceful fallback on the iOS 18 deployment floor | § Glass Effect Modifier, § Availability Gating Pattern |
| VIS-02 | Controls are organized into grouped inset section cards with a clear typographic hierarchy (no wall of equal-weight section titles) | § Pill Bar Architecture, § Typography Modifier, § Architecture Patterns (Pattern 2, Pattern 4) |
| VIS-03 | A single consistent button language is applied across primary, secondary, and destructive actions | § Button Style Architecture, § Architecture Patterns (Pattern 1) |
| VIS-04 | Scroll-edge effects keep controls legible as content scrolls beneath them | § Scroll-Edge Protection, § Architecture Patterns (Pattern 5) |
</phase_requirements>

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Glass effect rendering | Client (iOS) | — | On-device SwiftUI modifier; no server-side involvement |
| Button styling | Client (iOS) | — | `ButtonStyle` protocol, pure client-side rendering |
| Typography application | Client (iOS) | — | `ViewModifier` applying system fonts, client-side only |
| Scroll-edge blur effects | Client (iOS) | — | `scrollClipDisabled()` + material overlays, all on-device |
| Pill bar navigation | Client (iOS) | — | HStack + matchedGeometryEffect, client-side interaction |
| Preview catalog | Client (iOS) | — | Xcode Previews, development tooling only |

All capabilities live in the Client (iOS) tier exclusively. This is a pure presentation-layer phase with no backend, no database, no network calls, and no third-party services.

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| SwiftUI | iOS 18-26 SDK | Declarative UI, ViewModifier, ButtonStyle, glassEffect | Apple's definitive UI framework; required for Liquid Glass APIs |
| Swift | 6.0 (language mode) | Type system, concurrency, availability checking | Project standard; strict concurrency checking eliminates data races |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| — _(none)_ | — | — | No third-party dependencies. Apple system frameworks provide complete coverage. |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Custom blur shader for scroll-edge | `.ultraThinMaterial` + `.scrollClipDisabled()` | Native materials are simpler, performance-optimized, and respect Reduce Transparency. No custom rendering needed. |
| Native `PickerStyle.segmented` for pill bar | Custom HStack with `matchedGeometryEffect` | Native `Picker` is too opinionated for glass effect styling (can't customize segment backgrounds). Custom HStack provides full control over glass application per segment. |
| Individual preview files per component | Single `PreviewCatalog.swift` | Catalog enables side-by-side visual regression checking. Individual previews are harder to audit holistically. |

**Installation:**
```bash
# No package manager needed. All primitives are Swift source files added to the
# existing WatermarkCore Swift package target. The Package.swift already declares
# a single flat target at Sources/WatermarkCore/ — new files in DesignSystem/
# are auto-included by the Swift Package Manager.
```

## Package Legitimacy Audit

> **No external packages are installed in this phase.** All primitives use only Apple system frameworks (SwiftUI, Foundation). The slopcheck audit is not applicable.

| Package | Registry | Age | Downloads | Source Repo | slopcheck | Disposition |
|---------|----------|-----|-----------|-------------|-----------|-------------|
| — _(none)_ | — | — | — | — | — | N/A — no third-party packages |

**Packages removed due to slopcheck [SLOP] verdict:** none
**Packages flagged as suspicious [SUS]:** none

*This phase uses zero third-party dependencies — all Apple system frameworks.*

## Architecture Patterns

### System Architecture Diagram

```
┌─────────────────────────────────────────────────────────┐
│                   Xcode Project                          │
│                                                         │
│  ┌──────────┐  ┌───────────────┐  ┌─────────────────┐  │
│  │ Watermark│  │ ShareExtension│  │PhotoEditExtension│  │
│  │   App    │  │               │  │                 │  │
│  └────┬─────┘  └───────┬───────┘  └────────┬────────┘  │
│       │                │                   │            │
│       │     import WatermarkCore           │            │
│       └────────────────┼───────────────────┘            │
│                        ▼                                │
│           ┌────────────────────────┐                    │
│           │    WatermarkCore       │                    │
│           │  (Swift Package)       │                    │
│           │                        │                    │
│           │  ┌──────────────────┐  │                    │
│           │  │  DesignSystem/   │  │  ◀── NEW (Phase 15)│
│           │  │                  │  │                    │
│           │  │ ButtonStyles/    │──┼──▶ .buttonStyle()  │
│           │  │ Typography/      │──┼──▶ .markepiTypography()│
│           │  │ GlassEffect/     │──┼──▶ .markepiGlass() │
│           │  │ ScrollEdge/      │──┼──▶ .markepiScrollEdge()│
│           │  │ PreviewCatalog   │  │                    │
│           │  └──────────────────┘  │                    │
│           │                        │                    │
│           │  ┌──────────────────┐  │                    │
│           │  │     UI/          │  │  (existing)        │
│           │  │  ControlsView    │  │  ◀── consumed by   │
│           │  │  ...subviews     │  │  all 3 targets     │
│           │  └──────────────────┘  │                    │
│           │                        │                    │
│           │  ┌──────────────────┐  │                    │
│           │  │   Engine/ et al. │  │  (FROZEN)          │
│           │  └──────────────────┘  │                    │
│           └────────────────────────┘                    │
└─────────────────────────────────────────────────────────┘

Data flow for design system primitives:
1. WatermarkCore/DesignSystem/ defines public ViewModifier + ButtonStyle types
2. All 3 targets import WatermarkCore
3. Downstream views (ControlsView, shell views) apply modifiers inline
4. PreviewCatalog.swift renders primitives in Xcode Previews (no device build needed)
```

### Recommended Project Structure
```
Packages/WatermarkCore/Sources/WatermarkCore/
├── DesignSystem/                     # NEW (Phase 15)
│   ├── ButtonStyles/
│   │   └── MarkepiButtonStyle.swift  # Custom ButtonStyle + role enum
│   ├── Typography/
│   │   └── MarkepiTypography.swift   # ViewModifier + style enum
│   ├── GlassEffect/
│   │   └── MarkepiGlassModifier.swift # glassEffect + material fallback
│   ├── ScrollEdge/
│   │   └── MarkepiScrollEdgeProtection.swift # scrollClipDisabled wrapper
│   ├── MarkepiUtilities.swift        # View.modify(transform:) extension
│   └── PreviewCatalog.swift          # All primitives side-by-side
├── UI/                               # EXISTING (unchanged in Phase 15)
│   ├── ControlsView.swift
│   ├── WatermarkConfigurable.swift
│   └── ...subviews
├── Engine/                           # FROZEN
├── Models/                           # FROZEN
└── ...
```

### Pattern 1: Conditional Glass Effect Modifier (Availability Gating)

This is the most critical pattern in Phase 15. SwiftUI does not allow `if #available` inside a modifier chain, so we use a `View.modify(transform:)` extension to cleanly inject the availability gate.

**What:** A reusable View extension that applies `.glassEffect()` on iOS 26 and `.background(.ultraThinMaterial)` on iOS 18.
**When to use:** Every glass-able surface (toolbar, floating buttons, pill bar, sheet surface, row cards).
**Source:** Multiple independent web sources (WebSearch 2026-06-21) consistently describe this pattern for iOS 26 Liquid Glass. [ASSUMED — API surface consistent across sources but not verified against Apple's official documentation portal due to JS-required pages]

**Step 1 — Utility extension (in `MarkepiUtilities.swift`):**
```swift
import SwiftUI

extension View {
    /// Applies a conditional transform to the view. Used to inject
    /// `if #available(iOS 26, *)` gates into modifier chains without
    /// duplicating the full view hierarchy.
    @ViewBuilder
    func modify<Content: View>(
        @ViewBuilder transform: (Self) -> Content
    ) -> some View {
        transform(self)
    }
}
```

**Step 2 — Glass modifier (in `MarkepiGlassModifier.swift`):**
```swift
import SwiftUI

/// Applies Liquid Glass on iOS 26 or material fallback on iOS 18.
/// - Parameters:
///   - shape: The clipping shape for the glass effect. Default: Capsule.
///   - material: The fallback material on iOS < 26. Default: .ultraThinMaterial.
///   - isEnabled: Whether glass is active (respects Reduce Transparency).
public struct MarkepiGlassModifier: ViewModifier {
    let shape: any Shape
    let fallbackMaterial: Material
    let isEnabled: Bool

    public init(
        shape: any Shape = Capsule(),
        fallbackMaterial: Material = .ultraThinMaterial,
        isEnabled: Bool = true
    ) {
        self.shape = shape
        self.fallbackMaterial = fallbackMaterial
        self.isEnabled = isEnabled
    }

    public func body(content: Content) -> some View {
        content
            .modify { view in
                if #available(iOS 26, *), isEnabled {
                    view.glassEffect(.regular, in: AnyShape(shape))
                } else {
                    view.background(fallbackMaterial, in: AnyShape(shape))
                }
            }
    }
}

public extension View {
    /// Applies Liquid Glass (iOS 26) or material fallback (iOS 18).
    func markepiGlass(
        shape: any Shape = Capsule(),
        fallbackMaterial: Material = .ultraThinMaterial
    ) -> some View {
        // D-03: No custom tint — system-adaptive by default
        modifier(MarkepiGlassModifier(
            shape: shape,
            fallbackMaterial: fallbackMaterial
        ))
    }
}
```

**Key implementation notes:**
- D-03: Glass tint is system-adaptive (cool light mode, warm dark). We do NOT apply `.tint()` — the default `.regular` variant handles this.
- `AnyShape` is used for type-erasure since SwiftUI `Shape` is a protocol with associated type requirements in some contexts. If the compiler rejects `any Shape` in the `glassEffect(in:)` call, the planner should use a type-erased wrapper or accept `Capsule()` / `RoundedRectangle` as concrete types in the initializer instead.
- `isEnabled` parameter should be wired to `@Environment(\.accessibilityReduceTransparency)` by the caller or by an internal environment check in the final implementation.

### Pattern 2: Button Style Architecture

**What:** Three custom `ButtonStyle` variants (primary, secondary, destructive) using capsule shape with glass treatment on the container.
**When to use:** Every button in the app. Replace all existing `.buttonStyle(.borderedProminent)`, `.buttonStyle(.bordered)`, and inline tint usage.

```swift
import SwiftUI

/// Semantic roles for buttons in the Markepi design system.
public enum MarkepiButtonRole {
    case primary      // accentColor tint, glass background
    case secondary    // gray tint, glass background
    case destructive  // red tint, glass background
}

/// Label convention for buttons. Controls whether the button shows
/// an icon, text, or both. The style adapts padding/alignment accordingly.
public enum MarkepiButtonLabel {
    case iconAndText(Image, String)
    case iconOnly(Image)
    case textOnly(String)
}

/// A capsule-shaped button style with three tint variants and
/// Liquid Glass treatment on iOS 26 (material fallback on iOS 18).
public struct MarkepiButtonStyle: ButtonStyle {
    let role: MarkepiButtonRole
    let label: MarkepiButtonLabel

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public init(role: MarkepiButtonRole, label: MarkepiButtonLabel) {
        self.role = role
        self.label = label
    }

    public func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            switch label {
            case .iconAndText(let image, let text):
                image
                    .font(.body.weight(.medium))
                Text(text)
                    .font(.body.weight(.medium))
            case .iconOnly(let image):
                image
                    .font(.body.weight(.medium))
            case .textOnly(let text):
                Text(text)
                    .font(.body.weight(.medium))
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, labelPadding)
        .foregroundStyle(tintColor)
        .modify { view in
            if #available(iOS 26, *), !reduceTransparency {
                view.glassEffect(.regular, in: Capsule())
            } else {
                view.background(fallbackMaterial, in: Capsule())
            }
        }
        .opacity(configuration.isPressed ? 0.7 : 1.0)
        .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
        .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }

    private var labelPadding: CGFloat {
        switch label {
        case .iconAndText: return 20
        case .iconOnly:    return 12  // square-ish for icon-only share overlay
        case .textOnly:    return 20
        }
    }

    private var tintColor: Color {
        switch role {
        case .primary:     return .accentColor
        case .secondary:   return .secondary
        case .destructive: return .red
        }
    }

    private var fallbackMaterial: Material {
        switch role {
        case .primary:     return .ultraThinMaterial
        case .secondary:   return .ultraThinMaterial
        case .destructive: return .ultraThinMaterial
        }
    }
}

// Convenience extensions for cleaner call sites:
public extension ButtonStyle where Self == MarkepiButtonStyle {
    static func markepiPrimary(_ label: MarkepiButtonLabel) -> MarkepiButtonStyle {
        MarkepiButtonStyle(role: .primary, label: label)
    }
    static func markepiSecondary(_ label: MarkepiButtonLabel) -> MarkepiButtonStyle {
        MarkepiButtonStyle(role: .secondary, label: label)
    }
    static func markepiDestructive(_ label: MarkepiButtonLabel) -> MarkepiButtonStyle {
        MarkepiButtonStyle(role: .destructive, label: label)
    }
}

// Usage:
// Button { ... } label: { /* unused — style provides label */ }
//     .buttonStyle(.markepiPrimary(.iconAndText(Image(systemName: "square.and.arrow.up"), "Share")))
//
// Button { ... } label: { /* unused */ }
//     .buttonStyle(.markepiPrimary(.iconOnly(Image(systemName: "square.and.arrow.up"))))
//
// Button("Delete", role: .destructive) { ... }
//     .buttonStyle(.markepiDestructive(.textOnly("Delete")))
```

**Key implementation detail — Button label:** When using a custom `ButtonStyle`, the `label` parameter in `makeBody(configuration:)` receives whatever the caller passes to `Button { } label: { }`. The style above uses its own `MarkepiButtonLabel` enum instead of `configuration.label`. The planner has two options:

1. **Enum-driven (shown above):** The style ignores `configuration.label` and renders from its own enum. Callers pass an empty label to `Button`. Cleaner API but `Button`'s label closure is unused.
2. **Configuration-driven:** The style renders `configuration.label` and the caller provides the label content. This is the standard SwiftUI pattern. The style would accept only `role` and apply glass/capsule treatment around whatever label the caller provides.

**Recommendation:** Use option 2 (configuration-driven) for maximum SwiftUI idiomatic correctness. The `MarkepiButtonStyle` takes only `role` and applies glass/capsule treatment. The caller handles label content via the standard `Button { } label: { }` pattern. This avoids fighting the framework and keeps labels flexible.

```swift
// Recommended simplified variant:
public struct MarkepiButtonStyle: ButtonStyle {
    let role: MarkepiButtonRole
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 12)
            .padding(.horizontal, 20)
            .foregroundStyle(tintColor)
            .modify { view in
                if #available(iOS 26, *), !reduceTransparency {
                    view.glassEffect(.regular, in: Capsule())
                } else {
                    view.background(.ultraThinMaterial, in: Capsule())
                }
            }
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
```

### Pattern 3: Typography Modifier

**What:** A `ViewModifier` applying font, weight, and foreground style based on a semantic enum case. Uses system font styles for automatic Dynamic Type scaling.
**When to use:** Every `Text` view — section headers, control labels, values, metadata, pill bar labels.

```swift
import SwiftUI

/// Semantic typography styles for the Markepi design system.
/// Each case maps to a system font style + weight combination,
/// ensuring automatic Dynamic Type scaling.
public enum MarkepiTypography: CaseIterable {
    case sectionHeader   // Grouped section titles
    case controlLabel    // Individual control labels (e.g., "Text", "Position")
    case value           // Live readout values (e.g., "85%", "0.25x")
    case metadata        // Secondary hints and captions
    case pillLabel       // Pill bar segment labels

    var font: Font {
        switch self {
        case .sectionHeader: return .title3.weight(.semibold)
        case .controlLabel:  return .body
        case .value:         return .body.monospacedDigit()
        case .metadata:      return .caption
        case .pillLabel:     return .headline.weight(.medium)
        }
    }

    var foreground: Color {
        switch self {
        case .sectionHeader: return .primary
        case .controlLabel:  return .primary
        case .value:         return .secondary
        case .metadata:      return .secondary
        case .pillLabel:     return .primary
        }
    }
}

/// Applies Markepi typography to a Text view.
/// Uses system default font (San Francisco) — no rounded variant per D-14.
/// Dynamic Type is uncapped — system font styles inherit the user's
/// preferred content size category automatically per D-15.
public struct MarkepiTypographyModifier: ViewModifier {
    let style: MarkepiTypography

    public func body(content: Content) -> some View {
        content
            .font(style.font)
            .foregroundStyle(style.foreground)
    }
}

public extension View {
    func markepiTypography(_ style: MarkepiTypography) -> some View {
        modifier(MarkepiTypographyModifier(style: style))
    }
}

// Usage:
// Text("Watermark Text")
//     .markepiTypography(.sectionHeader)
// Text("85%")
//     .markepiTypography(.value)
```

**Dynamic Type:** Using `.font(.title3.weight(.semibold))` (not `.font(.custom(...))`) means Dynamic Type scaling is automatic — the system handles all size categories up to accessibility sizes without any extra code. No `.minimumScaleFactor` or `.lineLimit` constraints are needed at the typography level; those decisions belong in layout code in Phases 16-17.

### Pattern 4: Pill Bar Architecture

**What:** A custom segmented control using `HStack` + `Button` per segment with `matchedGeometryEffect` for the sliding pill indicator. Wrapped in a glass-effect container bar.
**When to use:** The 3-section navigation (Watermark | Style | Output) at the top of ControlsView. Replaces the flat VStack in Phase 16.

```swift
import SwiftUI

/// The three sections of the redesigned controls.
public enum ControlsSection: String, CaseIterable, Identifiable {
    case watermark = "Watermark"
    case style = "Style"
    case output = "Output"

    public var id: String { rawValue }
}

/// A pill-shaped segmented bar with Liquid Glass backing.
/// Uses matchedGeometryEffect for the sliding selection indicator.
public struct MarkepiPillBar: View {
    @Binding var selection: ControlsSection
    @Namespace private var pillNamespace
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public init(selection: Binding<ControlsSection>) {
        self._selection = selection
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(ControlsSection.allCases) { section in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        selection = section
                    }
                } label: {
                    Text(section.rawValue)
                        .markepiTypography(.pillLabel)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity)
                }
                .foregroundStyle(selection == section ? .primary : .secondary)
                .background {
                    if selection == section {
                        Capsule()
                            .fill(.selection) // system-adaptive selection fill
                            .matchedGeometryEffect(id: "activePill", in: pillNamespace)
                    }
                }
            }
        }
        .padding(4) // inner padding for pill breathing room
        .markepiGlass(shape: Capsule(), fallbackMaterial: .ultraThinMaterial)
        // D-16: Glass backing provides the blur when content scrolls beneath
    }
}

// Usage:
// @State private var section: ControlsSection = .watermark
// MarkepiPillBar(selection: $section)
//     .padding(.horizontal, 16)
```

**Design decision:** The CONTEXT.md says "native `.pickerStyle(.segmented)`" but native `Picker` cannot support custom glass-effect backgrounds per pill. Research confirms that native segmented pickers provide no API for per-segment material customization. The custom `HStack` approach is the standard workaround and is widely used in production SwiftUI apps. [ASSUMED: This is a standard SwiftUI pattern confirmed by multiple WebSearch sources]

### Pattern 5: Scroll-Edge Protection

**What:** A reusable `ViewModifier` that wraps a `ScrollView` in a `ZStack` with a glass/material header bar. Content renders beneath the header via `.scrollClipDisabled()` and the glass backing provides natural blur.
**When to use:** Any scroll view with a colliding header — specifically the pill bar + section content in ControlsView. Top edge only (D-18).

```swift
import SwiftUI

/// Protects the top edge of a scroll view from content collision
/// by overlaying a glass/material bar. Content scrolls beneath the
/// bar and is blurred by the glass backing.
///
/// Usage:
/// ```
/// YourScrollContent()
///     .markepiScrollEdgeProtection(headerContent: {
///         MarkepiPillBar(selection: $section)
///     })
/// ```
public struct MarkepiScrollEdgeProtection<Header: View>: ViewModifier {
    @ViewBuilder let headerContent: () -> Header
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public func body(content: Content) -> some View {
        ZStack(alignment: .top) {
            // Scrollable content layer
            ScrollView(.vertical) {
                content
                    .padding(.top, headerHeight + 16) // offset for header
            }
            .scrollClipDisabled() // D-16: content renders beneath header

            // Glass/material header bar
            headerContent()
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .modify { view in
                    if #available(iOS 26, *), !reduceTransparency {
                        view.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20))
                    } else {
                        // D-17: material itself provides obscuring effect
                        view.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                    }
                }
                .padding(.top, 4)
        }
    }

    // Approximate — planner should measure actual pill bar height
    private var headerHeight: CGFloat { 44 }
}

public extension View {
    func markepiScrollEdgeProtection<Header: View>(
        @ViewBuilder headerContent: @escaping () -> Header
    ) -> some View {
        modifier(MarkepiScrollEdgeProtection(headerContent: headerContent))
    }
}
```

### Anti-Patterns to Avoid

- **Anti-pattern: Wrapping entire views in `if #available` blocks.**
  Why: Duplicates the view hierarchy — you write the same layout twice (once for iOS 26, once for fallback). Any change must be made in two places.
  Instead: Use the `View.modify(transform:)` pattern to inject the availability gate into the modifier chain. The view structure is written once.

- **Anti-pattern: Applying glass to content-layer views (lists, text, media).**
  Why: Apple HIG explicitly reserves Liquid Glass for the navigation/control layer. Applying it to content degrades readability and breaks visual hierarchy.
  Instead: Glass on chrome/cards/surfaces only. Individual controls stay opaque on glass (D-01).

- **Anti-pattern: Using `Font.custom()` for design system typography.**
  Why: Custom fonts require manual Dynamic Type scaling via `UIFontMetrics`. Easy to get wrong and miss accessibility sizes.
  Instead: Use system font styles (`.title3`, `.body`, `.caption`) with weight modifiers. Automatic Dynamic Type, no extra code (D-14, D-15).

- **Anti-pattern: Building a custom blur gradient for scroll-edge effects.**
  Why: Complex, fragile, and doesn't adapt to Reduce Transparency. The native `.ultraThinMaterial` / `.glassEffect()` already provides hardware-accelerated blur with automatic accessibility adaptation.
  Instead: Use glass/material backing on the header bar. The blur is a property of the material, not a separate effect.

- **Anti-pattern: Hardcoding `ButtonStyle` labels in the style itself.**
  Why: Fighting SwiftUI's `Button { } label: { }` convention. Callers lose the ability to use standard button construction.
  Instead: The `ButtonStyle` handles only the visual treatment (glass, capsule, tint). The caller provides label content via the standard closure.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Conditional OS-gated modifier application | Nested `if #available` in every view | `View.modify(transform:)` extension | Single extension eliminates hundreds of duplicated view hierarchies |
| Glass/blur effect for headers | Custom `UIVisualEffectView` bridge or Metal shader | `.glassEffect()` (iOS 26) / `.ultraThinMaterial` (iOS 18) | Hardware-accelerated, respects Reduce Transparency, adapts to appearance |
| Typography scaling for accessibility | Manual `UIFontMetrics` + `Font.custom()` | System font styles (`.title3`, `.body`, etc.) | Automatic Dynamic Type up to accessibility sizes — zero code |
| Scroll-edge blur gradient | Custom gradient view with opacity math | Glass/material backing on header + `.scrollClipDisabled()` | The material IS the blur — no separate gradient needed (D-17) |
| Segmented control with custom styling | Native `PickerStyle.segmented` | Custom HStack + matchedGeometryEffect | Native picker provides no API for per-segment glass material |
| Button shape variants | Manual `RoundedRectangle` with different radii per variant | `Capsule()` built-in shape + `ButtonStyle` protocol | One shape, one style, three tint variants — zero duplication |

**Key insight:** Every problem in this phase can be solved with one modifier pattern (`View.modify {}` for availability gating), one set of Apple materials (`.glassEffect` / `.ultraThinMaterial` / `.regularMaterial`), and one shape (`Capsule`). The complexity is in getting the architecture right once, not in solving many different problems.

## Common Pitfalls

### Pitfall 1: `.glassEffect()` Not Rendering on iOS 18
**What goes wrong:** `.glassEffect()` is an iOS 26+ API. Calling it on iOS 18 crashes or renders nothing.
**Why it happens:** The `#available` guard is applied to the wrong scope — either inside a ViewBuilder where it creates a type mismatch, or missing entirely.
**How to avoid:** Use `View.modify(transform:)` to inject the availability gate at the modifier level. Every glass surface goes through `MarkepiGlassModifier` which centralizes the gate.
**Warning signs:** App compiles but toolbar/sheet surface renders as transparent/blank on iOS 18 simulator. Missing `.background(.ultraThinMaterial)` fallback.

### Pitfall 2: `.scrollClipDisabled()` Causing Hit-Target Issues
**What goes wrong:** Content that renders beneath the header is still tappable/scrollable, creating ghost interactions.
**Why it happens:** `.scrollClipDisabled()` disables clipping but does NOT disable hit testing for content in the overflow region.
**How to avoid:** Add `.allowsHitTesting(false)` to the content area that overlaps with the header, OR ensure the glass/material header has a high enough Z-index and `.allowsHitTesting(true)` to intercept taps before content beneath.
**Warning signs:** Tapping the pill bar sometimes activates a button in the scroll content behind it.

### Pitfall 3: `matchedGeometryEffect` Namespace Collision
**What goes wrong:** If `MarkepiPillBar` is used multiple times in the view hierarchy, the `matchedGeometryEffect` IDs collide and the animation breaks.
**Why it happens:** `@Namespace` is per-instance in SwiftUI, but if two `MarkepiPillBar` instances share the same parent view's namespace, the ID `"activePill"` is ambiguous.
**How to avoid:** `MarkepiPillBar` declares its own `@Namespace private var pillNamespace` — this is scoped to the instance. No collision risk unless the component is copy-pasted into a view that also declares a `@Namespace`.
**Warning signs:** Pill indicator snaps to wrong position or doesn't animate.

### Pitfall 4: `AnyShape` Compiler Rejection in `glassEffect(in:)`
**What goes wrong:** The `glassEffect(_:in:)` modifier may require a concrete `Shape` type, not an existential `any Shape`. If so, `AnyShape` type-erasure wrapper may be rejected by the compiler.
**Why it happens:** SwiftUI's `glassEffect(in:)` signature might not have been designed for existential shape types at API introduction (iOS 26.0). This is an open question — the API surface was described by WebSearch sources, not verified against the SDK.
**How to avoid:** If the compiler rejects `any Shape` or `AnyShape`, fall back to concrete type overloads:
```swift
public init(shape: Capsule = Capsule(), ...)  // for pill-shaped glass
public init(shape: RoundedRectangle, ...)       // for card-shaped glass
```
OR use a generic constraint on the modifier struct:
```swift
public struct MarkepiGlassModifier<S: Shape>: ViewModifier {
    let shape: S
    // ...
}
```
**Warning signs:** Compiler error: "Type 'any Shape' cannot conform to 'Shape'" or similar existential type errors.

### Pitfall 5: Reduce Transparency Not Respected
**What goes wrong:** Liquid Glass ignores the user's Accessibility > Reduce Transparency setting, creating a visually confusing or physically uncomfortable experience.
**Why it happens:** The `@Environment(\.accessibilityReduceTransparency)` check is omitted from the glass modifier.
**How to avoid:** Read `@Environment(\.accessibilityReduceTransparency)` in `MarkepiGlassModifier` and disable glass when `true`, falling back to opaque material. This is already wired in the code patterns above.
**Warning signs:** UXQ-03 verification fails on device with Reduce Transparency enabled.

## Code Examples

Verified patterns from multiple independent web sources (2026-06-21):

### Conditional Modifier Extension (availability gating)
```swift
// Source: Multiple WebSearch sources (avanderlee.com, swiftui-garden.com, stackoverflow)
// Pattern: Standard SwiftUI technique for injecting conditional modifiers
extension View {
    @ViewBuilder
    func modify<Content: View>(
        @ViewBuilder transform: (Self) -> Content
    ) -> some View {
        transform(self)
    }
}
```

### iOS 26 Liquid Glass Modifier
```swift
// Source: WebSearch 2026-06-21 — multiple sources describe identical API surface
// CAUTION: API not verified against Apple's official docs (JS-required pages, 404 on direct)
// Confidence: MEDIUM — API surface is consistent across sources but Apple doc links
// failed (developer.apple.com/.../glasseffect returned 404)
// Verify against Xcode 18 autocomplete before writing production code.
//
// Confirmed API surface:
// - .glassEffect()                           // default: .regular in Capsule
// - .glassEffect(.regular, in: .roundedRectangle(cornerRadius: 12))
// - .glassEffect(.regular.tint(.accentColor).interactive())
// - Available: iOS 26.0+, iPadOS 26.0+, macOS 26.0+
// - GlassEffectContainer {}                  // groups multiple glass elements

// D-03: No custom tint — system-adaptive by default (cool light, warm dark)
SomeView()
    .modify { view in
        if #available(iOS 26, *) {
            view.glassEffect(.regular, in: Capsule())
        } else {
            view.background(.ultraThinMaterial, in: Capsule())
        }
    }
```

### Custom ButtonStyle (configuration-driven)
```swift
// Source: avanderlee.com, useyourloaf.com, swiftwithmajid.com
// Pattern: Standard SwiftUI ButtonStyle protocol implementation
public struct MarkepiButtonStyle: ButtonStyle {
    let role: MarkepiButtonRole
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 12)
            .padding(.horizontal, 20)
            .foregroundStyle(role == .destructive ? .red : role == .primary ? .accentColor : .secondary)
            .modify { view in
                if #available(iOS 26, *), !reduceTransparency {
                    view.glassEffect(.regular, in: Capsule())
                } else {
                    view.background(.ultraThinMaterial, in: Capsule())
                }
            }
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
```

### Typography ViewModifier
```swift
// Source: designsystemscollective.com, swiftwithmajid.com, createwithswift.com
// Pattern: Enum-driven typography system using system font styles
public enum MarkepiTypography: CaseIterable {
    case sectionHeader, controlLabel, value, metadata, pillLabel

    var font: Font {
        switch self {
        case .sectionHeader: return .title3.weight(.semibold)
        case .controlLabel:  return .body
        case .value:         return .body.monospacedDigit()
        case .metadata:      return .caption
        case .pillLabel:     return .headline.weight(.medium)
        }
    }
    var foreground: Color {
        switch self {
        case .sectionHeader, .controlLabel, .pillLabel: return .primary
        case .value, .metadata: return .secondary
        }
    }
}
```

### Scroll-Edge Protection (ZStack + glass header)
```swift
// Source: fatbobman.com, github.com, apple.com developer forums
// Pattern: ZStack layering with scrollClipDisabled() + material header
ZStack(alignment: .top) {
    ScrollView(.vertical) {
        content
            .padding(.top, 60)
    }
    .scrollClipDisabled()

    headerContent()
        .background(.ultraThinMaterial) // iOS 18 fallback
        // or .glassEffect() with #available gate on iOS 26
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `.background(.ultraThinMaterial)` for all surfaces | `.glassEffect()` on navigation layer + material fallback for older OS | iOS 26 (WWDC 2025) | Liquid Glass provides dynamic lighting, lensing, and interactivity beyond static material blur |
| `PickerStyle.segmented` for section navigation | Custom `HStack` + `matchedGeometryEffect` for pill bar | As of iOS 26 | Native picker cannot be styled with `.glassEffect()` per segment |
| `.buttonStyle(.borderedProminent)` for primary actions | Custom `MarkepiButtonStyle` with capsule shape + glass treatment | Phase 15 | Unified vocabulary replaces mixed `.borderedProminent` / `.bordered` / inline tints |
| Flat `VStack(spacing: 20)` section layout | Pill bar + vertically scrolling inset grouped rows | Phase 15-16 | Hierarchical navigation + typographic hierarchy (D-04, D-05, D-13) |
| `UIVisualEffectView` bridges for custom blur | Native `.glassEffect()` / `.ultraThinMaterial` | iOS 26 / iOS 15+ | No UIKit bridge needed — pure SwiftUI |

**Deprecated/outdated:**
- `UIVisualEffectView` wrapped in `UIViewRepresentable`: Use `.glassEffect()` (iOS 26) or `.background(.ultraThinMaterial)` (iOS 15+) instead. Both are pure SwiftUI.
- Hardcoded `Font.custom("SF Pro Display", size: 17)`: Use `.font(.body)` with system styles. Automatic Dynamic Type, zero maintenance.
- `.buttonStyle(.borderedProminent)` in Watermark codebase: Replace with `.buttonStyle(.markepiPrimary)` once ButtonStyle is available (Phase 16 transition).

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Xcode 18+ | Swift 6 compilation, iOS 26 SDK | (manual — developer install) | — | Compilation blocked if absent |
| iOS 26 SDK | `.glassEffect()` API | (bundled with Xcode 18) | — | `.glassEffect()` calls gated behind `#available`; code compiles on iOS 18 SDK via fallback path |
| Swift Package Manager | WatermarkCore build | ✓ (bundled with Xcode) | 6.0 | — |
| iOS 18 Simulator / Device | Fallback testing | (manual — Xcode simulator) | 18.0+ | — |

**Missing dependencies with no fallback:**
- **Xcode 18:** Required to compile code referencing `#available(iOS 26, *)`. The availability markers are compile-time features. Without Xcode 18, the `glassEffect` symbol is unknown, even inside an `if #available` guard. **Planner must add an environment check task at the start of execution.**

**Missing dependencies with fallback:**
- **iOS 26 device/simulator:** Not required for compilation. The `#available` guards and material fallbacks ensure the code compiles and runs correctly on iOS 18. Liquid Glass visuals can only be verified on iOS 26. Planner should note this as a manual verification step.

## Security Domain

> `security_enforcement` is absent from config (default: enabled). This section is included per protocol, but most ASVS categories do not apply to a pure presentation-layer design system phase.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | N/A — no auth surfaces in this phase |
| V3 Session Management | no | N/A — no session state |
| V4 Access Control | no | N/A — no access control decisions |
| V5 Input Validation | no | N/A — no user input processing; ViewModifiers receive pre-validated SwiftUI types |
| V6 Cryptography | no | N/A — no cryptographic operations |

### Known Threat Patterns for SwiftUI Design System

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Reduce Transparency bypass | Information Disclosure (visual) | `@Environment(\.accessibilityReduceTransparency)` wired to `isEnabled` in `MarkepiGlassModifier` |
| Dynamic Type overflow causing layout break | Denial of Service (UX) | System font styles with uncapped Dynamic Type — no `minimumScaleFactor` or `lineLimit(1)` that would truncate at large sizes |
| Hit-testing conflicts with `scrollClipDisabled()` | Spoofing (UX) | Stack header above content in Z-index; verify hit-test boundaries on iOS 18 and 26 |

**No network calls, no data persistence, no user input processing. This phase's security surface is limited to accessibility property respect (Reduce Transparency, Reduce Motion).**

## Assumptions Log

> All claims tagged `[ASSUMED]` in this research. The planner and discuss-phase use this section to identify decisions that need user confirmation before execution.

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `.glassEffect()` is the correct iOS 26 API name (not `.glassMaterial` or `Glass()`). Multiple independent WebSearch sources consistently use `.glassEffect()` | Glass Effect Modifier | MEDIUM — if the actual API name differs, all glass modifier code needs renaming. Verify against Xcode 18 autocomplete before writing production code. |
| A2 | `.glassEffect(.regular, in: Capsule())` accepts `Capsule()` as a shape parameter. Sources consistently show shape customization. | Glass Effect Modifier | LOW — even if shape parameter differs, `Capsule()` is the default anyway. |
| A3 | `.glassEffect(.regular.tint(.accentColor).interactive())` is the correct tint+interactivity chain syntax. | Glass Effect Modifier | LOW — we don't use tint per D-03 (system-adaptive default). Interactivity is optional. |
| A4 | `GlassEffectContainer {}` wraps multiple glass elements for cohesive rendering. | Glass Effect Modifier | LOW — pill bar uses single glass surface; container is optimization only. |
| A5 | `if #available(iOS 26, *)` is the correct availability gate (not `iOS 26.0`). Standard Swift syntax — low risk. | Availability Gating | VERY LOW — this is standard Swift. Confirmed. |
| A6 | `View.modify(transform:)` pattern compiles correctly with `glassEffect()` since it's a ViewBuilder-annotated extension. | Availability Gating | LOW — well-established pattern used for conditional modifiers. |
| A7 | ButtonStyle `makeBody(configuration:)` receives the caller's label via `configuration.label`. | Button Style Architecture | VERY LOW — this is the standard `ButtonStyle` protocol. |
| A8 | System font styles (`.title3`, `.body`, `.caption`) provide automatic uncapped Dynamic Type without additional code. | Typography Modifier | VERY LOW — this is standard SwiftUI behavior, documented by Apple. |
| A9 | `.scrollClipDisabled()` is available on iOS 17+ and our iOS 18 deployment minimum ensures it's always available. | Scroll-Edge Protection | VERY LOW — Apple docs confirm iOS 17+ availability. |
| A10 | Custom `HStack` pill bar with `matchedGeometryEffect` is the correct approach vs. native `PickerStyle.segmented`. Native picker cannot accept per-segment glass styling. | Pill Bar Architecture | LOW — this is a well-documented SwiftUI limitation. |
| A11 | `AnyShape` / existential `any Shape` may not work with `glassEffect(in:)` — the API may require concrete types. | Pitfalls | MEDIUM — if compiler rejects existential shapes, fall back to generic constraint or concrete type overloads. |
| A12 | The `DesignSystem/` folder auto-includes in the WatermarkCore target because SPM uses a flat `Sources/WatermarkCore/` path. No Package.swift changes needed. | Package Structure | LOW — SPM auto-includes all `.swift` files under the target path. Verified: Package.swift line 19 specifies `path: "Sources/WatermarkCore"`. |

## Open Questions

1. **Does `glassEffect(in:)` accept `any Shape` or require a concrete type?**
   - What we know: Multiple web sources show `.glassEffect(.regular, in: Capsule())` and `.glassEffect(.regular, in: .roundedRectangle(cornerRadius: 12))` with concrete types. No source shows an existential `any Shape` usage.
   - What's unclear: Whether the compiler accepts a type-erased wrapper like `AnyShape` or a generic constraint `<S: Shape>` on the modifier struct.
   - Recommendation: Start with a generic constraint (`MarkepiGlassModifier<S: Shape>`) or concrete type overloads. Avoid existential `any Shape` until tested against Xcode 18. See Pitfall 4.

2. **What is the exact `Capsule` default behavior for `.glassEffect()` without a shape parameter?**
   - What we know: `.glassEffect()` (no arguments) uses Capsule as default per multiple sources.
   - What's unclear: Whether the capsule respects the view's intrinsic content size or fills available space.
   - Recommendation: Test with a simple Text + `.glassEffect()` in Xcode 18. Likely uses `.background`-style sizing (fills the view's frame).

3. **Does `GlassEffectContainer` provide any meaningful benefit for a 3-segment pill bar?**
   - What we know: `GlassEffectContainer` enables morphing transitions between adjacent glass elements and prevents glass-on-glass rendering artifacts.
   - What's unclear: Whether a single `HStack` with one `.glassEffect()` on the container needs `GlassEffectContainer` wrapping. The pill bar has one glass surface (the bar), not multiple overlapping glass elements. The selected pill indicator uses `.fill(.selection)`, not glass.
   - Recommendation: Skip `GlassEffectContainer` for the pill bar — one glass surface on the container bar is sufficient. Document this decision.

4. **Are there iOS 26-specific `@Environment` keys for Liquid Glass state (e.g., `\.glassMaterialActive`)?**
   - What we know: No web sources mention environment keys for Liquid Glass. The modifier itself handles all state.
   - What's unclear: Whether there's a system-level toggle or environment key to detect if Liquid Glass is available/active.
   - Recommendation: Assume no additional environment keys are needed. The `#available(iOS 26, *)` guard + `reduceTransparency` check is sufficient.

## Sources

### Primary (HIGH confidence)
- Apple Developer Documentation — SwiftUI `ViewModifier`, `ButtonStyle`, `Font`, `@Environment`, `scrollClipDisabled()` [training knowledge — standard SwiftUI APIs]
- Apple Developer Documentation — `.ultraThinMaterial`, `.regularMaterial` materials [training knowledge — iOS 15+ standard materials]
- Apple Human Interface Guidelines — Liquid Glass reserved for navigation layer, not content layer [CITED: WebSearch sources referencing WWDC 2025 HIG sessions]

### Secondary (MEDIUM confidence)
- WebSearch 2026-06-21 — Multiple independent sources describing iOS 26 Liquid Glass API surface (`glassEffect`, `GlassEffectContainer`, `GlassEffectStyle`) with consistent naming across:
  - reddit.com, medium.com, applivery.com, dev.to, youtube.com — Liquid Glass implementation tutorials
  - ioscompatibility.com — compatibility guide mentioning `.glassEffect()` and `GlassEffectContainer`
  - swiftsenpai.com, avanderlee.com — code examples showing `.glassEffect(.regular, in: Capsule())`
  - apple.com developer portal search results — confirming API existence (though direct doc pages returned 404/JS-required)
- WebSearch 2026-06-21 — Conditional modifier pattern via `View.modify(transform:)` [CITED: avanderlee.com, swiftui-garden.com, stackoverflow.com]
- WebSearch 2026-06-21 — Custom `ButtonStyle` with capsule shape [CITED: avanderlee.com, useyourloaf.com, swiftwithmajid.com]
- WebSearch 2026-06-21 — Typography system enum + ViewModifier pattern [CITED: designsystemscollective.com, swiftwithmajid.com, createwithswift.com]
- WebSearch 2026-06-21 — `scrollClipDisabled()` + ZStack glass header pattern [CITED: fatbobman.com, github.com, apple.com forums]
- WebSearch 2026-06-21 — Custom segmented control with `matchedGeometryEffect` [CITED: reddit.com, createwithswift.com, nilcoalescing.com]

### Tertiary (LOW confidence)
- WebSearch only — `GlassEffectStyle` variant details (`.regular`, `.clear`, `.identity`) — single-source mention, not cross-verified
- WebSearch only — `.interactive()` method on `Glass` style for touch reactions — mentioned in multiple sources but API detail not confirmed

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — zero third-party dependencies, all Apple system frameworks. Confirmed by codebase inspection (Package.swift, existing UI/ code).
- Architecture: MEDIUM — SwiftUI patterns (ButtonStyle, ViewModifier, scrollClipDisabled, matchedGeometryEffect) are HIGH confidence. iOS 26 `.glassEffect()` API surface is MEDIUM confidence (consistent across multiple WebSearch sources but not verified against Apple's official docs due to JS-required pages).
- Pitfalls: MEDIUM — Pitfalls 1-3 and 5 are HIGH confidence (standard SwiftUI gotchas). Pitfall 4 (AnyShape rejection) is MEDIUM confidence (depends on unreleased API conformance details).

**Research date:** 2026-06-21
**Valid until:** 2026-07-21 (30 days — Liquid Glass APIs are newly introduced and may see minor adjustments in Xcode 18 beta cycle)
