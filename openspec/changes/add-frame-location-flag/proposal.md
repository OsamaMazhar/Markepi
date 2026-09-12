## Why

The `{gps}` caption token (`CaptionField.gps`, displayed as "Location") renders raw coordinates — `"37.7749° N, 122.4194° W"` — which is accurate but unreadable at a glance and does not match how the photography community actually captions a shot: a place name and its flag. Every existing metadata field in this frame is human-readable text; GPS is the one field a viewer cannot parse without doing the conversion themselves.

## What Changes

- **Location caption reads as a place, not coordinates.** In a frame caption the `{gps}` token's output changes from raw lat/lon to a pin glyph, the resolved country's localized name, and that country's flag — e.g. `📍 France 🇫🇷`. This is a content change to the existing `.gps` field, used by both `classic`'s caption line and `gallery`'s caption slots; no new `CaptionField` case.
- **The free text watermark layer keeps coordinates.** `{gps}` also substitutes into the user's free text watermark, and that renderer draws glyphs as a white alpha mask and tints them, which would flatten a colour flag emoji into a solid blob. That path keeps today's coordinate output, unchanged. The new place formatting is reached only from the frame caption path — see design.md D7.
- **New offline country resolver.** A new on-device lookup resolves a GPS coordinate to an ISO 3166-1 alpha-2 country code with no network access: simplified country boundary polygons bundled as a package resource, with a per-country bounding-box prefilter ahead of a ray-casting point-in-polygon test. Country name and flag are then derived from the code alone: `Locale.localizedString(forRegionCode:)` for the name (no bundled name table), and an algorithmic Unicode Regional Indicator mapping for the flag (no bundled flag images) — both already free of network or heavy computation.
- **Coordinates are signed before lookup.** The `{GPS}` metadata dictionary stores latitude and longitude as *absolute* values with `LatitudeRef`/`LongitudeRef` carrying the hemisphere, and the app's own video path writes them that way too. The resolver takes signed degrees, so the caption path applies the refs first. Without this every southern or western coordinate resolves to the wrong country.
- **Country only, not city.** The resolver identifies the country a photo was taken in, not the locality. A city name would require a much larger place gazetteer and a nearest-neighbor search; out of scope for this change.
- **Consistent fallback.** No GPS metadata, or a coordinate that falls in no country's boundary (open ocean), both render as `--` and are elided by the existing missing-field handling — the same behavior every other metadata field already has. Nothing crashes or shows a wrong hardcoded default.
- **One-time offline dataset build.** The boundary resource is generated once from a public-domain source by a repo-local build script (`tools/geo/`, mirroring `tools/logos/build-logos.sh`'s convention of regenerating a shipped resource from source data) — never computed or fetched at runtime.

## Capabilities

### New Capabilities
- `offline-geolocation`: resolving a GPS coordinate to a country, entirely on-device and offline — the boundary lookup, the country name/flag derivation, and their combined fallback behavior. Kept separate from `photo-frames` because it is a general-purpose, metadata-agnostic capability that a caption field merely consumes; the caption itself stays a `photo-frames` concern.

### Modified Capabilities
- `photo-frames`: the `{gps}` / `Location` caption field's rendered content changes from raw coordinates to a pin glyph, resolved country name, and flag, sourced from the new `offline-geolocation` capability. No other frame behavior (styles, geometry, other fields) changes.

## Impact

- **New utility** — `Packages/WatermarkCore/Sources/WatermarkCore/Utilities/`: a `CountryResolver` (or similarly named) type wrapping the polygon lookup, name lookup, and flag derivation.
- **New resource** — bundled simplified country boundaries, added to `WatermarkCore`'s `Package.swift` resources alongside the existing `Fonts`/`Logos` entries.
- **New build tooling** — `tools/geo/`: a one-time script that regenerates the bundled boundaries from a public-domain source; not part of the app build or CI runtime path.
- **Modified** — `EXIFTokenParser.swift`: `formatGPS` gains a place-formatted variant reached from the caption path, applying `LatitudeRef`/`LongitudeRef` to produce signed degrees before resolving. The existing coordinate output stays as the default so `TextWatermarkRenderer`'s token substitution is unaffected.
- **Unchanged** — `TextWatermarkRenderer.swift`: no edit, but it is the reason the coordinate formatting has to stay reachable. Its alpha-mask tinting cannot render a colour emoji.
- **Tests** — `EXIFTokenParserTests` gains a GPS case group covering the place format, the coordinate format, and all four hemisphere quadrants; a new resolver unit-test target covers known coordinates, small territories, ocean coordinates, and the missing-GPS case. `CaptionBuilderTests` gains coverage for the new rendered text where `.gps` is used as a slot.
- **No UI change** — the location field is already offered in both styles' pickers; only its rendered text changes.
