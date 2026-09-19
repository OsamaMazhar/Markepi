## Context

`EXIFTokenParser.formatGPS` (Packages/WatermarkCore/Sources/WatermarkCore/Utilities/EXIFTokenParser.swift) currently reads `metadata["{GPS}"]["Latitude"/"Longitude"/"LatitudeRef"/"LongitudeRef"]` and formats raw coordinates. That token feeds both `classic`'s `captionFields` list and `gallery`'s `CaptionSlot`s via `WhiteFrameRenderer.resolveSlot`, which already treats a literal `"--"` result as "missing" and elides it from the caption (see `resolveSlot`'s `words.filter { $0 != "--" }`, and `DeviceMetadataProvider.caption`'s equivalent `value != "--"` guard). This change only needs to change what the caption path gets back; the missing-field plumbing already exists and needs no changes.

Two facts about the existing code constrain the design, and both were found by reading it rather than assumed:

- **Stored coordinates are unsigned.** `{GPS}.Latitude` and `.Longitude` hold *absolute* values, with `LatitudeRef`/`LongitudeRef` ("N"/"S", "E"/"W") carrying the hemisphere. That is why `formatGPS` itself calls `abs(lat)` and reads the refs. The app's own producers write them the same way: `VideoProcessor.swift` stores `abs(coord.lat)` with a derived ref, and the test factory `EXIFMetadataFactory` does too. Anything doing geometry on these numbers must re-sign them first.
- **`{gps}` is not confined to frame captions.** `TextWatermarkRenderer.render(config:metadata:)` substitutes the same tokens into the user's free text watermark. That renderer deliberately draws every glyph white and applies the real colour and opacity through an alpha mask, because its CoreImage generator emits gray. A colour emoji pushed through an alpha mask loses its colour and comes out as a solid tinted rectangle.

There is no reverse-geocoding or country-boundary data anywhere in the codebase today. The user asked about `CLGeocoder`/MapKit specifically; both require a network round trip to Apple's geocoding service (there is no offline mode, and no public Apple API for on-device coordinate→country lookup), which conflicts with the hard "no network access" requirement — so this change has to bring its own bundled dataset.

## Goals / Non-Goals

**Goals:**
- Resolve a GPS coordinate to a country entirely on-device, with no network dependency, at negligible cost per export.
- Reuse the existing "--"-means-missing convention rather than inventing a new fallback path.
- Keep the bundled dataset small — this is a decorative caption, not a mapping product.
- Leave every existing `{gps}` consumer that is not a frame caption rendering exactly what it renders today.

**Non-Goals:**
- City/locality resolution (confirmed out of scope by the user; would need a much larger place gazetteer and a nearest-neighbor search).
- Survey- or legal-grade border accuracy. A coordinate near a border may resolve to the wrong side; that is accepted, not fixed, by this change.
- Teaching `TextWatermarkRenderer` to composite colour emoji (see D7).
- Any UI change — the location field is already selectable in both styles; only its rendered text changes.

## Decisions

### D1: Reject CLGeocoder / MapKit reverse geocoding
Both require network access to Apple's geocoding service; there's no documented offline mode and no separate offline-capable Apple API for coordinate→country lookup. Since offline operation is a hard requirement, these are ruled out regardless of the country-only scope. Recorded here so the choice isn't revisited without new information.

### D2: Simplified boundary polygons with a bounding-box prefilter
Two on-device approaches were considered:

- **A pre-baked coordinate grid** — sample a boundary source on a regular grid at dataset-build time and record one country per cell, so runtime resolution is `floor(lat)`/`floor(lon)` array indexing. Rejected. Its appeal was O(1) lookup, but lookup cost is not the binding constraint here: this runs once per export, not once per pixel. Its real cost is fatal to the feature's point — a cell at any tractable resolution is tens of kilometres across, so Monaco, Singapore, Vatican City, Liechtenstein, Malta, Bahrain and Andorra simply cannot be sampled. Resolving Monaco needs roughly hundredth-degree cells, which is millions of them. A flag caption that cannot flag a city-state is the wrong trade.
- **Point-in-polygon against simplified country boundaries** (chosen) — bundle a public-domain simplified boundary set, precompute each country's bounding box at build time, and at runtime reject almost every country on a bounding-box compare before running a ray-casting winding test on the handful that survive. The ray cast is about twenty-five lines and handles multipolygons (archipelagos, exclaves) by testing each ring.

  **Correction, found while implementing: the source is 1:10m, not the 1:110m written here.** The 1:110m set carries 177 features and contains no Monaco, Vatican City, Liechtenstein, Andorra, San Marino, Malta, Bahrain or Singapore *at all* — the identical failure this decision rejected the grid for, two paragraphs above. Naming 1:110m here was the same mistake in a different costume. 1:10m carries 258 features including every one of them, and the size it costs is taken back by simplifying harder rather than by dropping countries, which is the trade that was actually wanted: coarse borders everywhere are fine, a missing country is not.

Chosen: polygons. The dataset is around the same order of size as the grid would have been, the code is marginally larger, and small territories resolve correctly. Border precision is still bounded by how aggressively the source is simplified, which is the accepted ceiling below — call it out in code as a `ponytail:` comment: simplified boundaries, upgrade path is a finer source revision if border complaints appear.

### D3: Dataset built offline, once, from public-domain data
A repo-local script under `tools/geo/` (mirroring `tools/logos/build-logos.sh`'s pattern of regenerating a shipped resource from source material, run by a maintainer, not part of the app or CI build) consumes a public-domain country-boundary source and emits the simplified rings plus their precomputed bounding boxes as a compact resource bundled into `WatermarkCore`. Never fetched, generated, or computed at runtime.

### D4: Flag and name need no bundled per-country table
Once an ISO 3166-1 alpha-2 code is resolved:
- **Flag**: built algorithmically from the two letters via their Unicode Regional Indicator Symbols (`🇫` = the indicator for 'F', etc.) — every emoji-capable font, including the system font on both iOS and macOS (relevant for the macOS Core Text render path used by `swift test`), already renders the pair as a single flag glyph. No bundled flag assets.
- **Name**: `Locale.current.localizedString(forRegionCode:)` — an *instance* method on `Locale`, not a static one, and it returns an optional. Where it returns nil the resolver falls back to the alpha-2 code itself rather than dropping the field, so a caption never silently loses its location. Already offline, already localized, ships with the OS.

Both keep the new bundled asset limited to the boundary data itself.

### D5: Location field's content changes in place; no new `CaptionField`
`.gps` already means "location" (its `displayName` is "Location"); changing what it renders is a content upgrade, not a new concept. A separate "raw coordinates" field was considered and rejected — nothing in the codebase or the request calls for keeping raw coordinates available as a *user-selectable field*, and adding it back speculatively would be scope no one asked for. Note this is separate from D7, which keeps the raw format reachable internally for a different caller.

### D6: Sign the coordinates from their refs before resolving
The resolver's entry point takes signed degrees, because that is what geometry against boundary polygons requires and what every other coordinate API in the ecosystem expects. The caption path is therefore responsible for combining `Latitude` with `LatitudeRef` and `Longitude` with `LongitudeRef` into signed values, using the same `ref == "S"`/`ref == "W"` negation the existing formatter implies, and falling back to the stored sign when a ref is absent (which is what `formatGPS` already does today).

This is called out as its own decision because getting it wrong is silent and total: unsigned input sends every southern-hemisphere photo to the wrong latitude and every western-hemisphere photo to the wrong longitude. Sydney would resolve to open Pacific, São Paulo to central Asia, and nothing would crash or warn. The task list carries a fixture covering all four hemisphere quadrants for exactly this reason.

### D7: Place formatting is reached from the caption path only
`{gps}` has two consumers, and only one of them can draw a colour emoji:

- The **frame caption** path (`WhiteFrameRenderer.resolveSlot` for `gallery`'s slots, `DeviceMetadataProvider.caption` for `classic`'s line) draws its text into a `CGContext` with a real foreground colour, so an emoji renders in full colour there.
- The **text watermark** path (`TextWatermarkRenderer`) draws white glyphs as an alpha mask and tints them. A flag emoji through that path is a solid tinted rectangle, and the pin is a blob.

So the place format is not a blanket replacement of `formatGPS`'s output. `formatGPS` keeps returning coordinates by default, and the frame caption path asks for the place format explicitly — whether by a parameter on the formatter or by resolving at the caption layer is an implementation detail, as long as `TextWatermarkRenderer`'s substitution is untouched. A user who has typed `{gps}` into a text watermark today sees exactly what they see now, which is the whole point: this change must not regress a feature it is not about.

Teaching `TextWatermarkRenderer` to split a glyph run into colour-emoji glyphs (composited as-is) and text glyphs (alpha-masked and tinted) would let the flag appear everywhere. It is real work in an unrelated renderer, for a token combination nobody has reported using. Explicitly not built now.

## Risks / Trade-offs

- **[Risk] Simplified boundaries misattribute a coordinate very near a border or coastline** → Mitigation: accepted and documented; the caption is decorative, not authoritative. Upgrade path is a finer source revision, noted in code, not built now.
- **[Risk] The flag emoji ignores the user's caption `textColor`, because colour emoji are drawn from their own glyph table** → Mitigation: accepted. A user who has recoloured their caption gets a full-colour flag against it. If that reads badly in practice the fallback is dropping the flag, not recolouring it.
- **[Risk] The two `{gps}` output formats drift apart or the wrong one is wired up** → Mitigation: `EXIFTokenParserTests` asserts both formats explicitly, and a test asserts that substitution through the text-watermark entry point still yields coordinates.
- **[Risk] Bundled dataset grows the app** → Mitigation: **verified at 315 KB.** A 1:10m source is *not* small by construction — it is 13MB of GeoJSON — so the size comes from the build step instead: proportional simplification, and storing each point as a 16-bit fraction of its own country's bounding box rather than as absolute 32-bit degrees. Confirmed byte-for-byte in the built app bundle with no multiplier, where it is smaller than a single bundled font and about a third of the brand logos.

## Open Questions

- ~~The exact public-domain source revision to build from, and how aggressively to simplify it~~ — settled: Natural Earth `ne_10m_admin_0_countries` at `v5.1.2`, simplified with a per-ring proportional Douglas-Peucker tolerance. Pinned in `tools/geo/README.md` and validated against the small-territory fixture list in `CountryResolverTests`. Note this was *not* purely an implementation detail after all: the resolution determines which countries exist at all, and the revision first written into this design could not have satisfied the spec. See D2.
