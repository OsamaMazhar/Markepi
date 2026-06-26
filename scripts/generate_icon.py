#!/usr/bin/env python3
"""
Markepi app icon generator.

Produces a layered 1024x1024 iOS app icon in three appearances so iOS 26 can
apply its Liquid Glass treatment and support Dark + Tinted modes:

  icon-any.png    — full-color (Light / Any appearance)
  icon-dark.png   — dark luminosity appearance
  icon-tinted.png — tinted appearance (grayscale plate + luminance foreground)

Design language:
  - A stack of translucent rounded "glass" sheets, offset diagonally — the
    watermark-overlay metaphor (layering one image over another).
  - A bold "M" monogram (Markepi).
  - A corner notch/fold hinting at a stamped corner watermark.

Rendered at 4x supersampling then downscaled with LANCZOS for crisp edges.
"""

from __future__ import annotations

import math
import os

from PIL import Image, ImageDraw, ImageFilter, ImageFont

# --- configuration ---------------------------------------------------------

SIZE = 1024            # final iOS single-size app icon
SS = 4                 # supersample factor
W = H = SIZE * SS      # working canvas

OUTPUT_DIR = os.path.join(os.path.dirname(__file__), "..", "App", "Assets.xcassets", "AppIcon.appiconset")

FONT_PATH = "/System/Library/Fonts/Avenir Next.ttc"
FONT_INDEX = 0  # Avenir Next Regular; we bump size + use stroke for weight


# --- helpers ---------------------------------------------------------------

def lerp(a, b, t):
    return a + (b - a) * t


def mix(c1, c2, t):
    return tuple(int(lerp(c1[i], c2[i], t)) for i in range(3))


def diagonal_gradient(size, c_top_left, c_bottom_right):
    """Diagonal linear gradient filling a square of `size`."""
    img = Image.new("RGB", (size, size))
    px = img.load()
    for y in range(size):
        for x in range(size):
            t = (x + y) / (2 * size - 2)
            px[x, y] = mix(c_top_left, c_bottom_right, t)
    return img


def radial_highlight(size, center, radius, color, max_alpha):
    """Soft radial glow added to an RGBA layer."""
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    cx, cy = center
    steps = 40
    for i in range(steps, 0, -1):
        t = i / steps
        r = int(radius * t)
        a = int(max_alpha * (1 - t) ** 2)
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(*color, a))
    return layer.filter(ImageFilter.GaussianBlur(radius // 6))


def rrect(draw, box, radius, **kw):
    draw.rounded_rectangle(box, radius=radius, **kw)


def glass_sheet(size, box, radius, fill_rgba, stroke_rgba=None, stroke_w=0, blur=0):
    """One translucent rounded-rectangle 'glass' sheet on its own RGBA layer."""
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    rrect(d, box, radius, fill=fill_rgba)
    if stroke_rgba and stroke_w:
        rrect(d, box, radius, outline=stroke_rgba, width=stroke_w)
    if blur:
        layer = layer.filter(ImageFilter.GaussianBlur(blur))
    return layer


def soft_shadow(size, box, radius, color, alpha, blur, offset):
    """Drop shadow for a rounded rectangle."""
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    ox, oy = offset
    b = [box[0] + ox, box[1] + oy, box[2] + ox, box[3] + oy]
    rrect(d, b, radius, fill=(*color, alpha))
    return layer.filter(ImageFilter.GaussianBlur(blur))


def load_font(weight_index, size):
    return ImageFont.truetype(FONT_PATH, size, index=weight_index)


# --- composition -----------------------------------------------------------

def base_background(palette):
    bg = diagonal_gradient(W, palette["bg_tl"], palette["bg_br"]).convert("RGBA")
    glow = radial_highlight(
        W,
        center=(int(W * 0.30), int(W * 0.22)),
        radius=int(W * 0.55),
        color=palette["glow"],
        max_alpha=palette["glow_alpha"],
    )
    bg.alpha_composite(glow)
    # subtle bottom vignette
    vig = radial_highlight(
        W,
        center=(int(W * 0.7), int(W * 0.85)),
        radius=int(W * 0.6),
        color=palette["vig"],
        max_alpha=palette["vig_alpha"],
    )
    bg.alpha_composite(vig)
    return bg


def monogram_layer(text, color_rgba, stroke_rgba, font):
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    # measure
    bbox = d.textbbox((0, 0), text, font=font, anchor="mm")
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    cx, cy = W / 2, H / 2 + int(H * 0.02)
    # stroke for weight
    sw = max(6, int(W * 0.012))
    d.text((cx, cy), text, font=font, anchor="mm",
           fill=color_rgba, stroke_width=sw, stroke_fill=stroke_rgba)
    return layer


def build_icon(palette):
    canvas = base_background(palette)

    pad = int(W * 0.16)           # inner content padding
    radius = int(W * 0.22)        # big rounded corners on sheets
    box_w = W - 2 * pad

    # three offset glass sheets (back -> front)
    offsets = [(-int(W * 0.055), -int(H * 0.055)),
               (-int(W * 0.022), -int(H * 0.022)),
               (0, 0)]

    # shadow under the stack
    front_box = [pad, pad, pad + box_w, pad + box_w]
    sh = soft_shadow(W, front_box, radius,
                     palette["shadow"], palette["shadow_alpha"],
                     blur=int(W * 0.05),
                     offset=(int(W * 0.02), int(W * 0.05)))
    canvas.alpha_composite(sh)

    for i, (ox, oy) in enumerate(offsets):
        b = [pad + ox, pad + oy, pad + box_w + ox, pad + box_w + oy]
        fill = palette["sheets"][i]
        stroke = palette["strokes"][i]
        sheet = glass_sheet(W, b, radius, fill, stroke_rgba=stroke,
                            stroke_w=int(W * 0.004))
        canvas.alpha_composite(sheet)

    # corner fold (stamped-corner watermark hint)
    fold = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    fd = ImageDraw.Draw(fold)
    fs = int(W * 0.16)  # fold size
    fx0 = pad + box_w - fs
    fy0 = pad
    fx1 = pad + box_w
    fy1 = pad + fs
    fd.polygon([(fx0, fy1), (fx1, fy1), (fx1, fy0)],
               fill=palette["fold_fill"])
    fd.line([(fx0, fy1), (fx1, fy0)], fill=palette["fold_line"],
            width=int(W * 0.006))
    canvas.alpha_composite(fold)

    # monogram
    font = load_font(palette["font_index"], int(W * 0.42))
    mono = monogram_layer("M", palette["mono"], palette["mono_stroke"], font)
    canvas.alpha_composite(mono)

    return canvas.resize((SIZE, SIZE), Image.LANCZOS)


# --- palettes --------------------------------------------------------------

LIGHT = {
    "bg_tl": (99, 102, 241),      # indigo-500
    "bg_br": (139, 92, 246),      # violet-500
    "glow": (196, 181, 253),      # soft violet glow
    "glow_alpha": 90,
    "vig": (49, 46, 129),         # indigo-900 vignette
    "vig_alpha": 70,
    "sheets": [
        (255, 255, 255, 70),
        (255, 255, 255, 90),
        (255, 255, 255, 115),
    ],
    "strokes": [(255, 255, 255, 120)] * 3,
    "shadow": (30, 27, 75),
    "shadow_alpha": 130,
    "fold_fill": (255, 255, 255, 150),
    "fold_line": (255, 255, 255, 235),
    "mono": (255, 255, 255, 255),
    "mono_stroke": (255, 255, 255, 255),
    "font_index": 1,  # Avenir Next Medium/Heavy — index varies; set below
}

DARK = {
    "bg_tl": (10, 10, 18),
    "bg_br": (22, 22, 38),
    "glow": (99, 102, 241),
    "glow_alpha": 80,
    "vig": (5, 5, 12),
    "vig_alpha": 110,
    "sheets": [
        (226, 232, 255, 28),
        (226, 232, 255, 40),
        (226, 232, 255, 58),
    ],
    "strokes": [(226, 232, 255, 70)] * 3,
    "shadow": (0, 0, 0),
    "shadow_alpha": 160,
    "fold_fill": (226, 232, 255, 70),
    "fold_line": (226, 232, 255, 200),
    "mono": (233, 235, 245, 255),
    "mono_stroke": (233, 235, 245, 255),
    "font_index": 1,
}

TINTED = {
    "bg_tl": (28, 28, 30),
    "bg_br": (28, 28, 30),
    "glow": (255, 255, 255),
    "glow_alpha": 0,
    "vig": (0, 0, 0),
    "vig_alpha": 0,
    "sheets": [
        (255, 255, 255, 40),
        (255, 255, 255, 55),
        (255, 255, 255, 80),
    ],
    "strokes": [(255, 255, 255, 90)] * 3,
    "shadow": (0, 0, 0),
    "shadow_alpha": 0,
    "fold_fill": (255, 255, 255, 120),
    "fold_line": (255, 255, 255, 255),
    "mono": (255, 255, 255, 255),
    "mono_stroke": (255, 255, 255, 255),
    "font_index": 1,
}


def pick_heavy_font_index():
    """Avenir Next.ttc weight ordering: 0 Regular,1 Medium,2 Semibold,3 Bold,
    4 Black,5 Heavy,6 Ultra. Prefer Heavy (5)."""
    try:
        from PIL import ImageFont
        for idx in (5, 6, 4, 3, 2, 1, 0):
            ImageFont.truetype(FONT_PATH, 64, index=idx)
            return idx
        return 1
    except Exception:
        return 1


def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    heavy = pick_heavy_font_index()
    for pal in (LIGHT, DARK, TINTED):
        pal["font_index"] = heavy

    out_any = os.path.join(OUTPUT_DIR, "icon-any.png")
    out_dark = os.path.join(OUTPUT_DIR, "icon-dark.png")
    out_tinted = os.path.join(OUTPUT_DIR, "icon-tinted.png")

    build_icon(LIGHT).save(out_any, "PNG")
    build_icon(DARK).save(out_dark, "PNG")
    build_icon(TINTED).save(out_tinted, "PNG")

    # a contact sheet preview
    preview = Image.new("RGB", (SIZE * 3 + 60, SIZE + 40), (240, 240, 245))
    for i, p in enumerate((out_any, out_dark, out_tinted)):
        img = Image.open(p).convert("RGB")
        preview.paste(img, (20 + i * (SIZE + 20), 20))
    preview.save(os.path.join(OUTPUT_DIR, "preview.png"), "PNG")

    print(f"wrote: {out_any}")
    print(f"wrote: {out_dark}")
    print(f"wrote: {out_tinted}")
    print(f"wrote: {os.path.join(OUTPUT_DIR, 'preview.png')}")


if __name__ == "__main__":
    main()
