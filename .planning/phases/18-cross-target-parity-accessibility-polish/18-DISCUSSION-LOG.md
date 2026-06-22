# Phase 18: Cross-Target Parity & Accessibility Polish - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-22
**Phase:** 18-cross-target-parity-accessibility-polish
**Areas discussed:** Extension Verification Scope, Empty State Redesign, Accessibility Audit Depth

---

## Extension Verification Scope

| Option | Description | Selected |
|--------|-------------|----------|
| Build + manual visual pass | Verify both extensions compile, visual checklist for ControlsView in extensions. Same pattern as Phase 15-03 cross-target catalog verification. | |
| Automated snapshot tests | XCTest snapshot tests rendering ControlsView in extension view controller dimensions, compared against reference images. | ✓ |
| Build-only | If WatermarkCore compiles and both extensions build, ControlsView works — rely on shared package guarantee. | |

**User's choice:** Automated snapshot tests
**Notes:** User wants automated verification, not manual. This drives the plan structure — snapshot infrastructure must be built before accessibility and empty-state work can be verified in extensions.

---

| Option | Description | Selected |
|--------|-------------|----------|
| Full root view snapshots | Snapshot complete ShareExtensionRootView + PhotosExtensionRootView at standard layout size. Covers 60/40 composition, toolbar items, preview. | ✓ |
| ControlsView-in-extension only | Render ControlsView alone at 40% frame height. Skip preview and toolbar. | |
| Per-section snapshots | Snapshot each pill section separately at extension dimensions. Granular but more test cases. | |

**User's choice:** Full root view snapshots
**Notes:** User wants end-to-end verification that extension root views render correctly, not just ControlsView in isolation.

---

| Option | Description | Selected |
|--------|-------------|----------|
| XCTest in WatermarkCore with SwiftUI snapshot helper | Lightweight SwiftUI-to-UIImage renderer, pixel comparison. No third-party dependency. Runs in existing test suite. | ✓ |
| Separate XCTest target | New WatermarkCoreUITests target for visual verification. Cleaner separation but another build target. | |
| Pre-recorded reference images + pixel-diff | Generate reference snapshots, commit them, compare diffs. Git-visible regression evidence. | |

**User's choice:** XCTest in WatermarkCore with SwiftUI snapshot helper
**Notes:** User wants no third-party dependencies. Simple pixel comparison with tolerance.

---

| Option | Description | Selected |
|--------|-------------|----------|
| Lightweight SnapshotTestViewModel in WatermarkCore | Test-only ViewModel with pre-populated config. Conforms to WatermarkConfigurable & Observable. | ✓ |
| Mock the real ViewModels | Mock ShareExtensionViewModel / PhotosExtensionViewModel. Heavier — depends on NSExtensionContext, CGImageSource, PHContentEditingInput. | |
| No mock — snapshot static previews | Xcode Previews with static WatermarkConfigurable mock. Doesn't test runtime but validates layout. | |

**User's choice:** Lightweight SnapshotTestViewModel in WatermarkCore
**Notes:** Avoids the complexity of mocking real ViewModels which depend on extension context types.

---

| Option | Description | Selected |
|--------|-------------|----------|
| Single iPhone size (Pro Max 430pt × 932pt) | One reference size per state. Layout is size-class driven, not pixel-dependent. | ✓ |
| Two sizes (compact + regular) | 430pt + 320pt for smaller phones. Catches Dynamic Type overflow on narrow devices but doubles test maintenance. | |
| View-in-isolation at intrinsic size | Let SwiftUI view determine its size. No fixed frame. Simpler but may miss clipping at real extension dimensions. | |

**User's choice:** Single iPhone Pro Max size
**Notes:** Sufficient for verifying ControlsView fits the extension's constrained 40% height. Additional sizes not needed.

---

| Option | Description | Selected |
|--------|-------------|----------|
| Key states: idle + rendered + multi-item | 3 Share Extension states + 2 Photos Extension states = 5 snapshots. Covers the states most likely to have layout issues. | ✓ |
| Every state | 10 snapshots. Higher maintenance burden. Error states rarely have layout surprises. | |
| Rendered state only | 2 snapshots. Minimum to verify ControlsView fits. | |

**User's choice:** Key states (idle + rendered + multi-item)
**Notes:** 5 snapshots total covers the important layout scenarios without excessive maintenance.

---

## Empty State Redesign

| Option | Description | Selected |
|--------|-------------|----------|
| Hero illustration + CTA button | Centered vertical stack: app icon/SF Symbol (glass circle), headline, body text, Markepi primary button. Matches modern iOS empty states. | ✓ |
| Just restyle existing button | Swap ultraThinMaterial → markepiGlass + MarkepiButtonStyle. Keep same "Add Photos" pill. | |
| Full-bleed sheet content | Show ControlsView sheet expanded with placeholder text in each pill section. Controls always visible, just empty. | |

**User's choice:** Hero illustration + CTA button
**Notes:** User wants a proper, designed empty state that matches the new visual system — not just a restyle of the old button.

---

| Option | Description | Selected |
|--------|-------------|----------|
| Shared EmptyStateView in WatermarkCore/DesignSystem | Standalone component consumed by all 3 targets. One component, consistent look. | ✓ |
| Inline in ContentView + extension root views | Each target handles its own empty state layout. 3 copies to maintain. | |
| Only in main app | Extensions don't have meaningful empty states — they're loading states. | |

**User's choice:** Shared EmptyStateView in WatermarkCore/DesignSystem
**Notes:** Mirrors the ShareActionButton extraction pattern from Phase 17. Design system component, shared by all targets.

---

| Option | Description | Selected |
|--------|-------------|----------|
| Hide sheet + pinned bar, only empty state | EmptyStateView replaces the full ZStack inspector layout. Clean, focused. Sheet/bar reappear when media loads. | ✓ |
| Keep sheet collapsed at peek, bar hidden | Sheet stays in peek, EmptyStateView fills preview area. No layout jumps. | |
| Keep everything visible | Empty state in preview area only. Sheet + bar stay, Share button disabled. More chrome visible. | |

**User's choice:** Hide sheet + pinned bar, show only empty state
**Notes:** When there's no media, there's nothing to configure or share. The inspector chrome is meaningless and should be hidden.

---

| Option | Description | Selected |
|--------|-------------|----------|
| SF Symbol + Headline + Body + CTA | Photo icon in glass circle, "Add a Photo" headline, body text, Markepi primary "Choose Photo" button. | ✓ |
| Icon + headline + button only | Skip body text. More minimal. | |
| App icon branding + CTA | Show Markepi app icon. Requires custom asset. | |

**User's choice:** SF Symbol + Headline + Body + CTA
**Notes:** Clean, informative, consistent with Apple's own empty state patterns (Photos, Files, Notes apps).

---

## Accessibility Audit Depth

| Option | Description | Selected |
|--------|-------------|----------|
| Audit + fix gaps + verify at scale | Find missing VoiceOver labels, add them, verify Dynamic Type at 200%, gate all animations on reduceMotion. | ✓ |
| Verify existing labels only | Regression check — confirm Phase 16 didn't break existing labels. No new labels for redesigned elements. | |
| Full WCAG-level audit | Comprehensive audit with contrast ratios, touch targets (44pt), VoiceOver rotor groups, custom actions. More than phase scope. | |

**User's choice:** Audit + fix gaps + verify at scale
**Notes:** User wants proactive accessibility — not just a regression check. This means labels for new elements AND Dynamic Type verification AND animation gating.

---

| Option | Description | Selected |
|--------|-------------|----------|
| Dynamic expanded height | Expanded detent scales to higher fraction (70%) or .large() when DynamicTypeSize >= .xxLarge. Peek stays fixed. | ✓ |
| Keep fixed heights, rely on scroll | 55% stays at all type sizes. ControlsView scrolls internally. | |
| Use .presentationDetents with dynamic sizing | Migrate InspectorSheetView to native sheet API. Handles Dynamic Type automatically. Requires refactoring. | |

**User's choice:** Dynamic expanded height
**Notes:** The 55% fixed fraction is too tight at 200% type. Peek height is intrinsic (pill bar self-sizes) so it handles Dynamic Type natively.

---

| Option | Description | Selected |
|--------|-------------|----------|
| Pill bar sections + glass control containers | VoiceOver labels for MarkepiPillBar segments and ControlSection glass containers. ~6-8 new labels. | ✓ |
| Only pill bar segments | Just label the 3 pill bar segments. Minimal additions. | |
| Every interactive element | Pill bar + containers + Menu indicators + slider value + template hints + logo/signature thumbnails. ~15+ labels. | |

**User's choice:** Pill bar sections + glass control containers
**Notes:** Menu controls (position, format) already work via system Menu accessibility. Focus on the new elements that don't have automatic labels.

---

| Option | Description | Selected |
|--------|-------------|----------|
| Gate pill bar indicator + audit everything | Add reduceMotion to MarkepiPillBar (disable indicator animation). Audit batch overlays + preview animation. Gate all. | ✓ |
| Gate pill bar indicator only | Just the MarkepiPillBar. Other animations are simple opacity and don't need gating. | |
| Leave as-is | Verify first, fix only if SwiftUI doesn't auto-respect system setting. | |

**User's choice:** Gate pill bar indicator + audit everything
**Notes:** Proactive gating. InspectorSheetView spring already gated (Phase 17). Pill bar indicator + batch overlay opacity + preview rendering animation all need checking.

---

## the agent's Discretion

- Snapshot comparison tolerance level
- Specific DynamicTypeSize threshold for sheet height scaling
- EmptyStateView layout metrics (spacing, padding, glass circle size)
- Snapshot reference image storage strategy
- Whether snapshot helper uses UIHostingController (for toolbar rendering) or direct SwiftUI views

## Deferred Ideas

None — discussion stayed within phase scope.
