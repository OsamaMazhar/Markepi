## Context

See proposal.md — Why.

The frame is rendered by `WhiteFrameRenderer`, which today returns a CIImage the same size as the photo: it fills the canvas white and punches a transparent hole with a `.clear` blend, so the border is composited *over* the photo's outer edge. `WatermarkEngine.buildFilterGraph` source-over-composites that on top of the watermark layers, and `VideoLayerBuilder` does the same as a `CALayer` above the video layer. Because the border covers the photo, both call sites carry a `frameInset` workaround that shrinks the rect watermarks are positioned against, so a corner watermark does not disappear under the border.

Two render paths must stay in step: `UIGraphicsImageRenderer` on iOS, and a `CGContext` + Core Text path on macOS used by `swift test` and the `markepi` CLI. They share one `drawFrame` function; only the text drawing differs.

Constraints that shape the approach:
- `WhiteFrameConfig` has hand-written `Codable` conformance; saved templates must keep decoding.
- `previewIdentifier` must mirror every render-affecting field or the live preview goes stale.
- WatermarkCore is an SPM target with directory-based source inclusion, so new `.swift` files under `Sources/WatermarkCore/` compile automatically — the classic-pbxproj manual-file-reference rule applies to the app and extension targets, not here.
- The package already ships resources (`Resources/Fonts`, `Resources/Media.xcassets`) loaded via `Bundle.module`.

## Goals / Non-Goals

**Goals:**
- One geometry — mat outside the photo — shared by every style, so there is a single set of rules to reason about.
- A style enum that a third style can join without touching the caption or geometry code.
- A logo that is genuinely resolution-independent at multi-megapixel export sizes, from official vector sources.
- Identical output from the UIKit and Core Text render paths.

**Non-Goals:**
- Reworking how watermark layers are positioned beyond deleting the `frameInset` workaround the new geometry makes unnecessary.
- User-configurable mat colour, corner radius, or drop shadow. Style-derived constants for now.
- A general SVG renderer. Only the specific logo artwork is needed.
- Migrating already-exported images. This changes what new exports look like, nothing retroactive.

## Decisions

### D1 — Expand the canvas rather than overlay the mat

The renderer returns a mat image sized `source + mat insets`, with a transparent hole at the photo's rect; the engine translates the composited photo into that hole and source-over-composites the mat.

*Why:* it is what the reference frame actually looks like, and it stops the frame from eating the photo. It also deletes code: with the photo no longer covered, the `frameInset` positioning workaround in both `WatermarkEngine` and `VideoLayerBuilder` goes away, along with the comment blocks explaining it.

*Alternative — keep overlaying:* a smaller diff, but it cannot reproduce the reference (the taller caption band would cover roughly the bottom 8% of the photo), and it keeps the `frameInset` workaround alive in two places.

*Alternative — expand for `gallery` only:* two geometries in the renderer forever, and the existing style keeps cropping. Rejected: the user asked for the existing frame to move to the new geometry too.

*Consequence:* this is a breaking output change. Exports get larger and are no longer byte-identical to previous runs. Snapshot baselines must be regenerated, and any test asserting output extent equals source extent needs updating.

### D2 — Extend `WhiteFrameConfig`, do not introduce a parallel config type

`FrameStyle` and the new fields go on the existing struct. `WatermarkConfiguration.whiteFrame` keeps its type, so nothing downstream re-plumbs.

*Why:* a second config type would need its own Codable, its own plumbing through the engine, the video builder, the view model, and `previewIdentifier`, to express what four extra fields express. Style-specific fields simply go unread by the styles that do not use them.

*Alternative — a `FrameRenderer` protocol with a case per style:* an interface with two implementations that share their geometry, their keyline and their font helpers. The shared part is most of it, so the protocol would mostly be a way to re-inject what the shared code already has.

*Trade-off:* fields that only apply to one style sit on the shared struct. Documented per field; acceptable at two styles, worth revisiting at four.

### D3 — Caption slots reuse `CaptionField`

A `CaptionSlot` enum with `.field(CaptionField)`, `.text(String)` and `.empty`. `.field` resolves through the existing `DeviceMetadataProvider` / `EXIFTokenParser` path used by the classic caption; `.text` goes through `EXIFTokenParser.substitute` so `{token}` interpolation works in free text too.

*Why:* every metadata field the slots need already exists, already has a display name for the picker, and already resolves against source metadata. A second token vocabulary would be a second thing to keep correct.

*Codable:* encode as a tagged single-value form (a field's raw value, or a text payload) so it round-trips without a nested container; absent slots decode to the style defaults.

### D4 — `drawFrame` takes a resolved caption model, not a `String`

Replace `attributionText: String?` with a small resolved struct — the centred line for `classic`, the four slot strings plus the logo choice for `gallery`. Resolution (metadata lookup, token substitution, empty-slot elision) happens once, before the platform branch.

*Why:* both render paths then draw from the same already-resolved values, which is what keeps them identical. It also keeps metadata access out of the drawing code.

### D5 — Logo ships as vector PDF, drawn with Core Graphics

Convert the official SVGs to single-page PDFs at authoring time, ship them under `Resources/Logos/`, load with `CGPDFDocument`, and draw with `CGContext.drawPDFPage` scaled to the caption band.

*Why:* `CGPDFDocument` is plain Core Graphics, so one code path serves both iOS and macOS with no `UIImage`/`NSImage` split and no asset-catalog vector-data caveats. It is vector all the way to the rasteriser, so it is sharp at any export size — which a PNG in an imageset, like the existing `BrandMark`, would not be.

*Alternative — SVG in the asset catalog with Preserve Vector Data:* needs the platform image split, and its behaviour for an SPM resource bundle on macOS is less certain than Core Graphics'.

*Alternative — transcribe the SVG paths into Swift `CGPath` code:* no resource loading at all, but the rainbow artwork uses elliptical arcs, and hand-porting arc-to-bézier is exactly the kind of fiddly conversion a PDF gets right for free.

*Sources (verified reachable):* rainbow `commons.wikimedia.org/.../8/84/Apple_Computer_Logo_rainbow.svg`, black `.../f/fa/Apple_logo_black.svg`, white `.../3/31/Apple_logo_white.svg`.

### D6 — The logo slot is pluggable and defaults to none

`FrameLogo` is an enum with `.none` as the default. Drawing takes the resolved PDF page, so a non-Apple mark is a new case plus a file.

*Why:* see the trademark risk below. A default of `.none` means the shipped app does not put Apple's mark on anyone's photo unless they choose it.

### D7 — Mat dimensions round to even pixels

The framed size is rounded up to even numbers in both dimensions.

*Why:* H.264 and HEVC want even dimensions; an odd `renderSize` is a real source of encoder trouble. Doing it for photos too keeps photo and video geometry identical, which is what makes them testable against each other.

## Risks / Trade-offs

- **Apple's mark is a registered trademark.** Reproducing it in exported images carries a real App Store review risk, and the reference frame's rainbow logo is Apple's 1977 mark. The user was told this and accepted it. → Mitigated by `.none` as the default, by keeping the slot pluggable per D6 so a neutral mark can replace it in one commit, and by recording here that the risk was accepted rather than overlooked.
- **Breaking output change.** Every framed export changes size; snapshot tests and any extent assertions fail until rebaselined. → Regenerate baselines as an explicit task and review the diffs by eye rather than accepting them wholesale, since a rebaseline can hide a real regression.
- **Video export is the fragile path.** `renderSize` growing means the video layer must be inset and the track transform must still map portrait/rotated footage upright. Simulator video export crashes with an unrelated CoreMedia XPC fault, so this can only be confirmed on device. → Keep the mat insets identical between photo and video code so a photo test covers the geometry, and verify video export on hardware before shipping.
- **Larger exports use more memory.** A mat on a 48MP photo adds a band of pixels to an already large intermediate. → The addition is a few percent of area; no mitigation planned, but worth watching if frame widths ever grow.
- **Two styles share one config struct.** Fields only one style reads sit alongside fields both read (D2). → Document each field's applicability; revisit if a third style makes the struct incoherent.
- **The caption can still overflow.** Four slots plus a logo on a narrow landscape photo is more content than the current single centred line. → Reuse the existing auto-shrink approach per text group, and let the left and right groups shrink independently so one long lens string does not shrink the device name with it.

## Migration Plan

No data migration: old configs decode into the new struct via `decodeIfPresent` and land on `.classic`, keyline off, logo none.

Rollout is the normal build. Rollback is reverting the change — configs written by the new version decode on the old one too, because the old decoder ignores unknown keys, and an unknown style falls back to `.classic`.

The one-way part is user-visible: anyone who framed a photo before this change gets differently-sized output afterwards. That is the intended behaviour change, called out in the proposal as BREAKING.
