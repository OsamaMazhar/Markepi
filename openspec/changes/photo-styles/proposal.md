## Why

iPhone 16 and later have next-generation Photographic Styles: skin-aware undertones, mood looks and a Tone/Color pad that can be changed after capture. Older iPhones (12–15) do not have them, and Apple offers no public API, so no app can call the real feature (the symbols in the iOS 27 SDK are private SPI, and the data that makes styles reversible is only captured by A18+ hardware). Users also keep asking for classic film looks. Markepi already owns the moment between "pick a photo" and "share it". A look applied at that moment, on any iPhone, fits the core value: style it, mark it, share it, and never clutter the camera roll.

## What Changes

- **New Looks tool** in the editor dock with three families of looks, applied to the photo before frames and watermarks:
  - **Moods (9):** Vibrant, Natural, Luminous, Dramatic, Quiet, Cozy, Ethereal, Muted B&W, Stark B&W.
  - **Undertones (5):** Neutral, Cool Rose, Rose Gold, Gold, Amber. These shift skin strongly and the rest of the photo lightly, using the person/skin mask.
  - **Film (8):** Pastel 400, Golden 200, Chrome 100, Velvet 50, Classic Neg, Tungsten 800, Silver 400, Faded. Each has its own tone and colour response plus film grain; Tungsten 800 adds red highlight halation. The names are our own and deliberately avoid film-maker trademarks.
  - **Original** (no style) is always the default.
- **Controls:** Intensity (0–100%), a Tone & Warmth pad (darker↔brighter, cooler↔warmer), and for film looks a Grain amount. A press-and-hold on the canvas shows the unstyled photo.
- **Skin awareness on every iPhone:** uses the skin matte that Portrait-mode photos already embed (iPhone XS and later). Otherwise it falls back to on-device person segmentation plus a skin-colour key. With no person found, an undertone applies only its light global shift.
- **Quality and metadata are kept:** HDR gain map, colour profile and all EXIF/GPS metadata survive styled exports exactly as they do today. B&W looks never turn the file into a grayscale image.
- **Previews match exports:** the live preview, the style thumbnails and the export render the same look, including grain scale.
- **Gating:** free users get Original, Vibrant, Natural and the Neutral undertone. Every other look, and the pad, intensity and grain controls, are Pro. Free users can preview Pro looks. A free export of a Pro look appears in the existing Free vs Pro comparison sheet, and the free file is exported without the Pro look.
- **Scope:** photos and Live Photo stills. Video styling is a follow-up change (the video export uses `AVVideoCompositionCoreAnimationTool`, which cannot run a per-frame filter in the same composition). A Live Photo with a look applied exports as a still photo.

## Capabilities

### New Capabilities
- `photo-styles`: the style catalogue (moods, undertones, film) and its controls, skin-aware rendering, the order relative to frames and watermarks, preview/export parity, quality and metadata preservation, persistence in templates, free/Pro gating, and media-type scope (photos and Live Photo stills, not video).

### Modified Capabilities
<!-- None. photo-frames requirements are unchanged: frames still never alter the photo; a style is a separate step that runs before the frame and is what photo-derived frames sample. -->

## Impact

- **MarkepiCore / Models:** new `PhotoStyle` (catalogue id) and `PhotoStyleSettings` (style, intensity, tone, color, grain) on `WatermarkConfiguration`, with lenient decoding (missing → Original, unknown id → Original). Templates carry it automatically.
- **MarkepiCore / Rendering:** new `PhotoStyleRenderer`: parametric recipes baked into colour cubes (no bundled LUT files and no licence exposure), the pad and intensity as live filters, grain and halation, and skin-masked undertones. New `SkinMaskProvider`: embedded matte, then Vision, then none, cached per source.
- **MarkepiCore / Engine:** `buildFilterGraph` applies the style first, so both `process` and `renderPreview` get it. Free-tier policy downgrades Pro looks to Original. `LivePhotoProcessor` drops motion when a look is active.
- **App:** `EditorTool.style`, a style panel (family pills, a thumbnail strip of looks rendered from the current photo, sliders and the pad), hold-to-compare on the canvas, `previewIdentifier` coverage, and the comparison sheet showing "Pro look" vs "Original".
- **Tests:** `swift test` for recipe and cube correctness, identity at Original and at 0% intensity, RGB-preserved B&W, mask-limited undertones, grain determinism and scale, metadata and gain-map survival, decode compatibility and free-tier downgrade. `scripts/build-gate.sh` must pass. Final look check on device.
- **No new dependencies and no network.** Everything runs on device with Core Image, ImageIO and Vision.
