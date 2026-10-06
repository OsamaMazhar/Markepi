## Context

See proposal.md (Why) and specs/photo-styles/spec.md (requirements). This design covers how the looks fit the existing pipeline.

Current pipeline facts that shape this design:
- **One filter graph, two entry points.** `WatermarkEngine.buildFilterGraph(base:config:metadata:renderScale:brandMark:layout:)` is shared by the export path (`process`, full-resolution `ImageLoader` decode, orientation-normalised) and the live preview (`renderPreview`, a `CGImageSourceCreateThumbnailAtIndex` decode at screen size). Anything inserted at the top of `buildFilterGraph` reaches both, along with batch (`BatchProcessor`) and the Live Photo still (`LivePhotoProcessor` → `process`).
- **HDR is a passthrough.** The photo is rendered SDR (RGBAh in `CIContextProvider`'s extended working space). The source gain map (`kCGImageAuxiliaryDataTypeHDRGainMap` or ISO) is realigned by `GainMapProcessor.aligned` and re-attached by `ImageWriter`. It is never recomputed.
- **Metadata** is carried by `ImageWriter` from `loaded.metadata` and is independent of the pixels.
- **Free tier** is `ExportPolicy(tier:)`. The comparison sheet is built in `WatermarkViewModel.ExportComparison`.
- **Preview refresh** is keyed on `WatermarkViewModel.previewIdentifier` (memory: every render-affecting field must be mirrored there).
- **App target** uses a classic pbxproj (memory: a new App/*.swift file needs project entries). The MarkepiCore package compiles new files automatically.
- **Known pitfalls in this codebase:** achromatic CIImages decay to a gray colour space and desaturate composites; `expandToHDR` desaturates on some sources (the loader deliberately avoids it); bitmap row 0 is the image top in render tests.

## Goals / Non-Goals

**Goals:**
- One renderer, `PhotoStyleRenderer.apply(_:to:skinMask:renderScale:) -> CIImage`. It is pure CIImage, so it runs anywhere `buildFilterGraph` runs.
- Looks are defined as data (recipes), so adding the 23rd look means adding one recipe, not new code.
- Original costs nothing: it returns the input image untouched, with no filter nodes.
- Preview and export match, including grain and masks.

**Non-Goals:**
- Video styling (follow-up change; needs a CI-filter video composition or a second pass instead of `AVVideoCompositionCoreAnimationTool`).
- Reading or reproducing Apple's private Smart Style data, or detecting that an iPhone 16+ photo was already styled. Original is always the default, so stacking only happens if the user chooses it.
- Per-person undertones in group shots (Apple doesn't offer this either). Sky, hair or clothing-specific adjustments.
- Recomputing the HDR gain map from the styled image.
- User-imported LUTs (.cube). The recipe format allows it later, but it is not built now.

## Decisions

### D1. Recipes, not bundled LUT files
Each look is a `StyleRecipe` value: an RGB tone curve (control points), optional per-channel curves, a 3×3 colour-mix matrix (for B&W channel mixing and crossover), saturation and vibrance, split toning (shadow and highlight hue/amount), fade (lifted blacks), and film extras (grain amount and size, halation strength). On first use the recipe is baked into a 33³ cube, about 36k RGBA float entries (~575 KB), and fed to `CIColorCubeWithColorSpace`, with the cube defined in gamma-encoded Display P3. Baked cubes are cached in a small dictionary keyed by look id.
- *Why:* no third-party LUT packs, so no CC-BY-SA or trademark exposure. Recipes are diffable and testable (the identity recipe must give an identity cube). One `CIColorCube` node is cheaper than a chain of curve filters. 33³ is the industry-standard cube size.
- *Alternatives:* free film-emulation HaldCLUT packs, rejected for share-alike licences and trademarked names. A chain of `CIToneCurve`/`CIColorControls` per look, rejected because it is slower and can't express channel crossover.
- Recipes are authored and tuned with `tools/styles/` (D9). The Swift source holds the final numbers.

### D2. Live controls are filters after the cube, not a re-bake
The Tone/Color pad maps to a `CIToneCurve` (tone: a midpoint lift or drop with protected endpoints) plus `CITemperatureAndTint` (color: about ±1500 K around neutral). Intensity mixes the styled image with the input via `CIFilter.mix()` (`amount` = intensity). Undertone masking uses `CIBlendWithMask` (D4).
- *Why:* dragging the pad must not re-bake a 36k-entry cube per frame. These filters are trivial on the GPU.
- Order inside the renderer: cube → pad → film extras → mask blend (undertones) → intensity mix against the input.

### D3. Where it sits in the graph
`buildFilterGraph` calls `PhotoStyleRenderer.apply` on `normalized` before anything else. The result becomes the base that the frame, layers, date stamp and brand mark are composited onto. This gives the spec's "Rendering order" requirement for free. `frameSample(of:)` and photo-derived frames read the styled photo, and watermark layers are untouched.
- `renderScale` is passed through, because grain size and halation radius are defined as a fraction of the *full-resolution* short edge (D6).
- Hold to compare re-renders the preview with `style = .original` through the same path. It is a cached second `PreviewRender`, produced lazily on the first press, so it is fast and still shows frame and watermarks.

### D4. Skin mask: embedded matte → Vision → none
New `SkinMaskProvider` (actor, in MarkepiCore/Processing):
1. **Embedded matte:** `CGImageSourceCopyAuxiliaryDataInfoAtIndex(..., kCGImageAuxiliaryDataTypeSemanticSegmentationSkinMatte)` → `CIImage(cvPixelBuffer:)` via `AVSemanticSegmentationMatte` (iPhone XS+ Portrait photos). Orientation is applied with the source's EXIF orientation, the same way `GainMapProcessor` treats the gain map.
2. **Vision:** `VNGeneratePersonInstanceMaskRequest` (iOS 17+) on a 1024-px long-edge decode gives the person matte. Within that matte, a skin-colour key is baked as a colour cube whose output is skin likelihood (hue band around 22°, mid saturation, not too dark), so it needs no custom kernel. The prototype in `reference/proto.swift` validated this. The two are multiplied, then feathered with `CIGaussianBlur` at 0.4% of the short edge.
3. **None:** returns nil. The undertone then applies only its global component.
- Both preview and export use the **same** mask, computed once at 1024 px from the source file and scaled to the target extent. That is what gives preview/export parity. The cache key is source URL + file size + modification date, and the cache holds about 8 entries (batch-friendly).
- Each undertone recipe has a `skin` strength and a `global` strength. Rendering is `blend(styled(global), styled(skin), mask)`, which costs two cube passes for undertones only.
- *Alternatives:* `VNGeneratePersonSegmentationRequest`, the fallback if the instance-mask request fails (simpler, single matte). A custom Core ML skin segmenter was rejected: no proven, licence-clean model, and it adds a dependency (memory: prefer proven, ready-made solutions).
- Mask work runs off the main actor. A pending mask never blocks the preview: the look renders global-only first and then refreshes when the mask lands (the mask-ready flag joins `previewIdentifier`).

### D5. Colour-space and HDR safety
- The cube runs in gamma-encoded Display P3 via `CIColorCubeWithColorSpace`, whatever the working space is. Output stays in the existing RGB output colour space chosen by `process`.
- B&W looks are implemented as an RGB colour-mix matrix with equal output channels. The result is then forced to stay RGB: explicit `CIImage.matchedToWorkingSpace` from Display P3 plus the existing RGB output-space selection. This avoids the known achromatic-to-gray-colour-space pitfall. A test asserts an RGB output model.
- Gain map: unchanged and re-attached as today. For B&W looks with a 3-channel ISO gain map, the map is collapsed to luminance before writing, so highlights don't regain colour on HDR displays. Apple's single-channel map needs nothing.
- Values are clamped to [0,1] after the cube. The SDR base must not carry extended values into a file whose gain map assumes SDR.

### D6. Grain and halation
- **Grain:** `CIRandomGenerator` (deterministic, fixed noise field) → scale so one grain cell is `grainSize × shortEdgeFull / 1500` px (× `renderScale` in the preview) → slight blur → typed `CIFilter.colorMatrix()` to *zero-mean* monochrome noise (negative values are fine in the float working space) → `CIAdditionCompositing` → `CIColorClamp`. Deterministic by construction. Round 1 showed that soft-light grain shifts the mean and blows up on out-of-range input, so it is rejected.
- **Halation (Tungsten 800):** highlight extraction with `CIColorMatrix` and a threshold via `CIToneCurve` → `CIGaussianBlur` with radius 1.2% of the short edge → tint to red-orange → `CIAdditionCompositing` at the recipe's strength.

### D7. Model and persistence
```swift
public enum PhotoStyle: String, Codable, CaseIterable, Sendable {  // lenient init(from:) → .original on unknown
    case original
    case vibrant, natural, luminous, dramatic, quiet, cozy, ethereal, mutedBW, starkBW
    case neutral, coolRose, roseGold, gold, amber
    case portrait400, golden200, chrome100, velvet50, classicNeg, tungsten800, silver400, faded
    var family: Family { … }         // .original / .mood / .undertone / .film
    var isFree: Bool { … }           // original, vibrant, natural, neutral
}
public struct PhotoStyleSettings: Codable, Sendable, Equatable {
    var style: PhotoStyle = .original
    var intensity: Double = 1        // 0…1
    var tone: Double = 0             // −1…1
    var color: Double = 0            // −1…1
    var grain: Double? = nil         // nil = recipe default; film only
    var isDefaultTuning: Bool { … }  // intensity 1, tone 0, color 0, grain nil
    var previewKey: String { … }     // mirrors every field, like WhiteFrameConfig.previewKey
}
```
- `WatermarkConfiguration.photoStyle: PhotoStyleSettings` uses `decodeIfPresent ?? .init()`. Templates and App Group config sync pick it up with no extra work.
- `previewIdentifier` appends `photoStyle.previewKey` and the mask-ready flag.

### D8. Free tier
`ExportPolicy` gains `allowsStyle(_ settings: PhotoStyleSettings) -> Bool` (free: `style.isFree && settings.isDefaultTuning`). `WatermarkEngine.process` replaces disallowed settings with `.init()` before building the graph, in the same place the policy already caps size and drops the gain map. The engine therefore enforces the rule, not the UI. `ExportComparison` sets a "Pro look" spec chip on the Pro card and "Original" on the Free card when the look would be downgraded, and the comparison render for the Free card uses the downgraded config. Previews are never gated.

### D9. Tuning workflow (`tools/styles/`)
A small Swift script, `tools/styles/render-contact-sheet.swift`, runs on macOS with MarkepiCore as a local package dependency. It renders every recipe over a fixed set of reference photos (portraits of varied skin tones, landscape, night, high-key) into one contact-sheet PNG, so recipes are tuned side by side and diffed between commits. Reference photos must be licence-clean, not Osama's personal photos, and contain no real names (store-screenshot rules). Final judgement happens on device (memory: verify on device).

Starting recipe intents, which tuning refines:

| Look | Intent |
|---|---|
| Vibrant | +sat/vibrance, mild S-curve |
| Natural | slight warmth, gentle contrast |
| Luminous | lifted mids, soft highlight roll-off |
| Dramatic | strong S-curve, darker mids, −sat |
| Quiet | low contrast, −sat, slight fade |
| Cozy | warm split (amber highlights), soft contrast |
| Ethereal | lifted blacks, pastel, cool-pink shadows |
| Muted B&W | luminance mix, low contrast, faded blacks |
| Stark B&W | red-weighted mix, hard S-curve |
| Undertones | skin hue rotation and saturation (Cool Rose −hue/+magenta, Rose Gold pink-warm, Gold yellow-warm, Amber orange-warm, Neutral reduces warm cast) at about 3× the global strength |
| Portrait 400 | soft contrast, warm skin, slightly cool shadows, low sat, fine grain |
| Golden 200 | warm/yellow bias, punchy mids, medium grain |
| Chrome 100 | slide film: deep blacks, cool-cyan shadows, high contrast, fine grain |
| Velvet 50 | high saturation, rich greens/reds, deep contrast, very fine grain |
| Classic Neg | muted, green-cyan shadows, magenta-ish highlights, hard toe, medium grain |
| Tungsten 800 | cool/teal balance, red halation, medium-heavy grain |
| Silver 400 | B&W, high contrast, heavy grain |
| Faded | expired film: lifted blacks, warm cast, washed sat, medium grain |

### D10. UI
- `EditorTool.style` ("Style", SF Symbol `camera.filters`) is inserted first in the dock: the photo comes before decoration. Changes go in the existing `EditorTool.swift` and `ToolPanelView.swift`, so there is no new App file.
- The panel lives in MarkepiCore/UI as `PhotoStylePanelView<ViewModel: WatermarkConfigurable & Observable>`, mirroring `WhiteFrameToggleView`. It has `MarkepiPillBar` for Moods / Undertones / Film, a horizontal thumbnail strip, an Intensity slider, a compact 2-D pad (drag knob, double-tap to centre), and a Grain slider for film. It uses design-system tokens only (`MarkepiSpacing`, `.markepiTypography`).
- Thumbnails: generated like `frameStyleThumbnails` (the existing max-pixel 360 path), but only for the visible family, lazily, keyed by photo identity and the pad-free style. Each thumbnail is an unframed `renderPreview` with that look.
- Pro marker: small crown/lock on locked looks for free users (the existing `PremiumCrownIcon` style).
- Hold to compare: a `LongPressGesture(minimumDuration: 0.15)` on `PreviewView`, which swaps to the cached Original render. VoiceOver gets an accessibility action "Show original".
- Landscape rail: the panel follows existing tool-panel layout rules. Nothing is persisted about layout.
- `WatermarkConfigurable` gains `photoStyle` get/set, so batch proxies conform automatically or with one property.

### D11. Live Photo and video
- Live Photo with `style != .original`: `LivePhotoProcessor` exports the styled still only, returning `livePhotoVideoURL = nil`. The view model already handles still-only results. The panel shows "Exports as a still photo".
- Video item: the panel is replaced by an explanatory empty state (the `emptyHint` pattern in ToolPanelView). `VideoProcessor` ignores `photoStyle`, and a test asserts the video output is unchanged.

## Risks / Trade-offs

- [String-keyed `applyingFilter("CIColorMatrix", parameters:)` vectors were silently ignored in the prototype, which made halation add the whole image] → Use the typed `CIFilter.*()` builders only, and clamp after every additive step. A test covers halation leaving mid-gray unchanged.
- [The skin key also catches red or ginger hair, because hue overlaps skin (round-1 mask)] → Use the embedded hair matte to subtract hair when present. Otherwise accept it, since the undertone shift on hair is mild. Revisit with `VNDetectFaceLandmarksRequest` face regions if review flags it.

- [Looks are judged by eye; recipes can disappoint] → Contact-sheet tool (D9) plus on-device review before ship. Recipes are data, so retuning is cheap and touches no code paths.
- [Vision skin key fails on very dark or very light skin, or in coloured light] → The chroma key is used only *inside* the person matte, which is reliable. Undertone skin strength is moderate, the mask is feathered, and test photos span skin tones (D9). Global-only fallback.
- [Preview latency from Vision on first open (~50–150 ms on A14)] → Asynchronous, cached per source, global-only render first (D4). No blocking.
- [Two cube passes per undertone double the GPU cost] → Undertones only, and still sub-frame at preview size. Exports run once.
- [HDR highlights don't match a heavy look exactly (gain map from the unstyled capture)] → Accepted; clamped base (D5), luminance-collapsed map for B&W. Documented non-goal.
- [Stacking on iPhone 16+ photos that already have a Smart Style] → Original default, and the user chooses deliberately.
- [Live Photo loses motion when styled] → Stated in the panel before export (spec). Follow-up video change can style the motion too.
- [Name/trademark exposure] → Names are our own and generic. No "Photographic Styles" wording. Film looks are labelled by ISO-like character, never by a brand.
- [Memory: a 33³ float cube is ~575 KB × up to 22 cached] → Bake lazily and keep only the cubes in use (LRU of 6), about 3.5 MB worst case.

## Migration Plan

Additive. Old configs and templates decode to Original (D7), so existing users see no change until they choose a look. Rollback means removing the Style tool from the dock: stored `photoStyle` values are inert if the renderer is skipped.
