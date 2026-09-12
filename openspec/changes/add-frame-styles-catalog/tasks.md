## 1. Baseline safety net

- [ ] 1.1 Capture current `classic` and `gallery` snapshot baselines (if not already committed under `Tests/WatermarkCoreTests/__Snapshots__`) so the refactor in section 2 can be checked against them, and verify they exist and are up to date with `main`

## 2. Shared mat-fill and multi-line drawing

- [ ] 2.1 Factor `matColor`/the inline gradient drawing in `drawFrame` into one `flat`/`graduated` mat-fill choice per `FrameStyle`, with `classic` and `gallery` mapped to their current fills, and verify `classic` and `gallery` render byte-identical output to the section 1 baselines
- [ ] 2.2 Generalize `classic`'s centred single-line caption drawing to take an ordered list of lines (each with its own weight/color) instead of one string, with `classic` passing exactly its existing single line, and verify `classic`'s rendered output is unchanged
- [ ] 2.3 Add a mixed-weight single-line drawing helper (ordered runs of text + weight rendered as one line), scoped to this one use, and verify a unit test asserts a multi-run line's rendered text matches the full concatenated string and that a bold run is measurably wider than the same text at regular weight

## 3. Manufacturer display name

- [ ] 3.1 Add a brand-key → display-name lookup alongside `BrandMarkRegistry` (most brands via `.capitalized`, explicit entries for the ones that don't capitalize correctly, e.g. "dji" → "DJI", "oneplus" → "OnePlus"), and verify a unit test covers every entry in `brandKeys` produces a sane display name
- [ ] 3.2 Verify a manufacturer that resolves to a brand mark also resolves to the correct display name via the same normalization path, for a representative sample of shipped brands

## 4. Config and style registration

- [ ] 4.1 Add `slate` and `studio` to `FrameStyle`, with `displayName`/`summary` copy, and verify `FrameStyleConfigTests` covers both alongside the existing lenient-decode-to-`classic` fallback for an unknown future style name
- [ ] 4.2 Verify a template saved with an older build (no `slate`/`studio` awareness) still decodes to `classic` unaffected, per the existing decode test pattern

## 5. Rendering — slate

- [ ] 5.1 Wire `slate` to reuse `gallery`'s caption resolution, geometry and brand-mark drawing entirely, changing only its mat fill to flat, and verify a test applies an identical config to both styles and asserts identical caption content/layout with only the mat fill differing
- [ ] 5.2 Verify `slate`'s keyline and brand mark colour/monochrome variant behave exactly as `gallery`'s do, via the existing gallery tests parametrized (or duplicated) over both styles

## 6. Rendering — studio

- [ ] 6.1 Add manufacturer-aware first-line resolution ("Shot on" + emphasized device model + resolved manufacturer name, manufacturer omitted when unresolved, whole line omitted when there is no device model), and verify unit tests cover: both present, manufacturer missing, device model missing
- [ ] 6.2 Add second-line resolution reusing `captionFields`/`captionPrefix` with plain-space joining (not `classic`'s "·"), and verify a unit test asserts the selected fields appear in canonical order with plain spacing, and that all-fields-missing yields no second line
- [ ] 6.3 Draw `studio`'s two-line centred caption on a flat mat using the section 2 helpers, and verify a rendered fixture shows both lines centred, the first line's device-model run measurably bolder than its surrounding text, and the mat free of any gradient
- [ ] 6.4 Verify the empty-caption case: no device model and no resolvable second-line fields collapses the bottom band to the same width as the other mat edges, consistent with the other styles' empty-caption behavior
- [ ] 6.5 Confirm the macOS Core Text render path draws `studio`'s mixed-weight line upright and correctly positioned, and verify by rendering through `swift test` and asserting text pixels fall inside the bottom band, mirroring how `gallery`'s platform-parity check works

## 7. UI

- [ ] 7.1 Add `slate` and `studio` to the style picker in `WhiteFrameToggleView`, showing `slate` the same rows as `gallery` and `studio` the same field-selection rows as `classic`, and verify each style's rows appear/disappear correctly when switching in a running build
- [ ] 7.2 Mirror any newly-relevant render-affecting fields in `previewIdentifier` for the two new styles (likely none beyond the style enum itself, since no new config fields were added — verify this rather than assume it) and verify the live preview refreshes when switching to/from `slate` or `studio`

## 8. Full-suite verification

- [ ] 8.1 Regenerate snapshot baselines for `slate` and `studio` and verify each by eye against its reference mockup before committing
- [ ] 8.2 Run `cd Packages/WatermarkCore && swift test` and verify the full suite passes, including the section 1 regression check for `classic`/`gallery`
- [ ] 8.3 Build the app (`xcodebuild -scheme WatermarkApp`) and verify it succeeds, then verify on a real device (not the Simulator, per this project's known video-export limitation) that both new styles render correctly end to end for a photo export
