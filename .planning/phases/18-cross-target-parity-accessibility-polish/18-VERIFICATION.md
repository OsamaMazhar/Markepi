---
phase: 18-cross-target-parity-accessibility-polish
verified: 2026-06-22T11:47:00Z
status: human_needed
score: 19/19 must-haves verified
overrides_applied: 0
human_verification:
  - test: "Activate VoiceOver (Settings → Accessibility → VoiceOver), navigate through ControlsView"
    expected: "Pill bar segments announce 'Watermark controls — selected, button — Shows watermark settings', ControlSection containers announce 'Text and position controls', 'Export options', 'Template controls'"
    why_human: "VoiceOver announcement text and navigation flow cannot be verified via code grep alone — requires actual screen reader interaction"
  - test: "Enable Reduce Motion (Settings → Accessibility → Motion → Reduce Motion ON). Return to app, tap pill bar segments and trigger batch processing"
    expected: "Pill bar indicator switches instantly (no slide animation). Batch overlay appears/disappears instantly (no fade). Preview rendering state transitions instantly (no 0.2s crossfade)"
    why_human: "Animation smoothness and instant-switch behavior require visual observation on device"
  - test: "Set Dynamic Type to 200% (Settings → Accessibility → Display & Text Size → Larger Text → max). Return to app with photo loaded, drag sheet to expanded"
    expected: "Sheet reaches ~70% height at large type. Controls scroll internally without clipping or truncation. No text overlap at any size"
    why_human: "Layout behavior at extreme Dynamic Type sizes requires visual verification with actual system text rendering"
  - test: "Cold launch the main app without selecting a photo (or dismiss picker without selecting)"
    expected: "Glass circle with photo SF Symbol renders centered. 'Add a Photo' headline visible. Body text 'Choose a photo or video to watermark and share instantly' visible. 'Choose Photo' primary button visible and tappable. No bottom sheet or Share bar visible"
    why_human: "Visual layout, typography rendering, and button interactivity require on-device verification"
  - test: "Share a photo from Photos app via Share Sheet → Watermark. Verify idle state (if briefly visible). Then load a photo via Photos app Edit → Watermark extension"
    expected: "Share Extension idle state shows EmptyStateView WITHOUT 'Choose Photo' CTA button. Photos Extension idle state same — EmptyStateView without CTA button. 'Preparing photo...' loading state preserved when sourceURL is set but preview not yet generated"
    why_human: "Extension idle state behavior depends on real NSExtensionContext and PHContentEditingInput data flow — cannot be verified via code grep alone"
---

# Phase 18: Cross-Target Parity & Accessibility Polish — Verification Report

**Phase Goal:** Verify the redesigned shared `ControlsView` works in both extensions and finish the accessibility and empty-state polish that makes the redesign production-ready.

**Verified:** 2026-06-22T11:47:00Z
**Status:** human_needed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Snapshot tests verify ShareExtensionRootView renders correctly with ControlsView at 60/40 layout | ✓ VERIFIED | `ExtensionSnapshotTests.swift`: `@Test("Share extension idle state snapshot")` passes. 36KB reference PNG committed |
| 2 | Snapshot tests verify PhotosExtensionRootView renders correctly with Done toolbar button | ✓ VERIFIED | `ExtensionSnapshotTests.swift`: `@Test("Photos extension preview rendered snapshot")` passes. `inNavigationController: true` for toolbar rendering |
| 3 | All 5 snapshot comparison tests pass via xcodebuild test | ✓ VERIFIED | `xcodebuild test -scheme WatermarkCore -only-testing:WatermarkCoreTests/ExtensionSnapshotTests` → **TEST SUCCEEDED**, 5/5 passed in 6.29s |
| 4 | Snapshot reference images committed to repo | ✓ VERIFIED | 5 PNG files at 36KB each in `__Snapshots__/`: share-ext-idle, share-ext-preview, share-ext-multi-item, photos-ext-idle, photos-ext-preview |
| 5 | VoiceOver announces pill bar segments with hints and .isSelected trait | ✓ VERIFIED | `MarkepiPillBar.swift:69-71`: `.accessibilityLabel("\(section.rawValue) controls")`, `.accessibilityHint("Shows ... settings")`, `.accessibilityAddTraits(selection == section ? [.isButton, .isSelected] : .isButton)` |
| 6 | VoiceOver announces ControlSection glass containers with group labels | ✓ VERIFIED | `ControlsView.swift:254-267`: `ControlSection` has `label: String` parameter → `.accessibilityElement(children: .contain)` + `.accessibilityLabel(label)`. All 4 call sites pass descriptive labels |
| 7 | Pill bar sliding indicator does not animate when Reduce Motion enabled | ✓ VERIFIED | `MarkepiPillBar.swift:59`: `withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8))` |
| 8 | Batch progress overlay does not fade when Reduce Motion enabled | ✓ VERIFIED | `BatchProgressOverlay.swift:25`: `@Environment(\.accessibilityReduceMotion)`. `ContentView.swift:209`: `.transition(reduceMotion ? .identity : .opacity)` |
| 9 | All existing VoiceOver labels on sub-views preserved unchanged | ✓ VERIFIED | Position Menu label (line 92), ScaleStepperView (line 38), WhiteFrameToggleView (line 33), LogoPickerView (line 104), SignatureCaptureView (line 84), LayerListView (line 77) all present in ControlsView |
| 10 | Empty state renders glass circle + SF Symbol + headline + body + CTA button | ✓ VERIFIED | `EmptyStateView.swift:38-75`: `Image(systemName: "photo.on.rectangle.angled")` 40pt in 80pt glass circle, "Add a Photo" `.sectionHeader`, body text `.controlLabel`, "Choose Photo" `.markepiPrimary()` |
| 11 | No photo loaded → sheet and Share bar hidden, only EmptyStateView displayed | ✓ VERIFIED | `ContentView.swift:89-91`: `if viewModel.currentPhoto == nil && viewModel.renderingState != .rendering { EmptyStateView(onChoosePhoto: { viewModel.showPicker = true }) }` |
| 12 | Photo loads → sheet and Share bar reappear automatically | ✓ VERIFIED | `ContentView.swift:92-104`: `else` branch renders existing ZStack with previewArea + batchOverlays + inspectorSheet + pinnedShareBar |
| 13 | Expanded sheet height: 70% at .xxLarge+, 55% otherwise | ✓ VERIFIED | `ContentView.swift:82-84`: `dynamicTypeSize >= .xxLarge ? geometry.size.height * 0.70 : geometry.size.height * 0.55` |
| 14 | Preview rendering state animation disabled when Reduce Motion enabled | ✓ VERIFIED | `ContentView.swift:178`: `.animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: viewModel.renderingState)` |
| 15 | Batch progress overlay appears/disappears without fade when Reduce Motion enabled | ✓ VERIFIED | `ContentView.swift:209`: `.transition(reduceMotion ? .identity : .opacity)` with `@Environment(\.accessibilityReduceMotion)` at line 31 |
| 16 | Share extension shows EmptyStateView without CTA button in idle state | ✓ VERIFIED | `ShareExtensionRootView.swift:136-138`: `else if viewModel.sourceURL == nil { EmptyStateView(onChoosePhoto: nil) }` |
| 17 | Photos extension shows EmptyStateView without CTA button in idle state | ✓ VERIFIED | `PhotosExtensionRootView.swift:122-124`: `else if viewModel.sourceURL == nil { EmptyStateView(onChoosePhoto: nil) }` |
| 18 | PreviewView pickerButton removed — empty state at ContentView level | ✓ VERIFIED | `PreviewView.swift:90-91`: fallback renders `Color.clear` with comment "Empty state is now handled by EmptyStateView at ContentView level" |
| 19 | All 3 targets compile (build gate passes) | ✓ VERIFIED | `bash scripts/build-gate.sh` → **BUILD GATE: PASSED** — WatermarkApp, ShareExtension, PhotoEditExtension all compile |

**Score:** 19/19 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `Packages/WatermarkCore/Tests/WatermarkCoreTests/TestHelpers/SnapshotTestViewModel.swift` | Test-only ViewModel with WatermarkConfigurable conformance + SnapshotRenderer + pixel comparator | ✓ VERIFIED | 298 lines. Structural conformance to WatermarkConfigurable proven by `any WatermarkConfigurable = vm` cast in test. Pre-populated config (2 layers, white frame). SnapshotRenderer.render() and pixel comparator included |
| `Packages/WatermarkCore/Tests/WatermarkCoreTests/ExtensionSnapshotTests.swift` | 5 snapshot tests + recordMode infrastructure | ✓ VERIFIED | 265 lines. 20+ @Test functions (15 infrastructure + 5 snapshot). recordMode = false for normal runs. 5 extension tests all pass |
| `Packages/WatermarkCore/Tests/WatermarkCoreTests/__Snapshots__/` | 5 reference PNG images | ✓ VERIFIED | 5 files at 36KB each: share-ext-idle, share-ext-preview, share-ext-multi-item, photos-ext-idle, photos-ext-preview |
| `Packages/WatermarkCore/Sources/WatermarkCore/DesignSystem/MarkepiPillBar.swift` | VoiceOver labels + Reduce Motion gating | ✓ VERIFIED | accessibilityLabel/hint/traits on each segment. `withAnimation(reduceMotion ? nil : .spring(...))` gate |
| `Packages/WatermarkCore/Sources/WatermarkCore/UI/ControlsView.swift` | ControlSection VoiceOver group labels | ✓ VERIFIED | ControlSection has `label: String` init parameter, accessibilityElement + accessibilityLabel on VStack. 4 call sites with descriptive labels |
| `App/Views/Batch/BatchProgressOverlay.swift` | Reduce Motion environment declaration | ✓ VERIFIED | `@Environment(\.accessibilityReduceMotion) private var reduceMotion` at line 25 |
| `Packages/WatermarkCore/Sources/WatermarkCore/DesignSystem/EmptyStateView.swift` | Shared empty state component | ✓ VERIFIED | 76 lines. Glass circle + SF Symbol + Markepi typography + conditional CTA button + Reduce Transparency gate + VoiceOver grouping |
| `App/Views/ContentView.swift` | Empty state integration + Dynamic Type + Reduce Motion gates | ✓ VERIFIED | EmptyStateView conditional branch. Dynamic Type: 70% at .xxLarge. Reduce Motion: preview animation gate + batch overlay transition gate |
| `App/Views/PreviewArea/PreviewView.swift` | Picker button removed | ✓ VERIFIED | Fallback renders `Color.clear`. All preview gestures + states preserved |
| `Packages/WatermarkCore/Sources/WatermarkCore/UI/ShareExtensionRootView.swift` | Extension idle state with EmptyStateView | ✓ VERIFIED | `EmptyStateView(onChoosePhoto: nil)` when `sourceURL == nil`. "Preparing photo..." loading state preserved |
| `Packages/WatermarkCore/Sources/WatermarkCore/UI/PhotosExtensionRootView.swift` | Extension idle state with EmptyStateView | ✓ VERIFIED | `EmptyStateView(onChoosePhoto: nil)` when `sourceURL == nil`. "Preparing photo..." loading state preserved |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| SnapshotTestViewModel | WatermarkConfigurable protocol | Structural conformance + @Observable | ✓ WIRED | `let configurable: any WatermarkConfigurable = vm` compiles (proven in test) |
| ExtensionSnapshotTests | ShareExtensionRootView | UIHostingController at 430×932 | ✓ WIRED | `ShareExtensionRootView(viewModel: vm)` rendered in tests |
| ExtensionSnapshotTests | PhotosExtensionRootView | UIHostingController in UINavigationController | ✓ WIRED | `PhotosExtensionRootView(viewModel: vm)` rendered with `inNavigationController: true` |
| MarkepiPillBar Button | Reduce Motion | withAnimation(reduceMotion ? nil : .spring(...)) | ✓ WIRED | `reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8)` |
| ControlsView ControlSection | VoiceOver | .accessibilityElement(children: .contain) + .accessibilityLabel | ✓ WIRED | All 4 call sites pass descriptive labels through `label: String` parameter |
| BatchProgressOverlay | Reduce Motion | .transition(reduceMotion ? .identity : .opacity) at ContentView call site | ✓ WIRED | Gate applied in ContentView.swift line 209 |
| ContentView.mainLayout | EmptyStateView | Conditional: currentPhoto == nil → EmptyStateView | ✓ WIRED | `EmptyStateView(onChoosePhoto: { viewModel.showPicker = true })` when empty |
| ContentView.mainLayout | DynamicTypeSize | expandedHeight computation | ✓ WIRED | `dynamicTypeSize >= .xxLarge ? 0.70 : 0.55` |
| ContentView.previewArea | Reduce Motion | Animation gating on renderingState change | ✓ WIRED | `.animation(reduceMotion ? nil : .easeInOut(...), value: viewModel.renderingState)` |
| ContentView.batchOverlays | Reduce Motion | Transition gating on BatchProgressOverlay | ✓ WIRED | `.transition(reduceMotion ? .identity : .opacity)` |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|--------------|--------|--------------------|--------|
| SnapshotTestViewModel | config.watermarks | Hardcoded in `init()` | ✓ (static test data, correct by design) | ✓ FLOWING |
| ExtensionSnapshotTests | SnapshotTestViewModel instance | `SnapshotTestViewModel()` | ✓ (pre-populated config) | ✓ FLOWING |
| ContentView EmptyState | viewModel.currentPhoto | ViewModel (real data source) | ✓ (real photo state) | ✓ FLOWING |
| ContentView expandedHeight | dynamicTypeSize | `@Environment(\.dynamicTypeSize)` | ✓ (system environment) | ✓ FLOWING |
| ContentView reduceMotion | reduceMotion | `@Environment(\.accessibilityReduceMotion)` | ✓ (system environment) | ✓ FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| 5 snapshot tests pass | `xcodebuild test -scheme WatermarkCore -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WatermarkCoreTests/ExtensionSnapshotTests` | "Test run with 5 tests in 1 suite passed after 6.291 seconds." | ✓ PASS |
| All 3 targets compile | `bash scripts/build-gate.sh` | "BUILD GATE: PASSED" | ✓ PASS |
| VoiceOver labels present in pill bar | grep for `accessibilityLabel.*controls` in MarkepiPillBar | 2 matches (label + hint per segment) | ✓ PASS |
| Reduce Motion syntax gating | grep for `reduceMotion ? nil` in MarkepiPillBar, ContentView | 2 matches (pill bar animation + preview animation) | ✓ PASS |
| Reduce Motion transition gating | grep for `reduceMotion ? .identity` in ContentView | 1 match (batch overlay transition) | ✓ PASS |
| Dynamic Type threshold | grep for `dynamicTypeSize >= .xxLarge` in ContentView | 1 match (expandedHeight computation) | ✓ PASS |
| EmptyStateView in all 3 targets | grep for `EmptyStateView` in ContentView + both extension root views | 3 matches (ContentView with CTA, both extensions with nil) | ✓ PASS |
| No debt markers | grep for TBD/FIXME/XXX in all Phase 18 files | No matches | ✓ PASS |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| XTG-01 | 18-01 | Redesigned ControlsView renders correctly in Share Extension | ✓ SATISFIED | 3 share extension snapshot tests pass. ShareExtensionRootView in WatermarkCore imports and renders ControlsView |
| XTG-02 | 18-01 | Redesigned ControlsView renders correctly in Photos Edit Extension | ✓ SATISFIED | 2 photos extension snapshot tests pass (with Done toolbar in UINavigationController). PhotosExtensionRootView imports and renders ControlsView |
| UXQ-01 | 18-02, 18-03 | Dynamic Type supported up to 200% with no truncation/overlap | ✓ SATISFIED | Expanded sheet height scales to 70% at .xxLarge+. ControlsView scrolls internally. MarkepiTypography uses standard font styles (inherently Dynamic Type-aware) |
| UXQ-02 | 18-02 | VoiceOver labels preserved or improved | ✓ SATISFIED | New labels on pill bar segments + ControlSection containers. All existing sub-view labels preserved unchanged. `.isSelected` trait on active pill segment |
| UXQ-03 | 18-02, 18-03 | Reduce Motion and Reduce Transparency respected | ✓ SATISFIED | Reduce Motion gates: pill bar animation, preview animation, batch overlay transition. Reduce Transparency gate: EmptyStateView glass circle. InspectorSheetView + ShareActionButton already gated (Phase 17) |
| UXQ-04 | 18-03 | Empty state redesigned | ✓ SATISFIED | EmptyStateView shared component in WatermarkCore/DesignSystem. Integrated in ContentView + both extensions. Replaces old ultraThinMaterial pill and "Preparing photo..." idle states |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| — | — | None found | — | All Phase 18 files are clean — no TBD, FIXME, XXX, TODO, HACK, PLACEHOLDER markers. No empty return/placeholder implementations |

### Human Verification Required

The following accessibility and visual quality checks require on-device verification. All code patterns are present and wired, but these behaviors must be confirmed by a human with an actual iOS device or simulator running the app.

#### 1. VoiceOver Label Verification

**Test:** Activate VoiceOver (Settings → Accessibility → VoiceOver), navigate through the full ControlsView in the main app.
**Expected:**
- Pill bar segments announce "Watermark controls — selected, button — Shows watermark settings" (and similar for Style/Output)
- ControlSection containers announce "Text and position controls", "Export options", "Template controls"
- All existing controls (position Menu, ScaleStepperView, WhiteFrameToggleView, LogoPickerView, SignatureCaptureView, LayerListView) announce correctly as before
- Active pill segment has `.isSelected` trait announced
**Why human:** VoiceOver announcement text and navigation flow cannot be verified via code grep alone — requires actual screen reader interaction.

#### 2. Reduce Motion Behavior

**Test:** Enable Reduce Motion (Settings → Accessibility → Motion → Reduce Motion ON). Return to app and: tap pill bar segments, trigger batch processing, observe rendering state transitions.
**Expected:**
- Pill bar indicator switches instantly to new segment position (no spring sliding animation)
- Batch progress overlay appears and disappears instantly (no opacity fade)
- Preview area transitions between idle/rendering/done states instantly (no 0.2s crossfade)
**Why human:** Animation smoothness and instant-switch behavior require visual observation on device.

#### 3. Dynamic Type at 200%

**Test:** Set Dynamic Type to maximum (Settings → Accessibility → Display & Text Size → Larger Text → max slider). Return to app with a photo loaded, drag the bottom sheet to its expanded detent.
**Expected:**
- Sheet reaches ~70% of screen height (noticeably taller than the standard 55%)
- All controls in the sheet scroll internally without clipping
- No text truncation, overlap, or layout breakage at extreme type sizes
- Controls remain usable (buttons tappable, menus openable)
**Why human:** Layout behavior at extreme Dynamic Type sizes requires visual verification with actual system text rendering — code patterns cannot predict exact rendering at every size.

#### 4. Empty State Visual Appearance

**Test:** Cold launch the main app without selecting a photo (tap outside the PhotosPicker to dismiss, or launch fresh without picking).
**Expected:**
- Glass circle with `photo.on.rectangle.angled` SF Symbol centered on screen
- "Add a Photo" headline visible in `.sectionHeader` typography
- Body text "Choose a photo or video to watermark and share instantly" visible in `.controlLabel` typography (secondary color)
- "Choose Photo" primary button visible and tappable (opens PhotosPicker)
- No bottom sheet or pinned Share bar visible
- Glass circle respects Reduce Transparency (no glass effect when setting enabled)
**Why human:** Visual layout, typography rendering, glass effect, and button interactivity require on-device verification.

#### 5. Extension Idle States

**Test:** Share a photo from Photos app via Share Sheet → Watermark, and also open a photo via Photos app Edit → Watermark extension.
**Expected:**
- Share Extension idle state (very brief, if visible at all) shows EmptyStateView WITHOUT "Choose Photo" CTA button
- Photos Extension idle state (brief) shows EmptyStateView WITHOUT "Choose Photo" CTA button
- "Preparing photo..." loading state (photo icon + text) still appears when media URL is set but preview hasn't generated yet
- Extensions function normally after media loads (ControlsView rendered, watermark editing works)
**Why human:** Extension idle state behavior depends on real `NSExtensionContext` and `PHContentEditingInput` data flow — cannot be verified via code grep alone.

### Gaps Summary

No gaps found. All 19 must-have truths verified against codebase evidence:
- 5/5 snapshot tests pass via xcodebuild
- All 3 targets compile (build gate PASSED)
- VoiceOver labels present on pill bar + ControlSection containers
- Reduce Motion gating wired at all 4 animation sites
- Reduce Transparency gated on EmptyStateView glass
- Dynamic Type sheet height scaling at .xxLarge threshold
- EmptyStateView integrated in all 3 targets with correct content recipe
- Existing accessibility labels preserved
- No debt markers, stubs, or placeholders in Phase 18 files

5 human verification items remain for accessibility and visual quality confirmation — these require on-device testing that code analysis cannot provide.

---

*Verified: 2026-06-22T11:47:00Z*
*Verifier: the agent (gsd-verifier)*
