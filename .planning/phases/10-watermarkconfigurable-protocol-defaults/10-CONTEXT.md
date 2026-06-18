# Phase 10: WatermarkConfigurable Protocol Defaults - Context

**Gathered:** 2026-06-18
**Status:** Ready for planning

<domain>
## Phase Boundary

This phase adds default implementations to the `WatermarkConfigurable` protocol for shared layer-management operations, collapsing ~186 lines of duplicated code across 3 ViewModels (WatermarkViewModel, ShareExtensionViewModel, PhotosExtensionViewModel) to ~20 lines. This is a pure refactor — no new user-facing features, no API changes, no behavior changes.

**Deliverables:**
1. Protocol extension on `WatermarkConfigurable` with default implementations for `addLogoLayer`, `removeLayer`, `updateLayerPosition`, `updateLayerScale`, `toggleWhiteFrame`, `addSignatureLayer`, `whiteFrameEnabled`, `outputFormat`, and `outputQuality`
2. Removal of duplicated implementations from WatermarkViewModel, ShareExtensionViewModel, and PhotosExtensionViewModel
3. Verification that all 227 existing tests pass and the Phase 9 build gate passes for all 3 targets

**Out of scope:** `renderAndPrepareShare()`, `cancelVideoExport()`, `presentShareSheet()` — these have genuinely different implementations per target and are not duplicated. `addSignatureLayer` real implementation stays in WatermarkViewModel (overrides the default no-op). No new features, no new tests.
</domain>

<decisions>
## Implementation Decisions

[auto] Selected all 4 gray areas. Recommended options auto-picked for each.

### Error Handling Strategy (addLogoLayer)
- **D-01:** Add `errorMessage: String? { get set }` and `showError: Bool { get set }` to the `WatermarkConfigurable` protocol so the default `addLogoLayer(pngData:)` can surface PNG validation failures directly. All 3 conformers already have these `@Published`/observable properties — this collapses the method into a single protocol default. Existing call sites (LogoPickerView's `onAppear` error alert binding) continue to work since they bind to the ViewModel properties already.

### Computed Property Collapse
- **D-02:** Include `whiteFrameEnabled: Bool`, `outputFormat: OutputFormat`, and `outputQuality: Float` computed properties in the protocol extension defaults alongside the 5 layer-management methods. All 3 are identical 3–5 line get/set wrappers around `config`. Collapsing them reduces total duplicated lines further and increases consistency. These already have `{ get }` / `{ get set }` requirements in the protocol.

### addSignatureLayer Default No-Op
- **D-03:** Add a default no-op implementation for `addSignatureLayer(strokeData:inkColor:strokeWidth:)` in the protocol extension (empty body). Both ShareExtensionViewModel and PhotosExtensionViewModel currently have empty stubs (`func addSignatureLayer(...) { }`). WatermarkViewModel overrides with the real PencilKit implementation. This removes 2 boilerplate stubs from extensions without changing behavior.

### Mutating Self Pattern
- **D-04:** Protocol extension methods mutate `self.config` and `self.activeLayerIndex` directly. The `AnyObject` class constraint guarantees reference semantics — no `@discardableResult`/return-new-config pattern needed. This matches the existing code's direct mutation style exactly, minimizing behavioral change. No `var` shadowing or copy-on-write concerns.

### WatermarkLayer Switch Statements
- **D-05:** Keep the 3-case switch (text/image/signature) for layer reconstruction in the protocol extension rather than adding `with(position:)`/`with(scale:)` helper methods to `WatermarkLayer`. The switch is already ~6 lines and adding helpers to the data model increases API surface without reducing total code. The protocol extension is the single point of duplication elimination — not a data model enhancement.

### Scope Boundary — What Stays Per-ViewModel
- **D-06:** The following methods remain per-ViewModel (not eligible for defaults — genuinely different behavior per target):
  - `renderAndPrepareShare()` — WatermarkViewModel renders to temp file + shows share sheet; PhotosExtensionViewModel renders to PHContentEditingOutput; ShareExtensionViewModel renders to App Group + invokes NSExtensionContext completion
  - `cancelVideoExport()` — different cancelation targets per ViewModel (Main App URLSession task vs. extension background tasks)
  - `presentShareSheet()` — different sheet presentation contexts (Main App window scene vs. extension view controller hierarchy)
  - `addSignatureLayer` real implementation — stays in WatermarkViewModel only; extensions get the default no-op from D-03

### Verification Strategy
- **D-07:** Verification is three-fold:
  1. **Existing tests:** All 227 automated tests must pass after the refactor (success criteria #4). The refactor changes zero behavior — only moves code location from per-ViewModel to protocol extension. Existing tests exercise the same code paths.
  2. **Build gate:** `bash scripts/build-gate.sh` must pass for all 3 targets (success criteria #5). Build gate was delivered in Phase 9 and runs xcodebuild across WatermarkApp scheme (covers all 3 targets + WatermarkCore via implicit dependencies).
  3. **grep audit:** grep for the 5 method signatures (`func addLogoLayer`, `func removeLayer`, `func updateLayerPosition`, `func updateLayerScale`, `func toggleWhiteFrame`) in each ViewModel confirms zero duplicated implementations remain (success criteria #2). The protocol extension in WatermarkCore is the single source of truth.

### No New Tests Required
- **D-08:** No new automated tests are required. The refactor is purely structural — moving code from 3 locations to 1 without changing any logic. The existing 227 tests cover the same code paths and will fail if the refactor introduces a regression. Adding new tests for a code-move would test the Swift compiler's protocol dispatch, not application logic. The build gate + grep audit provide equivalent verification.

### the agent's Discretion
- The exact ordering of protocol requirements vs. extension methods in WatermarkConfigurable.swift is left to the planner. Constraint: extension methods must be in the same file or a file that's part of the `WatermarkCore` target and imported by all 3 consuming targets.
- Whether to group the 5 layer-management methods + computed properties in one protocol extension or separate extensions (e.g., `// MARK: - Layer Management` / `// MARK: - Export Settings`) is left to the planner — follow the existing code organization conventions in WatermarkConfigurable.swift.
- The exact phrasing and placement of error-handling properties in the protocol (`errorMessage: String?`, `showError: Bool`) is left to the planner — group with the existing error-related protocol surface.
- Whether `outputFormat` and `outputQuality` protocol requirements need to change from `{ get set }` to allow default implementations is left to the researcher to verify. Current Swift behavior: protocol extension computed properties can satisfy `{ get set }` requirements as long as they provide both getter and setter.

### Folded Todos
None — no pending todos matched Phase 10's scope.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase scope + success criteria
- `.planning/ROADMAP.md` §"Phase 10: WatermarkConfigurable Protocol Defaults" — phase goal, depends-on (Phase 9), requirements (REFA-01), and the 5 success criteria (verbatim source of truth for what "done" means).
- `.planning/REQUIREMENTS.md` §"Refactor (REFA)" — defines REFA-01 and the v1.1 traceability table.
- `.planning/PROJECT.md` §"Current Milestone", §"Key Decisions" — v1.1 tech-debt framing; confirms the duplicatation root cause: "186 lines of near-duplicate ViewModel layer-management code across 3 targets."

### Protocol definition (the edit target)
- `Packages/WatermarkCore/Sources/WatermarkCore/UI/WatermarkConfigurable.swift` — the `WatermarkConfigurable` protocol. **This is where default implementations are added.** Currently 44 lines: declares `config`, `activeLayerIndex`, `renderingState`, `whiteFrameEnabled`, `outputFormat`, `outputQuality`, `sourceHasHDR`, `sourceFormatLabel`, and the 8 method requirements. No extension exists yet.

### Data model (what the defaults operate on)
- `Packages/WatermarkCore/Sources/WatermarkCore/Models/WatermarkConfiguration.swift` — `WatermarkConfiguration` struct (§1-68) and `WatermarkLayer` enum (§77-125). The enum has computed properties `position`, `scale`, `opacity`, `isVisible` (all get-only). `config.watermarks` is `[WatermarkLayer]`. Protocol defaults mutate `config.watermarks[index]` via switch-based reconstruction.

### Duplicated code (the code to collapse)
- `App/ViewModels/WatermarkViewModel.swift` lines 502-579 — duplicated implementations: `addLogoLayer` (502-515), `addSignatureLayer` real impl (517-521, stays), `removeLayer` (523-529), `updateLayerPosition` (531-542), `updateLayerScale` (544-556), `toggleWhiteFrame` (558-564), `whiteFrameEnabled` (566-568), `outputFormat` (570-573), `outputQuality` (575-579).
- `ShareExtension/ShareExtensionViewModel.swift` lines 651-737 — duplicated implementations: `addLogoLayer` (651-664), `addSignatureLayer` empty stub (667), `removeLayer` (671-677), `updateLayerPosition` (683-694), `updateLayerScale` (700-712), `toggleWhiteFrame` (715-721), `whiteFrameEnabled` (724-726), `outputFormat` (728-731), `outputQuality` (733-737).
- `PhotoEditExtension/PhotosExtensionViewModel.swift` lines 81-89 (outputFormat/outputQuality), lines 408-483 — duplicated implementations: `addLogoLayer` (408-421), `addSignatureLayer` empty stub (424), `removeLayer` (428-434), `updateLayerPosition` (440-451), `updateLayerScale` (457-469), `toggleWhiteFrame` (472-478), `whiteFrameEnabled` (481-483).

### Build gate (protects the refactor)
- `scripts/build-gate.sh` — Phase 9's xcodebuild gate. Runs after execution wave completes. Must pass for all 3 targets after the refactor (success criteria #5).
- `.planning/phases/09-wave-level-build-gate/09-CONTEXT.md` §"Implementation Decisions" — D-01 through D-14 document the build gate's invocation, exit codes, and wave-boundary wiring.

### Retrospective (why this phase exists)
- `.planning/RETROSPECTIVE.md` lines 28, 44 — Key Lesson #3: "Add default implementations to WatermarkConfigurable protocol. 186 lines of duplicated layer-management code across 3 ViewModels is a maintenance hazard. A protocol extension with defaults would collapse this to ~20 lines."

### Prior phase patterns
- `.planning/phases/08-traceability-reconciliation-recurrence-guard/08-CONTEXT.md` §"Implementation Decisions" — establishes repo conventions: atomic commits, AGENTS.md documentation, exit-code contracts.
- `.planning/phases/09-wave-level-build-gate/09-CONTEXT.md` §"Existing Code Insights" — established patterns for repo-local scripts and gate integration with the execute workflow.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`WatermarkConfigurable` protocol** — already declared in WatermarkCore, already `@MainActor` + `AnyObject`-constrained, already has the 5 method signatures + 3 computed property signatures. Protocol extension is added to the same file; no new files needed.
- **`WatermarkLayer` enum** — already has get-only computed properties (`position`, `scale`, `opacity`, `isVisible`) used by the duplicated switch statements. The protocol extension uses these for the guard-and-extract pattern.
- **`WatermarkConfiguration` struct** — `config.watermarks: [WatermarkLayer]` is the mutation target. `config.whiteFrame: WhiteFrameConfig?` is the toggleWhiteFrame target.
- **`CIImage(data:)`** and **`ImageWatermarkInput(pngData:)`** — used by `addLogoLayer` for PNG validation. Both already available in WatermarkCore.

### Established Patterns
- **`@MainActor @Observable` ViewModels** — all 3 conformers follow the same pattern: `@MainActor final class XxxViewModel: WatermarkConfigurable`. The protocol extension inherits `@MainActor` isolation.
- **Direct mutation style** — existing implementations mutate `self.config` and `self.activeLayerIndex` directly without intermediate copies or `@discardableResult`. The protocol extension preserves this exact style (per D-04).
- **Guard-then-switch-reconstruct pattern** — `updateLayerPosition` and `updateLayerScale` follow the same structure: (1) guard index bounds, (2) extract current position/scale from layer, (3) switch on layer case with 3 branches extracting input + preserved fields, (4) reconstruct with modified field. The protocol extension copies this pattern identically.
- **No third-party dependencies** — WatermarkCore uses only Apple frameworks (Foundation, SwiftUI, CoreImage). The protocol extension has zero dependency changes.

### Integration Points
- **`ControlsView`** — generic over `WatermarkConfigurable & Observable`. Reads from protocol requirements; doesn't need changes.
- **`PositionGridView`**, **`ScaleStepperView`**, **`LayerListView`**, **`LogoPickerView`**, **`WhiteFrameToggleView`**, **`SignatureCaptureView`**, **`TextWatermarkInputView`** — all generic over `WatermarkConfigurable & Observable`. Call the protocol methods; no changes needed.
- **`OutputFormatTests.swift`** (WatermarkCoreTests line 144-146) — tests that the protocol declares `outputFormat` and `outputQuality`. Adding defaults to the protocol doesn't change the protocol declaration; this test passes unchanged.
- **All 3 ViewModels** — remove the duplicated implementations. Keep their protocol conformance declaration. Keep per-ViewModel methods (`renderAndPrepareShare`, `cancelVideoExport`, `presentShareSheet`).

### Creative Options
- **File placement:** The protocol extension can go in `WatermarkConfigurable.swift` (same file, appended after the protocol declaration) or in a new file like `WatermarkConfigurable+Defaults.swift` in the same directory. The same-file approach is simpler and follows the existing pattern (no extensions file for this protocol yet). The planner chooses based on clarity.
- **MARK organization:** The existing protocol has no MARK comments. The extension can add `// MARK: - Default Implementations` with sub-MARKs for Layer Management, White Frame, Export Settings.
- **Future default candidates:** `cancelVideoExport()` and `renderAndPrepareShare()` could theoretically get default implementations if a common abstraction is introduced (e.g., a `cancelExportTask: Task<Void, Never>?` protocol requirement). This is noted for consideration if a future phase reduces ViewModel divergence further — NOT in scope for Phase 10.

</code_context>

<specifics>
## Specific Ideas

- The 5 methods that must have default implementations (per success criteria #1): `updateLayerPosition`, `updateLayerScale`, `removeLayer`, `toggleWhiteFrame`, `addLogoLayer`.
- The 3 computed properties to additionally collapse (per D-02): `whiteFrameEnabled`, `outputFormat`, `outputQuality`.
- The 1 method to add a default no-op for (per D-03): `addSignatureLayer`.
- Error properties to add to protocol (per D-01): `errorMessage: String? { get set }`, `showError: Bool { get set }`.
- Total target: ~186 duplicated lines → ~20 remaining lines across all 3 ViewModels (measured by removing the 8 duplicated implementations above + addSignatureLayer stubs, keeping only per-ViewModel methods). The ~20 remaining lines are: `addSignatureLayer` in WatermarkViewModel (~5 lines), `renderAndPrepareShare()` in each (~5-10 lines each), `cancelVideoExport()` in each (~5 lines each), `presentShareSheet()` in each (~3 lines each).
- The refactor touches 4 files: `WatermarkConfigurable.swift` (add extension), `WatermarkViewModel.swift` (remove 8 implementations), `ShareExtensionViewModel.swift` (remove 9 implementations), `PhotosExtensionViewModel.swift` (remove 9 implementations). All 4 files are within existing targets — no project file changes needed.
- Phase 9 build gate runs `xcodebuild -project Watermark.xcodeproj -scheme WatermarkApp -configuration Debug -destination 'generic/platform=iOS' build`. The refactor must pass this gate. Since the WatermarkApp scheme implicitly builds ShareExtension + PhotoEditExtension (via `buildImplicitDependencies = "YES"`), a single invocation covers all 3 targets.
- The `config.watermarks` array is mutated in place via `config.watermarks[index] = newLayer`. This works because `config` is a struct with `{ get set }` — the protocol extension writes the whole struct back. The existing code does the same pattern.
- `addLogoLayer` appends `.image(input, position: .bottomRight, scale: 0.15, opacity: 1.0, isVisible: true)` and sets `activeLayerIndex = config.watermarks.count - 1`. These hardcoded defaults are intentionally identical across all 3 ViewModels — keep them exactly as-is in the protocol default.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope. The following are already deferred at milestone level:
- **CUST-01 through CUST-04** (customization templates) — v2+ scope
- **BATC-01/02** (batch processing) — v2+ scope
- **PHRO-01** (per-phase VERIFICATION.md template) — deferred to future process-hardening milestone
- **PHRO-02** (worktree-safety fix) — GSD tooling concern

A possible future extension noted during analysis: `cancelVideoExport()` and `renderAndPrepareShare()` could get default implementations if a future phase introduces a common `cancelExportTask`/`exportContinuation` protocol requirement. NOT in scope for Phase 10 — the genuinely different per-target behavior in these methods is the design intent.

</deferred>

---

*Phase: 10-WatermarkConfigurable Protocol Defaults*
*Context gathered: 2026-06-18*
