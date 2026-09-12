## Context

`FrameStyle` (`WhiteFrameConfig.swift`) has two cases today, and every style-dependent behavior in `WhiteFrameRenderer.swift` is an explicit `switch config.style` with exactly those two arms: `matColor(for:)`, the mat-fill drawing in `drawFrame` (flat fill for `classic`, a hand-drawn `CGGradient` for `gallery`), `hasCaptionContent`, and caption resolution (`resolveCaption` for `classic`'s single line vs `resolveGalleryCaption` for `gallery`'s four slots). See proposal.md for why a third and fourth style are being added now and why more are expected later.

The two new mockups need two new caption compositions: `slate` needs nothing new — it is `gallery`'s existing two-column caption on a flat mat. `studio` needs a centred *two*-line caption where classic's drawing path only ever handled one line, and its first line needs *two font weights in the same line* — a regular "Shot on ", a bold device model, and a regular manufacturer name — which no current style does; every existing line is one weight end to end.

## Goals / Non-Goals

**Goals:**
- Make the mat fill (flat vs. graduated) a property a style picks, not code duplicated per style.
- Generalize `classic`'s centred single-line drawing into centred multi-line drawing, reused by `studio`.
- Add mixed-weight-within-one-line drawing as a small, self-contained primitive, used by `studio`'s first line.
- Ship `slate` and `studio` end to end: config, resolution, drawing, UI, tests.

**Non-Goals:**
- A dynamic/pluggable style registry. `FrameStyle` stays a closed `enum`; the compiler's exhaustiveness check on every `switch config.style` is a feature (it is what forces every new style to be handled everywhere it needs to be), not a limitation to design away.
- Making `gallery`'s two-column layout itself configurable beyond what it already offers. `slate` reuses it unchanged.
- Making `studio`'s first line user-configurable. The mockup shows one fixed composition; generalizing `CaptionSlot` to support inline mixed-weight runs (so a user could build arbitrary bold-in-the-middle lines) is a much bigger feature nobody has asked for — resist it (YAGNI) until a future mockup actually needs it.
- Anticipating specific requirements of frame styles beyond `slate` and `studio`. The reusable pieces built here (flat/graduated fill, centred multi-line drawing) are sized to what these two need; a future style with a genuinely new layout still gets new code when it arrives.

## Decisions

### D1: Factor mat fill into a `flat` / `graduated` choice, not a per-style function
Today `matColor(for:)` already returns one flat color per style (used for e.g. `isLight` checks) while the *actual fill* in `drawFrame` is a separate switch that special-cases `gallery`'s gradient. Collapse these into one small enum or two-case choice (`flat(CGColor)` / `graduated(top: CGColor, bottom: CGColor)`) that each `FrameStyle` maps to, and one drawing function that fills the canvas from it. `classic`, `slate`, `studio` map to `flat`; `gallery` keeps `graduated`. This is a refactor of existing code, not new behavior for `classic`/`gallery`.

**How that gets checked, since there is nothing to check against yet.** `Tests/WatermarkCoreTests/__Snapshots__` contains only share-extension images — there are no committed frame baselines, so "assert it matches the existing baseline" is not available and section 1 of the task list is really "build the safety net", not "reuse it". Two different checks, for two different purposes:

- **Throwaway, local, byte-identical.** Immediately before the refactor, render `classic` and `gallery` to files on the machine doing the work; immediately after, render again and compare bytes. This is the strongest possible check and it is valid here precisely because both renders happen on one machine within one sitting. It is not committed.
- **Committed, durable, cheap.** A byte-identical PNG comparison is the wrong thing to keep, because Core Text rasterizes differently across OS versions and hardware and the test would rot into a flake. What the committed test should assert is the thing the refactor can actually break: sample the mat pixel near the top edge and near the bottom edge, and assert they are equal for a flat style and different for a graduated one. That pins the fill behaviour per style without depending on glyph rasterization at all.

### D2: Generalize `classic`'s single centred line to a centred line *list*
`classic`'s current drawing path centres one string. Change its signature to take an ordered array of (text, weight, color) lines and stack them centred as a block, with `classic` continuing to pass exactly one line (its existing `resolveCaption` output, unweighted) so its rendering is unchanged. `studio` passes two lines: the mixed-weight credit line (D3) and the plain shooting-details line.

### D3: A small mixed-weight single-line primitive, scoped to one use
Add a drawing helper that takes an ordered list of (substring, weight) runs and lays them out as one line — implemented with `NSAttributedString`/`CTLine` (both render paths already use Core Text or UIKit text APIs for the existing per-line weight/color handling, so this is the same drawing family, not a new one). `studio`'s first line is the only caller: `[("Shot on ", .regular), (deviceModel, .bold), (" " + manufacturer, .regular)]`, with the manufacturer run omitted (per its own conditional) rather than left as a dangling space. This stays a narrow, single-purpose helper — not a general rich-text caption system.

### D4: Manufacturer name for `studio` reuses `BrandMarkRegistry`'s resolution
`BrandMarkRegistry` already normalizes a photo's recorded manufacturer into one of `brandKeys` (lowercase, e.g. `"apple"`, `"oneplus"`) to pick `gallery`'s mark — including alias and sub-brand handling. Reuse that same resolution for `studio`'s manufacturer-name text rather than re-deriving it from raw metadata. The brand key itself is not display-cased (`"dji"`, `"oneplus"`), so add a small key → display-name lookup (most brands: `.capitalized`; the handful that don't capitalize correctly — `DJI`, `OnePlus`, and any other exception found while implementing — get an explicit entry). No manufacturer resolved → `studio`'s first line omits the trailing name, exactly mirroring `gallery`'s "no mark, no divider" fallback for the same condition.

### D5: `studio`'s second line reuses field selection, not gallery's slots
`studio` is closer to `classic` than to `gallery` in configurability: one fixed line plus one field-driven line, not four independent slots. Reuse `WhiteFrameConfig.captionFields`/`captionPrefix` (already `classic`'s mechanism) rather than adding new slot properties. The join separator differs from `classic`'s `"·"` (the reference shows plain spacing) — implemented as a small separate join next to `DeviceMetadataProvider.caption` rather than parametrizing that function's separator, since `classic`'s dot-joined format is itself an established look not being changed here.

### D6: `studio` hides the caption-prefix row
D5 reuses `captionPrefix`/`captionFields` for `studio`'s *second* line. That collides with `studio`'s fixed first line, because the prefix field's own placeholder text is literally "e.g. Shot on" — a user following that hint would get "Shot on" rendered twice, once hardcoded on line one and once typed on line two.

Chosen: `studio` shows the field-selection row but **not** the caption-prefix row. Its first line is the credit line and is not user-configurable, which is exactly what the prefix would otherwise duplicate; its second line is a plain field list. The stored `captionPrefix` value is left untouched rather than cleared, so switching back to `classic` restores whatever the user had typed there.

Rejected alternative: make the first line's lead-in the `captionPrefix`, defaulting to "Shot on". It sounds tidier, but it makes an existing field mean something different depending on the selected style, and it would let a user type a prefix that leaves the bold device-model run dangling mid-sentence. Not worth it for a line the mockup shows as fixed.

### D7: Working names `slate` and `studio`
Chosen only as clear, single-word `FrameStyle` raw values consistent with `classic`/`gallery`. Not a product-copy decision — `displayName`/`summary` strings (and the raw values themselves, before any template ships with them saved) can change freely if the user prefers different names; flagged as a non-blocking open question below rather than re-asked now.

## Risks / Trade-offs

- **[Risk] The mat-fill and multi-line refactor accidentally changes `classic`/`gallery` pixel output** → Mitigation: the two-part check in D1 — a throwaway byte-identical local comparison across the refactor itself, plus a committed mat-fill pixel probe that survives OS and hardware differences.
- **[Risk] The style-dependent settings branch in `WhiteFrameToggleView` is binary today** (`classic` versus everything else), so adding two styles to it silently gives `studio` `gallery`'s slot rows → Mitigation: the branch is converted to a per-style decision, and the task list verifies each style's rows in a running build rather than by reading the diff.
- **[Risk] Mixed-weight single-line drawing behaves differently between the UIKit (iOS) and Core Text (macOS test) render paths** → Mitigation: `studio`'s credit line gets a platform-parity test the same way `gallery`'s two-column caption already does (per the original `add-frame-styles` change's task 5.7).
- **[Risk] Scope creep toward a general rich-text caption system** → Mitigation: D3 and D5 explicitly bound the new primitives to what `studio` needs; resist generalizing further until a concrete future style requires it.

## Open Questions

- Final display names for `slate`/`studio` (marketing copy, not raw enum values) — cosmetic, does not affect the spec, approach, or task breakdown; can be decided any time before shipping without touching this design.
- **Word order of the credit line, against the mockup.** This design assumes "Shot on *{model}* {manufacturer}". Read back, that gives "Shot on iPhone 15 Pro Max Apple" and "Shot on ILCE-7M4 Sony", both of which trail awkwardly, and for Apple devices the model already carries the brand. Check the reference image before implementing: the manufacturer may sit on the second line, or before the model, or be absent for brands whose model names already contain them. Cheap to settle now, annoying to re-render baselines for later.
