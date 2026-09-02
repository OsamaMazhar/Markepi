#!/usr/bin/env bash
# Rebuild the shipped brand marks from the artwork in LogoSources/.
#
#   tools/logos/build-logos.sh
#
# Sources are per-brand folders of supplied artwork. This produces the flat,
# uniformly named set the app actually loads:
#
#   <brand>-color.pdf   from <brand>.svg          — vector, every brand
#   <brand>-black.pdf   from <brand>-black.svg    — vector, where supplied
#   <brand>-black.png   from <brand>-black.png    — 1024px, otherwise
#   <brand>-white.*     same rule as black
#
# Vector wins where a vector exists. The 1024px monochrome rasters are only
# ever downscaled — a mark draws at a few hundred pixels even on a 48MP export
# — so they never soften in practice.
set -euo pipefail

SRC="Packages/WatermarkCore/LogoSources"
OUT="Packages/WatermarkCore/Sources/WatermarkCore/Resources/Logos"

command -v rsvg-convert >/dev/null || { echo "error: rsvg-convert not found (brew install librsvg)" >&2; exit 1; }
[ -d "$SRC" ] || { echo "error: no $SRC" >&2; exit 1; }

mkdir -p "$OUT"
find "$OUT" -name '*.pdf' -delete
find "$OUT" -name '*.png' -delete

vectors=0; rasters=0; brands=0
for dir in "$SRC"/*/; do
    brand=$(basename "$dir")
    brands=$((brands + 1))

    # color: always from the vector
    if [ -f "$dir/$brand.svg" ]; then
        rsvg-convert -f pdf -o "$OUT/$brand-color.pdf" "$dir/$brand.svg"
        vectors=$((vectors + 1))
    else
        echo "warn: $brand has no colour vector" >&2
    fi

    # black / white: vector if supplied, else the official 1024px raster
    for variant in black white; do
        if [ -f "$dir/$brand-$variant.svg" ]; then
            rsvg-convert -f pdf -o "$OUT/$brand-$variant.pdf" "$dir/$brand-$variant.svg"
            vectors=$((vectors + 1))
        elif [ -f "$dir/$brand-$variant.png" ]; then
            cp "$dir/$brand-$variant.png" "$OUT/$brand-$variant.png"
            rasters=$((rasters + 1))
        fi
    done
done

echo "built $brands brands: $vectors vector, $rasters raster -> $OUT"
tools/logos/check-pdf.swift "$OUT"/*.pdf | grep -c '^ok' | xargs -I{} echo "{} PDFs pass the CGPDFDocument check"
