#!/usr/bin/env bash
# Import a supplied brand mark into the app's logo resources.
#
#   tools/logos/import-logo.sh <brand-key> <color|mono> path/to/artwork.svg
#
# SVG is converted to a single-page PDF with rsvg-convert; a PDF is copied as
# is. Either way the result is checked with CGPDFDocument — the same check the
# app does at runtime — so a file that lands here is known to open and draw.
set -euo pipefail

LOGO_DIR="Packages/WatermarkCore/Sources/WatermarkCore/Resources/Logos"
README="$LOGO_DIR/README.md"

die() { echo "error: $*" >&2; exit 1; }

[ $# -eq 3 ] || die "usage: $0 <brand-key> <color|mono> <artwork.svg|.pdf>"
brand="$1"; variant="$2"; src="$3"

[ -f "$src" ] || die "no such file: $src"
case "$variant" in color|mono) ;; *) die "variant must be 'color' or 'mono', got '$variant'" ;; esac

# Brand keys come from the README table, so there is one list, not two.
keys=$(sed -n 's/^| `\([a-z]*\)` .*/\1/p' "$README")
grep -qx "$brand" <<<"$keys" || die "unknown brand key '$brand'. Known: $(tr '\n' ' ' <<<"$keys")"

out="$LOGO_DIR/$brand-$variant.pdf"
case "$src" in
    *.svg|*.SVG)
        command -v rsvg-convert >/dev/null || die "rsvg-convert not found (brew install librsvg)"
        rsvg-convert -f pdf -o "$out" "$src"
        ;;
    *.pdf|*.PDF)
        cp "$src" "$out"
        ;;
    *)
        die "expected .svg or .pdf, got: $src"
        ;;
esac

tools/logos/check-pdf.swift "$out" || { rm -f "$out"; die "converted file failed its check; not imported"; }
echo "imported $out"
echo "Now add its source and licence to the provenance table in $README"
