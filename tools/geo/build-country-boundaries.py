#!/usr/bin/env python3
"""Build the bundled country-boundary resource from Natural Earth.

Run by a maintainer, not by the app and not by CI — the output is committed.
Mirrors tools/logos/build-logos.sh: regenerate a shipped resource from source
data, keep the source out of the app bundle.

    python3 tools/geo/build-country-boundaries.py

Writes Packages/WatermarkCore/Sources/WatermarkCore/Resources/Geo/countries.bin.
See README.md in this directory for provenance and for why 1:10m is the source
rather than the lighter 1:110m.
"""

import json
import os
import struct
import sys
import urllib.request

# 1:10m, not 1:110m. The lighter set drops every micro-state — Monaco,
# Vatican, Liechtenstein, Andorra, San Marino, Malta, Bahrain and Singapore are
# all absent from it — and a flag caption that cannot flag a city-state is the
# whole thing we are trying not to ship.
SOURCE_URL = (
    "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/"
    "v5.1.2/geojson/ne_10m_admin_0_countries.geojson"
)

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
OUT = os.path.join(
    REPO, "Packages/WatermarkCore/Sources/WatermarkCore/Resources/Geo/countries.bin"
)
CACHE = os.path.join(HERE, ".cache-ne10.geojson")

# Each country's bounding box is stored as absolute integer degrees at this
# scale (1e6 is ~0.1m), and every point of that country is then stored as a
# 16-bit fraction *of its own bounding box*.
#
# That is half the bytes of absolute 32-bit coordinates and better precision
# where it matters: a point resolves to span/65535, so Russia lands within
# ~300m (finer than the simplification tolerance anyway) while Vatican City,
# whose box is 0.005 degrees across, resolves to well under a metre. One
# uniform rule, no escape cases, no per-country precision table.
BBOX_SCALE = 1_000_000
POINT_MAX = 65_535

# Douglas-Peucker tolerance in degrees for a large country, about 9km. Small
# rings get a proportionally tighter tolerance (see simplify_ring) so this does
# not flatten a city-state into nothing. A country outline is decoration here,
# not a map: the caption says "France", and it says it from a point tens of
# kilometres inside the border just as well as from one metre inside it.
BASE_TOLERANCE = 0.08

# An island smaller than this across is dropped, but never the last ring of a
# country — a country always keeps at least one ring.
MIN_ISLAND_SPAN = 0.05

MAGIC = b"MKGEO2\0\0"


def download():
    if not os.path.exists(CACHE):
        sys.stderr.write("downloading Natural Earth 1:10m admin-0 ...\n")
        urllib.request.urlretrieve(SOURCE_URL, CACHE)
    with open(CACHE) as handle:
        return json.load(handle)


def perpendicular_distance(point, start, end):
    (px, py), (x1, y1), (x2, y2) = point, start, end
    dx, dy = x2 - x1, y2 - y1
    if dx == 0 and dy == 0:
        return ((px - x1) ** 2 + (py - y1) ** 2) ** 0.5
    t = ((px - x1) * dx + (py - y1) * dy) / (dx * dx + dy * dy)
    t = max(0.0, min(1.0, t))
    return ((px - (x1 + t * dx)) ** 2 + (py - (y1 + t * dy)) ** 2) ** 0.5


def douglas_peucker(points, tolerance):
    """Iterative Douglas-Peucker; recursion would blow the stack on Antarctica."""
    if len(points) < 3:
        return points
    keep = [False] * len(points)
    keep[0] = keep[-1] = True
    stack = [(0, len(points) - 1)]
    while stack:
        first, last = stack.pop()
        if last <= first + 1:
            continue
        worst, worst_index = -1.0, first
        for i in range(first + 1, last):
            d = perpendicular_distance(points[i], points[first], points[last])
            if d > worst:
                worst, worst_index = d, i
        if worst > tolerance:
            keep[worst_index] = True
            stack.append((first, worst_index))
            stack.append((worst_index, last))
    return [p for p, k in zip(points, keep) if k]


def ring_span(ring):
    xs = [p[0] for p in ring]
    ys = [p[1] for p in ring]
    return max(max(xs) - min(xs), max(ys) - min(ys))


def simplify_ring(ring):
    """Simplify one ring, scaled so small shapes keep their shape.

    A flat tolerance is what destroys micro-states: 0.011 degrees is a
    rounding error on Brazil and the entire width of Monaco. Tying the
    tolerance to the ring's own span means every country is simplified by the
    same *proportion* rather than the same absolute distance.
    """
    span = ring_span(ring)
    tolerance = min(BASE_TOLERANCE, span / 40.0)
    simplified = douglas_peucker(ring, tolerance)
    # A ring needs three distinct corners to enclose anything. Below that, fall
    # back to the ring's own bounding box so the territory still resolves.
    if len(simplified) < 4:
        xs = [p[0] for p in ring]
        ys = [p[1] for p in ring]
        lo_x, hi_x, lo_y, hi_y = min(xs), max(xs), min(ys), max(ys)
        simplified = [(lo_x, lo_y), (hi_x, lo_y), (hi_x, hi_y), (lo_x, hi_y)]
    return simplified


def country_code(props):
    for key in ("ISO_A2_EH", "ISO_A2"):
        value = (props.get(key) or "").strip()
        if len(value) == 2 and value.isalpha() and value.isupper():
            return value
    return None


def build():
    data = download()
    countries = {}

    for feature in data["features"]:
        code = country_code(feature["properties"])
        if code is None:
            continue  # disputed or unassigned: no ISO code means no flag anyway
        geometry = feature["geometry"]
        polygons = (
            geometry["coordinates"]
            if geometry["type"] == "MultiPolygon"
            else [geometry["coordinates"]]
        )

        rings = []
        for polygon in polygons:
            # Outer ring only. Holes are enclaves of another country, and a
            # decorative caption that says "Italy" a few hundred metres inside
            # San Marino is not worth carrying every interior ring for.
            outer = [tuple(p[:2]) for p in polygon[0]]
            if len(outer) < 4:
                continue
            rings.append((ring_span(outer), simplify_ring(outer)))

        if not rings:
            continue
        # Drop slivers, but never everything: the biggest ring always stays.
        rings.sort(key=lambda r: r[0], reverse=True)
        kept = [rings[0][1]] + [r[1] for r in rings[1:] if r[0] >= MIN_ISLAND_SPAN]
        countries.setdefault(code, []).extend(kept)

    out = bytearray(MAGIC)
    out += struct.pack("<I", len(countries))
    total_points = 0

    for code in sorted(countries):
        rings = countries[code]
        lons = [p[0] for ring in rings for p in ring]
        lats = [p[1] for ring in rings for p in ring]
        min_lat, max_lat = min(lats), max(lats)
        min_lon, max_lon = min(lons), max(lons)
        # A zero-width box would divide by zero on both sides; give it a floor.
        lat_span = max(max_lat - min_lat, 1e-9)
        lon_span = max(max_lon - min_lon, 1e-9)

        out += code.encode("ascii")
        out += struct.pack("<H", len(rings))
        out += struct.pack(
            "<iiii",
            round(min_lat * BBOX_SCALE), round(min_lon * BBOX_SCALE),
            round(max_lat * BBOX_SCALE), round(max_lon * BBOX_SCALE),
        )
        for ring in rings:
            out += struct.pack("<I", len(ring))
            for lon, lat in ring:
                fx = round((lat - min_lat) / lat_span * POINT_MAX)
                fy = round((lon - min_lon) / lon_span * POINT_MAX)
                out += struct.pack("<HH", min(POINT_MAX, max(0, fx)),
                                   min(POINT_MAX, max(0, fy)))
                total_points += 1

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "wb") as handle:
        handle.write(out)

    print(f"countries: {len(countries)}")
    print(f"points:    {total_points}")
    print(f"written:   {OUT} ({len(out) / 1024:.0f} KB)")


if __name__ == "__main__":
    build()
