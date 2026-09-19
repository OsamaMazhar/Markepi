# Country boundary data

Builds `Packages/WatermarkCore/Sources/WatermarkCore/Resources/Geo/countries.bin`,
the offline coordinate-to-country lookup behind the location caption field.

```sh
python3 tools/geo/build-country-boundaries.py
```

Run by a maintainer when the boundaries need regenerating. The output is
committed; the app never generates or fetches it, and neither does CI. Same
convention as `tools/logos/build-logos.sh`.

## Source

| | |
|---|---|
| Dataset | Natural Earth `ne_10m_admin_0_countries` |
| Revision | `v5.1.2`, pinned in `SOURCE_URL` |
| Mirror | `github.com/nvkelso/natural-earth-vector` |
| Licence | Public domain |

The download is cached at `tools/geo/.cache-ne10.geojson` (git-ignored, 13MB).
Delete it to re-fetch.

## Why 1:10m and not 1:110m

The plan originally assumed Natural Earth's 1:110m set, on the reasoning that a
country outline for a decorative caption does not need much detail. That is true
of the *outlines* and false of the *country list*: 1:110m carries 177 features
and simply does not contain Monaco, Vatican City, Liechtenstein, Andorra, San
Marino, Malta, Bahrain or Singapore.

Those are precisely the territories the capability spec requires to resolve, and
the same ones that ruled out a pre-baked coordinate grid. Shipping 1:110m would
have reproduced the exact failure the approach was chosen to avoid, so the
source is 1:10m — 258 features, every micro-state present — and the size is
taken back out by simplification instead.

## What the script does

1. Keeps each feature's ISO 3166-1 alpha-2 code (`ISO_A2_EH`, falling back to
   `ISO_A2`). A feature with no valid code is dropped: it has no flag emoji, so
   it could not caption anything anyway.
2. Simplifies every ring with Douglas-Peucker at a tolerance **proportional to
   that ring's own span**, not a flat one. A flat tolerance is what destroys
   micro-states — 0.08° is a rounding error on Brazil and four times the width
   of Monaco.
3. Drops islands under `MIN_ISLAND_SPAN`, but never a country's last ring, so
   every country stays resolvable somewhere.
4. Keeps outer rings only. Interior rings are enclaves, and the resolver's
   smallest-match rule already handles those: Italy's polygon covers San Marino
   and Vatican City, and both win over Italy because their bounding boxes are
   smaller.
5. Writes the binary described below.

## Format

Little-endian throughout. Each country's bounding box is absolute; each of its
points is a 16-bit fraction *of that box*. That is half the bytes of absolute
32-bit coordinates, and the precision lands where it is needed: a point resolves
to span/65535, so Russia is good to ~300m (finer than the simplification) and
Vatican City to well under a metre.

```
"MKGEO2\0\0"                     8 bytes, magic
u32 countryCount
  repeated countryCount times:
    char[2]  ISO 3166-1 alpha-2
    u16      ringCount
    i32 x4   bbox: minLat, minLon, maxLat, maxLon, at 1e6
      repeated ringCount times:
        u32    pointCount
        u16 x2 per point: lat fraction, lon fraction, of the bbox
```

Bump the magic when the layout changes; `CountryResolver` rejects a file whose
magic it does not recognise and then resolves nothing, which degrades to the
same caption a photo with no GPS already gets.

## Current output

| | |
|---|---|
| Countries | 239 |
| Points | 75,732 |
| Size | 315 KB |

For scale, that is smaller than a single bundled font and about a third of the
brand logos.

## Tuning

`BASE_TOLERANCE` trades size against border accuracy; `MIN_ISLAND_SPAN` trades
size against small-island coverage. Raise either to shrink the file. If border
misattribution is ever reported, lower `BASE_TOLERANCE` and rebuild — neither
the format nor `CountryResolver` changes.

Re-run `swift test --filter CountryResolverTests` after any rebuild. Its
small-territory and hemisphere cases are what catch a tolerance that has been
pushed too far.
