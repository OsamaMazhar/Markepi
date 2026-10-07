## 0. Look approval (gate)

- [x] 0.1 Prototype every recipe in a standalone macOS Core Image script and render a contact sheet over licence-clean reference photos; verified by Osama reviewing `reference/01–04` (round 1)
- [x] 0.2 Round 1 approved as-is ("now implement all these"); the recipe numbers live in `PhotoLookRenderer.Recipe.base` (the Swift source is the record, no separate recipes.json); "Portrait 400" renamed "Pastel 400" (too close to a film trademark, caught by the catalogue test)

## 1. Model & persistence

- [x] 1.1 Add `PhotoLook` (22 looks + original, `family`, `isFree`, `isMonochrome`, lenient decode → `.original`) and `PhotoLookSettings` (`intensity`, `tone`, `color`, `grain`, `isDefaultTuning`, `previewKey`, clamped decode); verified by `PhotoLookTests.catalogue` and `.decoding`
- [x] 1.2 Add `photoLook` to `WatermarkConfiguration` (CodingKeys, `decodeIfPresent ?? .init()`, encode); verified by `PhotoLookTests.legacyConfig` (pre-Looks JSON → Original, round trip keeps the look)

## 2. Renderer

- [x] 2.1 `Recipe` + cube baking (33³, gamma-encoded Display P3) with an LRU cache of 6; verified identity cube max error < 1/255 (`identityCube`) and every recipe bakes in < 250 ms in a debug test build (`recipesInRange`)
- [x] 2.2 Port the approved recipes; verified every look renders a gradient chart without NaN or out-of-range values (`recipesInRange`)
- [x] 2.3 `PhotoLookRenderer.apply` (cube → pad → sky → halation → grain → intensity mix); verified Original and 0% return the input instance and 50% sits halfway (`identityPaths`)
- [x] 2.4 Tone/Color pad (midtone tone curve + red/blue warmth matrix); verified centre is a no-op, warmer raises R−B, brighter lifts mids (`pad`)
- [x] 2.5 Grain: zero-mean, short-edge-relative, opaque add/subtract blend so alpha stays 1; verified bit-identical repeats, unchanged mean, and similar σ at 512 px vs 2048 px shrunk (`grain`)
- [x] 2.6 Halation for Tungsten 800 (linear luminance ramp, not a spline); verified a red-dominant glow beside a white dot, untouched dark corners and mid-gray (`halation`)
- [x] 2.7 B&W looks stay RGB; verified neutral output, RGB colour-space model and a red text layer staying red over Muted B&W (`monochromeStaysRGB`)

## 3. Scene masks

- [x] 3.1 Embedded Portrait-mode skin matte minus hair matte, oriented; verified with a synthetic skin-matte HEIC (`embeddedSkinMatte`)
- [x] 3.2 Vision fallback: person instance mask (→ person segmentation) × skin-colour key cube, feathered, on a 1024-px decode; verified on the CC0 portrait fixture: face > 0.5, background < 0.1 (`visionSkinMask`)
- [x] 3.3 Per-source cache (path + size + mtime, 8 entries), nil without a person; verified a flat gray photo gets no masks and a second call hits the cache (`noMasks`, `visionSkinMask`)
- [x] 3.4 Undertones: global vs skin cube blended through the skin mask; verified masked half shifts ≥ 3× the unmasked half and no mask = global only (`undertoneUsesSkinMask`)
- [x] 3.5 Sky: embedded sky matte, else (no public sky segmentation in iOS) Vision's scene classifier must report "sky", then a sky-colour key weighted to the top of the frame, minus people; per-look sky saturation/exposure; verified the treatment reaches only the sky mask (`skyUsesSkyMask`) and visually on the windmill/Nyhavn/night sheet

## 4. Engine integration

- [x] 4.1 Apply the look at the top of `buildFilterGraph` for both `process` and `renderPreview`, masks fetched only for looks that read them; verified frame-mat pixels are identical with and without a look while photo pixels differ (`lookNeverTouchesFrame`)
- [x] 4.2 Metadata and HDR survival; verified an HDR HEIC with GPS/date/model exported under Cozy, Silver 400, Amber and Tungsten 800 keeps GPS, DateTimeOriginal, Model, colour profile and the gain map (`metadataAndHDRSurvive`)
- [x] 4.3 HDR is never traded away: the gain map is always re-attached as today, ISO multi-channel maps included (decision after "we don't want to compromise on hdr"); covered by 4.2
- [x] 4.4 `ExportPolicy.allowsLook` + downgrade in `process`; verified free Chrome 100 and free tuned Vibrant equal Original, free default Vibrant stays styled (`freeTierDowngrade`)
- [x] 4.5 Live Photo with an active (allowed) look exports a still from `processLivePhoto`; verified `livePhotoVideoURL == nil`, free-tier downgrade keeps it live (`livePhotoStill`)
- [x] 4.6 Video ignores the look: `VideoProcessor`/`VideoLayerBuilder` never read `photoLook` (grep), and the editor's video preview strips it
- [x] 4.7 Batch styles every photo with its own masks; verified both items export and the mask cache keys differ (`batch`)
- [x] 4.8 `swift test --skip ExtensionSnapshotTests --skip C2PARealSigningIntegrationTests` → 665 tests in 81 suites pass

## 5. App UI

- [x] 5.1 `EditorTool.looks` ("Looks", `camera.filters`, first in the dock) and its `ToolPanelView` case; `bash scripts/build-gate.sh` passes
- [x] 5.2 Looks panel in `ToolPanelView.swift` (App target, no new pbxproj entries), redesigned to match the editor after review: the app's glass `MarkepiPillBar` (now generic) for Moods / Undertones / Film with icons, a look strip using the frame-style strip's cell (photo-shaped, square corners, 3-pt accent ring, Pro crown), an Adjust card shown once a look is chosen (Intensity; the 2-D Tone & Warmth pad, kept at Osama's request and modernised: dot grid, cool→warm field, edge icons, knob grows while held, snap-to-centre tick, double-tap reset, live readouts, VoiceOver sees two sliders; Grain for film; Reset Adjustments), a Pro note with Unlock, the Live Photo note and the video empty state; builds via the gate
- [x] 5.2a Frame-style strip: hidden (and not re-rendered) while Looks is open; otherwise a refresh renders all cells first and swaps them in one crossfade, never cell by cell; a new photo still fills left to right; builds via the gate
- [ ] 5.3 Look thumbnails per family (240 px, keyed by photo + family) — implemented; verify on device that the strip fills left to right without blocking the editor
- [ ] 5.4 `photoLook.previewKey` in `previewIdentifier` — implemented; verify on device that every control change refreshes the preview
- [ ] 5.5 Hold to compare shows the unstyled render with frame and watermarks — implemented (`unstyledPreviewImage`); verify on device
- [ ] 5.6 Comparison sheet chips ("<Look> look" / "Original look") — implemented, and the Free card renders the downgraded edit through the engine; verify on device as a free user
- [ ] 5.7 Landscape side-rail and portrait dock with the extra Looks tool; verify on device in both orientations

## 6. Verification & ship

- [x] 6.1 `bash scripts/build-gate.sh` (PASSED) and the package suite (4.8) both exit 0
- [ ] 6.2 On-device pass (installed on Osama's iPhone 15 Pro Max, 2026-10-06): every look exports, metadata checked with `exiftool`, HDR visible in Photos for a Pro export, no photo-library writes
- [x] 6.3 No "Photographic Styles" wording and no film/camera brand names in App, ShareExtension or MarkepiCore sources (grep: only the word "portrait" as orientation)
