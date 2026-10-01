## Why

The four frame styles (`classic`, `gallery`, `print`, `banner`) are all variations on a white mat. Users want modern, minimal frames with depth, gradients and shading that still put the photo first. Twelve looks were mocked up on a real photo and approved (`reference/00-overview.jpg`); traditional frames, AI-generated frame art and styles that warp the photo were reviewed and rejected.

## What Changes

- **Twelve new frame styles** alongside the existing four:
  - Minimal: **Float** (rounded photo lifted off a warm white card), **Tone** (border in the photo's own deepest colour), **Swatch** (the photo's five dominant colours as the caption), **Spine** (caption on a slim side rail, read bottom-to-top), **Noir** (black, slightly rounded photo), **Readout** (one camera-style line with the aperture highlighted).
  - Photo-derived backdrops: **Ambient** (the photo, blurred, as its own backdrop), **Aura** (a soft gradient mixed from the photo's colours).
  - Effects: **Blend** (border graded from the photo's top-edge colour to its bottom-edge colour), **Emboss** (soft light/dark shades press the photo into the surface), **Sunlight** (window-blind light across the surround and a long cast shadow), **Glow** (the photo's colours as a subdued halo on a dark ground).
- **The photo is never altered.** Styles only draw around it. Rounded styles clip its corners, as a rounded print does; nothing is warped, filtered or recoloured.
- **The photo stays dominant.** Borders scale with the photo's short edge, the same way the existing millimetre sizing does. There is no fixed 4:5 canvas that would put wide borders around landscape photos.
- **Frames can read the photo.** Several styles take colour, or a blur, from the photo itself. For video, one representative frame is sampled.
- **One shared caption for the new styles:** maker mark plus model and date on the left, shooting values and place on the right. It is driven by the existing Include list and logo switch, and never by invented text.

## Capabilities

### Modified Capabilities
- `photo-frames`: the style set grows from four to sixteen; new requirements cover the twelve looks, photo-derived colour and backdrop, the rule that no style alters the photo, the shared caption for the new styles, and video parity for photo-derived styles.

## Impact

- **Models**: `FrameStyle` gains 12 cases. Decoding stays lenient, so an older build reading a new style falls back to `classic`. Capability flags (`drawsBrandMark`, `castsShadow`, `hasSideMat`, `offersKeyline`, etc.) are extended.
- **Rendering**: `WhiteFrameRenderer` gets a photo sample input (a small downsampled `CGImage`), a palette helper, per-style mat fills, a backdrop step (Ambient, Aura, Glow), rounded holes, coloured and dual shadows, the blinds pattern, and the shared row caption. `FrameGeometry` gets per-style edge proportions.
- **Callers**: `WatermarkEngine` passes the composited photo sample. `VideoProcessor` and `VideoLayerBuilder` sample one frame from the asset.
- **UI**: the style picker, the thumbnail strip (16 previews) and the settings rows follow each style's capabilities.
- **Tests**: `swift test` covers the fills, the photo-rect transparency (photo untouched), the palette fallback and decode compatibility. `scripts/build-gate.sh` must pass.
