# Handoff — Editor Layout Polish (Portrait + Landscape)

**Date:** 2026-06-29
**Branch:** `fix/watermark-preview-scale-whiteframe-tests`
**Status:** IN PROGRESS — landscape dock↔Share alignment reworked to the robust **anchor-measurement** approach (build green). NEEDS a fresh landscape screenshot to confirm. Several other items landed and look acceptable.

---

## What this work is

Iterative visual polish of the photo-editor screen in **`App/Views/ContentView.swift`** (portrait bottom-dock layout vs. landscape side-rail layout). Driven entirely by user screenshots — there is **no automated visual test**; the user rotates a real device / simulator and sends screenshots, we adjust, repeat.

The editor has two layouts, chosen by aspect ratio:
- **Portrait:** `PreviewView` + `.safeAreaInset(.bottom)` holding media controls, the tool panel (`ToolPanelView`), and the horizontal `EditorToolDock`.
- **Landscape:** `landscapeLayout(_:)` — an `HStack { canvasColumn ; landscapeRightRail }`. The rail holds the open tool panel (left) + the vertical `EditorToolDock` (right). Chrome (Back / Settings / Add / Files / Share) is the **system navigation toolbar** in BOTH orientations.

Key fact: the portrait/landscape decision is computed from the **live `geometry.size`** in the `GeometryReader` (`isLandscape(_:)`), threaded into `mainLayout(_:landscape:)`. Do NOT reintroduce a lagged `@State` size for this — it flip-flops on rotation.

---

## LANDSCAPE CHROME REDESIGN (this session — two custom glass rails)

The user reversed the old "landscape reuses the system toolbar" rule. **In landscape-while-editing the system nav bar is now emptied + hidden, and all chrome lives in two custom `markepiGlass` rails:**

- **Left** (`landscapeLeftChrome`, `.overlay(alignment:.topLeading)` on `landscapeLayout`): `VStack { Back (Circle glass) ; VStack{Settings,Add,Files,(Reset)} Capsule glass pill }`. `chromeButton(systemImage:label:action:)` helper, 44pt targets.
- **Right** (`landscapeRightRail`): `VStack { ExportToolbarButton.labelStyle(.iconOnly) ; EditorToolDock(axis:.vertical) }` — Share directly above the dock ⇒ one shared center BY CONSTRUCTION (no measurement).
- The dock uses `.markepiGlass(.bar)` material (both orientations, accepted). The left chrome uses `chromeGlass(in:isEnabled:)` = **device-live real glass**: `#if targetEnvironment(simulator)` material / `#else glassEffect(.regular, in:)`. User chose "SwiftUI glass, device-only" (2026-06-30): real glass matching the toolbar ON DEVICE, material on simulator (glassEffect crashes there — no 26.2 sim). NOT UIKit (rejected), NOT the global `MARKEPI_LIQUID_GLASS` flag. Both simulator + `generic/platform=iOS` builds compile green. **Verify on a real device** — the simulator will show the material fallback, which is expected, not the final look.

Wiring: `toolbarContent(landscapeEditing:)` early-returns nothing when `landscapeEditing`; body computes `let landscapeEditing = landscape && viewModel.currentPhoto != nil` and applies `.toolbar(landscapeEditing ? .hidden : .automatic, for: .navigationBar)`.

**Vertical symmetry (also fixed this session):** the *visible* nav bar reserved the top safe-area inset, pushing the photo up (flush top, gap at bottom). Hiding it in landscape + the existing `.ignoresSafeArea(.container, edges:.vertical)` lets the photo center symmetrically.

**Dock↔Share alignment — SOLVED by the VStack. Do NOT reintroduce measurement.** All measurement code is gone (`landscapeDockWidth`, `shareButtonMidX`, `landscapeDockMidX`, `landscapeDockOffset`, `realignLandscapeDock()`, `WindowMidXReader`). Dead ends: `.offset(safeAreaInsets.trailing)` overshoots; `.offset(landscapeDockWidth/2)` still off; SwiftUI `.onGeometryChange`/`.frame(in:.global)` never fires inside a UIKit toolbar item (stays 0).

**Landscape Share button glass (2026-06-30):** `borderedProminent` outside a toolbar is a flat fill (no glass). The landscape Share now uses `ExportToolbarButton(glassCircle: true)` → `ProminentExportStyle` modifier in `ExportControls.swift`: `.buttonStyle(.glassProminent)` (real tinted Liquid Glass, gated `#if !targetEnvironment(simulator)` + `if #available(iOS 26)`), `.buttonBorderShape(.circle)`, `.controlSize(.large)`. Simulator / iOS<26 fall back to `.borderedProminent` circle. So on DEVICE the Share is a round glass button matching the portrait toolbar; simulator shows a flat circle.

**Icon sizing:** landscape chrome glyphs (Back/Settings/Add/Files/Share) use `ContentView.chromeIconSize = 20` (regular) to match the portrait system-toolbar glyph size (was 17pt medium, too small). Tunable if still off — confirm on device.

**Active-tool highlight (vertical dock):** `EditorToolDock` insets the selected-segment capsule (`6pt` h / `3pt` v) in `.vertical` axis only, so it nests concentrically in the dock pill instead of butting the straight sides as a lozenge.

**Sizing polish (2026-06-30, 2nd pass) — all tunable constants:**
- Share button was oversized (`controlSize(.large)`) + glyph off-centre. Fixed: dropped `controlSize`, the circle now sizes from a square label `ExportToolbarButton.railLabelSize = 30` (centres the glyph). Tune that constant for Share diameter.
- Back button was narrower than the group pill. Both now share `ContentView.chromeRailWidth = 56` (Back framed to 56×56; group `.frame(width: 56)`).
- Active-tool highlight radius now matches the pill: `EditorToolDock.activeHighlight(isFirst:isLast:)` — vertical rail uses `UnevenRoundedRectangle` with end-cap radius `railWidth/2` (= the pill's inner radius) on the first/last tools, `12` on the middle. `railWidth = 64`.

**NEXT:** fresh landscape screenshot ON DEVICE. Confirm (a) Share circle size matches Back/chrome + glyph centred, (b) Back == group pill width, (c) active-tool highlight caps follow the pill's rounded ends, (d) glyph sizes match portrait. All are one-line constant tweaks if slightly off.

### Why this is hard
The Share button is positioned by UIKit inside the system nav bar; its exact x cannot be read declaratively. We're aligning a custom rail element to a system-positioned button across variable landscape **trailing safe-area insets** (Dynamic-Island-side gutter).

### Attempts already made (do NOT repeat blindly)
1. `trailing` padding tweaks (xs/sm/md) — never aligned; Share sits where the system puts it.
2. Moved Share INTO the rail above the dock (guaranteed collinear). **User rejected** — Share must stay in the toolbar.
3. `.offset(x: geometry.safeAreaInsets.trailing)` — **overshot** (dock pushed past Share, touching the edge). Reason: BOTH dock and Share respect the safe-area inset, so it **cancels** — offsetting by it double-counts.
4. `.offset(x: landscapeDockWidth / 2)` (current) — derived from measurement that the no-offset dock center sits ~half-dock-width further from the trailing edge than Share's center. Build green; **alignment still reported wrong.**

### Hard constraints from the user (REPEATED, important)
- **No hardcoded point values / no magic screen fractions.** Derive from measured/relative values (control sizes via `onGeometryChange`, safe-area insets, aspect ratios). See memory `derive-layout-from-display-not-magic-fractions`.
- Must be correct across **all display sizes** and rotations.

### Suggested next approaches (unexplored)
- Measure Share's actual frame: give `ExportToolbarButton` (or a sibling) a coordinate-space anchor / `onGeometryChange` reporting its midX in `.global` (or a named coordinate space spanning the whole editor), and align the dock's midX to it directly. This removes ALL guesswork — it's the only truly robust path. Likely needs a shared `coordinateSpace(.named(...))` on the root and an `anchorPreference`/`onGeometryChange` on both the Share button and the dock.
- If reading the toolbar item proves impossible, reconsider with the user whether a custom Share in the rail (rejected once) is acceptable given it's the only way to guarantee collinearity.

---

## What landed this session (verify with screenshots, likely OK)

All in `App/Views/ContentView.swift` unless noted.

1. **Landscape chrome = system toolbar in both orientations.** Removed all hand-rolled landscape glass buttons. `toolbarContent` (computed property) is used for both. Reason: only the OS gives real Liquid Glass; our material fallback never matched. `glassEffect` is gated OFF (it crashes — see memory `glasseffect-ios260-beta-runtime-crash`).
2. **Rotation layout flip-flop fixed** — `isLandscape(geometry.size)` from live geometry, not `@State containerSize` (removed). `mainLayout(_:landscape:)`.
3. **Portrait panel height is display/content-derived** (NOT a fraction): `editorControls(_:)` computes `photoHeight = geometry.size.width / previewAspectRatio`; `panelCap = max(minPanelHeight, geometry.size.height - photoHeight - dockReserve)`. Tall portrait photo → short panel; wide photo → taller panel. `previewAspectRatio` reads `viewModel.previewImage.size`.
4. **Portrait: photo no longer touches panel** — `.padding(.top, MarkepiSpacing.md)` on the bottom inset; removed extra bottom padding so the floating dock sits just above the home-indicator safe area. User confirmed they want the **floating pill** dock (not a full-width bottom bar). The thin band at the very bottom is the home-indicator safe area (accepted).
5. **Landscape photo uses full height + is vertically symmetric** — `landscapeLayout` applies `.ignoresSafeArea(.container, edges: .vertical)` to the **whole HStack container** (NOT a per-child — doing it on one HStack child distorts width distribution and bleeds asymmetrically). Photo and open panel both center → aligned + symmetric.
6. **Landscape sparse panels shrink** — `landscapePanelWidth(_:for:)` returns a narrower width for `isLandscapePanelSparse(tool)` (logo/signature with no layer yet = just an "Add…" button); content-rich panels keep full width.
7. **Signature panel no longer wraps "Sig-na-ture"** — in `Packages/WatermarkCore/Sources/WatermarkCore/UI/SignatureCaptureView.swift`, the "Signature" label got `.lineLimit(1).fixedSize(horizontal: true, vertical: false)`.
8. **Rotation white box (light mode) fixed** — it was the `UIWindow.backgroundColor` (system white) showing in rotation gaps beneath SwiftUI. Added `WindowBackgroundColor: UIViewRepresentable` (bottom of ContentView.swift), applied as `.background(...)` on the NavigationStack: black while editing (`viewModel.currentPhoto != nil`), `.systemBackground` otherwise. See memory `rotation-gap-is-window-background`.

---

## Build / test

```
xcodebuild build -scheme WatermarkApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -configuration Debug 2>&1 | tail -4
```
- If you hit `Could not resolve package dependencies` / missing `c2pa-swift` xcframework or crypto vectors: the DerivedData SPM cache is corrupted — run
  `xcodebuild -resolvePackageDependencies -scheme WatermarkApp -project Watermark.xcodeproj` then rebuild.
- SourceKit shows a persistent false `No such module 'WatermarkCore'` on line 4 — **ignore it**, the real compile links fine.
- The user does NOT want the agent driving the simulator / adding media (they said so explicitly). They provide screenshots. Don't `simctl addmedia` or launch+screenshot unless asked.

---

## Relevant memories (in `~/.claude/projects/-Users-osama-Projects-Watermark/memory/`)

- `landscape-reuses-system-toolbar` — chrome = system toolbar both orientations; the dock↔Share alignment note.
- `responsive-layout-from-live-geometry` — decide branch from live geometry, not async @State.
- `derive-layout-from-display-not-magic-fractions` — user rejects hardcoded constants; derive from real content/control sizes.
- `rotation-gap-is-window-background` — white flash on rotation = UIWindow.backgroundColor.
- `glasseffect-ios260-beta-runtime-crash` — glassEffect gated off; material fallback only.

---

## Files touched
- `App/Views/ContentView.swift` (the bulk)
- `Packages/WatermarkCore/Sources/WatermarkCore/UI/SignatureCaptureView.swift` (signature label wrap)

## First step for next session
1. Get a fresh landscape screenshot of the CURRENT build (offset = `landscapeDockWidth / 2`).
2. Measure dock-center vs Share-center offset in the screenshot.
3. If still off, implement the **anchor-based measurement** of the Share button (named coordinate space + onGeometryChange on both Share and dock, align midX). That's the robust fix; everything else is guesswork.
