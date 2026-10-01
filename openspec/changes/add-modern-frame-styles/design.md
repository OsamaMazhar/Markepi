## Context

`WhiteFrameRenderer.render` draws only the frame: a `CIImage` the size of the framed canvas with a transparent hole at `geometry.photoRect`. The caller (`WatermarkEngine` for photos, `VideoLayerBuilder` for video) composites the photo underneath. `FrameGeometry` sizes every edge from millimetre settings converted at a DPI derived from the photo's short edge (10" reference print), so borders are already proportional to the photo. The renderer never sees photo pixels today, but six of the new styles need them (see proposal).

References: `reference/*.jpg` (approved renders), `reference/modern.py` and `reference/effects.py` (exact proportions and colours, as PIL at a 1200×1600 photo, short edge S=1200).

## Goals / Non-Goals

**Goals:** pixel-faithful photo; one shared caption for the new styles; photo-derived surrounds on photo and video; exhaustive `switch`es stay the safety net (closed enum, no registry).

**Non-Goals:** no new user controls beyond what existing styles expose; no per-frame video surround (one sample per export); no Pro gating changes.

## Decisions

**D1 — Photo sample as an optional render input.** `render(config:geometry:metadata:scale:sourceImage: CGImage? = nil)`. Callers pass a small downsampled copy (long edge ≤ 512 px) of the image that goes into the hole: the photo engine renders it from `watermarkedResult` with the shared `CIContext`, and the video path grabs one frame with `AVAssetImageGenerator` at ~10% of the duration, using `appliesPreferredTrackTransform`. The alternative, having the renderer take the full `CIImage`, was rejected: it couples frame drawing to the photo pipeline and makes palette work scale with megapixels. When the sample is nil, a neutral fallback is used (spec: Sample unavailable).

**D2 — `PhotoPalette` helper (package, pure Core Graphics).** It draws the sample into a fixed 48×64 RGB bitmap, so the cost is constant whatever the resolution, then derives:
- `dominant(count:)`: coarse 4-bit-per-channel buckets, ranked by population and merged when close.
- `deep`: the lowest (luminance − 1.5×saturation).
- `warm`: the highest (r − b + luminance/6).
- `edgeAverage(.top/.bottom)`: the mean of the top and bottom 1/12 of rows.

This mirrors `modern.py`'s `palette()`, which uses PIL median-cut; bucketing is close enough for surround colour and needs no dependency. Colours are coerced to sRGB `CGColor`s, which avoids the achromatic gray-colour-space pitfall.

**D3 — Edges are multiples of the mat.** Each new style declares side, top and bottom edges as factors of `mat` (the `borderMillimetres` pixels). With the default 8 mm border, mat ≈ 3.15% of S, so the mockup percentages convert as mockup% ÷ 3.15%:
- float: side 2.2, bottom 6.0
- tone: side 1.4, bottom 4.8
- swatch: side 1.4, bottom 4.8
- spine: side 1.3, rail 3.5
- noir: side 1.1, bottom 4.1
- readout: side 1.1, bottom 3.5
- ambient, aura, glow, emboss, sunlight: side 2.5, bottom 7.0
- blend: side 1.6, bottom 5.1

Bottom bands collapse to the side edge when there is no caption content, as `gallery` does. This keeps landscape photos proportionate (spec: The photo stays dominant). A fixed 4:5 canvas was rejected by the user's "photo first" rule.

**D4 — Surround drawing order (back → front), all Core Image after the CG pass, like `applyingShadow`:**
1. Backdrop: blurred sample (ambient), a palette blob gradient (aura) or a blurred halo over near-black (glow).
2. The CG-drawn mat, with a transparent (optionally rounded) hole, the blinds and the caption.
3. Shadows are composited on the mat only, masked out of the hole: a tinted shadow (aura), dual light and dark shades (emboss), and a long offset shadow (sunlight).

Where a style has a backdrop, the CG mat fill is transparent except for caption glyphs.

Doing effects in Core Image after the platform branch reuses the existing reason documented on `applyingShadow`: the CG shadow offset flips between the UIKit and macOS paths.

**D5 — Rounded corners are part of the hole.** The hole is punched as a rounded rect of radius k×S, where k comes from the mockups (float 2.8%, noir 1.2%, ambient and aura 2.6%, blend 2.0%, emboss 3.5%, glow 2.6%). The corners stay mat-opaque, so they hide the photo's corners. No photo pixel is changed.

**D6 — The shared row caption is a new layout, not `gallery`'s four slots.** It is resolved from the Include list, like `banner`'s:
- left primary: model (with the mark before it)
- left secondary: date and time
- right primary: shooting values (focal length, aperture, shutter, ISO)
- right secondary: place

Each style chooses the ink and sub-ink colours, and the mark variant is picked against the surround tone. Spine draws the same text as one rotated run. Readout draws a single line with monospaced digits (`UIFont.monospacedDigitSystemFont`; SF Camera is not public API) and yellow aperture text.

**D7 — Capability flags drive the UI.** The new styles have:
- `drawsBrandMark` = true
- `offersKeyline` = false
- `castsShadow` = false (their shadows are intrinsic, not the user's `print` shadow)
- `offersGradient` = false
- `usesGalleryCaption` = false

The settings screen shows the Include list, the logo switch and the border and caption size for them, and nothing else.

**D8 — Thumbnail strip.** Sixteen previews, driven by `FrameStyle.allCases`, so no view-model change is needed. Each preview is rendered from a small downsampled source, as it is today. The engine takes the ≤512 px sample from that already-small image, so sampling once per style costs almost nothing. That is simpler than threading a shared sample through the strip.

## Risks / Trade-offs

- [Palette differs slightly from the PIL mockups] → accept. Tests assert behaviour (the colour follows the photo), not exact RGB.
- [Video surround is static while the content moves] → documented in the spec. One frame keeps export cost flat.
- [16 thumbnail renders cost time on older devices] → keep the small source, and render sequentially off the main actor, as today.
- [Backdrop blur on HDR sources] → the sample is SDR sRGB, so the backdrop is SDR while the photo in the hole keeps HDR, which matches the existing mat.
