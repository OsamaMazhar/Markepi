## 0. Look approval (gate — nothing below starts until Osama approves the samples)

- [ ] 0.1 Prototype every recipe (D1, D2, D4, D6) in a standalone macOS Core Image script and render a contact sheet over licence-clean reference photos (portraits of varied skin tones, landscape, night, high-key); verify by Osama reviewing the sheet
- [ ] 0.2 Retune recipes from feedback until each look is approved; record the final recipe numbers in the change folder (`reference/recipes.json`) and verify the sheet re-renders from that file

## 1. Model & persistence

- [ ] 1.1 Add `PhotoStyle` (22 looks + original, `family`, `isFree`, lenient decode → `.original`) and `PhotoStyleSettings` (`intensity`, `tone`, `color`, `grain`, `isDefaultTuning`, `previewKey`) in MarkepiCore/Models; verify with `PhotoStyleModelTests` (round-trip, unknown id → original, missing key → defaults)
- [ ] 1.2 Add `photoStyle` to `WatermarkConfiguration` (CodingKeys, `decodeIfPresent ?? .init()`, encode) and to `WatermarkConfigurable`; verify a pre-styles config/template JSON fixture decodes to `.original`

## 2. Renderer

- [ ] 2.1 Implement `StyleRecipe` + cube baking (33³, gamma-encoded Display P3) with an LRU cache of 6; verify the identity recipe bakes an identity cube (max error < 1/255) and each recipe bakes in < 15 ms on macOS
- [ ] 2.2 Port the approved recipes from `reference/recipes.json` into Swift; verify a test renders each look on a gray ramp + colour chart without NaN/out-of-range values
- [ ] 2.3 Implement `PhotoStyleRenderer.apply` (cube → pad → film extras → mask blend → intensity mix); verify `.original` returns the input instance untouched and intensity 0 is pixel-identical to the input
- [ ] 2.4 Implement the Tone/Color pad (`CIToneCurve` + `CITemperatureAndTint`); verify pad centre is a no-op and +color moves a neutral gray toward amber (R−B increases)
- [ ] 2.5 Implement grain (D6) with full-resolution-relative scale; verify two renders are bit-identical and grain variance at a 512-px preview matches the 4096-px render within 10% after downsampling
- [ ] 2.6 Implement halation for Tungsten 800; verify a bright dot on black gains red-dominant pixels around it and corner pixels stay black
- [ ] 2.7 Make B&W looks stay RGB (D5); verify the rendered output colour-space model is `.rgb` and a red logo composited on top keeps R ≫ G,B

## 3. Skin mask

- [ ] 3.1 Implement `SkinMaskProvider` embedded-matte path (skin matte aux data + orientation); verify with a Portrait HEIC fixture carrying a skin matte that the mask is non-empty and aligned (sample a known skin pixel)
- [ ] 3.2 Implement the Vision path (`VNGeneratePersonInstanceMaskRequest`, fallback `VNGeneratePersonSegmentationRequest`) × YCbCr skin key, feathered, at 1024 px; verify on a portrait fixture that the face region averages > 0.5 and the background < 0.1
- [ ] 3.3 Add the per-source cache (URL + size + mtime, 8 entries) and nil-on-no-person; verify a landscape fixture returns nil and a second call hits the cache
- [ ] 3.4 Implement undertone rendering (global vs skin cube blended by mask); verify with a synthetic half-masked image that the masked half shifts ≥ 3× the unmasked half

## 4. Engine integration

- [ ] 4.1 Apply the style at the top of `buildFilterGraph`, passing `renderScale` and the mask, for both `process` and `renderPreview`; verify a test that a framed export's frame mat pixels are identical with and without a look while photo pixels differ
- [ ] 4.2 Verify metadata/HDR survival: export an HDR HEIC fixture with GPS under Cozy and assert GPS, DateTimeOriginal, Model, ICC and gain-map aux data are present (extend `MediaPipelineRegressionTests`)
- [ ] 4.3 Collapse 3-channel ISO gain maps to luminance for B&W looks; verify with the ISO gain-map fixture that the written map's channels are equal
- [ ] 4.4 Add `ExportPolicy.allowsStyle` and the downgrade in `process`; verify in `FreeTierExportTests` that a free export of Chrome 100 equals a free export of Original, and that free Vibrant (default tuning) stays styled
- [ ] 4.5 Live Photo: export a still only when a look is active; verify in `LivePhotoProcessorTests` that `livePhotoVideoURL` is nil with a look and non-nil with Original
- [ ] 4.6 Video ignores `photoStyle`; verify a `VideoProcessor` test that the output is unchanged with a look set
- [ ] 4.7 Batch uses each photo's own mask; verify in `BatchProcessorTests` that two different fixtures are each styled and the mask cache holds two keys
- [ ] 4.8 Run `cd Packages/MarkepiCore && swift test --skip ExtensionSnapshotTests --skip C2PARealSigningIntegrationTests` under a timeout and verify it passes

## 5. App UI

- [ ] 5.1 Add `EditorTool.style` (first in the dock, `camera.filters`) and its `ToolPanelView` case; verify `bash scripts/build-gate.sh` passes
- [ ] 5.2 Build `PhotoStylePanelView` in MarkepiCore/UI (family pills, look strip, Intensity, 2-D pad with double-tap reset, Grain for film, Pro markers, still-photo note for Live Photos, disabled state for video); verify with an Xcode Preview of each family and state
- [ ] 5.3 Generate per-family look thumbnails lazily from the current photo (360 px, keyed by photo + look); verify on device that the strip fills left-to-right without blocking the editor
- [ ] 5.4 Add `photoStyle.previewKey` + mask-ready flag to `previewIdentifier`; verify on device that every control change refreshes the preview and that an undertone updates once the mask lands
- [ ] 5.5 Hold to compare on `PreviewView` (cached Original render, VoiceOver "Show original" action); verify on device that press-and-hold shows the unstyled photo with frame and watermarks intact
- [ ] 5.6 Comparison sheet: "Pro look" / "Original" chips and a downgraded Free render when a Pro look is active; verify on device as a free user (DEBUG Force Premium off) and that Pro users see no prompt
- [ ] 5.7 Landscape side-rail and keyboard-safe layout check for the Style panel; verify on device in portrait and landscape that the panel follows the existing rail rules

## 6. Verification & ship

- [ ] 6.1 Run `bash scripts/build-gate.sh` and the package suite (4.8); verify both exit 0
- [ ] 6.2 On-device pass on an older iPhone (≤ 15) and Osama's iPhone: every look exports, metadata checked with `exiftool`, HDR visible in Photos for a Pro export, no photo-library writes; record results in the change folder
- [ ] 6.3 Check that the paywall/feature copy says "Styles" (never "Photographic Styles") and that no look names a film or camera brand; verify by grepping the App and MarkepiCore sources for brand names
