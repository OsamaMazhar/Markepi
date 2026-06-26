#!/usr/bin/env python3
"""
Markepi app icon set — 10 creative concepts.

Each concept is built from layered translucent elements so iOS 26 Liquid Glass
can re-tint/re-light it. Every concept renders three appearances:

  Any (Light)  — full color, light plate
  Dark         — dark luminance plate, bright accents
  Tinted       — flat gray plate, luminance-only foreground

All output goes to /Users/osama/Projects/Watermark/icons/<concept>/
plus a top-level contact sheet contact-sheet.png showing all 30 tiles.

Concepts:
  01 glass-stack     — offset glass sheets + M (watermark-overlay metaphor)
  02 droplet         — water droplet with M (water + mark = markepi)
  03 aperture        — camera iris/lens rings + M (photography)
  04 frame-corner    — quartered white frame brackets + M (metadata frame)
  05 wax-seal        — stamped wax seal with M (branded stamp)
  06 polaroid-fanout — fanned polaroid stack + M (photo stack)
  07 halftone-reveal — dot grid whose gap reveals M (print metaphor)
  08 neon-outline    — neon M outline on glass (modern glow)
  09 origami-fold    — folded paper M facets (origami)
  10 ripple-rings    — concentric ripples + M (drop a mark in water)
"""

from __future__ import annotations

import math
import os

from PIL import Image, ImageDraw, ImageFilter, ImageFont

# --- paths & sizes ---------------------------------------------------------

SIZE = 1024
SS = 4
W = H = SIZE * SS

ROOT = "/Users/osama/Projects/Watermark"
OUT_ROOT = os.path.join(ROOT, "icons")

FONT_PATH = "/System/Library/Fonts/Avenir Next.ttc"
HEAVY_IDX = _resolve_heavy = None  # filled in main()


# --- low-level helpers -----------------------------------------------------

def lerp(a, b, t):
    return a + (b - a) * t

def mix(c1, c2, t):
    return tuple(int(lerp(c1[i], c2[i], t)) for i in range(3))

def diagonal_gradient(size, c_tl, c_br):
    img = Image.new("RGB", (size, size))
    px = img.load()
    for y in range(size):
        for x in range(size):
            px[x, y] = mix(c_tl, c_br, (x + y) / (2 * size - 2))
    return img

def radial_glow(size, center, radius, color, max_alpha, falloff=2.0):
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    cx, cy = center
    steps = 48
    for i in range(steps, 0, -1):
        t = i / steps
        r = int(radius * t)
        a = int(max_alpha * (1 - t) ** falloff)
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(*color, a))
    return layer.filter(ImageFilter.GaussianBlur(max(1, radius // 8)))

def rrect(d, box, r, **kw):
    d.rounded_rectangle(box, radius=r, **kw)

def glass_sheet(size, box, r, fill, stroke=None, sw=0, blur=0):
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    rrect(d, box, r, fill=fill)
    if stroke and sw:
        rrect(d, box, r, outline=stroke, width=sw)
    if blur:
        layer = layer.filter(ImageFilter.GaussianBlur(blur))
    return layer

def soft_shadow(size, box, r, color, alpha, blur, offset):
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    ox, oy = offset
    rrect(d, [box[0]+ox, box[1]+oy, box[2]+ox, box[3]+oy], r, fill=(*color, alpha))
    return layer.filter(ImageFilter.GaussianBlur(blur))

def font(size, idx=None):
    return ImageFont.truetype(FONT_PATH, size, index=idx if idx is not None else HEAVY_IDX)

def text_layer(text, color, stroke, sw, anchor="mm", cx=None, cy=None, size=None, idx=None):
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    f = font(size or int(W * 0.42), idx)
    if cx is None: cx = W / 2
    if cy is None: cy = H / 2
    d.text((cx, cy), text, font=f, anchor=anchor, fill=color, stroke_width=sw, stroke_fill=stroke)
    return layer

def blend(base, layer):
    if base.mode != "RGBA":
        base = base.convert("RGBA")
    base.alpha_composite(layer)
    return base


# --- shared background builder ---------------------------------------------

def make_bg(p):
    bg = diagonal_gradient(W, p["bg_tl"], p["bg_br"]).convert("RGBA")
    if p["glow_alpha"]:
        bg = blend(bg, radial_glow(W, p["glow_c"], int(W*0.55), p["glow"], p["glow_alpha"]))
    if p["vig_alpha"]:
        bg = blend(bg, radial_glow(W, p["vig_c"], int(W*0.6), p["vig"], p["vig_alpha"], falloff=1.5))
    return bg


# --- 01 glass-stack --------------------------------------------------------

def c01_glass_stack(p):
    pad = int(W*0.16); r = int(W*0.22); bw = W - 2*pad
    front = [pad, pad, pad+bw, pad+bw]
    canvas = make_bg(p)
    canvas = blend(canvas, soft_shadow(W, front, r, p["shadow"], p["shadow_alpha"], int(W*0.05), (int(W*0.02), int(W*0.05))))
    offs = [(-int(W*0.055), -int(H*0.055)), (-int(W*0.022), -int(H*0.022)), (0,0)]
    for i,(ox,oy) in enumerate(offs):
        b = [pad+ox, pad+oy, pad+bw+ox, pad+bw+oy]
        canvas = blend(canvas, glass_sheet(W, b, r, p["sheets"][i], p["strokes"][i], int(W*0.004)))
    # corner fold
    fold = Image.new("RGBA",(W,H),(0,0,0,0)); fd=ImageDraw.Draw(fold)
    fs=int(W*0.16); fx0=pad+bw-fs; fy0=pad; fx1=pad+bw; fy1=pad+fs
    fd.polygon([(fx0,fy1),(fx1,fy1),(fx1,fy0)], fill=p["fold_fill"])
    fd.line([(fx0,fy1),(fx1,fy0)], fill=p["fold_line"], width=int(W*0.006))
    canvas = blend(canvas, fold)
    canvas = blend(canvas, text_layer("M", p["mono"], p["mono_stroke"], max(6,int(W*0.012))))
    return canvas.resize((SIZE,SIZE), Image.LANCZOS)


# --- 02 droplet ------------------------------------------------------------

def _droplet_path(cx, cy, r):
    """Teardrop pointing down."""
    top = (cx, cy - r*1.6)
    left = (cx - r, cy)
    right = (cx + r, cy)
    bottom = (cx, cy + r*0.95)
    return [top, left, bottom, right]

def c02_droplet(p):
    canvas = make_bg(p)
    r = int(W*0.30)
    cx, cy = W/2, H/2 + int(H*0.04)
    # shadow
    sh = soft_shadow(W, [cx-r, cy-r, cx+r, cy+r*1.6], int(r*0.9), p["shadow"], p["shadow_alpha"], int(W*0.04), (0, int(W*0.04)))
    canvas = blend(canvas, sh)
    # droplet body (glass)
    pts = _droplet_path(cx, cy, r)
    body = Image.new("RGBA",(W,H),(0,0,0,0)); d=ImageDraw.Draw(body)
    d.polygon(pts, fill=p["drop_fill"])
    d.line(pts + [pts[0]], fill=p["drop_line"], width=int(W*0.006), joint="curve")
    body = body.filter(ImageFilter.GaussianBlur(int(W*0.0015) or 0))
    canvas = blend(canvas, body)
    # inner highlight (small offset droplet, brighter, blurred)
    hl = Image.new("RGBA",(W,H),(0,0,0,0)); hd=ImageDraw.Draw(hl)
    hpts = _droplet_path(cx - r*0.18, cy - r*0.10, r*0.55)
    hd.polygon(hpts, fill=p["drop_hi"])
    hl = hl.filter(ImageFilter.GaussianBlur(int(W*0.02)))
    canvas = blend(canvas, hl)
    # M inside
    canvas = blend(canvas, text_layer("M", p["mono"], p["mono_stroke"], max(6,int(W*0.012)), cx=cx, cy=cy+int(r*0.10), size=int(W*0.30)))
    return canvas.resize((SIZE,SIZE), Image.LANCZOS)


# --- 03 aperture ------------------------------------------------------------

def c03_aperture(p):
    canvas = make_bg(p)
    cx, cy = W/2, H/2
    R = int(W*0.34)
    # shadow
    sh = soft_shadow(W, [cx-R, cy-R, cx+R, cy+R], R, p["shadow"], p["shadow_alpha"], int(W*0.04), (0,int(W*0.03)))
    canvas = blend(canvas, sh)
    # outer glass disc
    disc = Image.new("RGBA",(W,H),(0,0,0,0)); d=ImageDraw.Draw(disc)
    d.ellipse([cx-R, cy-R, cx+R, cy+R], fill=p["disc_fill"], outline=p["disc_line"], width=int(W*0.005))
    disc = disc.filter(ImageFilter.GaussianBlur(int(W*0.0015) or 0))
    canvas = blend(canvas, disc)
    # 6 iris blades
    n=6; br=R*0.78
    blades = Image.new("RGBA",(W,H),(0,0,0,0)); bd=ImageDraw.Draw(blades)
    for i in range(n):
        a = math.pi/2 + i*2*math.pi/n
        # blade triangle from center to two points on inner ring
        p1 = (cx + br*math.cos(a), cy + br*math.sin(a))
        p2 = (cx + br*math.cos(a+2*math.pi/n*0.85), cy + br*math.sin(a+2*math.pi/n*0.85))
        bd.polygon([(cx,cy), p1, p2], fill=p["blade_fill"](i), outline=p["blade_line"], width=int(W*0.003))
    blades = blades.filter(ImageFilter.GaussianBlur(int(W*0.0015) or 0))
    canvas = blend(canvas, blades)
    # center hub with M
    hubR = int(R*0.34)
    hub = Image.new("RGBA",(W,H),(0,0,0,0)); hd=ImageDraw.Draw(hub)
    hd.ellipse([cx-hubR, cy-hubR, cx+hubR, cy+hubR], fill=p["hub_fill"], outline=p["hub_line"], width=int(W*0.004))
    canvas = blend(canvas, hub)
    canvas = blend(canvas, text_layer("M", p["mono"], p["mono_stroke"], max(6,int(W*0.012)), size=int(W*0.24)))
    return canvas.resize((SIZE,SIZE), Image.LANCZOS)


# --- 04 frame-corner -------------------------------------------------------

def c04_frame_corner(p):
    canvas = make_bg(p)
    m = int(W*0.18); t = int(W*0.045); seg = int(W*0.22)
    # four corner brackets
    layer = Image.new("RGBA",(W,H),(0,0,0,0)); d=ImageDraw.Draw(layer)
    corners = [(m,m,1,1),(W-m,m,-1,1),(m,H-m,1,-1),(W-m,H-m,-1,-1)]
    for (x,y,sx,sy) in corners:
        d.line([(x, y), (x+sx*seg, y)], fill=p["bracket"], width=t)
        d.line([(x, y), (x, y+sy*seg)], fill=p["bracket"], width=t)
        # small dot at corner
        d.ellipse([x-t, y-t, x+t, y+t], fill=p["bracket"])
    canvas = blend(canvas, layer)
    # glass plate behind M
    plate = glass_sheet(W, [int(W*0.30), int(H*0.30), int(W*0.70), int(H*0.70)], int(W*0.10), p["plate_fill"], p["plate_line"], int(W*0.004))
    canvas = blend(canvas, plate)
    canvas = blend(canvas, text_layer("M", p["mono"], p["mono_stroke"], max(6,int(W*0.012)), size=int(W*0.36)))
    return canvas.resize((SIZE,SIZE), Image.LANCZOS)


# --- 05 wax-seal ------------------------------------------------------------

def c05_wax_seal(p):
    canvas = make_bg(p)
    cx, cy = W/2, H/2; R = int(W*0.34)
    # shadow
    sh = soft_shadow(W, [cx-R, cy-R, cx+R, cy+R], R, p["shadow"], p["shadow_alpha"], int(W*0.05), (int(W*0.02), int(W*0.05)))
    canvas = blend(canvas, sh)
    # wax disc with irregular edge
    body = Image.new("RGBA",(W,H),(0,0,0,0)); d=ImageDraw.Draw(body)
    # build a polygon with wavy edge
    pts=[]
    steps=72
    for i in range(steps):
        a = i*2*math.pi/steps
        rr = R + int(R*0.06*math.sin(3*a + 0.4))
        pts.append((cx + rr*math.cos(a), cy + rr*math.sin(a)))
    d.polygon(pts, fill=p["wax_fill"], outline=p["wax_line"], width=int(W*0.005))
    body = body.filter(ImageFilter.GaussianBlur(int(W*0.002)))
    canvas = blend(canvas, body)
    # inner rim
    rim = Image.new("RGBA",(W,H),(0,0,0,0)); rd=ImageDraw.Draw(rim)
    r2 = int(R*0.78)
    rd.ellipse([cx-r2, cy-r2, cx+r2, cy+r2], outline=p["rim"], width=int(W*0.006))
    rim = rim.filter(ImageFilter.GaussianBlur(int(W*0.002)))
    canvas = blend(canvas, rim)
    # highlight crescent
    hl = Image.new("RGBA",(W,H),(0,0,0,0)); hd=ImageDraw.Draw(hl)
    hd.ellipse([cx-R, cy-R, cx+R, cy+R], fill=(255,255,255,0))
    hd.ellipse([cx-int(R*0.78), cy-int(R*0.78), cx+int(R*0.5), cy+int(R*0.5)], fill=(*p["wax_hi"], 60))
    hl = hl.filter(ImageFilter.GaussianBlur(int(W*0.03)))
    canvas = blend(canvas, hl)
    # M debossed (slightly darker, emboss stroke)
    canvas = blend(canvas, text_layer("M", p["mono"], p["mono_stroke"], max(8,int(W*0.018)), size=int(W*0.40)))
    return canvas.resize((SIZE,SIZE), Image.LANCZOS)


# --- 06 polaroid-fanout ----------------------------------------------------

def c06_polaroid_fanout(p):
    canvas = make_bg(p)
    pw = int(W*0.46); ph = int(pw*1.18); bandh = int(ph*0.14)
    cx, cy = W/2, H/2
    rotations = [-16, -8, 0, 8, 16]
    # shadow
    sh = soft_shadow(W, [cx-pw/2, cy-ph/2, cx+pw/2, cy+ph/2], int(W*0.04), p["shadow"], p["shadow_alpha"], int(W*0.05), (0, int(W*0.04)))
    canvas = blend(canvas, sh)
    # polaroids back-to-front
    for i, rot in enumerate(rotations):
        card = Image.new("RGBA",(W,H),(0,0,0,0)); cd = ImageDraw.Draw(card)
        # white frame
        box=[cx-pw/2, cy-ph/2, cx+pw/2, cy+ph/2]
        rrect(cd, box, int(W*0.03), fill=p["card_fill"], outline=p["card_line"], width=int(W*0.004))
        # inner image area
        imgbox=[cx-pw/2+int(pw*0.07), cy-ph/2+int(ph*0.07), cx+pw/2-int(pw*0.07), cy+ph/2-bandh-int(ph*0.07)]
        rrect(cd, imgbox, int(W*0.02), fill=p["card_img"])
        card = card.rotate(rot, center=(cx,cy), resample=Image.BICUBIC)
        canvas = blend(canvas, card)
    # front polaroid with M inside its image area
    front = Image.new("RGBA",(W,H),(0,0,0,0)); fd=ImageDraw.Draw(front)
    box=[cx-pw/2, cy-ph/2, cx+pw/2, cy+ph/2]
    rrect(fd, box, int(W*0.03), fill=p["card_fill"], outline=p["card_line"], width=int(W*0.005))
    imgbox=[cx-pw/2+int(pw*0.07), cy-ph/2+int(ph*0.07), cx+pw/2-int(pw*0.07), cy+ph/2-bandh-int(ph*0.07)]
    rrect(fd, imgbox, int(W*0.02), fill=p["card_img"])
    # M in image area
    fmono = font(int(W*0.26))
    fd.text((cx, (imgbox[1]+imgbox[3])//2), "M", font=fmono, anchor="mm", fill=p["mono"], stroke_width=max(6,int(W*0.01)), stroke_fill=p["mono_stroke"])
    front = front.rotate(0, center=(cx,cy), resample=Image.BICUBIC)
    canvas = blend(canvas, front)
    return canvas.resize((SIZE,SIZE), Image.LANCZOS)


# --- 07 halftone-reveal ----------------------------------------------------

def c07_halftone_reveal(p):
    canvas = make_bg(p)
    # build a halftone dot field where dots shrink near the M glyph
    grid = 36
    cell = W / grid
    dots = Image.new("RGBA",(W,H),(0,0,0,0)); d=ImageDraw.Draw(dots)
    # render M to a mask to drive dot size
    mask = Image.new("L",(W,H),0); md=ImageDraw.Draw(mask)
    f = font(int(W*0.42))
    md.text((W/2,H/2), "M", font=f, anchor="mm", fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(int(W*0.01)))
    for gy in range(grid):
        for gx in range(grid):
            x = int((gx+0.5)*cell); y = int((gy+0.5)*cell)
            # base dot size shrinks with mask value (more ink near glyph)
            v = mask.getpixel((x,y)) if 0 <= x < W and 0 <= y < H else 0
            # near glyph: small dots; far: big dots
            base = cell*0.42
            dotR = base * (1 - v/255*0.85)
            if dotR < 0.5: continue
            d.ellipse([x-dotR, y-dotR, x+dotR, y+dotR], fill=p["dot"](v))
    dots = dots.filter(ImageFilter.GaussianBlur(int(W*0.0015) or 0))
    canvas = blend(canvas, dots)
    # subtle glyph outline for crispness
    canvas = blend(canvas, text_layer("M", p["mono"], p["mono_stroke"], max(4,int(W*0.006)), size=int(W*0.42)))
    return canvas.resize((SIZE,SIZE), Image.LANCZOS)


# --- 08 neon-outline -------------------------------------------------------

def c08_neon_outline(p):
    canvas = make_bg(p)
    cx, cy = W/2, H/2
    R = int(W*0.34)
    # glass disc
    disc = glass_sheet(W, [cx-R, cy-R, cx+R, cy+R], R, p["disc_fill"], p["disc_line"], int(W*0.004))
    canvas = blend(canvas, disc)
    # outer glow rings
    for i in range(4):
        rr = R + int(W*0.04*i)
        ring = Image.new("RGBA",(W,H),(0,0,0,0)); rd=ImageDraw.Draw(ring)
        rd.ellipse([cx-rr, cy-rr, cx+rr, cy+rr], outline=(*p["neon"], max(20, 120 - 30*i)), width=max(2,int(W*0.006 - i*2)))
        ring = ring.filter(ImageFilter.GaussianBlur(int(W*0.012)))
        canvas = blend(canvas, ring)
    # M as outlined strokes only (transparent fill, neon stroke)
    layer = Image.new("RGBA",(W,H),(0,0,0,0)); d=ImageDraw.Draw(layer)
    f = font(int(W*0.44))
    d.text((cx, cy), "M", font=f, anchor="mm", fill=(0,0,0,0), stroke_width=max(10,int(W*0.022)), stroke_fill=p["neon"])
    layer = layer.filter(ImageFilter.GaussianBlur(int(W*0.003)))
    canvas = blend(canvas, layer)
    # crisp core stroke
    core = Image.new("RGBA",(W,H),(0,0,0,0)); cd=ImageDraw.Draw(core)
    cd.text((cx, cy), "M", font=f, anchor="mm", fill=(0,0,0,0), stroke_width=max(4,int(W*0.008)), stroke_fill=p["neon_core"])
    canvas = blend(canvas, core)
    return canvas.resize((SIZE,SIZE), Image.LANCZOS)


# --- 09 origami-fold ------------------------------------------------------

def c09_origami_fold(p):
    canvas = make_bg(p)
    cx, cy = W/2, H/2; S = int(W*0.34)
    # soft shadow
    sh = soft_shadow(W, [cx-S, cy-S, cx+S, cy+S], int(S*0.3), p["shadow"], p["shadow_alpha"], int(W*0.04), (0, int(W*0.03)))
    canvas = blend(canvas, sh)
    # facets composing a stylized M from 4 triangular panels
    facets = [
        # (pts, fill_idx, line_idx)
        ([(cx-S, cy-S), (cx, cy-S*0.1), (cx-S*0.5, cy+S*0.4)], 0, 0),
        ([(cx, cy-S*0.1), (cx+S, cy-S), (cx+S*0.5, cy+S*0.4)], 1, 0),
        ([(cx-S*0.5, cy+S*0.4), (cx, cy-S*0.1), (cx, cy+S)], 2, 0),
        ([(cx, cy-S*0.1), (cx+S*0.5, cy+S*0.4), (cx, cy+S)], 3, 0),
    ]
    layer = Image.new("RGBA",(W,H),(0,0,0,0)); d=ImageDraw.Draw(layer)
    for pts, fi, li in facets:
        d.polygon(pts, fill=p["facet"](fi), outline=p["facet_line"], width=int(W*0.005))
    layer = layer.filter(ImageFilter.GaussianBlur(int(W*0.0015) or 0))
    canvas = blend(canvas, layer)
    # top highlight strip
    hl = Image.new("RGBA",(W,H),(0,0,0,0)); hd=ImageDraw.Draw(hl)
    hd.polygon([(cx-S, cy-S), (cx, cy-S*0.1), (cx-S*0.5, cy-S*0.3)], fill=(*p["facet_hi"], 50))
    hd.polygon([(cx, cy-S*0.1), (cx+S, cy-S), (cx+S*0.5, cy-S*0.3)], fill=(*p["facet_hi"], 50))
    hl = hl.filter(ImageFilter.GaussianBlur(int(W*0.02)))
    canvas = blend(canvas, hl)
    return canvas.resize((SIZE,SIZE), Image.LANCZOS)


# --- 10 ripple-rings ------------------------------------------------------

def c10_ripple_rings(p):
    canvas = make_bg(p)
    cx, cy = W/2, H/2
    # soft water surface
    surf = glass_sheet(W, [int(W*0.08)]*2 + [W-int(W*0.08)]*2, int(W*0.18), p["water_fill"], p["water_line"], int(W*0.003), blur=int(W*0.002))
    canvas = blend(canvas, surf)
    # concentric rings, decreasing alpha outward
    rings = Image.new("RGBA",(W,H),(0,0,0,0)); d=ImageDraw.Draw(rings)
    r0 = int(W*0.06); step=int(W*0.05)
    for i in range(7):
        r = r0 + i*step
        a = max(0, p["ring_alpha"] - i*22)
        d.ellipse([cx-r, cy-r, cx+r, cy+r], outline=(*p["ring"], a), width=max(2, int(W*0.008 - i*1)))
    rings = rings.filter(ImageFilter.GaussianBlur(int(W*0.002)))
    canvas = blend(canvas, rings)
    # center drop
    drop = Image.new("RGBA",(W,H),(0,0,0,0)); dd=ImageDraw.Draw(drop)
    dr = int(W*0.07)
    dd.ellipse([cx-dr, cy-dr, cx+dr, cy+dr], fill=p["drop_fill"])
    drop = drop.filter(ImageFilter.GaussianBlur(int(W*0.005)))
    canvas = blend(canvas, drop)
    # M at the focal point
    canvas = blend(canvas, text_layer("M", p["mono"], p["mono_stroke"], max(6,int(W*0.012)), size=int(W*0.22)))
    return canvas.resize((SIZE,SIZE), Image.LANCZOS)


# --- palettes per concept --------------------------------------------------

# Reusable accent colors
INDIGO = (99,102,241); VIOLET=(139,92,246); SKY=(56,189,248); ROSE=(244,63,94)
TEAL=(20,184,166); AMBER=(245,158,11); EMERALD=(16,185,129); SLATE=(100,116,139)

def base_light(accent_a, accent_b, glow_c):
    return {
        "bg_tl": accent_a, "bg_br": accent_b,
        "glow": glow_c, "glow_alpha": 90, "glow_c": (int(W*0.30), int(H*0.22)),
        "vig": mix(accent_a,(0,0,0),0.6), "vig_alpha": 60, "vig_c": (int(W*0.7), int(H*0.85)),
        "shadow": (20,20,40), "shadow_alpha": 120,
        "mono": (255,255,255,255), "mono_stroke": (255,255,255,255),
    }

def base_dark(accent_a, accent_b, glow_c):
    return {
        "bg_tl": (10,12,22), "bg_br": (20,20,38),
        "glow": glow_c, "glow_alpha": 90, "glow_c": (int(W*0.30), int(H*0.22)),
        "vig": (0,0,0), "vig_alpha": 120, "vig_c": (int(W*0.7), int(H*0.85)),
        "shadow": (0,0,0), "shadow_alpha": 180,
        "mono": (235,238,255,255), "mono_stroke": (235,238,255,255),
    }

def base_tinted():
    return {
        "bg_tl": (28,28,30), "bg_br": (28,28,30),
        "glow": (255,255,255), "glow_alpha": 0, "glow_c": (int(W*0.30), int(H*0.22)),
        "vig": (0,0,0), "vig_alpha": 0, "vig_c": (int(W*0.7), int(H*0.85)),
        "shadow": (0,0,0), "shadow_alpha": 0,
        "mono": (255,255,255,255), "mono_stroke": (255,255,255,255),
    }

# Per-concept palette packs. Each returns (light, dark, tinted) dicts.
def palette_for(name):
    key = name.split("-",1)[1] if name[0:2].isdigit() else name
    name = key
    if name == "glass-stack":
        L = base_light(INDIGO, VIOLET, (196,181,253))
        L.update(dict(sheets=[(255,255,255,70),(255,255,255,90),(255,255,255,118)], strokes=[(255,255,255,120)]*3, fold_fill=(255,255,255,150), fold_line=(255,255,255,235)))
        D = base_dark(INDIGO, VIOLET, INDIGO)
        D.update(dict(sheets=[(226,232,255,28),(226,232,255,40),(226,232,255,58)], strokes=[(226,232,255,70)]*3, fold_fill=(226,232,255,70), fold_line=(226,232,255,200)))
        T = base_tinted()
        T.update(dict(sheets=[(255,255,255,40),(255,255,255,55),(255,255,255,80)], strokes=[(255,255,255,90)]*3, fold_fill=(255,255,255,120), fold_line=(255,255,255,255)))
        return L, D, T
    if name == "droplet":
        L = base_light(SKY, INDIGO, (186,230,253))
        L.update(dict(drop_fill=(255,255,255,180), drop_line=(255,255,255,235), drop_hi=(255,255,255,180)))
        D = base_dark(SKY, INDIGO, SKY)
        D.update(dict(drop_fill=(226,232,255,80), drop_line=(226,232,255,200), drop_hi=(150,200,255,140)))
        T = base_tinted()
        T.update(dict(drop_fill=(255,255,255,180), drop_line=(255,255,255,255), drop_hi=(255,255,255,80)))
        return L, D, T
    if name == "aperture":
        L = base_light((30,30,46), (8,8,20), (80,80,120))
        L.update(dict(disc_fill=(255,255,255,40), disc_line=(255,255,255,160),
                      blade_fill=lambda i: (*mix((255,255,255),(200,210,235), i/6), 120) , blade_line=(255,255,255,200),
                      hub_fill=(255,255,255,180), hub_line=(255,255,255,255)))
        D = base_dark((30,30,46), (8,8,20), INDIGO)
        D.update(dict(disc_fill=(226,232,255,40), disc_line=(226,232,255,140),
                      blade_fill=lambda i: (*mix((120,130,180),(226,232,255), i/6), 90), blade_line=(226,232,255,160),
                      hub_fill=(226,232,255,120), hub_line=(226,232,255,255)))
        T = base_tinted()
        T.update(dict(disc_fill=(255,255,255,40), disc_line=(255,255,255,180),
                      blade_fill=lambda i: (255,255,255, max(60,140 - i*15)), blade_line=(255,255,255,200),
                      hub_fill=(255,255,255,180), hub_line=(255,255,255,255)))
        return L, D, T
    if name == "frame-corner":
        L = base_light(EMERALD, TEAL, (167,243,208))
        L.update(dict(bracket=(255,255,255,235), plate_fill=(255,255,255,90), plate_line=(255,255,255,160)))
        D = base_dark(EMERALD, TEAL, EMERALD)
        D.update(dict(bracket=(226,232,255,235), plate_fill=(226,232,255,40), plate_line=(226,232,255,120)))
        T = base_tinted()
        T.update(dict(bracket=(255,255,255,235), plate_fill=(255,255,255,90), plate_line=(255,255,255,160)))
        return L, D, T
    if name == "wax-seal":
        L = base_light(ROSE, (120,30,60), (255,128,128))
        L.update(dict(wax_fill=(220,40,80,230), wax_line=(255,200,200,200), rim=(140,30,60,200), wax_hi=(255,220,220,120)))
        D = base_dark(ROSE, (60,15,30), ROSE)
        D.update(dict(wax_fill=(180,30,60,220), wax_line=(255,180,180,180), rim=(255,80,80,160), wax_hi=(255,160,160,90)))
        T = base_tinted()
        T.update(dict(wax_fill=(255,255,255,200), wax_line=(255,255,255,255), rim=(180,180,180,200), wax_hi=(255,255,255,80)))
        return L, D, T
    if name == "polaroid-fanout":
        L = base_light((255,255,255), (255,255,255), (255,255,255))  # white bg
        L.update(dict(bg_tl=(245,247,255), bg_br=(220,225,240), glow=(255,255,255), glow_alpha=0, vig_alpha=0, shadow=(100,110,140), shadow_alpha=120,
                       card_fill=(255,255,255,235), card_line=(180,190,210,200), card_img=(235,238,250,200)))
        D = base_dark((10,10,18),(22,22,38), INDIGO)
        D.update(dict(card_fill=(226,232,255,200), card_line=(150,160,200,180), card_img=(40,50,80,200)))
        T = base_tinted()
        T.update(dict(card_fill=(255,255,255,230), card_line=(180,180,180,200), card_img=(200,200,200,200)))
        return L, D, T
    if name == "halftone-reveal":
        L = base_light((15,15,30),(45,45,80),(120,130,180))
        L.update(dict(dot=lambda v: (255,255,255, max(20, 200 - int(v*0.2)))))
        D = base_dark((10,12,22),(40,45,80), INDIGO)
        D.update(dict(dot=lambda v: (226,232,255, max(20, 200 - int(v*0.2)))))
        T = base_tinted()
        T.update(dict(dot=lambda v: (255,255,255, max(40, 220 - int(v*0.2)))))
        return L, D, T
    if name == "neon-outline":
        L = base_light((20,15,40),(60,20,90),(180,100,255))
        L.update(dict(disc_fill=(255,255,255,30), disc_line=(255,255,255,80), neon=(180,255,200), neon_core=(220,255,230)))
        D = base_dark((6,8,18),(20,10,30), (60,200,150))
        D.update(dict(disc_fill=(120,200,150,30), disc_line=(120,200,150,80), neon=(100,255,170), neon_core=(200,255,210)))
        T = base_tinted()
        T.update(dict(disc_fill=(255,255,255,30), disc_line=(255,255,255,80), neon=(255,255,255), neon_core=(255,255,255)))
        return L, D, T
    if name == "origami-fold":
        L = base_light(AMBER, ROSE, (255,200,150))
        L.update(dict(facet=lambda i: (*mix(AMBER, ROSE, i/3), 230), facet_line=(255,255,255,150), facet_hi=(255,255,255)))
        D = base_dark(AMBER, ROSE, AMBER)
        D.update(dict(facet=lambda i: (*mix(AMBER, ROSE, i/3), 220), facet_line=(255,230,200,150), facet_hi=(255,230,200)))
        T = base_tinted()
        T.update(dict(facet=lambda i: (255,255,255, max(120, 230 - i*30)), facet_line=(255,255,255,200), facet_hi=(255,255,255,200)))
        return L, D, T
    if name == "ripple-rings":
        L = base_light(SKY, INDIGO, (186,230,253))
        L.update(dict(water_fill=(255,255,255,90), water_line=(255,255,255,200), ring=(255,255,255), ring_alpha=200, drop_fill=(255,255,255,220)))
        D = base_dark(SKY, INDIGO, SKY)
        D.update(dict(water_fill=(120,180,255,80), water_line=(150,200,255,200), ring=(150,200,255), ring_alpha=200, drop_fill=(150,200,255,200)))
        T = base_tinted()
        T.update(dict(water_fill=(255,255,255,90), water_line=(255,255,255,200), ring=(255,255,255), ring_alpha=200, drop_fill=(255,255,255,220)))
        return L, D, T
    raise ValueError(name)


CONCEPTS = [
    ("01-glass-stack",   c01_glass_stack),
    ("02-droplet",       c02_droplet),
    ("03-aperture",      c03_aperture),
    ("04-frame-corner",  c04_frame_corner),
    ("05-wax-seal",      c05_wax_seal),
    ("06-polaroid-fanout", c06_polaroid_fanout),
    ("07-halftone-reveal", c07_halftone_reveal),
    ("08-neon-outline",  c08_neon_outline),
    ("09-origami-fold",   c09_origami_fold),
    ("10-ripple-rings",   c10_ripple_rings),
]


def resolve_heavy_font_index():
    for idx in (5,6,4,3,2,1,0):
        try:
            ImageFont.truetype(FONT_PATH, 64, index=idx); return idx
        except Exception: continue
    return 1


def main():
    global HEAVY_IDX
    HEAVY_IDX = resolve_heavy_font_index()
    os.makedirs(OUT_ROOT, exist_ok=True)
    tiles = []  # (label, image) for contact sheet
    for name, fn in CONCEPTS:
        d = os.path.join(OUT_ROOT, name)
        os.makedirs(d, exist_ok=True)
        L, D, T = palette_for(name)
        for tag, pal, fn_name in (("any", L, name), ("dark", D, name), ("tinted", T, name)):
            img = fn(pal)
            p = os.path.join(d, f"icon-{tag}.png")
            img.save(p, "PNG")
            tiles.append((f"{name}\n{tag}", Image.open(p).convert("RGB")))
    # contact sheet: 10 rows x 3 cols
    cols, rows = 3, 10
    cw, ch = 320, 320
    pad = 16; labh = 40
    sheet_w = cols*cw + (cols+1)*pad
    sheet_h = rows*(ch+labh) + (rows+1)*pad
    sheet = Image.new("RGB", (sheet_w, sheet_h), (240,240,245))
    from PIL import ImageFont as IF
    labf = IF.truetype(FONT_PATH, 22, index=0)
    for i,(lab,img) in enumerate(tiles):
        r, c = divmod(i, cols)
        x = pad + c*(cw+pad)
        y = pad + r*(ch+labh+pad)
        thumb = img.resize((cw,ch), Image.LANCZOS)
        sheet.paste(thumb, (x, y+labh))
        d = ImageDraw.Draw(sheet)
        d.text((x+cw//2, y+labh//2), lab, font=labf, anchor="mm", fill=(40,40,50))
    sheet.save(os.path.join(OUT_ROOT, "contact-sheet.png"))
    print(f"wrote 30 icons under {OUT_ROOT}/<concept>/")
    print(f"contact sheet: {OUT_ROOT}/contact-sheet.png")


if __name__ == "__main__":
    main()
