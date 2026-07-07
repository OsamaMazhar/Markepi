# Plan: Day/Night Theme + iPad Two-Column Layout + Adaptive Sizing + Welcome

**Last updated:** 2026-06-27
**Branch base:** `fix/watermark-preview-scale-whiteframe-tests`
**Min deployment target:** iOS 18.0 (universal: iPhone `TARGETED_DEVICE_FAMILY = 1`, iPad `= 2`; the app target is `"1,2"`)
**Bundle IDs:** app `com.osamamazhar.markepi`, share extension `com.osamamazhar.markepi.share`

> This is a **build guide for a junior engineer**. Read Sections 2–4 before writing any code. Work the phases in order — each one ships on its own with a green build gate.

---

## 1. Scope

1. **Day/Night theme** — three modes (System / Light / Dark), selectable in Settings, persisted, applied at launch. Replaces the current hard-coded `.preferredColorScheme(.dark)` lock.
2. **iPad two-column editor** (the headline feature) — on wide layouts, photos/canvas on the **left**, edit menus on a **right-edge rail**, like Apple Photos. Falls back to the current bottom-dock layout on narrow widths.
3. **Landscape-optimized secondary screens** — Settings & Paywall present as centered, readable-width form sheets on iPad (never stretched). All screens must look correct in landscape.
4. **First-launch Welcome / onboarding** — new, multi-page paged flow (Welcome → Features → Get Started), shown once, UserDefaults-gated. Does not exist today.
5. **Dynamic sizing for smaller displays** — spacing/radius/sizing tokens, finish adopting `MarkepiTypography`, remove hard-coded numeric sizes, ≥44 pt touch targets.

### Non-Goals (v1)
- Per-template / user-defined accent colors.
- Theme preference synced into the Share Extension (extension keeps System appearance + shared color tokens).
- Mac Catalyst-specific affordances beyond what the wide layout already gives.
- A from-scratch asset-catalog migration of every icon.

---

## 2. How to use this plan

- **Build order matters.** Phases 1 → 7 are sequenced so each is independently shippable. Don't jump ahead — Phase 5 (iPad layout) depends on tokens from Phase 2/3.
- **After every phase:** run `bash scripts/build-gate.sh`. If you added/changed a requirement ID, also run `bash scripts/test-sync-requirements.sh`.
- **Line numbers drift.** Citations like `ContentView.swift:117` were accurate on 2026-06-27 but WILL move as you edit. Anchor your searches to **symbol names** (`PreviewView`, `bottomControls`, `SettingsView`), not line numbers.
- **When in doubt, match the surrounding code.** Naming, indentation, comment density — mirror what's already there.
- **Gotchas are called out with ⚠️.** Read every one; they are real bugs this project has hit before.

---

## 3. Current state (corrected audit)

> Verified against the codebase on 2026-06-27. Earlier drafts had a few inaccuracies — this table is the source of truth.

| Area | Status | Evidence |
|---|---|---|
| Asset catalog | **None exists.** No `*.xcassets`, no `*.colorset` anywhere (app or package). `AppIcon` is produced by the build scripts. | `find . -name "*.xcassets"` → empty |
| Appearance | **Hard-locked to dark.** | `App/WatermarkApp.swift:47` — `.preferredColorScheme(.dark)` (rationale comment `:42–46`) |
| Inline theme colors | Widespread. | `Color.black` canvas (`ContentView.swift:145`), `.white` foreground (`ContentView.swift` ~`:696`; `PreviewView.swift:57`; `ThumbnailStripView.swift:140,172`), `.tint(.blue/.red)` literals |
| Semantic UIKit colors | Used; never light-tested because of the dark lock | `Color(.systemGroupedBackground)`, `Color(.systemGray5/6)`, `Color(.secondarySystemGroupedBackground)` — these **do** auto-flip; they're fine once the lock is removed |
| Typography scale | **Exists AND is already partly adopted** (earlier draft said "unused" — that was wrong) | `MarkepiTypography.swift` (cases: `.sectionHeader`, `.controlLabel`, `.value`, `.metadata`, `.pillLabel`). Already called in `ToolPanelView.swift` and `BatchItemDetailSheet.swift` |
| Hard-coded fonts | 8 sites in App + 1 in package | e.g. `ContentView.swift:695` (24), `EditorToolDock.swift:40,43` (17/10), `ToolPanelView.swift:204` (32), `ThumbnailStripView.swift:139,167` (9/12), `EmptyStateView.swift:102` (46) |
| Spacing / radius / sizing tokens | **None.** | ~28 `cornerRadius` literals, 100+ `padding/spacing` literals, ~22 fixed `.frame` |
| Size-class / idiom awareness | **Essentially zero** (one stray detent) | No `horizontalSizeClass`, `verticalSizeClass`, `UIDevice.idiom`, `LazyVGrid`, `NavigationSplitView`, `readableContentWidth`. `.presentationDetents([.large])` exists once at `BatchItemDetailSheet.swift:92` (no-op on iPad) |
| Adaptive layout mechanism | Ad-hoc `GeometryReader` + height fractions + `dynamicTypeSize` | `ContentView.swift:41` (GeometryReader), `:292–350` (`bottomControls`), `PaywallView.swift:30` (`geo.size.height < 680` heuristic) |
| Root architecture | `WindowGroup → NavigationStack → ContentView`. **Single view, no `TabView`, no push nav.** All secondary screens are modal `.sheet`s, each with its own nested `NavigationStack`. | `WatermarkApp.swift:39–70`, `ContentView.swift:40` |
| Settings / Paywall entry | Toolbar buttons → `.sheet` | Gear `ContentView.swift:232–237` → `$showSettings`; Crown `:221–228` → `$showPaywall` |
| Onboarding / first-launch | **None.** Launches straight to `EmptyStateView`. | No `onboarding`/`welcome`/`firstLaunch`/`hasCompleted*` anywhere |
| Editor chrome anchoring | **Bottom-anchored** via `.safeAreaInset(edge: .bottom) { bottomControls }` | `ContentView.swift:119–120` |
| Orientations | iPad: all 4. iPhone: Portrait + LandscapeLeft + LandscapeRight. No programmatic lock; `UIRequiresFullScreen` is **not** set → app already supports iPad multitasking/resize. | `project.pbxproj` `INFOPLIST_KEY_UISupportedInterfaceOrientations_*` |
| Design-system home | `Packages/WatermarkCore/Sources/WatermarkCore/DesignSystem/` has `Typography/`, `ButtonStyles/`, `GlassEffect/`, `ScrollEdge/`, `EmptyStateView.swift`. **No `Theme/`, `Spacing/`, `Radius/`, `Sizing/` yet.** | Shared with the Share Extension automatically (SPM package) |

**Refactor-surface estimate:** Theme = Medium. iPad two-column = **Large**. Welcome = Medium. Small-display sizing = Medium.

---

## 4. Concepts primer (read this if any of this is new)

### 4.1 Size class — coarse by design
`@Environment(\.horizontalSizeClass)` reports `.compact` or `.regular`. It is **deliberately coarse** — it tells you "is this a phone-ish or iPad-ish amount of room," not the pixel width. The iPad truth table:

| iPad state | Approx width | `horizontalSizeClass` |
|---|---|---|
| Full screen (portrait **or** landscape) | ~1024 pt | `.regular` |
| 70% Split View | ~700 pt | `.regular` |
| **50% Split View** | **~600 pt** | **`.regular`** ← same class as full screen |
| 33% Split View / Slide Over | ~320–430 pt | `.compact` |

⚠️ **The trap:** if you branch your layout on `horizontalSizeClass == .regular` alone, full-screen iPad (1024 pt) and 50%-split iPad (600 pt) look identical to your code. A fixed 420 pt right-rail is great at 1024 pt and **breaks** at 600 pt (canvas crushed to ~150 pt). That's why we combine size class **and** a real width read (4.2).

Also note: **large iPhones (Plus / Max) report `.regular` width in landscape.** That's fine — they genuinely have room, and "respond to available space, not device identity" is the goal.

### 4.2 `onGeometryChange` — the modern geometry read (prefer over `GeometryReader`)
`GeometryReader` is **greedy** — it expands to fill all available space and disturbs sibling layout. iOS 18 gives us `onGeometryChange`, which reads the same size information as a side effect **without** changing layout. Since our deployment target is iOS 18, use it for any new geometry-driven decision:

```swift
@State private var isWide = false
// ...
content
  .onGeometryChange(for: CGFloat.self) { proxy in
    proxy.size.width
  } action: { width in
    isWide = width >= 700
  }
```

### 4.3 Adaptive colors without an asset catalog — `UIColor` dynamic provider
Normally you'd use an asset catalog with light/dark colorsets. **This project has no asset catalog**, and introducing the first one into the shared SPM package means a `bundle: .module` footgun (colors silently render transparent if forgotten). Instead we use `UIColor`'s dynamic provider — pure Swift, lives in the shared package, **auto-adapts to the resolved `userInterfaceStyle`** (which `.preferredColorScheme` drives), and needs zero resource steps:

```swift
public static let panelBackground = Color(uiColor: UIColor { traits in
    traits.userInterfaceStyle == .dark
        ? UIColor(white: 0.10, alpha: 1)   // dark mode
        : UIColor.systemGroupedBackground  // light mode
})
```

### 4.4 `.readableContentWidth` — don't reinvent it
SwiftUI ships `.frame(maxWidth: .readableContentWidth)` (iOS 13+). It caps content to a comfortable reading width and centers it. Use this for Settings/Paywall/Welcome — do **not** invent a custom `markepiReadableWidth` constant.

### 4.5 `.presentationDetents` on iPad
⚠️ **`.presentationDetents` are ignored on iPad.** iPad sheets are already centered "form sheets" that do not stretch edge-to-edge (edge-to-edge stretching is an iPhone-landscape behavior). So on iPad: rely on the default form-sheet sizing + `.readableContentWidth` inside the content. Don't lean on detents to control iPad sheet width — they won't.

---

## 5. Architecture decisions

### D1 — Appearance preference (enum + root consumption)
- `public enum AppearancePreference: String, CaseIterable, Identifiable { case system, light, dark }` with a `colorScheme: ColorScheme?` computed property (`system → nil`, `light → .light`, `dark → .dark`).
- Stored via `@AppStorage("appearancePreference")` at the app root (first `@AppStorage` usage in the project — that's fine here; it's UI-level, not a watermark setting).
- Consumed at `WatermarkApp.swift:47`: replace `.preferredColorScheme(.dark)` with `.preferredColorScheme(appearance.colorScheme)`.

### D2 — Color tokens via `UIColor` dynamic providers (no asset catalog, v1)
- New `DesignSystem/Theme/MarkepiColors.swift` in the shared package. Static `Color` constants using `Color(uiColor: UIColor { traits in ... })`.
- **Two distinct categories — do not mix them up:**
  - **Media-canvas colors (do NOT flip):** the photo/video backdrop stays black in both schemes. `canvasBackground = Color.black`. Text/overlays sitting **on the canvas** (`.white` on the photo) **stay white** in both schemes — see D6.
  - **Chrome colors (flip):** `panelBackground`, `chromeBackground`, `controlStroke`, `pillBackground`, `pillStroke`, status colors. These adapt via the dynamic provider.
- ⚠️ **Scope boundary:** `MarkepiColors` is for **UI chrome only.** Do NOT route the watermark **render** path through it — `VideoLayerBuilder` and the text/frame/signature compositing must keep using their own colors (this project has hit the "achromatic CIImage → gray colorspace" bug on white frames/text; keeping render colors separate avoids re-triggering it).
- Future option: migrate to a package asset catalog (`Color("PanelBackground", bundle: .module)`) when Share-Extension theming is in scope.

### D3 — Spacing / Radius / Sizing tokens
New files in `DesignSystem/`:
- `Spacing/MarkepiSpacing.swift` — `enum MarkepiSpacing { static let xs=4, sm=8, md=12, lg=16, xl=20, xxl=24, xxxl=32 }` (the recurring values already in the codebase).
- `Radius/MarkepiRadius.swift` — `enum MarkepiRadius { static let sm=6, md=10, lg=12, xl=16, xxl=20, pill=999 }`.
- `Sizing/MarkepiSizing.swift` — semantic size tokens (`thumbnailCell`, `controlIcon`, `grabber`, `loadingGlyph`, `minTouchTarget = 44`) + a `MarkepiMetrics` helper for geometry-relative values (e.g. `thumbnailStripHeight(width:)`).

### D4 — iPad two-column editor (see Section 6 for full detail)
Wide layout = `horizontalSizeClass == .regular` **AND** measured width ≥ 700 pt (via `onGeometryChange`). Left column = canvas + media controls; right column = edit-menu rail. Narrow layout = unchanged bottom dock.

### D5 — Typography adoption (finish the job)
- Replace remaining hard-coded `.font(.system(size:))` (8 sites) and unstyled semantic `.font(...)` with `.markepiTypography(...)`. Add cases (`largeTitle`, `glyph`) to `MarkepiTypography` only if no existing case fits.
- Keep Dynamic Type uncapped.

### D6 — `.white` migration has TWO buckets (correctness-critical)
Phase 2 must split every `.white` literal by where it lives:
- **`.white` on the dark media canvas** (overlay text/badges on the photo) → **stays `.white`** (canvas is always dark; flipping would make it illegible in Light mode). You may alias these to a documented `MarkepiColors.canvasOverlayText = .white` for clarity, but the value does not flip.
- **`.white` on chrome** (a toolbar, a panel) → becomes a flipping token or `.primary`.

### D7 — Welcome / onboarding + secondary-screen landscape optimization
- **Welcome:** new multi-page `TabView` (`.page` style), 3 pages, shown once via `@AppStorage("hasCompletedOnboarding")`. Landscape-optimized: readable width, centered, looks intentional wide (see Section 7).
- **Settings & Paywall:** landscape-optimized single column — `.readableContentWidth`, centered form sheet, no stretching (see Section 8).

---

## 6. The iPad two-column editor (centerpiece)

### 6.1 Target layouts

**Narrow (iPhone; iPad Slide Over / 33% / 50% Split View):** unchanged.
```
┌─────────────────────────────┐
│        media canvas         │
│                             │
│                             │
├─────────────────────────────┤
│  thumbnail strip (if many)  │
│  video scrubber (if video)  │
│  ── active tool panel ──    │
│  ▢ ▢ ▢  tool dock  ▢ ▢ ▢    │  ← bottom-anchored (current)
└─────────────────────────────┘
```

**Wide (iPad full screen / large-iPhone landscape / ≥700 pt):** Apple-Photos-style.
```
┌──────────────────────┬──────────────────┐
│                      │ Watermark│Style│…│  ← EditorToolDock (top tabs)
│                      ├──────────────────┤
│                      │                  │
│    media canvas      │  active tool     │
│                      │  controls        │
│                      │  (ToolPanelView) │
│                      │                  │
├──────────────────────┤                  │
│ thumbnail strip      │                  │
│ video scrubber       │                  │
└──────────────────────┴──────────────────┘
        ← canvas column →   ← edit rail →
                          (maxWidth ~ 380–420)
```

### 6.2 Refactor: split `bottomControls` into two reusable groups
Today `bottomControls` (`ContentView.swift:292–350`) is one `VStack` mixing media navigation with edit controls. Split it:

| Piece | Contents | Narrow placement | Wide placement |
|---|---|---|---|
| `mediaControls` | `ThumbnailStripView`, `VideoScrubBar` | bottom, above dock | **under the canvas** (left column) |
| `editorControls` | `EditorToolDock`, `ToolPanelView` | bottom (current) | **right rail** |
| `RenderProgressBanner` | transient | overlay | overlay (unchanged) |

`EditorToolDock` itself can **stay a horizontal tab bar** — it just moves from the bottom to the **top of the right rail**. Minimal change to `EditorToolDock` internally.

### 6.3 Width detection (combine size class + real width)
```swift
@Environment(\.horizontalSizeClass) private var hSizeClass
@State private var availableWidth: CGFloat = 0

private var isWideLayout: Bool {
    hSizeClass == .regular && availableWidth >= 700
}

// in body:
mainLayout(geometry)
    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = $0 }
```
Why both signals? Size class alone can't tell 1024 pt from 600 pt (both `.regular`); width alone would fire on devices we don't intend. Together they mean "genuinely wide iPad-ish room."

### 6.4 Sketch of the branched body
```swift
Group {
    if isWideLayout {
        HStack(spacing: 0) {
            canvasColumn(geometry)          // PreviewView + mediaControls
                .frame(maxWidth: .infinity)
            editorRail                       // EditorToolDock (top) + ToolPanelView
                .frame(width: 400)
                .frame(maxHeight: .infinity)
                .background(MarkepiColors.panelBackground)
        }
    } else {
        PreviewView(...)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 0) { mediaControls; editorControls }
            }
    }
}
```

### 6.5 ⚠️ iPad gotchas
- **50% Split View must collapse to the narrow layout.** With the `availableWidth >= 700` guard it will (600 pt < 700). Verify this in Simulator with Split View.
- **Don't save layout state based on width.** If the user resizes (iOS 26 free-form windows), the layout must revert cleanly when width returns. Drive everything from the live `availableWidth`, never persist `isWideLayout`.
- **Navigation toolbar:** the root `NavigationStack` toolbar (`ContentView.swift:208–268`) stays at the top spanning both columns. Make sure toolbar buttons aren't duplicated or hidden in wide mode.
- **Stage Manager / external display:** same width rules apply automatically — no extra work, but test.

---

## 7. Welcome / onboarding (new)

### 7.1 Files
- New: `App/Views/Onboarding/OnboardingView.swift` (+ small `OnboardingPageView` per-page component, or inline).
- Modify: `App/WatermarkApp.swift` — branch root on `hasCompletedOnboarding`.

### 7.2 Structure
```swift
// WatermarkApp.swift
@AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

WindowGroup {
    if hasCompletedOnboarding {
        ContentView(viewModel: viewModel)
            .preferredColorScheme(appearance.colorScheme)
            // ...existing URL/scenePhase handlers
    } else {
        OnboardingView()
            .preferredColorScheme(appearance.colorScheme)
    }
}
```

### 7.3 Pages (TabView, `.page` style)
1. **Welcome** — app name "Markepi", one-line value prop, hero graphic. (Use `EmptyStateView`'s SF Symbol style as a reference for tone.)
2. **Features** — three quick callouts: signature watermark, frame, caption/positioning. (Mirror the `EditorToolDock` tool set so onboarding matches the real UI.)
3. **Get Started** — explains photo access, single "Get Started" button → sets `hasCompletedOnboarding = true`. (Trigger the photo permission request only when the user actually opens the picker, not on this screen — unless product wants otherwise.)

### 7.4 iPad/landscape
- Onboarding is a **single centered column** (per chosen scope), not two-column. Wrap page content in `.frame(maxWidth: .readableContentWidth)` and center, so it never stretches edge-to-edge on iPad.
- Pages must read fine in landscape (avoid tall hero graphics that clip — use `ViewThatFits` or scalable layout).

### 7.5 ⚠️
- **`hasCompletedOnboarding` default.** `@AppStorage` defaults to `false` → onboarding shows for everyone on first launch. Good. Existing users upgrading will also see it once — confirm with product whether that's acceptable, or seed the default from a one-time migration.
- **Skip button:** add a "Skip" control on every page so users can bail into the editor.
- **Don't block handoff.** The Share Extension's `watermark://shared` URL handling still needs to land in the editor — if onboarding is showing when a share arrives, complete onboarding first, then process the share.

---

## 8. Settings & Paywall — landscape-optimized single column

These are already `.sheet`s with their own `NavigationStack`, so on iPad they're already centered form sheets. The work is small:

- **Settings (`SettingsView`, `ContentView.swift:608–669`):** wrap the `Form` content in `.frame(maxWidth: .readableContentWidth)` (or set `.navigationSplitViewColumnWidth` is **not** needed — we chose single-column). Confirm sections read well in landscape.
- **Paywall (`PaywallView.swift`):**
  - Replace the `geo.size.height < 680` heuristic (`PaywallView.swift:30`) with `verticalSizeClass` + `dynamicTypeSize` (the existing plan item — keep it).
  - Cap content with `.readableContentWidth`; verify the price/CTA buttons look right in landscape (stack vertically when narrow via `ViewThatFits`).
- ⚠️ Don't add `.presentationDetents` expecting them to shape the iPad sheet — they're ignored on iPad (Section 4.5). Use `.readableContentWidth` + default form-sheet behavior.

---

## 9. Implementation phases

### Phase 1 — Foundation: tokens + theme plumbing (no visual change yet)
**Add (shared package):** `DesignSystem/Theme/AppearancePreference.swift`, `DesignSystem/Theme/MarkepiColors.swift`, `DesignSystem/Spacing/MarkepiSpacing.swift`, `DesignSystem/Radius/MarkepiRadius.swift`, `DesignSystem/Sizing/MarkepiSizing.swift`.
**Modify:**
- `WatermarkApp.swift:47` → `.preferredColorScheme(appearance.colorScheme)` (add `@AppStorage("appearancePreference")`).
- `SettingsView` → add a segmented `Picker` (System / Light / Dark) bound to the preference.

**Steps**
1. Create `AppearancePreference` with `colorScheme: ColorScheme?` mapping.
2. Create the four token files (values from D2/D3).
3. Wire `@AppStorage` + `.preferredColorScheme` at the root. App still looks identical in Dark.
4. Add the Settings picker.

**Exit criteria:** Dark looks identical; System/Light selectable (UI not yet light-corrected — Phase 2). Build gate green.

⚠️ **Live-preview identifier:** if any preview keys its refresh off `WatermarkViewModel` config via a `previewIdentifier`, you don't need to add `appearancePreference` there (it's root-level, not per-render). But double-check nothing in the VM assumed the dark lock.

### Phase 2 — Migrate inline colors to tokens (theme correctness)
Iterate view-by-view; each file is one commit. **Apply the D6 two-bucket rule everywhere.**
1. `ContentView.swift` — `canvasBackground` (`:145`), `LoadingOverlay` scrim + `.white` text (`~:696`): bucket each `.white` (canvas vs chrome).
2. `PreviewView.swift` — scrim (`:55`), `.white` tint (`:57`) → canvas bucket.
3. `ThumbnailStripView.swift` — `.white` (`:140,172`) → these are badges/labels on the strip; decide bucket per use.
4. `BatchProgressOverlay.swift` — status tints (`:58,81`).
5. `Editor/*` — `.tint(.blue)` literals (`ExportControls.swift:46,55`).
6. Audit `Color(.system*)` usages in light scheme — confirm each reads right; flip only where the dark lock hid a problem.

**Exit criteria:** Fully legible and intentional in **both** light and dark; no raw `Color.black`/`.white` literals for **chrome** surfaces remain (canvas `.white`/`.black` are intentional and documented).

### Phase 3 — Spacing / Radius / Typography adoption
- Sweep `cornerRadius:` → `MarkepiRadius.*` (28 sites).
- Sweep recurring `padding`/`spacing` → `MarkepiSpacing.*` (one-shot isolated literals can stay).
- Sweep remaining `.font(.system(size:))` → `.markepiTypography(...)` (add cases only if needed).

**Exit criteria:** No `cornerRadius` literals; `MarkepiTypography` is the single font source in the App layer.

### Phase 4 — Dynamic sizing for smaller displays
- `ThumbnailStripView.swift` — derive `cellSize` (`:34`) and strip height (`:119`) from `MarkepiSizing`, scaled by `dynamicTypeSize` with a min-size guard for iPhone SE.
- Fixed frames → tokens: `64×64` (`ContentView.swift:699`), `48×48` (`TemplatePreviewThumbnail.swift`), `width 220` (`BatchProgressOverlay.swift:82`), `40×5` grabber (`ToolPanelView.swift:64`), `7×7`/`22×22` badges (`ThumbnailStripView.swift:141,229`).
- `PaywallView.swift:30` `< 680` heuristic → `verticalSizeClass` + `dynamicTypeSize`.
- Apply `MarkepiSizing.minTouchTarget` (≥44 pt) to icon-buttons currently < 44 pt.

**Exit criteria:** Reflows cleanly on iPhone SE and Pro Max; no clipped text, no oversized panels.

### Phase 5 — iPad two-column editor (see Section 6)
- Split `bottomControls` into `mediaControls` + `editorControls`.
- Add `availableWidth` via `onGeometryChange` + `isWideLayout` guard.
- Implement the branched body (narrow safeAreaInset vs wide HStack rail).
- `EditorToolDock` moves to top-of-rail in wide mode (keep it horizontal).
- Verify 50% Split View collapses to narrow.

**Exit criteria:** Full-screen iPad shows canvas + right rail; 50%/33% Split View and Slide Over degrade to the phone layout; no crushed canvas, no stretched controls.

### Phase 6 — Welcome / onboarding (see Section 7)
- Build `OnboardingView` (3-page paged TabView).
- Branch root in `WatermarkApp` on `hasCompletedOnboarding`.
- Add Skip; verify share-handoff still lands in the editor.

**Exit criteria:** First launch shows onboarding once; subsequent launches go straight to the editor; iPad shows a centered, readable column.

### Phase 7 — Secondary screens + polish/tests/docs
- Settings + Paywall `.readableContentWidth` + landscape pass (Section 8).
- Visual review matrix (Section 10).
- Unit tests: `AppearancePreference` round-trip + `colorScheme` mapping; `MarkepiMetrics` scaling table; `hasCompletedOnboarding` default.
- Update `AGENTS.md` design-system section (tokens in shared package; appearance preference pattern; `onGeometryChange` width guard).
- Run `bash scripts/build-gate.sh` and `bash scripts/test-sync-requirements.sh`.

---

## 10. Testing checklist (manual + unit)

**Device/size matrix — check every cell in Light AND Dark:**
- iPhone SE (3rd) — narrow, small
- iPhone 15 — narrow
- iPhone Pro Max — narrow (portrait) and **wide (landscape → two-column)**
- iPad mini — wide (portrait + landscape)
- iPad Pro 13" — wide (portrait + landscape)
- **iPad 50% Split View** — must be narrow layout
- iPad 33% Split View / Slide Over — narrow layout

**Per device, verify:**
- [ ] Canvas never crushed; no clipped text
- [ ] Right rail appears only when genuinely wide; collapses otherwise
- [ ] Settings/Paywall/Welcome centered, readable width, not stretched
- [ ] Onboarding shows once, then never
- [ ] Toolbar buttons reachable, not duplicated, in both layouts
- [ ] All three appearance modes legible

**Unit tests:** AppearancePreference round-trip + mapping; token value sanity; `MarkepiMetrics` scaling; onboarding default = false.

⚠️ The project's test scheme has gaps (schemes historically lacked a test action). Confirm `WatermarkCoreTests` runs under an iOS-Sim scheme before relying on it.

---

## 11. Risk register

| Risk | Likelihood | Mitigation |
|---|---|---|
| Light mode reveals illegible spots | High | Phase 2 D6 two-bucket audit + visual pass before closing. |
| `.white` on canvas accidentally tokenized → illegible in light | High | D6: canvas white stays white. Reviewer checks every `.white` change. |
| 50% Split View crushes canvas | High | `availableWidth >= 700` guard; explicit test in matrix. |
| Two-column touches VM state | Low | Phase 5 is view-layer only (env reads); keep VM untouched. |
| Fixed-frame removal regresses current devices | Medium | Phase 4 per-file with build gate + visual check; old values are token defaults. |
| Onboarding shows for existing upgraders | Medium | Confirm with product; optionally seed default via migration. |
| Share handoff blocked by onboarding | Medium | Complete onboarding first, then process `watermark://shared`. |
| Theme tokens leak into render path (white-frame/CIImage bug) | Medium | D2 scope boundary; `MarkepiColors` is chrome-only. |
| Raw `.glassEffect()` crashes (iOS 26 beta) | Low | Reuse existing `GlassEffect/` component (gated behind `MARKEPI_LIQUID_GLASS`); don't call `.glassEffect()` directly. |

---

## 12. Quick reference — key files & symbols

| File | Symbols | Why |
|---|---|---|
| `App/WatermarkApp.swift` | `body`, `.preferredColorScheme` (`:47`) | Root; add `@AppStorage`, branch onboarding, swap scheme |
| `App/Views/ContentView.swift` | `body` (`:40`), `mainLayout`, `firstPage`, `PreviewView` use (`:117`), `bottomControls` (`:292–350`), `SettingsView` (`:608`), toolbar (`:208–268`), sheets (`:87–92`) | Two-column refactor, theme literals, settings entry |
| `App/Views/PreviewArea/PreviewView.swift` | scrim/tint (`:55,57`) | Theme migration |
| `App/Views/Navigation/ThumbnailStripView.swift` | `cellSize` (`:34`), strip height (`:119`), badges | Sizing + theme |
| `App/Views/Editor/EditorToolDock.swift`, `ToolPanelView.swift`, `ExportControls.swift` | dock, panel, tints | Rail refactor, literals |
| `App/Views/Batch/BatchProgressOverlay.swift`, `BatchItemDetailSheet.swift` | status tints, `width 220`, detent (`:92`) | Theme/sizing; detent is iPad no-op |
| `App/Views/Premium/PaywallView.swift` | height heuristic (`:30`), fonts (`:85`) | Landscape optimization |
| `App/Views/Templates/TemplatePreviewThumbnail.swift` | `48×48` | Sizing |
| `App/Views/Onboarding/OnboardingView.swift` | — (new) | Welcome |
| `App/ViewModels/WatermarkViewModel.swift` | `didSet` pattern (`:63–75`) | Reference pattern (appearance uses `@AppStorage` at root instead) |
| `Packages/WatermarkCore/.../DesignSystem/Typography/MarkepiTypography.swift` | cases: `sectionHeader`, `controlLabel`, `value`, `metadata`, `pillLabel` | Adopt/extend |
| `Packages/WatermarkCore/.../DesignSystem/` | new `Theme/`, `Spacing/`, `Radius/`, `Sizing/` | Token home (shared with extension) |

---

## 13. Out-of-scope / future
- Package asset catalog (`*.colorset` light/dark, `bundle: .module`) — once Share-Extension theming is in scope.
- Theme preference synced to the Share Extension via App Group `UserDefaults`.
- Two-column Settings (sidebar + detail) on iPad — v1 is single-column form sheet.
- Mac Catalyst-specific affordances beyond the wide layout.
- Custom landscape-iPhone-only layout (the wide-layout rule already handles large iPhones).
