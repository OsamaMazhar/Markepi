## Context

`EXIFTokenParser.formatGPS` (Packages/WatermarkCore/Sources/WatermarkCore/Utilities/EXIFTokenParser.swift) currently reads `metadata["{GPS}"]["Latitude"/"Longitude"/"LatitudeRef"/"LongitudeRef"]` and formats raw coordinates. That token feeds both `classic`'s `captionFields` list and `gallery`'s `CaptionSlot`s via `WhiteFrameRenderer.resolveSlot`, which already treats a literal `"--"` result as "missing" and elides it from the caption (see `resolveSlot`'s `words.filter { $0 != "--" }`). This change only needs to change what `formatGPS` returns; the missing-field plumbing already exists and needs no changes.

There is no reverse-geocoding or country-boundary data anywhere in the codebase today. The user asked about `CLGeocoder`/MapKit specifically; both require a network round trip to Apple's geocoding service (there is no offline mode, and no public Apple API for on-device coordinate→country lookup), which conflicts with the hard "no network access" requirement — so this change has to bring its own compact, bundled dataset.

## Goals / Non-Goals

**Goals:**
- Resolve a GPS coordinate to a country entirely on-device, with no network dependency, at negligible CPU cost per export.
- Reuse the existing "--"-means-missing convention rather than inventing a new fallback path.
- Keep the bundled dataset small — this is a decorative caption, not a mapping product.

**Non-Goals:**
- City/locality resolution (confirmed out of scope by the user; would need a much larger place gazetteer and a nearest-neighbor search).
- Survey- or legal-grade border accuracy. A coordinate near a border may resolve to the wrong side; that is accepted, not fixed, by this change.
- Any UI change — the location field is already selectable in both styles; only its rendered text changes.

## Decisions

### D1: Reject CLGeocoder / MapKit reverse geocoding
Both require network access to Apple's geocoding service; there's no documented offline mode and no separate offline-capable Apple API for coordinate→country lookup. Since offline operation is a hard requirement, these are ruled out regardless of the country-only scope. Recorded here so the choice isn't revisited without new information.

### D2: A bundled coarse coordinate grid, not real polygon boundaries
Two on-device approaches were considered:
- **Point-in-polygon against simplified country boundaries** (e.g. Natural Earth 1:110m) — the more "correct" approach, but variable per-lookup cost (ring traversal, multipolygons for archipelagos/exclaves) and more code (geometry, winding rules).
- **A pre-baked coordinate grid** (chosen): at dataset-build time, sample the same kind of boundary source on a coarse regular grid (e.g. every 0.5°–1° of latitude/longitude) and record which country's territory covers each cell's center. At runtime, resolution is `floor(lat)`/`floor(lon)` array indexing — O(1), no geometry code, trivially "without a lot of computation" per the user's own framing.

Chosen: the grid. It trades border/coastline precision (a cell can only ever report one country, even where the true boundary crosses it) for a much smaller runtime surface and a dataset size that scales with grid resolution rather than boundary complexity. This is the same kind of accepted-ceiling shortcut this codebase already uses elsewhere (e.g. the brand-mark registry resolving an unsupported manufacturer to "no mark" rather than guessing) — call out explicitly in code as a `ponytail:`-style comment: coarse grid, upgrade path is swapping in real polygons if border-accuracy complaints appear.

### D3: Dataset built offline, once, from public-domain data
A repo-local script under `tools/geo/` (mirroring `tools/logos/build-logos.sh`'s pattern of regenerating a shipped resource from source material, run by a maintainer, not part of the app or CI build) consumes a public-domain country-boundary source (e.g. Natural Earth admin-0) and emits the grid as a small resource bundled into `WatermarkCore`. Never fetched, generated, or computed at runtime.

### D4: Flag and name need no bundled per-country table
Once an ISO 3166-1 alpha-2 code is resolved:
- **Flag**: built algorithmically from the two letters via their Unicode Regional Indicator Symbols (`🇫` = the indicator for 'F', etc.) — every emoji-capable font, including the system font on both iOS and macOS (relevant for the macOS Core Text render path used by `swift test`), already renders the pair as a single flag glyph. No bundled flag assets.
- **Name**: `Locale.localizedString(forRegionCode:)`, using the code alone. Already offline, already localized, ships with the OS.

Both keep the new bundled asset limited to the coordinate grid itself.

### D5: Location field's content changes in place; no new `CaptionField`
`.gps` already means "location" (its `displayName` is "Location"); changing what it renders is a content upgrade, not a new concept. A separate "raw coordinates" field was considered and rejected — nothing in the codebase or the request calls for keeping raw coordinates available, and adding it back speculatively would be scope no one asked for.

## Risks / Trade-offs

- **[Risk] Coarse grid misattributes a coordinate near a border or coastline to the wrong country** → Mitigation: accepted and documented; the caption is decorative, not authoritative. Upgrade path (real polygons) is noted in code, not built now.
- **[Risk] Small territories (city-states, small islands) may fall between grid samples at a coarse resolution** → Mitigation: grid resolution is an implementation parameter (see Open Questions) chosen to keep every populated country resolvable; validated against a fixture list of small-territory coordinates before shipping.
- **[Risk] Bundled dataset grows the app** → Mitigation: a coarse grid is small by construction (tens to low hundreds of KB depending on resolution), far smaller than a polygon or gazetteer dataset would be.

## Open Questions

- Exact grid resolution (e.g. 0.5° vs 1° cells) and the specific public-domain source revision to build it from — an implementation detail that doesn't change the spec, the approach, or the task breakdown; to be settled when `tools/geo/` is actually built, validated against known small-territory coordinates.
