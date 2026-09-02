## 1. Logo assets

- [ ] 1.1 Download the three official SVGs (rainbow, black, white) from the Wikimedia Commons URLs in design.md — D5, and verify each file is non-empty and parses as XML
- [ ] 1.2 Convert each SVG to a single-page PDF preserving its vector paths, and verify with `CGPDFDocument` that each opens and reports one page with a non-zero media box
- [ ] 1.3 Add `Resources/Logos/` to the WatermarkCore target's `resources:` in Package.swift, and verify `swift build` succeeds and `Bundle.module.url(forResource:)` resolves all three at runtime
- [ ] 1.4 Record the source URL, licence and trademark status of each file in a `Resources/Logos/README.md`, and verify it names all three files

## 2. Config model

- [ ] 2.1 Add `FrameStyle` (`.classic`, `.gallery`, defaulting to `.classic`) to WhiteFrameConfig.swift and verify a unit test asserts the default
- [ ] 2.2 Add `CaptionSlot` (`.field(CaptionField)`, `.text(String)`, `.empty`) with the tagged single-value Codable form from design.md — D3, and verify a round-trip test covers all three cases
- [ ] 2.3 Add `FrameLogo` (`.none` default, plus the three Apple variants) and verify a unit test asserts `.none` is the default
- [ ] 2.4 Add the four slot properties, `keylineEnabled` (default false) and `logo` to `WhiteFrameConfig`, with gallery defaults reproducing the reference (camera model / date / handle text / lens details), and verify a test asserts each default
- [ ] 2.5 Extend the hand-written `init(from:)`/`encode(to:)` using `decodeIfPresent` for every new key, and verify a test decodes a JSON blob containing only the pre-existing keys and gets `.classic`, keyline off, logo none

## 3. Geometry — mat outside the photo

- [ ] 3.1 Add a single source of truth for framed geometry (mat insets per edge for a given style, config and source size, plus the resulting framed size rounded up to even in both dimensions — D7), and verify unit tests cover classic vs gallery insets, both orientations, and the even-rounding
- [ ] 3.2 Change `WhiteFrameRenderer.render` to return a mat image at the framed size with a transparent hole at the photo rect, and verify a test asserts the returned extent equals the framed size and that the hole is fully transparent while the mat is opaque
- [ ] 3.3 Update `WatermarkEngine.buildFilterGraph` to translate the composited photo into the hole and composite the mat over it, and verify a test asserts the output extent is the framed size and that a known source pixel is unchanged at its translated position
- [ ] 3.4 Delete the `frameInset` watermark-positioning workaround in `WatermarkEngine.buildFilterGraph` and verify a test asserts a corner watermark lands at the same position on the photo with and without a frame
- [ ] 3.5 Update the render call and `graphMetadata` PixelWidth/PixelHeight to report the framed size, and verify an exported file's recorded dimensions match the framed size

## 4. Renderer — caption resolution and drawing

- [ ] 4.1 Introduce the resolved caption model and move metadata lookup, token substitution and empty-slot elision ahead of the platform branch — D4, and verify a test resolves the four slots from a metadata dictionary including the missing-field case
- [ ] 4.2 Change `drawFrame` to take the resolved model instead of `attributionText: String?`, keeping classic's centred single line unchanged apart from the new geometry, and verify the existing classic renderer tests pass
- [ ] 4.3 Draw the gallery two-column caption — left group left-aligned, right group right-aligned, primary line heavier and darker, secondary lighter — and verify a test asserts the left group's left edge and the right group's right edge sit within the mat, and that primary and secondary use different weights
- [ ] 4.4 Apply per-group auto-shrink so a long right-hand string does not shrink the left group, and verify a test with an overlong lens string asserts the left group's font size is unchanged and neither group overflows the band
- [ ] 4.5 Draw the logo and its vertical divider before the right group, vertically centred on that group, omitting both when the logo is `.none`, and verify tests cover the `.none` case and the vertical-centre alignment
- [ ] 4.6 Draw the optional keyline between the photo rect and the mat for both styles, scaled to the source's shorter dimension, and verify a test asserts the stroke is present on all four edges when enabled, absent when disabled, and covers no more of the photo than its own thickness
- [ ] 4.7 Confirm the macOS Core Text path renders the gallery caption upright and correctly positioned (its baseline/text-matrix handling still applies per line), and verify by rendering a gallery frame through `swift test` on macOS and asserting text pixels fall inside the bottom band

## 5. Video parity

- [ ] 5.1 Grow `videoComposition.renderSize` to the framed size and inset the video layer to the photo rect in `VideoLayerBuilder`/`VideoProcessor`, reusing the task 3.1 geometry, and verify a test asserts the built layer tree's video layer frame equals the photo rect within the framed parent
- [ ] 5.2 Delete the `frameInset` workaround in `VideoLayerBuilder` to match task 3.4, and verify a test asserts photo and video place the same corner watermark at the same relative position
- [ ] 5.3 Verify a real device video export with each style: the export completes, output dimensions are the framed size, and source metadata is preserved (Simulator cannot be used — its CoreMedia XPC fault is unrelated and pre-existing)

## 6. UI

- [ ] 6.1 Add the style picker to `WhiteFrameToggleView` and show each style's rows conditionally beneath it, and verify both styles' rows appear and disappear when switching in a running build
- [ ] 6.2 Add the four slot pickers (metadata field or free text) with the reference defaults, and verify changing a slot updates only that line in the live preview
- [ ] 6.3 Add the keyline toggle and the logo picker, and verify both take effect in the live preview and that the logo picker offers none
- [ ] 6.4 Mirror every new render-affecting field in `previewIdentifier` and verify the preview refreshes on a change to each new field individually — a stale preview here is the known failure mode

## 7. Tests and rebaseline

- [ ] 7.1 Regenerate the frame snapshot baselines under `Tests/WatermarkCoreTests/__Snapshots__` and verify each regenerated image by eye against the reference before committing, so a real regression is not rebaselined away
- [ ] 7.2 Update `WhiteFrameRendererTests`, `CaptionBuilderTests` and `MediaPipelineRegressionTests` for the framed extent, and verify the full `swift test` suite passes
- [ ] 7.3 Add a gallery-style regression test rendering the reference configuration end to end, and verify it asserts framed extent, both caption groups, the logo and the keyline together
- [ ] 7.4 Build the app and share extension for iOS and verify `xcodebuild -scheme WatermarkApp` succeeds, since the package is shared with both targets
