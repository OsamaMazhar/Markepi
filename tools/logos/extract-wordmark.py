#!/usr/bin/env python3
"""Derive a usable monochrome mark from a badge-style brand logo.

Some official logos are a solid shape with the wordmark knocked out of it —
Nikon's yellow square, GoPro's black box, Leica's red circle, realme's and
Xiaomi's rounded rectangles. Taking their silhouette (which is what a
monochrome conversion does) yields a filled block, not a logo.

This drops the badge and keeps the knocked-out wordmark, then crops tight so
the mark fills its own box: the renderer sizes marks by height, and a wordmark
floating in the badge's square canvas would draw a fraction of its intended
size.

Usage: extract-wordmark.py <brand> <keep-index>[,<keep-index>...]
"""
import re
import subprocess
import sys
from pathlib import Path

SRC = Path("Packages/WatermarkCore/LogoSources")
SHAPE = re.compile(r'<(?:path|rect|circle|polygon|ellipse)\b[^>]*?/?>', re.S)


def render(svg_text, out_png, width):
    tmp = Path("/tmp/_wordmark.svg")
    tmp.write_text(svg_text)
    subprocess.run(["rsvg-convert", "-w", str(width), "-o", str(out_png), str(tmp)], check=True)


def alpha_bbox(png):
    from PIL import Image
    im = Image.open(png).convert("RGBA")
    bbox = im.getchannel("A").point(lambda p: 255 if p > 8 else 0).getbbox()
    return bbox, im.size


def main():
    brand, keep = sys.argv[1], {int(i) for i in sys.argv[2].split(",")}
    source = SRC / brand / f"{brand}.svg"
    text = source.read_text()

    root = re.search(r"<svg\b[^>]*>", text, re.S).group(0)
    box = re.search(r'viewBox="([-\d.eE]+)[ ,]+([-\d.eE]+)[ ,]+([-\d.eE]+)[ ,]+([-\d.eE]+)"', root)
    if box:
        vx, vy, vw, vh = (float(g) for g in box.groups())
    else:
        vx = vy = 0.0
        vw = float(re.search(r'width="([\d.]+)', root).group(1))
        vh = float(re.search(r'height="([\d.]+)', root).group(1))

    # Drop the badge, keep the mark. Transforms on wrapping <g>s are left
    # untouched, so the kept paths stay where the artwork put them.
    shapes = SHAPE.findall(text)
    stripped = text
    for index, shape in enumerate(shapes):
        if index not in keep:
            stripped = stripped.replace(shape, "", 1)

    def recolour(svg, colour):
        svg = re.sub(r'fill="(?!none)[^"]*"', f'fill="{colour}"', svg)
        svg = re.sub(r'fill:\s*(?!none)[^;"\']+', f"fill:{colour}", svg)
        return svg

    black = recolour(stripped, "#000000")

    # Crop tight: render once, measure the ink, and restate the viewBox around it.
    probe = Path("/tmp/_wordmark_probe.png")
    render(black, probe, 1600)
    bbox, (pw, ph) = alpha_bbox(probe)
    if bbox is None:
        raise SystemExit(f"{brand}: kept shapes drew nothing — wrong index?")
    x0, y0, x1, y1 = bbox
    ux, uy = vx + vw * x0 / pw, vy + vh * y0 / ph
    uw, uh = vw * (x1 - x0) / pw, vh * (y1 - y0) / ph
    pad = uh * 0.02          # a hair of air, so glyph edges are not clipped
    ux, uy, uw, uh = ux - pad, uy - pad, uw + pad * 2, uh + pad * 2

    for variant, colour in (("black", "#000000"), ("white", "#ffffff")):
        svg = recolour(stripped, colour)
        new_root = re.sub(r'\s(width|height|viewBox|enable-background)="[^"]*"', "", root)
        new_root = new_root[:-1] + (
            f' viewBox="{ux:.3f} {uy:.3f} {uw:.3f} {uh:.3f}"'
            f' width="{uw:.3f}" height="{uh:.3f}">'
        )
        svg = svg.replace(root, new_root, 1)
        out = SRC / brand / f"{brand}-{variant}.svg"
        out.write_text(svg)
        print(f"  {out}  {uw:.0f}x{uh:.0f}  aspect {uw / uh:.2f}")

    # The supplied rasters are the broken silhouettes; the vector now wins, but
    # leaving them would keep shipping a solid block if the SVG ever fails.
    for variant in ("black", "white"):
        stale = SRC / brand / f"{brand}-{variant}.png"
        if stale.exists():
            stale.unlink()
            print(f"  removed {stale.name} (solid-silhouette raster)")


if __name__ == "__main__":
    main()
