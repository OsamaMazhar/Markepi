# Phase 18: Cross-Target Parity & Accessibility Polish - Context

**Gathered:** 2026-06-22
**Status:** Ready for planning

<domain>
## Phase Boundary

Verify the redesigned shared `ControlsView` renders and functions in both extensions (Share and Photos Edit), implement accessibility polish (Dynamic Type to 200%, VoiceOver labels for redesigned elements, Reduce Motion gating, Reduce Transparency verification), and redesign the empty state to match the Markepi design system.

**This phase delivers verification, not new features.** The redesigned ControlsView already propagates to extensions via the WatermarkCore Swift package. Phase 18 proves it works. Accessibility work adds labels and gates to elements that shipped in Phases 15-17. The empty state is the only net-new visual component.

**Requirements:** XTG-01, XTG-02, UXQ-01, UXQ-02, UXQ-03, UXQ-04
</domain>

<decisions>
## Implementation Decisions

### Extension Verification (XTG-01, XTG-02)
- **D-01:** Automated snapshot tests — NOT build-only or manual checklist. XCTest snapshot tests in the WatermarkCore test target verify both extension root views render correctly at the extension's layout dimensions.
- **D-02:** Full root view snapshots — capture the complete `ShareExtensionRootView` and `PhotosExtensionRootView` at the extension's 60/40 layout. Pill bar fitting in 40%, all controls rendered, toolbar items, preview area. NOT ControlsView-only or per-section.
- **D-03:** XCTest in WatermarkCore with a lightweight SwiftUI-to-UIImage snapshot renderer. No third-party dependency. Image data comparison within tolerance. Tests run as part of the existing `xcodebuild test` suite.
- **D-04:** Lightweight `SnapshotTestViewModel` in WatermarkCore test target — conforms to `WatermarkConfigurable & Observable` with pre-populated config (text watermark, logo, frame, 2 layers). Test-only, not shipped. Avoids mocking real ViewModels (ShareExtensionViewModel / PhotosExtensionViewModel) which depend on NSExtensionContext, CGImageSource, PHContentEditingInput.
- **D-05:** Single device size: 430pt × 932pt (iPhone 16 Pro Max). One reference size per state — layout is size-class driven, not pixel-dependent.
- **D-06:** 3 key states per extension, 5 snapshots total:
  - Share Extension: idle (empty state) + preview rendered (controls visible) + multi-item progress bar
  - Photos Extension: idle (empty state) + preview rendered

### Empty State Redesign (UXQ-04)
- **D-07:** Hero illustration + CTA button design. Centered vertical stack with app iconography, headline, body text, and a primary action button. Replaces the current ultraThinMaterial "Add Photos" pill and extension "Preparing photo..." idle state.
- **D-08:** Shared `EmptyStateView` component in `WatermarkCore/Sources/WatermarkCore/DesignSystem/` — consumed by main app and both extensions. One component, 3 targets, consistent look.
- **D-09:** When empty state is showing (`currentPhoto == nil` and not loading), the bottom sheet and pinned Share bar are hidden. Only the `EmptyStateView` is displayed. Sheet and bar reappear automatically when media loads.
- **D-10:** Empty state content recipe:
  - Large SF Symbol (`photo.on.rectangle.angled`, 40pt) in a circular glass-backed container
  - Headline: "Add a Photo" — MarkepiTypography `.sectionHeader`
  - Body: "Choose a photo or video to watermark and share instantly" — `.controlLabel`, secondary color
  - CTA: Markepi primary button "Choose Photo" — triggers `viewModel.showPicker = true`

### Accessibility (UXQ-01, UXQ-02, UXQ-03)
- **D-11:** Audit + fix gaps + verify at scale. Not just verify existing labels still work. Proactive: find missing labels on Phase 15-17 elements, add them, verify Dynamic Type at 200%, gate animations on Reduce Motion, verify Reduce Transparency at every glass usage site.
- **D-12:** Dynamic expanded sheet height when `DynamicTypeSize >= .xxLarge`. The expanded detent scales to a higher fraction (e.g., 70%) or uses `.large()` to give large type more room. Peek height stays fixed — the pill bar self-sizes via its intrinsic content. Sheet remains overlay (no push/resize of preview per Phase 17 D-02). ControlsView scrolls internally so overflow is handled.
- **D-13:** VoiceOver labels added to:
  - MarkepiPillBar segments: "Watermark controls", "Style controls", "Output controls"
  - ControlSection glass containers: identified by their content group (e.g., "Text and position controls", "Logo and signature controls", "Export options")
  - Menu-based controls (position, format) already work via system Menu accessibility — no new labels needed there
- **D-14:** Reduce Motion gating:
  - MarkepiPillBar matched-geometry sliding indicator: disabled when `reduceMotion` is true (section switches without animation)
  - Batch overlay transitions (opacity): audited and gated
  - Preview rendering state animation (ContentView line 163): audited and gated
  - InspectorSheetView spring already gated (Phase 17 line 127) — verify, no change needed

### the agent's Discretion
- Snapshot comparison tolerance — planner chooses a reasonable pixel-difference threshold that handles minor system font/rendering drift across OS versions.
- The specific `DynamicTypeSize` threshold for scaling the sheet expanded height — planner determines from testing.
- Exact layout metrics for EmptyStateView (spacing, padding, glass circle size) — follow Markepi design system conventions.
- Snapshot reference image storage — planner decides whether to commit them to the repo or generate on first test run.
- Whether the snapshot helper renders root views inside a UIHostingController (required for toolbar items) or directly as SwiftUI views — planner determines based on what produces accurate extension-context rendering.
</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project-Level
- `.planning/PROJECT.md` — Core value, constraints, v2.1 milestone context (presentation-only), key decisions
- `.planning/REQUIREMENTS.md` — XTG-01, XTG-02, UXQ-01 through UXQ-04 (what Phase 18 must deliver); traceability table; v2.1 scope note
- `.planning/ROADMAP.md` § Phase 18 — Goal, success criteria, depends on Phase 17, plans TBD
- `.planning/STATE.md` — v2.1 phase map, risk re: shared ControlsView + extension layout

### Upstream Phases (deliverables consumed here)
- `.planning/phases/15-visual-design-system-shared-primitives/15-CONTEXT.md` — Design system decisions: Liquid Glass (D-01 through D-03), pill bar (D-04 through D-08), button vocabulary (D-09 through D-12), typography (D-13 through D-15), scroll-edge (D-16 through D-19), Reduce Transparency gating (D-03), Dynamic Type uncapped (D-15)
- `.planning/phases/16-redesigned-controls/16-CONTEXT.md` — ControlsView redesign: pill bar sections (D-04/D-05), position Menu (D-01/D-02), button roles (D-09/D-10), shell-agnostic mandate, scroll-edge (D-12)
- `.planning/phases/17-inspector-bottom-sheet-shell/17-CONTEXT.md` — Inspector shell: detent strategy (D-01 through D-04), Share button extraction (D-05 through D-08), sheet chrome (D-09 through D-13), ControlsView-in-sheet (D-14 through D-17), extensions keep 60/40

### Design System Primitives (to consume or modify)
- `Packages/WatermarkCore/Sources/WatermarkCore/DesignSystem/MarkepiPillBar.swift` — Pill bar with `ControlsSection` enum; needs reduceMotion gating + VoiceOver labels
- `Packages/WatermarkCore/Sources/WatermarkCore/DesignSystem/GlassEffect/MarkepiGlassModifier.swift` — `.markepiGlass()` with `isEnabled: !reduceTransparency`
- `Packages/WatermarkCore/Sources/WatermarkCore/DesignSystem/Typography/MarkepiTypography.swift` — Semantic typography (uses standard font styles = Dynamic Type by default)
- `Packages/WatermarkCore/Sources/WatermarkCore/DesignSystem/ButtonStyles/MarkepiButtonStyle.swift` — `.markepiPrimary()` for empty state CTA
- `Packages/WatermarkCore/Sources/WatermarkCore/DesignSystem/ShareActionButton.swift` — Extracted Share button (consumed in ControlsView Output section)
- `Packages/WatermarkCore/Sources/WatermarkCore/DesignSystem/MarkepiUtilities.swift` — `.modify {}` conditional helper

### Source Files (being modified or referenced)
- `Packages/WatermarkCore/Sources/WatermarkCore/UI/ControlsView.swift` — Redesigned ControlsView (267 lines); voiceOver labels go on pill bar + ControlSection containers; reduceMotion environment already declared (line 14)
- `Packages/WatermarkCore/Sources/WatermarkCore/UI/InspectorSheetView.swift` — Inspector sheet (177 lines); spring animation already gated on reduceMotion (line 127); expanded height needs Dynamic Type scaling (D-12)
- `Packages/WatermarkCore/Sources/WatermarkCore/UI/WatermarkConfigurable.swift` — Protocol surface (frozen — do not modify); SnapshotTestViewModel conforms to this
- `App/Views/ContentView.swift` — Main app shell (384 lines); empty state replaces previewArea when no media (D-09); preview rendering state animation needs reduceMotion gate (line 163)
- `App/Views/PreviewArea/PreviewView.swift` — Current empty state `pickerButton` (line 128-142) — replaced by EmptyStateView at ContentView level
- `ShareExtension/ShareExtensionRootView.swift` — Share extension root (222 lines); consumes ControlsView (line 146); snapshot target; idle state shows "Preparing photo..."
- `PhotoEditExtension/PhotosExtensionRootView.swift` — Photos extension root (161 lines); consumes ControlsView (line 134); snapshot target; idle state shows "Preparing photo..."

### Test Target
- `Packages/WatermarkCore/Tests/WatermarkCoreTests/` — Existing test target; SnapshotsTestViewModel + extension snapshot tests added here
</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **MarkepiGlassModifier** — Already built with `isEnabled: !reduceTransparency`. Reuse for EmptyStateView glass circle. Verify every usage site has the gate.
- **MarkepiTypography** — `.sectionHeader`, `.controlLabel`, `.value`, `.metadata` semantic styles. Already Dynamic Type-aware (standard font styles). Use for EmptyStateView text hierarchy.
- **MarkepiButtonStyle** — `.markepiPrimary()` for "Choose Photo" CTA in EmptyStateView. Already Reduce Transparency-aware.
- **ShareActionButton** — Extracted component. No changes needed. Already consumed by ControlsView Output section.
- **WatermarkConfigurable protocol** — Frozen. SnapshotTestViewModel conforms to this for test-only usage.
- **RenderingState enum** — Already defined. Used by SnapshotTestViewModel to simulate idle/rendered states.
- **ControlsView existing VoiceOver labels** — Position Menu (line 92-93), ScaleStepperView (line 38-39), WhiteFrameToggleView (line 33-34), LogoPickerView (line 104-105), SignatureCaptureView (line 84-85), LayerListView (line 77-78). All preserved from Phase 16 redesign.

### Established Patterns
- **Generic over `WatermarkConfigurable & Observable`** — SnapshotTestViewModel follows this. All snapshot views are generic.
- **`@Environment(\.accessibilityReduceTransparency)`** — Already declared in 11+ files. Consistent pattern: pass `!reduceTransparency` as `isEnabled` to glass modifier. Audit new elements follow this.
- **`@Environment(\.accessibilityReduceMotion)`** — Declared in InspectorSheetView (line 63), ControlsView (line 14), PreviewView (line 5), ShareActionButton (line 26). Pattern: `reduceMotion ? nil : .spring(...)`.
- **Shared code in WatermarkCore** — EmptyStateView and snapshot tests both live in the package. Extensions consume EmptyStateView via import.
- **`if #available(iOS 26, *)`** — Pattern from Phase 15 for glass fallback. Already applied in MarkepiGlassModifier. No new platform gates needed in Phase 18.

### Integration Points
- **ContentView.swift:83-97** — The ZStack inspector shell. When `viewModel.currentPhoto == nil`, the entire ZStack is replaced by `EmptyStateView`. The `onAppear` (line 56-60) already triggers `showPicker = true` when empty, so the empty state is visible briefly on cold launch.
- **ContentView.swift:163** — Preview rendering state animation `.animation(.easeInOut(duration: 0.2), value: ...)`. Needs reduceMotion gate.
- **ShareExtensionRootView.swift:129-139** — Extension idle state (photo icon + "Preparing photo..."). This is where EmptyStateView is rendered in the extension.
- **PhotosExtensionRootView.swift:115-125** — Same pattern. EmptyStateView replaces the current VStack.
- **InspectorSheetView.swift:129** — `reduceMotion ? nil : .spring(...)` — already done. Verify, no change needed.
- **MarkepiPillBar.swift** — Matched-geometry sliding indicator. Needs `@Environment(\.accessibilityReduceMotion)` and conditional animation disable.
</code_context>

<specifics>
## Specific Ideas

- **Snapshot tests are user's explicit choice** — not build-only, not manual. User wants automated verification of extension rendering. This drives the plan structure: snapshot infrastructure must be built before the accessibility and empty-state work can be verified in extensions.
- **EmptyStateView must be a shared design system component** — user wants consistency across all 3 targets. Not inline in ContentView, not per-target copies. This mirrors the ShareActionButton extraction pattern from Phase 17.
- **Dynamic Type at 200% is a firm requirement** — the expanded sheet height must adapt. User explicitly chose dynamic height scaling over "keep fixed, rely on scroll."
- **Accessibility is additive, not just preservative** — user chose audit + fix gaps + verify at scale. This means VoiceOver labels for new elements (pill bar, glass containers) AND Dynamic Type verification at 200% AND Reduce Motion gating for all animations. More work than a simple regression check.
</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.
</deferred>

---

*Phase: 18-Cross-Target Parity & Accessibility Polish*
*Context gathered: 2026-06-22*
