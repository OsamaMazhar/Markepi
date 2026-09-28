## 1. Model and geometry

- [x] 1.1 Add the 12 cases to `FrameStyle` (displayName, summary, capability flags per design D7, `defaultCaptionMillimetres`); verify `swift test` compiles and an old config with `"style":"classic"` plus an unknown style string still decodes (FrameStyleConfigTests)
- [x] 1.2 Extend `FrameGeometry` with per-style edge factors (design D3), rail on the right for `spine`, collapse the band without caption content, and a `cornerRadius` for the hole (D5); verify with geometry tests for a portrait and a landscape source that the edges are proportional and `photoRect` equals the source size

## 2. Photo sampling

- [x] 2.1 Add `PhotoPalette` (design D2) in the package with dominant/deep/warm/edgeAverage over a fixed small bitmap; verify with unit tests on synthetic solid and two-tone images
- [x] 2.2 Add an optional `sourceImage: CGImage?` to `WhiteFrameRenderer.render` (both overloads) and `hasCaptionContent` stays metadata-only; verify existing renderer tests pass unchanged

## 3. Rendering

- [x] 3.1 Mat fills and holes: tone/blend from the palette, flat tones for float/noir/emboss/sunlight/swatch/readout, transparent for backdrop styles; rounded hole punch; verify fill-probe tests (tone follows the photo, blend is graduated) and that hole pixels are fully transparent
- [x] 3.2 Shared row caption (design D6) plus the spine (rotated) and readout (single line, monospaced digits, yellow aperture) variants and swatch dots; verify tests that caption text follows the Include list and that no band is drawn with no content
- [x] 3.3 Core Image surround pass (design D4): ambient blur backdrop, aura blob gradient, glow halo, aura tinted shadow, emboss dual shade, sunlight blinds (on the mat only) and long shadow, float/noir/blend soft shadows; verify tests that photo-rect pixels of a framed export equal the unframed photo (outside rounded corners), for every style
- [x] 3.4 Neutral fallback when `sourceImage` is nil; verify each photo-derived style renders without error and with a caption

## 4. Callers

- [x] 4.1 `WatermarkEngine`: render a ≤512px sample of `watermarkedResult` with the shared CIContext and pass it; verify the engine export test renders a `tone` frame whose border differs for two different photos
- [x] 4.2 Video: sample one frame (AVAssetImageGenerator, ~10% in, preferred transform) in `VideoProcessor` and thread it through `VideoLayerBuilder` to the renderer; nil on failure; verify `swift build` and the VideoLayerBuilder tests pass

## 5. UI

- [x] 5.1 `WhiteFrameToggleView` shows only the Include list, logo switch and size rows for the new styles (flags from 1.1); verify in the app build
- [x] 5.2 Thumbnail strip renders all 16 styles with one shared palette sample; confirm `previewKey` needs no new fields (no new config fields added); verify in the app build

## 6. Verification

- [x] 6.1 `cd Packages/MarkepiCore && swift test` passes (632/632 with `--skip "ExtensionSnapshotTests|C2PARealSigningIntegrationTests"`; those two hang on a clean HEAD too — pre-existing, environmental)
- [x] 6.2 `bash scripts/build-gate.sh` passes for Markepi and ShareExtension
- [x] 6.3 (CLI render of all 16 styles matches `reference/`; installed on the iPhone 15 Pro Max and checked there by Osama) Render the reference photo (`~/Downloads/IMG_1929.heic`) in all 16 styles with the `markepi` CLI and compare against `reference/`; install on the iPhone and check the live preview and the strip there
