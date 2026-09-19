> **Superseded in places.** Both styles this design proposed were built and
> then dropped: `slate` collapsed into a gradient setting on `gallery` (D8) and
> `studio` collapsed into `classic` (D10), so every `slate` and `studio`
> reference below is a record of what was planned rather than of what shipped.
> A third style, `print`, was added during the same work and is what carries
> `studio`'s credit caption; see D9. The original text is kept deliberately —
> the two collapses are the most useful thing this document records.

## Context

`FrameStyle` (`WhiteFrameConfig.swift`) has two cases today, and every style-dependent behavior in `WhiteFrameRenderer.swift` is an explicit `switch config.style` with exactly those two arms: `matColor(for:)`, the mat-fill drawing in `drawFrame` (flat fill for `classic`, a hand-drawn `CGGradient` for `gallery`), `hasCaptionContent`, and caption resolution (`resolveCaption` for `classic`'s single line vs `resolveGalleryCaption` for `gallery`'s four slots). See proposal.md for why a third and fourth style are being added now and why more are expected later.

The two new mockups need two new caption compositions: `slate` needs nothing new — it is `gallery`'s existing two-column caption on a flat mat. `studio` needs a centred *two*-line caption where classic's drawing path only ever handled one line, and its first line needs *two font weights in the same line* — a regular "Shot on ", a bold device model, and a regular manufacturer name — which no current style does; every existing line is one weight end to end.

## Goals / Non-Goals

**Goals:**
- Make the mat fill (flat vs. graduated) a property a style picks, not code duplicated per style.
- Generalize `classic`'s centred single-line drawing into centred multi-line drawing, reused by `studio`.
- Add mixed-weight-within-one-line drawing as a small, self-contained primitive, used by `studio`'s first line.
- Ship `slate` and `studio` end to end: config, resolution, drawing, UI, tests. *(`slate` shipped as a setting instead — D8.)*

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

### D4: Manufacturer name for `studio` reuses `BrandMarkRegistry`'s resolution, on the second line

**Word order, settled (was the open question below).** The credit line is
"Shot on *{model}*" and the manufacturer's name leads the *second* line, ahead
of the selected fields. Read back, trailing the maker on line one gives "Shot on
iPhone 15 Pro Max Apple" and "Shot on ILCE-7M4 Sony", both of which trail
awkwardly, and for Apple devices the model already carries the brand. Where the
credit line names the device, the camera field is dropped from the second line
rather than printing the same device twice — the same "don't say it twice"
rule `gallery` already applies to its lens string.

`BrandMarkRegistry` already normalizes a photo's recorded manufacturer into one of `brandKeys` (lowercase, e.g. `"apple"`, `"oneplus"`) to pick `gallery`'s mark — including alias and sub-brand handling. Reuse that same resolution for `studio`'s manufacturer-name text rather than re-deriving it from raw metadata. The brand key itself is not display-cased (`"dji"`, `"oneplus"`), so add a small key → display-name lookup (most brands: `.capitalized`; the handful that don't capitalize correctly — `DJI`, `OnePlus`, and any other exception found while implementing — get an explicit entry). No manufacturer resolved → `studio`'s first line omits the trailing name, exactly mirroring `gallery`'s "no mark, no divider" fallback for the same condition.

### D5: `studio`'s second line reuses field selection, not gallery's slots
`studio` is closer to `classic` than to `gallery` in configurability: one fixed line plus one field-driven line, not four independent slots. Reuse `WhiteFrameConfig.captionFields`/`captionPrefix` (already `classic`'s mechanism) rather than adding new slot properties. The join separator differs from `classic`'s `"·"` (the reference shows plain spacing) — implemented as a small separate join next to `DeviceMetadataProvider.caption` rather than parametrizing that function's separator, since `classic`'s dot-joined format is itself an established look not being changed here.

### D6: `studio` hides the caption-prefix row
D5 reuses `captionPrefix`/`captionFields` for `studio`'s *second* line. That collides with `studio`'s fixed first line, because the prefix field's own placeholder text is literally "e.g. Shot on" — a user following that hint would get "Shot on" rendered twice, once hardcoded on line one and once typed on line two.

Chosen: `studio` shows the field-selection row but **not** the caption-prefix row. Its first line is the credit line and is not user-configurable, which is exactly what the prefix would otherwise duplicate; its second line is a plain field list. The stored `captionPrefix` value is left untouched rather than cleared, so switching back to `classic` restores whatever the user had typed there.

Rejected alternative: make the first line's lead-in the `captionPrefix`, defaulting to "Shot on". It sounds tidier, but it makes an existing field mean something different depending on the selected style, and it would let a user type a prefix that leaves the bold device-model run dangling mid-sentence. Not worth it for a line the mockup shows as fixed.

### D8: `slate` collapsed into a setting on `gallery` (supersedes the `slate` parts of D1)

Built as specified, `slate` reused `gallery`'s caption resolution, geometry, brand mark, keyline and sizing *in full*, and differed only in `matFill`. Its tests read as "assert slate equals gallery" line after line, which is the shape of a distinction that is not one.

So the gradient is now a boolean on `WhiteFrameConfig` that only `gallery` reads, and `matFill` takes the whole config rather than the style alone. There is one fewer style, one fewer set of branches to keep in step, and a control that says what it does ("Gradient", on/off) instead of a name the user has to learn.

**The flat tone, corrected.** It was first the gradient's own bottom tone, reasoning that extending the caption band's ground kept every contrast decision already tuned for it untouched. That reasoning was sound and the result was wrong: the tone is a mid grey, and a mat with the gradient turned off is expected to be white. It is now the same plain white `classic` and `print` use, and that is also the default — the graduated mat is the choice, not the starting point.

This is the conclusion D1 was already pointing at — mat fill is a property a style picks, not an identity — followed one step further.

### D9: `print`'s shadow is Core Image, not `CGContext.setShadow`

The shadow is applied to the finished mat in `WhiteFrameRenderer.applyingShadow`, after the platform branch, rather than drawn inside `drawFrame`.

Core Graphics resolves a shadow offset against the context's *base* user space, and the two render paths disagree about which way that space points: the UIKit renderer bakes its flip into the base, while the macOS path applies its own on top. The same offset therefore casts the shadow downwards on one and upwards on the other — and there is no way to verify both from one machine. Drawing it once in Core Image, in one coordinate space, removes the question rather than answering it.

Two things were got wrong on the way there and are worth recording, because both are the kind that look fine until they do not:

- Offsetting the caster rect instead, while filling it opaque, left a hard black band across the strip it overhangs — only the photo's *own* rect is cleared, not the caster's.
- A large offset relative to the blur turns the shadow's dense core into a visible grey slab. The offset has to stay well below the blur radius. But not near zero either: an unoffset shadow hugs all four edges equally and doubles up where two meet, which reads as a *rounded corner* on a photo whose corners are perfectly square. That was reported as rounded corners, and the corners were never rounded.

### D10: `studio` collapsed into `classic` (supersedes D3's second caller, D5, D6 and the `studio` half of D1)

Rendered side by side, `studio` and `classic` differed in one thing: `studio` broke the same caption over two lines and set the device name bold. Same flat white mat, same uniform border, same keyline, same field selection, same sizing. A style whose whole identity is a line break is a setting at best, and it cost a picker entry that the user had to read twice to tell apart.

So `studio` is gone. Nothing it was built from is: the centred multi-line drawing path (D3), the mixed-weight run primitive, the credit-caption resolution and the `BrandMarkRegistry` display-name lookup (D4) all carry on under `print`, which is where a two-line credit earns its space — the band is already taller to clear the shadow, and the caption is already set larger.

D6's reasoning moved with it: `print` is now the style that hides the caption-prefix row, for exactly the reason `studio` did — its first line *is* the "Shot on" credit, and the prefix field's own placeholder invites the user to type it a second time.

What this and D8 have in common is worth stating plainly, because two of the three styles proposed here went the same way: a new mat fill and a new line count both looked like styles on a mockup and turned out to be settings in the code. The test for a style is whether its *layout* differs, not whether its output does.

### D11: `banner` is the first style whose export does not grow in both dimensions

Every style before it surrounds the photo, and that had hardened into an assumption: a committed geometry test asserted the framed canvas is larger than the source in *both* dimensions, for every style, and the renderer's side-edge thickness was one value used for top, left and right alike.

`banner` has no side mat at all — the photograph runs to the top and both edges and the caption sits in a bar beneath it, which is the entire look. So the side edge became a style-dependent value, and the geometry test now asserts the thing that is actually invariant: the canvas never crops, always grows in height, and grows in width only where there is a side mat.

Two smaller consequences worth recording. A `banner` with nothing to say collapses to *no frame at all* rather than to a uniform mat, because a bar with nothing in it is a blank white stripe. And `banner` takes `classic`'s field rows together with `gallery`'s mark rows, which is neither style's row set — the settings branch had already been converted from a style-name test to a layout test (D6, task 7.1), and this is the case that would have broken it again had it not been.

### D12: The caption and the mark follow the mat, until the user says otherwise

Widening the frame left the caption at its old size, so a wide mat came out with small text floating in it. The sizes are not independent of the border: every default in `FrameMetrics` is *already* written as a ratio of the default border — `captionToBorder`, `markToBorder` — so the fix is to keep that ratio at whatever thickness the user picks rather than to freeze the number it produced at 8mm.

Stored as an absent-or-present override (`captionMillimetresOverride`, `logoMillimetresOverride`) rather than a size plus a "did they touch it" flag beside it. Nil *is* "follow the mat", which makes the two states impossible to get out of step, and it deleted the inference in `FrameStyleSettings.restyled`, which had been comparing the stored size against the style default to guess the same thing.

Two consequences had to be handled rather than discovered later. Every template saved before this records a size, so decoding each one as hand-set would freeze every existing user's caption forever; a stored size still equal to the style's default is therefore read as untouched, which is what it means, and the encoder now also writes the flag so no future reader has to infer it. And the two sliders had fixed spans (1–10mm, 1–15mm) that a size grown by a thick mat would exceed, leaving the control pinned at its end and reading as stuck — the spans move with the mat, and always contain the current value.

### D7: Working names `slate` and `studio`
Chosen only as clear, single-word `FrameStyle` raw values consistent with `classic`/`gallery`. Not a product-copy decision — `displayName`/`summary` strings (and the raw values themselves, before any template ships with them saved) can change freely if the user prefers different names; flagged as a non-blocking open question below rather than re-asked now.

## Risks / Trade-offs

- **[Risk] The mat-fill and multi-line refactor accidentally changes `classic`/`gallery` pixel output** → Mitigation: the two-part check in D1 — a throwaway byte-identical local comparison across the refactor itself, plus a committed mat-fill pixel probe that survives OS and hardware differences.
- **[Risk] The style-dependent settings branch in `WhiteFrameToggleView` is binary today** (`classic` versus everything else), so adding two styles to it silently gives `studio` `gallery`'s slot rows → Mitigation: the branch is converted to a per-style decision, and the task list verifies each style's rows in a running build rather than by reading the diff.
- **[Risk] Mixed-weight single-line drawing behaves differently between the UIKit (iOS) and Core Text (macOS test) render paths** → Mitigation: `studio`'s credit line gets a platform-parity test the same way `gallery`'s two-column caption already does (per the original `add-frame-styles` change's task 5.7).
- **[Risk] Scope creep toward a general rich-text caption system** → Mitigation: D3 and D5 explicitly bound the new primitives to what `studio` needs; resist generalizing further until a concrete future style requires it.

## Open Questions

- ~~Final display names for `slate`/`studio`~~ — moot: neither style shipped (D8, D10).
- ~~Word order of the credit line~~ — settled before implementation: the model alone is credited on line one and the manufacturer leads line two. See D4.
