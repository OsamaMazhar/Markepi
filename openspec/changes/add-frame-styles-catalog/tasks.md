## 0. Prerequisite

- [ ] 0.1 Confirm the reference mockup's credit-line word order before writing section 6, resolving design.md's open question ("Shot on *{model}* {manufacturer}" versus manufacturer first, second line, or omitted), and record the answer in design.md D4, updating the `photo-frames` spec delta too if it differs from the order written there
- [ ] 0.2 Archive the `add-frame-styles` change so `openspec/specs/photo-frames/spec.md` exists, since this change modifies a requirement defined there and `openspec/specs/` is currently empty

## 1. Baseline safety net

There are no frame snapshot baselines committed today — `Tests/WatermarkCoreTests/__Snapshots__` holds only share-extension images — so this section builds the net rather than reusing one. See design.md D1 for why the local check and the committed check are different things.

- [ ] 1.1 Render `classic` and `gallery` to files from the current `main` on the working machine and keep them outside the repo as the pre-refactor reference, and verify both files are non-empty and visually correct
- [ ] 1.2 Add a committed mat-fill test that samples the mat pixel near the top edge and near the bottom edge of a rendered frame, and verify it passes today: equal for `classic`, different for `gallery`

## 2. Shared mat-fill and multi-line drawing

- [ ] 2.1 Factor `matColor`/the inline gradient drawing in `drawFrame` into one `flat`/`graduated` mat-fill choice per `FrameStyle`, with `classic` and `gallery` mapped to their current fills, and verify both render byte-identical to the 1.1 reference files and that the 1.2 test still passes
- [ ] 2.2 Generalize `classic`'s centred single-line caption drawing to take an ordered list of lines (each with its own weight/color) instead of one string, with `classic` passing exactly its existing single line, and verify `classic` still renders byte-identical to its 1.1 reference file
- [ ] 2.3 Add a mixed-weight single-line drawing helper (ordered runs of text + weight rendered as one line), scoped to this one use, and verify a unit test asserts a multi-run line's rendered text matches the full concatenated string and that a bold run is measurably wider than the same text at regular weight

## 3. Manufacturer display name

- [ ] 3.1 Add a brand-key → display-name lookup alongside `BrandMarkRegistry` (most brands via `.capitalized`, explicit entries for the ones that don't capitalize correctly, e.g. "dji" → "DJI", "oneplus" → "OnePlus"), and verify a unit test covers every entry in `brandKeys` produces a sane display name
- [ ] 3.2 Verify a manufacturer that resolves to a brand mark also resolves to the correct display name via the same `BrandMarkRegistry.brandKey(metadata:)` path, for a representative sample of shipped brands

## 4. Config and style registration

- [ ] 4.1 Add `slate` and `studio` to `FrameStyle`, with `displayName`/`summary` copy, and verify `FrameStyleConfigTests` covers both alongside the existing lenient-decode-to-`classic` fallback for an unknown future style name
- [ ] 4.2 Verify a template saved with an older build (no `slate`/`studio` awareness) still decodes to `classic` unaffected, per the existing decode test pattern

## 5. Rendering — slate

- [ ] 5.1 Wire `slate` to reuse `gallery`'s caption resolution, geometry and brand-mark drawing entirely, changing only its mat fill to flat, and verify a test applies an identical config to both styles and asserts identical caption content/layout with only the mat fill differing
- [ ] 5.2 Verify `slate`'s keyline and brand mark colour/monochrome variant behave exactly as `gallery`'s do, via the existing gallery tests parametrized (or duplicated) over both styles

## 6. Rendering — studio

- [ ] 6.1 Add manufacturer-aware first-line resolution in the word order settled in 0.1, with the manufacturer omitted when unresolved and the whole line omitted when there is no device model, and verify unit tests cover: both present, manufacturer missing, device model missing
- [ ] 6.2 Add second-line resolution reusing `captionFields` with plain-space joining (not `classic`'s "·"), and verify a unit test asserts the selected fields appear in canonical order with plain spacing, and that all-fields-missing yields no second line
- [ ] 6.3 Draw `studio`'s two-line centred caption on a flat mat using the section 2 helpers, and verify a rendered fixture shows both lines centred, the first line's device-model run measurably bolder than its surrounding text, and the mat free of any gradient
- [ ] 6.4 Verify the empty-caption case: no device model and no resolvable second-line fields collapses the bottom band to the same width as the other mat edges, consistent with the other styles' empty-caption behavior
- [ ] 6.5 Confirm the macOS Core Text render path draws `studio`'s mixed-weight line upright and correctly positioned, and verify by rendering through `swift test` and asserting text pixels fall inside the bottom band, mirroring how `gallery`'s platform-parity check works

## 7. UI

- [ ] 7.1 Convert `WhiteFrameToggleView`'s binary `if style == .classic { … } else { … }` settings branch into a per-style decision, and verify in a running build that `slate` shows `gallery`'s slot and mark rows and `studio` shows the field-selection rows, with each style's rows appearing and disappearing correctly when switching
- [ ] 7.2 Hide the caption-prefix row for `studio` per design.md D6, leaving the stored `captionPrefix` value untouched, and verify that switching `studio` → `classic` restores a previously typed prefix
- [ ] 7.3 Confirm no `previewIdentifier` change is needed — the style's raw value is already included — and verify the live preview refreshes when switching to and from `slate` and `studio` in **both** `App/ViewModels/WatermarkViewModel.swift` and `ShareExtension/ShareExtensionViewModel.swift`

## 8. Full-suite verification

- [ ] 8.1 Render `slate` and `studio` fixtures and verify each by eye against its reference mockup before committing
- [ ] 8.2 Run `cd Packages/WatermarkCore && swift test` and verify the full suite passes, including the section 1 mat-fill test
- [ ] 8.3 Build the app (`xcodebuild -scheme WatermarkApp`) and verify it succeeds, then verify on a real device (not the Simulator, per this project's standing rule) that both new styles render correctly end to end for a photo export
