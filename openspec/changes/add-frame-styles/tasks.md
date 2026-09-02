## 1. Brand mark assets

- [ ] 1.1 Define and document the drop convention for supplied artwork — one file per brand and variant, named by brand key and variant — in `Resources/Logos/README.md`, and verify it lists the brand keys the registry expects so the sourcing work has an unambiguous target
- [ ] 1.2 Add a repeatable conversion step from a supplied vector to a single-page PDF, and verify with `CGPDFDocument` that a converted file opens, reports one page, and has a non-zero media box
- [ ] 1.3 Add `Resources/Logos/` to the WatermarkCore target's `resources:` in Package.swift, and verify `swift build` succeeds and `Bundle.module.url(forResource:)` resolves a converted mark at runtime
- [ ] 1.4 Convert and register each brand's artwork as it is supplied, recording source and licence per file in the README, and verify each converted mark opens and draws
- [ ] 1.5 Verify a brand whose artwork has not been supplied yet resolves to no mark and no divider, so a partly-populated registry is a valid state and implementation never blocks on sourcing

## 2. Config model

- [ ] 2.1 Add `FrameStyle` (`.classic`, `.gallery`, defaulting to `.classic`) to WhiteFrameConfig.swift and verify a unit test asserts the default
- [ ] 2.2 Add `CaptionSlot` (`.field(CaptionField)`, `.text(String)`, `.empty`) with the tagged single-value Codable form from design.md — D3, and verify a round-trip test covers all three cases
- [ ] 2.3 Add a `LogoVariant` preference (colour or monochrome) and verify a unit test asserts its default and that it round-trips through Codable
- [ ] 2.4 Add the four slot properties, `keylineEnabled` (default false) and the variant preference to `WhiteFrameConfig`, with gallery defaults reproducing the reference (camera model / date / handle text / lens details), and verify a test asserts each default. The brand itself is NOT a config field — it is resolved from metadata
- [ ] 2.5 Extend the hand-written `init(from:)`/`encode(to:)` using `decodeIfPresent` for every new key, and verify a test decodes a JSON blob containing only the pre-existing keys and gets `.classic` with the keyline off and the default variant

## 3. Geometry — mat outside the photo

- [ ] 3.1 Add a single source of truth for framed geometry (mat insets per edge for a given style, config and source size, plus the resulting framed size rounded up to even in both dimensions — D7), and verify unit tests cover classic vs gallery insets, both orientations, and the even-rounding
- [ ] 3.2 Change `WhiteFrameRenderer.render` to return a mat image at the framed size with a transparent hole at the photo rect, and verify a test asserts the returned extent equals the framed size and that the hole is fully transparent while the mat is opaque
- [ ] 3.3 Update `WatermarkEngine.buildFilterGraph` to translate the composited photo into the hole and composite the mat over it, and verify a test asserts the output extent is the framed size and that a known source pixel is unchanged at its translated position
- [ ] 3.4 Delete the `frameInset` watermark-positioning workaround in `WatermarkEngine.buildFilterGraph` and verify a test asserts a corner watermark lands at the same position on the photo with and without a frame
- [ ] 3.5 Update the render call and `graphMetadata` PixelWidth/PixelHeight to report the framed size, and verify an exported file's recorded dimensions match the framed size

## 4. Brand resolution

- [ ] 4.1 Add the brand registry mapping a normalised manufacturer key to that brand's available mark files, and verify a test asserts a registered brand resolves and an unregistered one resolves to nothing
- [ ] 4.2 Implement manufacturer normalisation — case-folding, trimming, stripping trailing corporate suffixes — and verify a test covers the real-world spellings for each shipped brand, including a camera body writing its maker in capitals with a corporate suffix
- [ ] 4.3 Implement variant selection: use the user's preference when the resolved brand ships both, otherwise the single available mark, and verify tests cover both-available, one-available, and no-preference-set
- [ ] 4.4 Verify end to end that a photo's metadata drives the mark: a fixture from each shipped brand resolves to that brand's mark, and a fixture with no manufacturer resolves to none

## 5. Renderer — caption resolution and drawing

- [ ] 5.1 Introduce the resolved caption model and move metadata lookup, token substitution and empty-slot elision ahead of the platform branch — D4, and verify a test resolves the four slots from a metadata dictionary including the missing-field case
- [ ] 5.2 Change `drawFrame` to take the resolved model instead of `attributionText: String?`, keeping classic's centred single line unchanged apart from the new geometry, and verify the existing classic renderer tests pass
- [ ] 5.3 Draw the gallery two-column caption — left group left-aligned, right group right-aligned, primary line heavier and darker, secondary lighter — and verify a test asserts the left group's left edge and the right group's right edge sit within the mat, and that primary and secondary use different weights
- [ ] 5.4 Apply per-group auto-shrink so a long right-hand string does not shrink the left group, and verify a test with an overlong lens string asserts the left group's font size is unchanged and neither group overflows the band
- [ ] 5.5 Draw the resolved mark and its vertical divider before the right group, vertically centred on that group, omitting both when metadata resolved no mark, and verify tests cover the resolved case, the no-mark case, and the vertical-centre alignment
- [ ] 5.6 Draw the optional keyline between the photo rect and the mat for both styles, scaled to the source's shorter dimension, and verify a test asserts the stroke is present on all four edges when enabled, absent when disabled, and covers no more of the photo than its own thickness
- [ ] 5.7 Confirm the macOS Core Text path renders the gallery caption upright and correctly positioned (its baseline/text-matrix handling still applies per line), and verify by rendering a gallery frame through `swift test` on macOS and asserting text pixels fall inside the bottom band

## 6. Video parity

- [ ] 6.1 Grow `videoComposition.renderSize` to the framed size and inset the video layer to the photo rect in `VideoLayerBuilder`/`VideoProcessor`, reusing the task 3.1 geometry, and verify a test asserts the built layer tree's video layer frame equals the photo rect within the framed parent
- [ ] 6.2 Delete the `frameInset` workaround in `VideoLayerBuilder` to match task 3.4, and verify a test asserts photo and video place the same corner watermark at the same relative position
- [ ] 6.3 Verify a real device video export with each style: the export completes, output dimensions are the framed size, and source metadata is preserved (Simulator cannot be used — its CoreMedia XPC fault is unrelated and pre-existing)

## 7. UI

- [ ] 7.1 Add the style picker to `WhiteFrameToggleView` and show each style's rows conditionally beneath it, and verify both styles' rows appear and disappear when switching in a running build
- [ ] 7.2 Add the four slot pickers (metadata field or free text) with the reference defaults, and verify changing a slot updates only that line in the live preview
- [ ] 7.3 Add the keyline toggle and the colour/monochrome variant control, showing the variant control only when the resolved brand ships both, and verify both take effect in the live preview and that the variant control is absent for a single-variant brand
- [ ] 7.4 Mirror every new render-affecting field in `previewIdentifier` and verify the preview refreshes on a change to each new field individually — a stale preview here is the known failure mode

## 8. Tests and rebaseline

- [ ] 8.1 Regenerate the frame snapshot baselines under `Tests/WatermarkCoreTests/__Snapshots__` and verify each regenerated image by eye against the reference before committing, so a real regression is not rebaselined away
- [ ] 8.2 Update `WhiteFrameRendererTests`, `CaptionBuilderTests` and `MediaPipelineRegressionTests` for the framed extent, and verify the full `swift test` suite passes
- [ ] 8.3 Add a gallery-style regression test rendering the reference configuration end to end, and verify it asserts framed extent, both caption groups, the metadata-resolved mark and the keyline together
- [ ] 8.4 Build the app and share extension for iOS and verify `xcodebuild -scheme WatermarkApp` succeeds, since the package is shared with both targets
