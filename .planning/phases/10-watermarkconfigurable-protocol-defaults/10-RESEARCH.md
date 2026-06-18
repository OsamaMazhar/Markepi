# Phase 10: WatermarkConfigurable Protocol Defaults — Research

**Researched:** 2026-06-18
**Domain:** Swift protocol extensions / code deduplication (pure refactor)
**Confidence:** HIGH

## Summary

Phase 10 is a pure structural refactor: add default implementations to the `WatermarkConfigurable` protocol for 5 layer-management methods and 3 computed properties that are identically duplicated across all 3 ViewModels (WatermarkViewModel, ShareExtensionViewModel, PhotosExtensionViewModel). Additionally, add `errorMessage` and `showError` to the protocol (D-01) so the `addLogoLayer` default can surface validation errors without per-ViewModel special-casing. The `addSignatureLayer` method gets a default no-op (D-03) eliminating 2 empty stubs in the extensions.

All 3 conforming types are `@Observable @MainActor final class` with identical structure. The protocol is already `@MainActor` + `AnyObject`-constrained. A single protocol extension in `WatermarkConfigurable.swift` provides the defaults; all 3 ViewModels drop their duplicated implementations and inherit from the extension. The refactor changes zero behavior — only code location.

**Primary recommendation:** Add all default implementations in a single protocol extension block within `WatermarkConfigurable.swift` (same file, appended after the existing protocol declaration), organized with `// MARK:` comments. Use direct mutation of `self.config` and `self.activeLayerIndex` (D-04). No new files, no project structure changes, no new targets.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Add `errorMessage: String? { get set }` and `showError: Bool { get set }` to the `WatermarkConfigurable` protocol so the default `addLogoLayer(pngData:)` can surface PNG validation failures directly. All 3 conformers already have these `@Published`/observable properties — this collapses the method into a single protocol default.
- **D-02:** Include `whiteFrameEnabled: Bool`, `outputFormat: OutputFormat`, and `outputQuality: Float` computed properties in the protocol extension defaults alongside the 5 layer-management methods. All 3 are identical 3–5 line get/set wrappers around `config`. These already have `{ get }` / `{ get set }` requirements in the protocol.
- **D-03:** Add a default no-op implementation for `addSignatureLayer(strokeData:inkColor:strokeWidth:)` in the protocol extension (empty body). Both ShareExtensionViewModel and PhotosExtensionViewModel currently have empty stubs. WatermarkViewModel overrides with the real PencilKit implementation.
- **D-04:** Protocol extension methods mutate `self.config` and `self.activeLayerIndex` directly. The `AnyObject` class constraint guarantees reference semantics — no `@discardableResult`/return-new-config pattern needed.
- **D-05:** Keep the 3-case switch (text/image/signature) for layer reconstruction in the protocol extension rather than adding `with(position:)`/`with(scale:)` helper methods to `WatermarkLayer`.
- **D-06:** The following methods remain per-ViewModel (genuinely different behavior): `renderAndPrepareShare()`, `cancelVideoExport()`, `presentShareSheet()`. `addSignatureLayer` real implementation stays in WatermarkViewModel only.
- **D-07:** Verification is three-fold: (1) all 227 existing tests pass, (2) build gate passes for all 3 targets, (3) grep audit confirms zero duplicated implementations.
- **D-08:** No new automated tests are required. The refactor is purely structural.

### the agent's Discretion
- Exact ordering of protocol requirements vs. extension methods in WatermarkConfigurable.swift
- Whether to group methods in one protocol extension or separate extensions with MARK comments
- Exact placement of error properties in the protocol
- Whether `outputFormat` and `outputQuality` protocol requirements need adjustment for default implementations (verified: no changes needed — computed properties in extensions satisfy `{ get set }` requirements)

### Deferred Ideas (OUT OF SCOPE)
- `cancelVideoExport()` and `renderAndPrepareShare()` default implementations — genuinely different per-target behavior; not in scope
- CUST-01 through CUST-04 — v2+ scope
- BATC-01/02 — v2+ scope
- PHRO-01/02 — deferred process-hardening items
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| REFA-01 | `WatermarkConfigurable` protocol provides default implementations for shared layer-management operations, eliminating ~186 lines of per-target duplication | All 5 methods + 3 computed properties are identical across the 3 ViewModels. Protocol extension with computed properties for `{ get set }` requirements is verified to compile in Swift 6 with `@MainActor`. |

**Success criteria mapping:**
1. Protocol extension provides defaults for 5 ops + 3 computed properties → §Standard Stack, §Code Examples
2. Zero duplicated implementations across the 3 ViewModels → §Verification strategy (grep audit)
3. ~186 lines reduced to ~20 → §Code Examples (line count analysis)
4. All 227 existing tests pass → §Verification (existing test suite)
5. Build gate passes for all 3 targets → §Architecture Patterns (build gate integration)
</phase_requirements>

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Protocol default implementations | WatermarkCore (shared Swift Package) | — | Single source of truth consumed by all 3 targets; eliminates cross-target duplication |
| Layer mutation (config.watermarks) | WatermarkCore (protocol extension) | — | Extension mutates `self.config` directly on the class-constrained protocol; same access pattern for all conformers |
| Error surfacing (addLogoLayer validation) | WatermarkCore (protocol extension via errorMessage/showError) | — | Protocol gains error properties so the default impl can set them without per-ViewModel special-casing |
| Per-ViewModel rendering (renderAndPrepareShare, cancelVideoExport, presentShareSheet) | Each ViewModel target | — | Genuinely different behavior per target; NOT eligible for defaults (D-06) |
| Build verification | Xcode toolchain (build-gate.sh) | — | Single xcodebuild invocation via WatermarkApp scheme covers all 3 targets + WatermarkCore |

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| **Swift** | 6.2.3 (Xcode 26.2) | Language | Protocol extensions with default implementations are a core Swift language feature. Swift 6 strict concurrency + `@MainActor` isolation required for ViewModel protocol extensions. |
| **SwiftUI** | iOS 18 SDK | UI framework (unaffected) | No UI changes. All Views already generic over `WatermarkConfigurable & Observable`. |
| **Foundation** | iOS 18 SDK | Core types (Data, String, etc.) | Used by `CIImage(data:)` validation in `addLogoLayer` default. |
| **CoreImage** | iOS 18 SDK | PNG validation in addLogoLayer | `CIImage(data:)` returns nil for invalid PNG — used in the default implementation. |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| — _(none)_ | — | — | No third-party libraries needed. This is a pure Swift language refactor — protocol extensions are a first-class language construct. |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Protocol extension defaults (recommended) | Add `with(position:)`/`with(scale:)` helper methods to `WatermarkLayer` enum | WatermarkLayer is a data model — adding mutation helpers increases API surface without reducing total duplicated code. The 3-case switch is already ~6 lines; moving it to helpers saves zero lines while adding complexity to the data model. **Rejected per D-05.** |
| Protocol extension defaults (recommended) | Add a base class `WatermarkViewModelBase` | Swift's `@Observable` does not support class inheritance well (observable tracking breaks with subclass overrides). Protocol + extension is the idiomatic Swift approach for shared behavior across ViewModels. |
| Single extension block (recommended) | Separate extension files (`WatermarkConfigurable+LayerManagement.swift`, etc.) | Extra files add navigation overhead without benefit at this scale (~8 defaults). Same-file keeps the protocol + its defaults co-located for discoverability. |

**Installation:**
```bash
# No package manager needed. Protocol extensions are built into the Swift language.
# The refactor edits 4 existing files within existing Xcode targets.
```

**Version verification:** Not applicable — no external packages. Swift language feature verified via local compilation test (Swift 6.2.3, Xcode 26.2). Protocol extension default implementations for computed `{ get set }` properties compile cleanly with `@MainActor` isolation in Swift 6 language mode. [VERIFIED: local swift compilation test]

## Package Legitimacy Audit

> **Skipped.** This phase installs zero external packages. The refactor uses only the Swift language and Apple system frameworks already linked by the project. No npm/pip/cargo packages are recommended, proposed, or installed.

## Architecture Patterns

### System Architecture Diagram

```
┌─────────────────────────────────────────────────────┐
│  WatermarkCore (Shared Swift Package)               │
│                                                     │
│  ┌─────────────────────────────────────────────┐   │
│  │ WatermarkConfigurable Protocol              │   │
│  │ (@MainActor, AnyObject)                     │   │
│  │                                             │   │
│  │ Requirements:                               │   │
│  │  config, activeLayerIndex,                  │   │
│  │  errorMessage, showError,                   │   │
│  │  whiteFrameEnabled, outputFormat,           │   │
│  │  outputQuality, sourceHasHDR,               │   │
│  │  sourceFormatLabel                          │   │
│  │                                             │   │
│  │ Methods:                                    │   │
│  │  addLogoLayer, addSignatureLayer,           │   │
│  │  removeLayer, updateLayerPosition,          │   │
│  │  updateLayerScale, toggleWhiteFrame,        │   │
│  │  renderAndPrepareShare, presentShareSheet,  │   │
│  │  cancelVideoExport                          │   │
│  └──────────────┬──────────────────────────────┘   │
│                 │                                    │
│  ┌──────────────▼──────────────────────────────┐   │
│  │ Protocol Extension (Defaults)               │   │
│  │                                             │   │
│  │ ✅ addLogoLayer(pngData:)                   │   │
│  │ ✅ addSignatureLayer(...) [no-op]           │   │
│  │ ✅ removeLayer(at:)                         │   │
│  │ ✅ updateLayerPosition(at:position:)        │   │
│  │ ✅ updateLayerScale(at:scale:)              │   │
│  │ ✅ toggleWhiteFrame()                       │   │
│  │ ✅ whiteFrameEnabled: Bool { get }          │   │
│  │ ✅ outputFormat: OutputFormat { get set }   │   │
│  │ ✅ outputQuality: Float { get set }         │   │
│  └──────────────┬──────────────────────────────┘   │
│                 │                                    │
│  Consumed by:   │                                    │
│  ┌──────────────┼──────────────────────────────┐   │
│  │ WatermarkConfiguration                     │   │
│  │  config.watermarks: [WatermarkLayer]        │   │
│  │  config.whiteFrame: WhiteFrameConfig?       │   │
│  │  config.outputFormat/outputQuality          │   │
│  └────────────────────────────────────────────┘   │
└──────────────────────┬──────────────────────────────┘
                       │
         ┌─────────────┼─────────────┐
         │             │             │
         ▼             ▼             ▼
┌─────────────┐ ┌─────────────┐ ┌─────────────────┐
│ Main App    │ │ Share       │ │ Photo Edit      │
│ Target      │ │ Extension   │ │ Extension       │
│             │ │ Target      │ │ Target          │
│ WatermarkVM │ │ ShareExtVM  │ │ PhotosExtVM     │
│             │ │             │ │                 │
│ Keeps:      │ │ Keeps:      │ │ Keeps:          │
│ • addSig    │ │ • render    │ │ • render        │
│   nature    │ │   AndPrep   │ │   AndPrep       │
│   Layer     │ │   areShare  │ │   areShare      │
│   (real)    │ │ • cancel    │ │ • cancel        │
│ • render    │ │   Video     │ │   Video         │
│   AndPrep   │ │   Export    │ │   Export        │
│   areShare  │ │ • present   │ │                 │
│ • cancel    │ │   Share     │ │ (inherits all   │
│   Video     │ │   Sheet     │ │  8 defaults     │
│   Export    │ │             │ │  from protocol  │
│ • present   │ │ (inherits   │ │  extension)     │
│   Share     │ │  all 8      │ │                 │
│   Sheet     │ │  defaults   │ │                 │
│             │ │  from       │ │                 │
│ (inherits   │ │  protocol   │ │                 │
│  all 8      │ │  extension) │ │                 │
│  defaults   │ │             │ │                 │
│  from       │ │             │ │                 │
│  protocol   │ │             │ │                 │
│  extension) │ │             │ │                 │
└─────────────┘ └─────────────┘ └─────────────────┘
```

### Recommended Project Structure
```
Packages/WatermarkCore/Sources/WatermarkCore/UI/
└── WatermarkConfigurable.swift    # Protocol (44 lines) + Extension (~100 lines added)
                                    # Single file, appended after protocol declaration

App/ViewModels/
└── WatermarkViewModel.swift       # Remove 8 duplicated implementations
                                    # Keep: addSignatureLayer (real), renderAndPrepareShare,
                                    #        cancelVideoExport, presentShareSheet

ShareExtension/
└── ShareExtensionViewModel.swift  # Remove 9 duplicated implementations
                                    # Keep: renderAndPrepareShare, cancelVideoExport,
                                    #        presentShareSheet

PhotoEditExtension/
└── PhotosExtensionViewModel.swift # Remove 9 duplicated implementations
                                    # Keep: renderAndPrepareShare, cancelVideoExport

Packages/WatermarkCore/Tests/WatermarkCoreTests/
└── OutputFormatTests.swift        # Unchanged — protocol declaration still has requirements
```

### Pattern 1: Protocol Default Implementation (Methods)
**What:** Protocol extension provides a default method implementation. Conforming types inherit it automatically but can override. In this case, all 3 conformers have identical implementations — they drop their copies and use the default.

**When to use:** When multiple `@Observable @MainActor` ViewModels share identical logic that operates on protocol-required properties.

**Example — removeLayer default:**
```swift
// Source: Protocol extension default (to be added to WatermarkConfigurable.swift)
// This replaces 3 identical copies (WatermarkViewModel L523-529,
// ShareExtensionViewModel L671-677, PhotosExtensionViewModel L428-434)
extension WatermarkConfigurable {
    func removeLayer(at index: Int) {
        guard index >= 0, index < config.watermarks.count else { return }
        config.watermarks.remove(at: index)
        if activeLayerIndex >= config.watermarks.count {
            activeLayerIndex = max(0, config.watermarks.count - 1)
        }
    }
}
```

### Pattern 2: Protocol Default Implementation (Computed Property, Get-Set)
**What:** Protocol extension provides a computed property with getter and setter that delegates to `self.config`. Satisfies `{ get set }` protocol requirements without per-ViewModel boilerplate.

**When to use:** When computed properties are pure passthrough wrappers around `config` — identical across all conformers.

**Swift 6 verification:** Verified that protocol extension computed properties with `{ get set }` compile in Swift 6 language mode with `@MainActor` isolation. The conforming type need only provide the backing `config` property; the extension provides the passthrough. [VERIFIED: local swift compilation test — Swift 6.2.3]

**Example — outputFormat default:**
```swift
// Source: Protocol extension default
// Replaces 3 identical copies
extension WatermarkConfigurable {
    var outputFormat: OutputFormat {
        get { config.outputFormat }
        set { config.outputFormat = newValue }
    }

    var outputQuality: Float {
        get { config.outputQuality }
        set { config.outputQuality = newValue }
    }

    var whiteFrameEnabled: Bool {
        config.whiteFrame?.isEnabled ?? false
    }
}
```

### Pattern 3: Protocol Default with Error Surfacing (addLogoLayer)
**What:** Default implementation accesses `self.errorMessage` and `self.showError` (added to the protocol per D-01) to surface validation failures. All 3 conformers already have these properties.

**When to use:** When a default method needs to communicate errors to the UI layer, and all conformers share the same error display mechanism (alert binding in SwiftUI).

**Example — addLogoLayer default:**
```swift
// Source: Protocol extension default
// Requires errorMessage and showError in the protocol (D-01)
extension WatermarkConfigurable {
    func addLogoLayer(pngData: Data) {
        guard let _ = CIImage(data: pngData) else {
            errorMessage = "The selected image is not a valid PNG file."
            showError = true
            return
        }
        guard let input = try? ImageWatermarkInput(pngData: pngData) else {
            errorMessage = "The selected image is not a valid PNG file."
            showError = true
            return
        }
        config.watermarks.append(.image(input, position: .bottomRight, scale: 0.15, opacity: 1.0, isVisible: true))
        activeLayerIndex = config.watermarks.count - 1
    }
}
```

### Pattern 4: Switch-Reconstruct for Enum Layer Mutation
**What:** `WatermarkLayer` is an enum with associated values. To mutate a single field (position/scale), the default implementation extracts current values from the layer, then reconstructs the enum case with the modified field. The 3-case switch preserves the input data + all other associated values.

**When to use:** When mutating a single field on a Swift enum with associated values. This is the standard pattern — Swift enums with associated values cannot have `var position: WatermarkPosition { get set }` that mutates in place.

**Example — updateLayerPosition default:**
```swift
// Source: Protocol extension default
// Identical 3-case switch pattern across all 3 ViewModels
extension WatermarkConfigurable {
    func updateLayerPosition(at index: Int, position: WatermarkPosition) {
        guard index >= 0, index < config.watermarks.count else { return }
        let scale = config.watermarks[index].scale
        switch config.watermarks[index] {
        case .text(let input, _, _, let opacity, let isVisible):
            config.watermarks[index] = .text(input, position: position, scale: scale, opacity: opacity, isVisible: isVisible)
        case .image(let input, _, _, let opacity, let isVisible):
            config.watermarks[index] = .image(input, position: position, scale: scale, opacity: opacity, isVisible: isVisible)
        case .signature(let input, _, _, let opacity, let isVisible):
            config.watermarks[index] = .signature(input, position: position, scale: scale, opacity: opacity, isVisible: isVisible)
        }
    }
}
```

### Pattern 5: Default No-Op for Extension ViewModels
**What:** `addSignatureLayer` default is an empty body. WatermarkViewModel (main app) overrides with the real PencilKit implementation. ShareExtensionViewModel and PhotosExtensionViewModel drop their empty stubs and inherit the no-op.

**When to use:** When a protocol method is genuinely implemented by only one conformer; others need a stub for protocol conformance.

**Example:**
```swift
extension WatermarkConfigurable {
    func addSignatureLayer(strokeData: Data, inkColor: CGColor, strokeWidth: CGFloat) {
        // Default: no-op. Overridden by WatermarkViewModel with PencilKit impl.
    }
}
```

### Anti-Patterns to Avoid
- **Do not add stored properties via protocol extension:** Protocol extensions cannot add stored properties. The pattern works because `config`, `activeLayerIndex`, `errorMessage`, and `showError` are already declared in the protocol — the extension reads/writes them.
- **Do not return a new config instead of mutating:** Per D-04, mutate `self.config` directly. A `@discardableResult`/return-new-config pattern would break the existing call-site contracts (all callers expect mutation, not return value).
- **Do not touch the 3 ViewModels' `config` property declarations:** Each ViewModel has a `config` with a `didSet { AppGroupConfigSync.save(config) }` observer. The protocol extension calls through this same property accessor — `didSet` fires correctly on mutation regardless of whether the mutation originates in the ViewModel or the protocol extension.
- **Do not add `with(position:)`/`with(scale:)` to WatermarkLayer:** Per D-05, the 3-case switch stays in the protocol extension. Adding helpers to the data model increases API surface without reducing total code.

## Don't Hand-Roll

This phase IS the "stop hand-rolling" fix. The current state has ~186 lines of hand-rolled duplicated implementations across 3 ViewModels. The protocol extension eliminates this.

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Duplicated layer-management logic across 3 ViewModels | Per-ViewModel copy-paste of identical methods | Protocol extension with default implementations | Single source of truth; any future bug fix or enhancement applies to all 3 targets simultaneously |
| Duplicated computed property wrappers (outputFormat, outputQuality, whiteFrameEnabled) | Get/set boilerplate in every ViewModel | Protocol extension computed property | 3–5 lines each × 3 ViewModels = 9–15 lines → 3–5 lines in protocol extension |
| Empty `addSignatureLayer` stubs in 2 extension ViewModels | Per-ViewModel empty function bodies | Default no-op in protocol extension | 2 stubs eliminated; conformers that need the real impl override |

**Key insight:** The protocol extension pattern preserves the important design property that all 3 ViewModels conform to the same interface. `ControlsView` and all sub-views are generic over `WatermarkConfigurable & Observable` — they call `viewModel.addLogoLayer(data)` without knowing or caring whether the implementation comes from the ViewModel or a protocol extension. Zero call-site changes required.

## Runtime State Inventory

> Phase 10 is a pure code refactor — no rename, rebrand, or migration. The "name" of the protocol, protocol requirements, and conforming types are unchanged. Methods change location (from ViewModel to protocol extension) but their signatures are unchanged.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | None — no database migration needed. `WatermarkConfiguration` struct is unchanged; `config.watermarks` array structure identical. | None |
| Live service config | None — no external service configurations reference the refactored code. | None |
| OS-registered state | None — no OS-level registrations reference the refactored code. | None |
| Secrets/env vars | None — no secrets or env vars are affected. | None |
| Build artifacts | None — no compiled artifacts carry code-location metadata that would break. The binary output is functionally identical. | None |

**Nothing found in any category.** The refactor is a pure source-code restructuring — no runtime state is affected.

## Common Pitfalls

### Pitfall 1: Protocol Extension Shadowing by ViewModel Override
**What goes wrong:** If a ViewModel retains a method with the same signature as the protocol extension default, the ViewModel's version "wins" (Swift's most-specific-implementation rule). This is actually the desired behavior for `addSignatureLayer` in WatermarkViewModel — but could mask a missed deletion if the executor accidentally leaves a duplicate behind.

**Why it happens:** Swift resolves method dispatch for protocol extension defaults as: most-derived implementation first. A class method always shadows a protocol extension default.

**How to avoid:** The grep audit in the verification strategy (success criteria #2) explicitly confirms zero duplicated implementations remain. Grep for each method signature in each ViewModel file.

**Warning signs:** Tests still pass after deleting a ViewModel method... but also still pass if you forgot to delete it (because the ViewModel's override shadows the default). **The grep audit is the authoritative check, not test pass/fail alone.**

### Pitfall 2: Computed Property Protocol Requirements in Swift 6
**What goes wrong:** A protocol declares `var outputFormat: OutputFormat { get set }` and the extension provides a computed property with both getter and setter. In earlier Swift versions, computed properties in protocol extensions were sometimes treated as read-only defaults. In Swift 6, this is well-defined — but the compiler error messages can be opaque if the pattern is slightly wrong.

**Why it happens:** Swift's protocol conformance rules are complex. The extension's computed property must have the exact same access level (`get set` matches `get set`; `get` matches `get`). A computed property in a protocol extension with only `get` cannot satisfy a `{ get set }` requirement.

**How to avoid:** For `outputFormat` and `outputQuality`, the protocol already declares `{ get set }`. The extension provides `{ get { ... } set { ... } }` — this matches exactly. This was verified to compile in Swift 6.2.3 with `@MainActor`. No protocol requirement changes needed. [VERIFIED: local swift compilation test]

**Warning signs:** Compiler error "protocol requires property 'outputFormat' with type 'OutputFormat' (Swift.OutputFormat); do you want to add a stub?" — means the extension's computed property access level doesn't match the protocol requirement.

### Pitfall 3: `@MainActor` Isolation with Protocol Extensions
**What goes wrong:** In Swift 6, protocol conformance isolation checking is strict. If the protocol is `@MainActor` and the extension methods mutate MainActor-isolated properties (`config`, `activeLayerIndex`), the extension must be on a `@MainActor` protocol.

**Why it happens:** Swift 6's data-race safety model. Extension methods that access MainActor-isolated state must themselves be MainActor-isolated.

**How to avoid:** The existing protocol is already `@MainActor public protocol WatermarkConfigurable: AnyObject`. The protocol extension automatically inherits this isolation. All 3 conforming ViewModels are `@MainActor @Observable final class`. No isolation changes needed. [VERIFIED: local swift compilation test — protocol extension with `@MainActor` protocol compiles cleanly in Swift 6 mode]

**Warning signs:** Swift 6 compiler errors about "main actor-isolated property cannot satisfy nonisolated requirement" or "conformance crosses into main actor-isolated code."

## Code Examples

Verified patterns from official sources and local compilation:

### Protocol Declaration Changes (add error properties)
```swift
// Source: WatermarkConfigurable.swift (protocol declaration, lines to add after sourceFormatLabel)
// D-01: error properties for addLogoLayer validation surfacing

    var errorMessage: String? { get set }
    var showError: Bool { get set }
```

### Full Protocol Extension Block
```swift
// Source: WatermarkConfigurable.swift (appended after existing protocol declaration)
// D-04: direct mutation of self.config and self.activeLayerIndex

// MARK: - Default Implementations

extension WatermarkConfigurable {

    // MARK: Layer Management

    func addLogoLayer(pngData: Data) {
        guard let _ = CIImage(data: pngData) else {
            errorMessage = "The selected image is not a valid PNG file."
            showError = true
            return
        }
        guard let input = try? ImageWatermarkInput(pngData: pngData) else {
            errorMessage = "The selected image is not a valid PNG file."
            showError = true
            return
        }
        config.watermarks.append(.image(input, position: .bottomRight, scale: 0.15, opacity: 1.0, isVisible: true))
        activeLayerIndex = config.watermarks.count - 1
    }

    func addSignatureLayer(strokeData: Data, inkColor: CGColor, strokeWidth: CGFloat) {
        // Default: no-op. Overridden by WatermarkViewModel with PencilKit implementation.
    }

    func removeLayer(at index: Int) {
        guard index >= 0, index < config.watermarks.count else { return }
        config.watermarks.remove(at: index)
        if activeLayerIndex >= config.watermarks.count {
            activeLayerIndex = max(0, config.watermarks.count - 1)
        }
    }

    func updateLayerPosition(at index: Int, position: WatermarkPosition) {
        guard index >= 0, index < config.watermarks.count else { return }
        let scale = config.watermarks[index].scale
        switch config.watermarks[index] {
        case .text(let input, _, _, let opacity, let isVisible):
            config.watermarks[index] = .text(input, position: position, scale: scale, opacity: opacity, isVisible: isVisible)
        case .image(let input, _, _, let opacity, let isVisible):
            config.watermarks[index] = .image(input, position: position, scale: scale, opacity: opacity, isVisible: isVisible)
        case .signature(let input, _, _, let opacity, let isVisible):
            config.watermarks[index] = .signature(input, position: position, scale: scale, opacity: opacity, isVisible: isVisible)
        }
    }

    func updateLayerScale(at index: Int, scale scaleInput: CGFloat) {
        guard index >= 0, index < config.watermarks.count else { return }
        let clamped = min(max(scaleInput, 0.01), 0.90)
        let position = config.watermarks[index].position
        switch config.watermarks[index] {
        case .text(let input, _, _, let opacity, let isVisible):
            config.watermarks[index] = .text(input, position: position, scale: clamped, opacity: opacity, isVisible: isVisible)
        case .image(let input, _, _, let opacity, let isVisible):
            config.watermarks[index] = .image(input, position: position, scale: clamped, opacity: opacity, isVisible: isVisible)
        case .signature(let input, _, _, let opacity, let isVisible):
            config.watermarks[index] = .signature(input, position: position, scale: clamped, opacity: opacity, isVisible: isVisible)
        }
    }

    // MARK: White Frame

    func toggleWhiteFrame() {
        if config.whiteFrame?.isEnabled == true {
            config.whiteFrame = nil
        } else {
            config.whiteFrame = WhiteFrameConfig(isEnabled: true)
        }
    }

    var whiteFrameEnabled: Bool {
        config.whiteFrame?.isEnabled ?? false
    }

    // MARK: Export Settings

    var outputFormat: OutputFormat {
        get { config.outputFormat }
        set { config.outputFormat = newValue }
    }

    var outputQuality: Float {
        get { config.outputQuality }
        set { config.outputQuality = newValue }
    }
}
```

### Line Count Reduction
```
Before (duplicated across 3 ViewModels):
  addLogoLayer:      14 lines × 3 = 42
  addSignatureLayer:  5 (real) + 2 (stub) + 2 (stub) = 9
  removeLayer:        7 × 3 = 21
  updateLayerPosition: 12 × 3 = 36
  updateLayerScale:  13 × 3 = 39
  toggleWhiteFrame:   7 × 3 = 21
  whiteFrameEnabled:  3 × 3 = 9
  outputFormat:       4 × 3 = 12
  outputQuality:      5 × 3 = 15
  ─────────────────────────
  Total: ~204 lines (including doc comments, ~186 implementation lines)

After (protocol extension as single source of truth):
  Protocol extension: ~100 lines (8 defaults in one file)
  Remaining in ViewModels: ~5 lines (addSignatureLayer real impl)
  ─────────────────────────
  Net reduction: ~186 → ~5 in ViewModel layer-management code
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Per-ViewModel copy-paste of identical layer-management methods | Protocol extension with default implementations | Swift 2.0 (2015) — protocol extensions are a mature language feature | Single source of truth; fixes the exact maintenance hazard identified in Retrospective Key Lesson #3 |
| `@ObservableObject` with `ObservableObject` conformance | `@Observable` macro (Swift 5.9 / iOS 17+) | Already adopted in this project | Protocol extension works identically with `@Observable`; no ObservableObject-specific patterns needed |
| Manual protocol conformance without defaults | Protocol extensions providing defaults | Swift 2.0+ standard practice | Reduces boilerplate; conforming types only override what they need |

**Deprecated/outdated:**
- **Class inheritance for ViewModel sharing:** `@Observable` does not interoperate well with class hierarchies (observation tracking breaks with subclass overrides). Protocol + extension is the idiomatic Swift pattern. This project already uses protocols — Phase 10 completes the pattern by adding defaults.

## Assumptions Log

> All claims in this research were verified or cited — no user confirmation needed.

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| — | _(none)_ | — | — |

**All claims verified:** Protocol extension behavior verified via local Swift 6.2.3 compilation test. Duplicated code verified via direct file reading of all 3 ViewModels. Protocol structure verified via file reading. Build gate verified via script inspection. No unverified assumptions.

## Open Questions

1. **MARK comment organization**
   - What we know: The existing protocol has no MARK comments. The extension can introduce them (Layer Management, White Frame, Export Settings).
   - What's unclear: Whether the planner prefers a single extension block or multiple blocks separated by MARK. Both are valid Swift.
   - Recommendation: Use a single `extension WatermarkConfigurable { ... }` block with `// MARK:` comments inside — simpler to review and diff. The planner has discretion per CONTEXT.md.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Swift (swiftc) | Protocol extension compilation | ✓ | 6.2.3 | — |
| Xcode (xcodebuild) | Build gate verification | ✓ | 26.2 | — |
| git | Commit workflow | ✓ | (system) | — |

**Missing dependencies with no fallback:** None — all required tools are available.

**Missing dependencies with fallback:** None.

## Validation Architecture

> **Skipped.** `workflow.nyquist_validation` is explicitly `false` in `.planning/config.json`. No Validation Architecture section required.

### Verification Strategy (in lieu of Nyquist validation)

Per D-07 and D-08, verification is three-fold with no new tests required:

1. **Existing test suite:** Run the full test suite after the refactor. All 227 existing tests must pass (success criteria #4). Since the refactor changes zero behavior — only code location — existing tests exercise the same code paths regardless of whether the implementation lives in the ViewModel or the protocol extension.

2. **Build gate:** Run `bash scripts/build-gate.sh` after each refactor step. Must pass for all 3 targets (success criteria #5). The WatermarkApp scheme builds WatermarkCore + Main App + ShareExtension + PhotoEditExtension via implicit dependencies.

3. **grep audit:** After removing duplicated implementations from each ViewModel, grep for the 5 method signatures to confirm zero remain:
   ```bash
   grep -n "func addLogoLayer" App/ViewModels/WatermarkViewModel.swift ShareExtension/ShareExtensionViewModel.swift PhotoEditExtension/PhotosExtensionViewModel.swift
   grep -n "func removeLayer" App/ViewModels/WatermarkViewModel.swift ShareExtension/ShareExtensionViewModel.swift PhotoEditExtension/PhotosExtensionViewModel.swift
   grep -n "func updateLayerPosition" App/ViewModels/WatermarkViewModel.swift ShareExtension/ShareExtensionViewModel.swift PhotoEditExtension/PhotosExtensionViewModel.swift
   grep -n "func updateLayerScale" App/ViewModels/WatermarkViewModel.swift ShareExtension/ShareExtensionViewModel.swift PhotoEditExtension/PhotosExtensionViewModel.swift
   grep -n "func toggleWhiteFrame" App/ViewModels/WatermarkViewModel.swift ShareExtension/ShareExtensionViewModel.swift PhotoEditExtension/PhotosExtensionViewModel.swift
   ```
   Expected: grep returns no matches in any of the 3 ViewModels (all implementations are now in the protocol extension). Exception: `addSignatureLayer` in WatermarkViewModel only — this is the real PencilKit impl that stays.

4. **Line count verification:** After the refactor, count the remaining layer-management code in the 3 ViewModels to confirm ~186 → ~20 reduction (success criteria #3).

## Security Domain

### Security Assessment

**This is a pure structural refactor — no new security surface is introduced.** The refactor:
- Moves identical code from 3 locations to 1 without changing any logic
- Does not introduce new data flows, inputs, outputs, or API endpoints
- Does not add, remove, or modify any cryptographic operations
- Does not change how `config` is serialized to App Group UserDefaults (the `didSet { AppGroupConfigSync.save(config) }` fires identically whether the mutation originates in the ViewModel or the protocol extension)
- Does not change the `addLogoLayer` PNG validation logic — the same `CIImage(data:)` guard + `ImageWatermarkInput` try? pattern is used

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | No | — |
| V3 Session Management | No | — |
| V4 Access Control | No | — |
| V5 Input Validation | No (unchanged) | Existing `CIImage(data:)` PNG validation in `addLogoLayer` is preserved identically in the protocol extension default |
| V6 Cryptography | No | — |

### Known Threat Patterns

No new threat patterns introduced. The existing security properties of the codebase are preserved:
- `config` mutation still goes through the same `didSet` → `AppGroupConfigSync.save` path
- `addLogoLayer` still validates PNG data before appending to watermark layers
- All processing remains on-device (no network calls in any of the refactored methods)

## Sources

### Primary (HIGH confidence)
- **Local compilation test** — Swift 6.2.3 protocol extension with `@MainActor`, computed properties with `{ get set }`, and `AnyObject` constraint verified to compile cleanly. [VERIFIED: local swift compilation test]
- **Codebase file reading** — All 3 ViewModels' duplicated implementations confirmed identical via direct file inspection of `WatermarkViewModel.swift` (L502-579), `ShareExtensionViewModel.swift` (L651-737), `PhotosExtensionViewModel.swift` (L81-89, L408-483)
- **Codebase file reading** — `WatermarkConfigurable.swift` protocol declaration (44 lines) confirmed; no extension exists yet
- **Codebase file reading** — `WatermarkConfiguration.swift`: `WatermarkLayer` enum with computed properties `position`, `scale`, `opacity`, `isVisible` confirmed; `config.watermarks: [WatermarkLayer]` mutation target confirmed

### Secondary (MEDIUM confidence)
- **Apple Swift documentation** — Protocol extensions (Swift Programming Language: Protocols → Providing Default Implementations) [CITED: docs.swift.org/swift-book/documentation/the-swift-programming-language/protocols/#Providing-Default-Implementations]
- **Google Web Search** — Verified that protocol extension computed properties with `{ get set }` satisfy protocol requirements in Swift. Multiple sources (Stack Overflow, Swift.org, medium.com technical blogs) confirm this is standard, well-established behavior.

### Tertiary (LOW confidence)
- None — all claims verified through either compilation test, codebase inspection, or authoritative Swift documentation.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — pure Swift language feature; no external dependencies; verified via local compilation
- Architecture: HIGH — protocol extension pattern is the standard Swift approach for shared ViewModel behavior; all 3 ViewModels share identical structure and the same protocol conformance
- Pitfalls: HIGH — pitfalls are well-understood from Swift's protocol dispatch rules and Swift 6's concurrency checking; mitigation strategies are concrete and testable

**Research date:** 2026-06-18
**Valid until:** 2026-07-18 — stable domain (protocol extensions are a mature Swift feature, no anticipated Swift 6 changes that would affect this pattern)

**File analysis summary:**
- 4 files edited: `WatermarkConfigurable.swift` (add extension), `WatermarkViewModel.swift` (remove 8 impls), `ShareExtensionViewModel.swift` (remove 9 impls), `PhotosExtensionViewModel.swift` (remove 9 impls)
- 0 files created
- 0 project structure changes
- 0 new targets or build settings
- ~186 duplicated lines eliminated → protocol extension ~100 lines added
