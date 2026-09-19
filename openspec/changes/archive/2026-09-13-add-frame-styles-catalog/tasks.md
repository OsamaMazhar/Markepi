## 0. Prerequisite

- [x] 0.1 Confirm the reference mockup's credit-line word order before writing section 6, resolving design.md's open question ("Shot on *{model}* {manufacturer}" versus manufacturer first, second line, or omitted), and record the answer in design.md D4, updating the `photo-frames` spec delta too if it differs from the order written there
- [ ] 0.2 Archive the `add-frame-styles` change so `openspec/specs/photo-frames/spec.md` exists, since this change modifies a requirement defined there and `openspec/specs/` is currently empty

## 1. Baseline safety net

There are no frame snapshot baselines committed today — `Tests/WatermarkCoreTests/__Snapshots__` holds only share-extension images — so this section builds the net rather than reusing one. See design.md D1 for why the local check and the committed check are different things.

- [x] 1.1 Render `classic` and `gallery` to files from the current `main` on the working machine and keep them outside the repo as the pre-refactor reference, and verify both files are non-empty and visually correct
      — done via a second git worktree at `b069aa5`; both styles re-rendered after the refactor compared **byte-identical**
- [x] 1.2 Add a committed mat-fill test that samples the mat pixel near the top edge and near the bottom edge of a rendered frame, and verify it passes today: equal for `classic`, different for `gallery`

## 2. Shared mat-fill and multi-line drawing

- [x] 2.1 Factor `matColor`/the inline gradient drawing in `drawFrame` into one `flat`/`graduated` mat-fill choice per `FrameStyle`, with `classic` and `gallery` mapped to their current fills, and verify both render byte-identical to the 1.1 reference files and that the 1.2 test still passes
- [x] 2.2 Generalize `classic`'s centred single-line caption drawing to take an ordered list of lines (each with its own weight/color) instead of one string, with `classic` passing exactly its existing single line, and verify `classic` still renders byte-identical to its 1.1 reference file
- [x] 2.3 Add a mixed-weight single-line drawing helper (ordered runs of text + weight rendered as one line), scoped to this one use, and verify a unit test asserts a multi-run line's rendered text matches the full concatenated string and that a bold run is measurably wider than the same text at regular weight

## 3. Manufacturer display name

- [x] 3.1 Add a brand-key → display-name lookup alongside `BrandMarkRegistry` (most brands via `.capitalized`, explicit entries for the ones that don't capitalize correctly, e.g. "dji" → "DJI", "oneplus" → "OnePlus"), and verify a unit test covers every entry in `brandKeys` produces a sane display name
- [x] 3.2 Verify a manufacturer that resolves to a brand mark also resolves to the correct display name via the same `BrandMarkRegistry.brandKey(metadata:)` path, for a representative sample of shipped brands

## 4. Config and style registration

- [x] 4.1 Add `slate` and `studio` to `FrameStyle`, with `displayName`/`summary` copy, and verify `FrameStyleConfigTests` covers both alongside the existing lenient-decode-to-`classic` fallback for an unknown future style name
      — neither shipped as a style in the end: `slate` became `gallery.gradientEnabled` (design.md D8) and `studio` collapsed into `classic` (D10). `print` is the one style added.
- [x] 4.2 Verify a template saved with an older build (no `slate`/`studio` awareness) still decodes to `classic` unaffected, per the existing decode test pattern

## 5. Rendering — gallery's gradient setting (was: slate)

- [x] 5.1 Wire `slate` to reuse `gallery`'s caption resolution, geometry and brand-mark drawing entirely, changing only its mat fill to flat, and verify a test applies an identical config to both styles and asserts identical caption content/layout with only the mat fill differing
      — built, and that is exactly what showed it should not be a style: it reused *everything*. Now `gradientEnabled` on `gallery`, with tests asserting the caption, layout, mark and keyline are identical either way
- [x] 5.2 Verify `slate`'s keyline and brand mark colour/monochrome variant behave exactly as `gallery`'s do, via the existing gallery tests parametrized (or duplicated) over both styles
      — they are the same style now, so this holds by construction; the flat tone is the one the graduated mat already reached at the caption, so no contrast decision was retuned

## 5b. Rendering — print

- [x] 5b.1 Add a `print` style: a flat mat with a drop shadow behind the photo, the shadow falling either downwards or on all four sides, and verify tests cover the offset per variant, the shadow scaling with the mat, and that only `print` casts one
- [x] 5b.2 Apply the shadow in Core Image after the platform branch rather than via `CGContext.setShadow`, per design.md D9, and verify the shadow is masked to the mat so it never darkens the photograph
- [x] 5b.3 Verify the photo's corners stay square in every style and with either shadow variant — no corner rounding has been asked for, and an unoffset shadow doubling up at the corners was reported as rounding
- [x] 5b.4 Give `print` a larger caption and a taller band than `classic`, and verify a test asserts both
- [x] 5b.5 Hide the keyline for `print` and verify the stored preference survives switching away and back
- [x] 5b.6 Verify the keyline stays the user's switch in every style that offers it — asked for as "make the black keyline optional in classic"; it already was, and a pixel test now pins that classic with it off shows an unbroken mat right up to the photo

## 5c. Rendering — banner

- [x] 5c.1 Add a `banner` style: the photo bleeding to the top and both side edges with a caption bar beneath, its height measured from the border setting as `gallery`'s band is, and verify tests cover the zero side mat, the bar tracking the border, and the photo reaching both edges in the rendered pixels
- [x] 5c.2 Relax the committed "the framed canvas is larger than the source in both dimensions" geometry test, which `banner` deliberately breaks, and verify it still holds for every style that has a side mat and that `banner` never crops
- [x] 5c.3 Draw the bar's two blocks hugging opposite ends — mark and maker credit at the left, shooting values over equipment at the right, all caps with tracking — and verify a rendered fixture carries ink at both ends of the bar
- [x] 5c.4 Drive both right-hand lines from the user's ticked fields, with the equipment fields on the second line and everything else on the first, and verify no value is printed twice and that unticking the equipment empties the second line
- [x] 5c.5 Share `gallery`'s device-name trim rather than restating it, so a lens string that repeats the device is trimmed identically in both styles
- [x] 5c.6 Omit each part on its own when it cannot be resolved, and verify that a photo with nothing to say gets no bar at all rather than a blank stripe
- [x] 5c.7 Hide the keyline for `banner` — there is no mat to stroke it in — and verify the stored preference survives
- [x] 5c.8 Show the brand-mark rows for `banner` as well as `gallery`, and verify the settings list is the field rows plus the mark rows, which is neither existing style's row set

## 5d. Rendering — the photographer's line

- [x] 5d.1 Let the user write their own text before and/or after `print`'s device credit, both empty by default, and verify tests cover either side, both at once, whitespace-only input, token substitution, and standing alone when the photo names no device
      — first built as a third caption line; rejected on sight, because a signature belongs beside the credit it signs rather than under the equipment data
- [x] 5d.2 Keep the caption at two lines, and verify the band does not grow when a credit is typed
- [x] 5d.3 Keep the device model the only emphasised run on the line, and verify a test asserts exactly one
- [x] 5d.4 Offer the rows only in `print`, and verify both new fields reach `previewKey` — the coverage test fails otherwise

## 6. Rendering — the centred credit caption

Written for `studio`; `studio` was dropped (design.md D10) and `print` is what
draws this caption. Every item below was verified against `print`.

- [x] 6.1 Add manufacturer-aware first-line resolution in the word order settled in 0.1, with the manufacturer omitted when unresolved and the whole line omitted when there is no device model, and verify unit tests cover: both present, manufacturer missing, device model missing
- [x] 6.2 Add second-line resolution reusing `captionFields` with plain-space joining (not `classic`'s "·"), and verify a unit test asserts the selected fields appear in canonical order with plain spacing, and that all-fields-missing yields no second line
- [x] 6.3 Draw the two-line centred caption on a flat mat using the section 2 helpers, and verify a rendered fixture shows both lines centred, the first line's device-model run measurably bolder than its surrounding text, and the mat free of any gradient
      — the flat mat and the two-line ink span are asserted; the *bolder* run is asserted at the resolved-caption level (the model run carries a heavier weight than its lead-in) rather than by measuring glyph widths
- [x] 6.4 Verify the empty-caption case: no device model and no resolvable second-line fields collapses the bottom band to the same width as the other mat edges, consistent with the other styles' empty-caption behavior
      — on `print` it collapses to what the shadow needs rather than to a uniform mat: the photo still has to be lifted off something
- [x] 6.5 Confirm the macOS Core Text render path draws the mixed-weight line upright and correctly positioned, and verify by rendering through `swift test` and asserting text pixels fall inside the bottom band, mirroring how `gallery`'s platform-parity check works

## 7. UI

- [x] 7.1 Convert `WhiteFrameToggleView`'s binary `if style == .classic { … } else { … }` settings branch into a per-style decision, and verify in a running build that each style shows only its own rows, appearing and disappearing correctly when switching
      — branch now keys on `FrameStyle.usesGalleryCaption`, not on a style name
- [x] 7.4 Replace the segmented style picker with a dropdown menu, since four styles already truncate their labels in a segmented control and more are expected, and verify each style's name and summary are legible in the menu
- [x] 7.2 Hide the caption-prefix row for the credit-caption style per design.md D6, leaving the stored `captionPrefix` value untouched, and verify that switching `print` → `classic` restores a previously typed prefix
- [x] 7.3 Confirm no `previewIdentifier` change is needed — the style's raw value is already included — and verify the live preview refreshes when switching style in **both** `App/ViewModels/WatermarkViewModel.swift` and `ShareExtension/ShareExtensionViewModel.swift`
      — **it was needed.** The share extension keyed on `whiteFrame.isEnabled` alone, so every frame control there edited a config its preview never re-rendered from. Both view models now share `WhiteFrameConfig.previewKey`, covered by a test that fails if any frame field is missing from it

## 9. Choosing a style by looking

- [x] 9.1 Keep frame settings per style on `WatermarkConfiguration`, with switching style remembering what the style being left was set to, and verify tests cover switching back, an unvisited style inheriting the settings on screen, and the caption size following the style only when the user has not set one
- [x] 9.2 Add the apply-to-all-styles control at the top of the frame settings, defaulting to off, and verify an edit reaches every style with it on and only the style on screen with it off
- [x] 9.3 Verify an edit applied to all styles is not applied twice to a style nobody has visited — it derives from the style on screen, so deriving it after the edit would toggle it back
- [x] 9.4 Keep `isEnabled` out of the per-style memory, and verify turning the frame off and then switching style leaves it off
- [x] 9.5 Route every frame mutation — the settings rows, the style dropdown and the resolution row — through the shared rule rather than assigning `config.whiteFrame` directly
- [x] 9.6 Show the single-image style strip in place of the batch strip, in both portrait and landscape, with no edit, remove or reorder affordances and the whole framed image visible rather than a crop
- [x] 9.9 Shape each cell like the framed image rather than fitting it inside a square — reported on a portrait photo, where a square cell left the preview small between two empty bands. The short side is fixed so a row stays even; the style's name is free of the cell's width so a narrow cell does not truncate it
- [x] 9.7 Render one preview per style off a `.task(id:)` keyed on every style's settings, and verify it re-renders when an apply-to-all edit changes styles that are not on screen
- [ ] 9.8 Verify on a real device that the strip populates, that selecting a style switches the frame, and that per-style edits hold while switching back and forth

## 10. One list of what a caption may say

- [x] 10.1 Apply the Include list to `gallery`, so an unticked entry draws nothing whatever line it is assigned to, and verify a test covers both dropping and restoring a line
- [x] 10.2 Apply it to `print`'s device credit as well — the one place the checkbox did not mean what it says — and verify a test covers it
- [x] 10.3 Leave typed free text unfiltered, and verify a test covers it
- [x] 10.4 Show the Include grid in `gallery`'s settings above the slot rows, with a line saying what it does there
- [x] 10.6 Draw the ticked entries no slot names, run on after the column's detail line, and verify tests cover where they land, that unticking takes them away again, and that an assigned entry still leads its line
      — filtering alone made the grid a lie in `gallery`: four lines against ten entries meant most ticks named nothing, so the whole grid could be ticked and the caption still read the device name alone
- [x] 10.7 Shrink an overlong caption line on its own rather than shrinking its whole column, so a long detail line no longer drags the device name above it down with it
- [x] 10.8 Resolve the lens in one place for every style, dropping the device name always and the focal length and aperture when those entries are printed too, and verify a test covers all four styles plus a camera lens whose product name must survive
      — `gallery` printed "iPhone 15 Pro Max" above "back triple camera 48mm f/1.78" beside "48mm f/1.8": three readings twice over
- [x] 10.9 Divide `gallery`'s columns by subject — device, date and place on the left; lens, exposure and file on the right — so the place sits under the device that was carried there
- [ ] 10.5 Verify on a real device that ticking an entry shows it in `gallery` and unticking it takes it away again

## 11. Sizes follow the mat

- [x] 11.1 Derive the caption size and the mark height from the border width, keeping the ratio each default was already stated in, and verify a test covers both growing with a wider mat
- [x] 11.2 Keep a size the user sets as given, storing it as an absent-or-present override rather than inferring it by comparison, and carry it in proportion when the mat changes afterwards — "it should also be increased according to the frame width unless the user later reduces it manually" — verifying a test covers both halves
- [x] 11.3 Read a template saved before this — every one of which records a size — as untouched when its size is still the default, and verify a test covers both halves
- [x] 11.4 Move the two sliders' spans with the mat, and keep the current value inside the span, so a grown size never reads as pinned to the end of its control
- [x] 11.5 Stop the CLI restating the defaults for `--border-caption-mm` / `--border-logo-mm`, which froze both at the 8mm mat
- [x] 11.8 Break a too-long caption line at its gaps, within the lines the band can hold, and shrink only what is still over — the per-line shrink added in 10.7 pinned the shooting details to a fixed width, so they stayed the same size however wide the mat got, which is what "the font size of the metadata is not changing" was
- [x] 11.7 Bump `CURRENT_PROJECT_VERSION`, which had stayed at 1 across every install, so the build on the device can be told apart from the one before it (`devicectl device info apps` reports it)
- [ ] 11.6 Verify on a real device that widening the frame grows the caption and the mark, and that a size set by hand then stays put

## 8. Full-suite verification

- [x] 8.1 Render a fixture per style and verify each by eye against its reference mockup before committing
      — done for `classic`, both `gallery` fills, both `print` shadows and `banner`; `studio`'s fixture is what showed it was `classic` with a line break (design.md D10)
- [x] 8.2 Run `cd Packages/WatermarkCore && swift test` and verify the full suite passes, including the section 1 mat-fill test
- [ ] 8.3 Build the app (`xcodebuild -scheme WatermarkApp`) and verify it succeeds, then verify on a real device (not the Simulator, per this project's standing rule) that `print`, `banner` and the gradient toggle render correctly end to end for a photo export
