# Modern frames with depth, gradients and shade. Same rules as modern.py:
# the photo stays the hero, one caption block, real metadata + maker mark.
import os, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageEnhance, ImageOps, ImageChops
from frames import PHOTO, W, H, HERE, rmask, shadow, paste_round, fit, texture, lerp, palette, radial
from modern import row_caption, sf, logo, S

OUT = os.path.join(HERE, "effects"); os.makedirs(OUT, exist_ok=True)
CW, CH = 1600, 2000  # 4:5, the feed format

def save(img, name):
    img.convert("RGB").save(os.path.join(OUT, name + ".jpg"), quality=92); print("wrote", name, img.size)

def vgrad(size, top, bottom):
    g = Image.linear_gradient("L").resize(size)
    return Image.composite(Image.new("RGB", size, bottom), Image.new("RGB", size, top), g)

def colours():
    cols = palette(PHOTO, 8)
    sat = lambda q: max(q) - min(q)
    deep = min(cols, key=lambda q: sum(q) - 2 * sat(q))
    warm = max(cols, key=lambda q: q[0] - q[2] + sum(q) / 6)
    return deep, warm

def perspective(img, quad, size):
    """Warp img so its corners land on quad (TL, TR, BR, BL) in an image of `size`."""
    src = [(0, 0), (img.width, 0), (img.width, img.height), (0, img.height)]
    A, B = [], []
    for (x, y), (u, v) in zip(quad, src):
        A += [[x, y, 1, 0, 0, 0, -u * x, -u * y], [0, 0, 0, x, y, 1, -v * x, -v * y]]; B += [u, v]
    coeffs = np.linalg.solve(np.array(A, float), np.array(B, float))
    rgba = img.convert("RGBA")
    return rgba.transform(size, Image.PERSPECTIVE, tuple(coeffs), Image.BICUBIC)

def layout(scale=0.80):
    p = fit(PHOTO, CW * 0.84, CH * scale)
    x, y = (CW - p.width) // 2, round((CH - p.height) * 0.30)
    return p, x, y

def cap_y(y, p, frac=0.33): return y + p.height + (CH - y - p.height) * frac

# 1 ── Blend: the border continues the photo's own edge colours, top to bottom
def blend():
    a = np.asarray(PHOTO).astype(float)
    top = tuple(int(v) for v in a[: H // 12].reshape(-1, 3).mean(0))
    bot = tuple(int(v) for v in a[-H // 12:].reshape(-1, 3).mean(0))
    bot = lerp(bot, (0, 0, 0), 0.35)
    side, bottom = round(S * 0.05), round(S * 0.16)
    c = texture(vgrad((W + 2 * side, H + side + bottom), lerp(top, (255, 255, 255), 0.15), bot), 3, 0.6)
    shadow(c, (side, side, side + W, side + H), round(S * 0.02), 24, 0.35, (0, 10))
    paste_round(c, PHOTO, (side, side), round(S * 0.02))
    row_caption(c, side, side + W, side + H + bottom * 0.30, S * 0.06, (255, 255, 255), (220, 222, 232), "white")
    return c

# 2 ── Tilt: the print turned a few degrees in space, shadow falling away
def tilt():
    deep, warm = colours()
    c = texture(vgrad((CW, CH), lerp(warm, (255, 255, 255), 0.55), lerp(deep, (255, 255, 255), 0.55)), 3, 0.6)
    p = fit(PHOTO, CW * 0.74, CH * 0.72)
    x, y = (CW - p.width) // 2 + 20, round(CH * 0.08)
    w, h = p.width, p.height
    # rotate about the vertical axis: near (left) edge full height, far edge shorter and closer
    quad = [(x - w * 0.02, y), (x + w * 0.94, y + h * 0.045), (x + w * 0.94, y + h * 0.955), (x - w * 0.02, y + h)]
    warped = perspective(ImageOps.expand(p, 10, (255, 255, 255)), quad, (CW, CH))
    a = warped.split()[3]
    sh = Image.new("L", (CW, CH), 0); sh.paste(a.point(lambda v: v * 0.5), (38, 46))
    c.paste(lerp(deep, (0, 0, 0), 0.6), (0, 0), sh.filter(ImageFilter.GaussianBlur(40)))
    c.paste(warped, (0, 0), warped)
    # a sheen across the surface, strongest at the near edge
    sheen = Image.linear_gradient("L").rotate(90).resize((CW, CH)).point(lambda v: v * 0.10)
    c.paste((255, 255, 255), (0, 0), ImageChops.multiply(sheen, a))
    row_caption(c, x, x + w * 0.94, y + h + (CH - y - h) * 0.40, CW * 0.05, (30, 30, 34), (90, 92, 100), "black")
    return c

# 3 ── Block: a gallery-wrap print with real thickness and a cast shadow
def block():
    c = texture(vgrad((CW, CH), (234, 230, 222), (200, 194, 184)), 4, 1)
    p, x, y = layout(0.76); x -= 14
    d = round(S * 0.035)  # depth of the block
    shadow(c, (x, y, x + p.width + d, y + p.height + d), 0, 36, 0.45, (40, 50), (50, 40, 30))
    # sides: the photo's own edge pixels wrapped round, darkened by the light
    right = ImageEnhance.Brightness(p.crop((p.width - 1, 0, p.width, p.height)).resize((d, p.height))).enhance(0.62)
    bottom = ImageEnhance.Brightness(p.crop((0, p.height - 1, p.width, p.height)).resize((p.width, d))).enhance(0.42)
    rs = perspective(right, [(x + p.width, y), (x + p.width + d, y + d), (x + p.width + d, y + p.height + d), (x + p.width, y + p.height)], (CW, CH))
    bs = perspective(bottom, [(x, y + p.height), (x + p.width, y + p.height), (x + p.width + d, y + p.height + d), (x + d, y + p.height + d)], (CW, CH))
    c.paste(rs, (0, 0), rs); c.paste(bs, (0, 0), bs)
    c.paste(p, (x, y))
    row_caption(c, x, x + p.width + d, cap_y(y, p, 0.40) + d / 2, CW * 0.05, (30, 30, 32), (110, 106, 100), "black")
    return c

# 4 ── Emboss: soft light & dark shades press the photo into the surface
def emboss():
    base = (231, 232, 236)
    c = Image.new("RGB", (CW, CH), base)
    p, x, y = layout(0.78)
    r = round(CW * 0.035)
    shadow(c, (x, y, x + p.width, y + p.height), r, 34, 0.30, (22, 26), (120, 124, 140))
    shadow(c, (x, y, x + p.width, y + p.height), r, 34, 0.95, (-22, -26), (255, 255, 255))
    paste_round(c, p, (x, y), r)
    # debossed caption: dark glyphs with a light edge beneath
    ty = cap_y(y, p, 0.36)
    row_caption(c, x, x + p.width, ty + 2, CW * 0.05, (255, 255, 255), (255, 255, 255), "white")
    row_caption(c, x, x + p.width, ty, CW * 0.05, (84, 88, 100), (140, 144, 156), "black")
    return c

# 5 ── Sunlight: late light through blinds falls across the wall, not the photo
def sunlight():
    wall = (236, 227, 213)
    c = Image.new("RGB", (CW, CH), wall)
    blinds = Image.new("L", (CW * 2, CH * 2), 0); bd = ImageDraw.Draw(blinds)
    for i in range(-10, 40):
        yy = i * 120; bd.rectangle([0, yy, CW * 2, yy + 52], fill=255)
    blinds = blinds.rotate(-28, Image.BICUBIC).crop((CW // 2, CH // 2, CW // 2 + CW, CH // 2 + CH)).filter(ImageFilter.GaussianBlur(14))
    light = radial((CW, CH), (int(CW * 0.8), int(CH * 0.2)), int(CH * 0.9), (255, 255, 255), (0, 0, 0)).convert("L")
    c.paste((150, 128, 104), (0, 0), ImageChops.multiply(blinds, light).point(lambda v: v * 0.55))
    c = texture(c, 4, 1)
    p, x, y = layout(0.78)
    # long soft shadow cast away from the light
    shadow(c, (x, y, x + p.width, y + p.height), 0, 30, 0.42, (-46, 54), (90, 70, 50))
    c.paste(p, (x, y))
    row_caption(c, x, x + p.width, cap_y(y, p, 0.40), CW * 0.05, (48, 40, 32), (130, 116, 100), "black")
    return c

# 6 ── Mirror: floating above a dark glossy floor, with its reflection
def mirror():
    c = vgrad((CW, CH), (46, 50, 62), (8, 8, 11))
    p = fit(PHOTO, CW * 0.70, CH * 0.62)
    x, y = (CW - p.width) // 2, round(CH * 0.07)
    r = round(CW * 0.02)
    floor_y = y + p.height + round(CH * 0.012)
    c.paste(vgrad((CW, CH - floor_y), (18, 18, 22), (6, 6, 8)), (0, floor_y))
    refl = ImageOps.flip(p).crop((0, 0, p.width, round(p.height * 0.32)))
    fade = Image.linear_gradient("L").resize(refl.size).point(lambda v: int((255 - v) * 0.30))
    fade = ImageChops.multiply(fade, rmask(refl.size, r))
    c.paste(refl, (x, floor_y + 4), fade)
    shadow(c, (x, y, x + p.width, y + p.height), r, 40, 0.5, (0, 20))
    paste_round(c, p, (x, y), r)
    row_caption(c, x, x + p.width, CH - CH * 0.10, CW * 0.048, (240, 240, 244), (140, 142, 152), "white")
    return c

# 7 ── Layers: slabs in the photo's colours step back behind it
def layers():
    c = Image.new("RGB", (CW, CH), (250, 249, 246))
    cols = sorted(palette(PHOTO, 6)[:4], key=lambda q: -sum(q))
    p, x, y = layout(0.76); x -= 30; y -= 10
    r = round(CW * 0.03); step = round(CW * 0.022)
    for i, col in reversed(list(enumerate(cols[:3], 1))):
        box = (x + i * step, y + i * step, x + p.width + i * step, y + p.height + i * step)
        shadow(c, box, r, 20, 0.12, (0, 8))
        ImageDraw.Draw(c).rounded_rectangle(box, r, fill=col)
    shadow(c, (x, y, x + p.width, y + p.height), r, 24, 0.25, (0, 10))
    paste_round(c, p, (x, y), r)
    row_caption(c, x, x + p.width + 3 * step, cap_y(y, p, 0.42) + 3 * step / 2, CW * 0.05, (28, 28, 30), (140, 138, 134), "black")
    return c

# 8 ── Glow: the photo's own light spills softly onto a dark ground
def glow():
    c = Image.new("RGB", (CW, CH), (12, 12, 15))
    p, x, y = layout(0.80)
    halo = Image.new("RGB", (CW, CH), (12, 12, 15))
    halo.paste(ImageEnhance.Color(p).enhance(1.6), (x, y))
    halo = halo.filter(ImageFilter.GaussianBlur(90))
    c = ImageChops.screen(c, ImageEnhance.Brightness(halo).enhance(0.75))
    r = round(CW * 0.026)
    paste_round(c, p, (x, y), r)
    row_caption(c, x, x + p.width, cap_y(y, p, 0.36), CW * 0.05, (245, 245, 248), (150, 152, 162), "white")
    return c

STYLES = [("blend", "Blend", blend), ("tilt", "Tilt", tilt), ("block", "Block", block), ("emboss", "Emboss", emboss),
          ("sunlight", "Sunlight", sunlight), ("mirror", "Mirror", mirror), ("layers", "Layers", layers), ("glow", "Glow", glow)]

if __name__ == "__main__":
    only = set(sys.argv[1:])
    for key, _, fn in STYLES:
        if not only or key in only: save(fn(), key)
