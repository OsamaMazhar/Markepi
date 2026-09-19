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

### D5 — Vector where a vector exists, official raster otherwise

The supplied artwork is 25 brands, each with an official full-colour SVG and official monochrome renditions — vector for Apple, 1024px transparent PNG for the rest. `tools/logos/build-logos.sh` rebuilds `Resources/Logos/` from `LogoSources/`: colour SVGs become vector PDFs for every brand, mono becomes a PDF where a mono SVG was supplied and the official PNG otherwise. Loading is `CGPDFDocument` for PDFs and `CGImageSource` for rasters, behind one artwork type with one draw call.

*Why not vector for everything:* the official monochrome artwork only exists as raster for 24 of the 25 brands. Deriving mono by forcing every fill in the colour vector to one colour would be a guess — it happens to be right for a wordmark and wrong for any logo with a knockout shape, and the supplied renditions are authoritative. A raster here costs nothing real: a mark draws at roughly 200–400px even on a 48MP export, so a 1024px master is only ever downscaled. A test asserts the raster masters stay large enough for that to hold.

*Why PDF rather than the asset catalog:* `CGPDFDocument` is plain Core Graphics, so one code path serves both iOS and macOS with no `UIImage`/`NSImage` split and no asset-catalog vector-data caveats.

*Sources live outside the target.* `LogoSources/` sits beside `Sources/`, so the original artwork is kept verbatim and reviewable without shipping 1.7MB of unused masters in the app bundle; the generated set is 936KB.

*Most of these are wordmarks, not glyphs.* Aspect ratios run from about 10:1 (Canon, Sony) to taller-than-wide. The renderer therefore sizes a mark by height to fit the caption band and lets width follow, then caps width so a long wordmark cannot crowd out the caption text. Sizing by width would make a wordmark microscopic and a square glyph enormous.

### D6 — The mark is resolved from metadata, not chosen

A brand registry maps a normalised manufacturer key to that brand's available mark files. Resolution reads the manufacturer from the source image's metadata, normalises it, and looks it up; a miss — no manufacturer recorded, or one with no shipped mark — yields no mark, and the renderer then draws neither mark nor divider.

*Normalisation matters more than it looks.* Manufacturers write themselves into EXIF inconsistently: lowercase, uppercase, with corporate suffixes. Matching therefore case-folds, trims, and strips trailing corporate suffixes before lookup, rather than comparing raw strings.

*Sub-brands need the model, not just the make.* Redmi phones write `Make = Xiaomi` and put the sub-brand in `Model`. Make alone would give every Redmi the Xiaomi mark, so resolution checks the model for known sub-brands before falling back to the make. Honor is the mirror case and needs no special handling: current devices write `HONOR`, Huawei-era ones wrote `HUAWEI`, and those correctly get the Huawei mark — that is what the metadata says.

*Which monochrome is not a user choice.* Both a dark and a light rendition ship. Monochrome resolves to whichever contrasts with the mat, so the light rendition simply becomes reachable if a dark mat is ever added, with no new control and no spec change.

*Why derived rather than chosen:* a mark that is derived is a statement of fact about the photo — the device that took it. A mark that is chosen is decoration, and decoration with someone else's trademark is the version that gets an app rejected. It also removes a picker from an already busy controls column.

*What the user does control:* colour versus monochrome, as a single preference that applies to whichever brand is resolved. It is offered only when the resolved brand ships both variants, so the control reflects what actually exists rather than promising a variant that would silently fall back.

*Pluggable, for the implementer:* adding a brand is a vector file plus a registry entry. No renderer, config, or UI change.

*Alternative — a user-facing brand picker:* rejected by the user, and it is the trademark-risky shape.

### D7 — Mat dimensions round to even pixels

The framed size is rounded up to even numbers in both dimensions.

*Why:* H.264 and HEVC want even dimensions; an odd `renderSize` is a real source of encoder trouble. Doing it for photos too keeps photo and video geometry identical, which is what makes them testable against each other.

### D8 — Gallery measures in millimetres; classic stays proportional

`gallery` sizes its border, caption text and brand mark in millimetres, converted against the photo's resolution. `classic` keeps `frameWidthRatio` and `textFontSizeRatio`.

*Why per-style rather than a mode flag:* the two styles genuinely mean different things by "border". Classic is a proportion of the photo and always has been; gallery is a mat on a print. A `borderSizing` enum would make every call site ask which mode it is in, to express what the style already says.

*Why every gallery measurement is metric, not just the border:* mixing units within one style makes the parts fight. Caption text sized as a proportion of the photo would, on a 48MP export, come out taller than a 5mm border — and the bottom band would stop tracking the border setting, because the text floor would always dominate. One unit per style keeps the band a function of the setting.

*Why the mark is sized by height:* the supplied artwork runs from about 10:1 wordmarks to square glyphs. A width-based size would make a wordmark microscopic and a glyph enormous.

*Resolving DPI:* the photo's own resolution is used when it is at least a plausible print-intent value, and 300 otherwise. A great many files carry 72 DPI because it is the format default rather than a measurement; believing it would turn a 5mm border into 14px on an 8000px photo, which reads as no border at all. This floor is a deliberate deviation from taking the metadata literally, and is the piece to revisit if a real low-resolution source ever needs framing.

*Trade-off:* a physical border does not scale with the photo, so on screen a 5mm border looks thicker on a small image than a large one. That is what a physical unit means, and it is the right behaviour for a frame intended to be printed.

## Risks / Trade-offs

- **Every brand mark is a third-party registered trademark**, and this change ships roughly fifteen of them. Reproducing them in exported images carries App Store review risk, and the risk scales with the number of brands rather than staying flat. The user was told this and accepted it. → Materially reduced by D6: because the mark is derived from the photo's own metadata, it only ever appears on a photo actually taken on that manufacturer's device, which is factual attribution rather than decoration, and no user can stamp one brand's mark onto another brand's photo. Reduced further by marks being per-brand files — pulling one brand is deleting a file. Not eliminated: attribution is still reproduction, and each brand's own usage guidelines may differ.
- **Sourcing runs ahead of implementation.** Fifteen brands' artwork arrives over time, from the user. → The registry treats a missing file as "no mark for this brand", so every brand is independently shippable and a half-populated registry is a valid state, not a broken one.
- **Breaking output change.** Every framed export changes size; snapshot tests and any extent assertions fail until rebaselined. → Regenerate baselines as an explicit task and review the diffs by eye rather than accepting them wholesale, since a rebaseline can hide a real regression.
- **Video export is the fragile path.** `renderSize` growing means the video layer must be inset and the track transform must still map portrait/rotated footage upright. Simulator video export crashes with an unrelated CoreMedia XPC fault, so this can only be confirmed on device. → Keep the mat insets identical between photo and video code so a photo test covers the geometry, and verify video export on hardware before shipping.
- **Larger exports use more memory.** A mat on a 48MP photo adds a band of pixels to an already large intermediate. → The addition is a few percent of area; no mitigation planned, but worth watching if frame widths ever grow.
- **Two styles share one config struct.** Fields only one style reads sit alongside fields both read (D2). → Document each field's applicability; revisit if a third style makes the struct incoherent.
- **The caption can still overflow.** Four slots plus a logo on a narrow landscape photo is more content than the current single centred line. → Reuse the existing auto-shrink approach per text group, and let the left and right groups shrink independently so one long lens string does not shrink the device name with it.

## Migration Plan

No data migration: old configs decode into the new struct via `decodeIfPresent` and land on `.classic`, keyline off, logo none.

Rollout is the normal build. Rollback is reverting the change — configs written by the new version decode on the old one too, because the old decoder ignores unknown keys, and an unknown style falls back to `.classic`.

The one-way part is user-visible: anyone who framed a photo before this change gets differently-sized output afterwards. That is the intended behaviour change, called out in the proposal as BREAKING.
