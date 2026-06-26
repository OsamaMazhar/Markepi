#!/usr/bin/env python3
"""
Extract a clean, transparent foreground (white frame + "M") from the source
mock-up Copilot_20260623_215106.png for Apple Icon Composer.

Source structure (verified):
  - a near full-bleed blue rounded square (touches all four edge midpoints)
  - white only in the four rounded-corner gaps
  - white inner frame + stylised "M" inside the blue

For a layered Liquid-Glass icon we want:
  - blue  -> re-tintable BACKGROUND FILL (set via `icon-composer fill`)
  - inner white frame + M -> transparent FOREGROUND layer

Strategy:
  1. Binary white mask (min channel high).
  2. Connected-component label the white mask; any component touching the
     image border is an outer corner-gap -> dropped. Interior components
     (frame + M) are kept.
  3. Alpha = normalised whiteness for smooth anti-aliased edges; RGB = white.
  4. Output 1024x1024 (source is already full-bleed, so no crop needed).
"""
from __future__ import annotations

import os

import numpy as np
from PIL import Image
from scipy import ndimage

SRC = "/Users/osama/Projects/Watermark/Copilot_20260623_215106.png"
OUT = "/Users/osama/Projects/Watermark/icons/src/foreground.png"
OUT_SIZE = 1024

WHITE_THRESH = 170
BLUE_MIN = 30.0
WHITE_MAX = 254.0


def main() -> None:
    img = Image.open(SRC).convert("RGB")
    arr = np.asarray(img).astype(np.float32)
    h, w, _ = arr.shape
    minc = arr.min(axis=2)

    white = minc >= WHITE_THRESH
    labels, n = ndimage.label(white)

    # any component touching the border = outer corner-gap -> drop
    border_ids = set(labels[0, :]) | set(labels[-1, :]) \
        | set(labels[:, 0]) | set(labels[:, -1])
    border_ids.discard(0)
    interior = white & ~np.isin(labels, list(border_ids))
    print(f"components={n} border_drop={sorted(border_ids)} "
          f"interior_px={interior.sum()}")

    # alpha = whiteness, restricted to interior white shapes
    alpha = np.clip((minc - BLUE_MIN) / (WHITE_MAX - BLUE_MIN), 0.0, 1.0)
    alpha[~interior] = 0.0
    alpha8 = (alpha * 255).astype(np.uint8)

    rgba = np.zeros((h, w, 4), dtype=np.uint8)
    rgba[:, :, :3] = 255
    rgba[:, :, 3] = alpha8
    fg = Image.fromarray(rgba, "RGBA")

    # pad to square (source is 695x671) then resize to 1024
    side = max(w, h)
    sq = Image.new("RGBA", (side, side), (255, 255, 255, 0))
    sq.paste(fg, ((side - w) // 2, (side - h) // 2))
    out = sq.resize((OUT_SIZE, OUT_SIZE), Image.LANCZOS)

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    out.save(OUT)
    print(f"wrote {OUT} ({OUT_SIZE}x{OUT_SIZE})")


if __name__ == "__main__":
    main()
