# Frame concept mockups for Markepi. Renders 14 frame styles around one photo.
# Mockups only (PIL) — the app versions would be Core Graphics in WhiteFrameRenderer.
import math, os, random, subprocess, sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageOps, ImageChops, ImageEnhance

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "frames")
os.makedirs(OUT, exist_ok=True)
SRC = os.path.expanduser("~/Downloads/IMG_1929.heic")
JPG = os.path.join(HERE, "src.jpg")
if not os.path.exists(JPG):
    subprocess.run(["sips", "-s", "format", "jpeg", "-Z", "1600", SRC, "--out", JPG], check=True, capture_output=True)
PHOTO = ImageOps.exif_transpose(Image.open(JPG)).convert("RGB")
W, H = PHOTO.size  # ~1200x1600

MODEL = "iPhone 15 Pro Max"
EXIF = ["24mm", "f/1.8", "1/783s", "ISO 64"]
EXIF_LINE = "  ·  ".join(EXIF)
DATE = "30 Aug 2026"

FONTS = "/Users/osama/.superset/worktrees/Markepi/we-need-to-now-agressively-ask/Packages/MarkepiCore/Sources/MarkepiCore/Resources/Fonts/"
def F(name, size):
    table = {
        "hn": ("/System/Library/Fonts/HelveticaNeue.ttc", 0), "hn-bold": ("/System/Library/Fonts/HelveticaNeue.ttc", 1),
        "hn-light": ("/System/Library/Fonts/HelveticaNeue.ttc", 7), "hn-med": ("/System/Library/Fonts/HelveticaNeue.ttc", 10),
        "hn-cblack": ("/System/Library/Fonts/HelveticaNeue.ttc", 9),
        "avenir": ("/System/Library/Fonts/Avenir Next.ttc", 7), "avenir-demi": ("/System/Library/Fonts/Avenir Next.ttc", 2),
        "menlo": ("/System/Library/Fonts/Menlo.ttc", 0), "menlo-bold": ("/System/Library/Fonts/Menlo.ttc", 1),
        "courier-bold": ("/System/Library/Fonts/Supplemental/Courier New Bold.ttf", 0),
        "futura": ("/System/Library/Fonts/Supplemental/Futura.ttc", 0), "futura-cond": ("/System/Library/Fonts/Supplemental/Futura.ttc", 3),
        "didot": ("/System/Library/Fonts/Supplemental/Didot.ttc", 0), "didot-italic": ("/System/Library/Fonts/Supplemental/Didot.ttc", 1),
        "cormorant": (FONTS + "CormorantGaramond-Regular.ttf", 0), "playfair": (FONTS + "PlayfairDisplay-Regular.ttf", 0),
        "script": (FONTS + "MarckScript-Regular.ttf", 0), "sacramento": (FONTS + "Sacramento-Regular.ttf", 0),
    }
    p, i = table[name]
    return ImageFont.truetype(p, int(size), index=i)

# ---------- helpers ----------
def rmask(size, r):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, size[0] - 1, size[1] - 1], r, fill=255)
    return m

def shadow(canvas, box, r=0, blur=40, opacity=0.4, offset=(0, 20), color=(0, 0, 0)):
    x0, y0, x1, y1 = box
    pad = blur * 3
    layer = Image.new("L", (x1 - x0 + 2 * pad, y1 - y0 + 2 * pad), 0)
    ImageDraw.Draw(layer).rounded_rectangle([pad, pad, pad + x1 - x0, pad + y1 - y0], r, fill=int(255 * opacity))
    layer = layer.filter(ImageFilter.GaussianBlur(blur))
    canvas.paste(Image.new("RGB", layer.size, color), (x0 - pad + offset[0], y0 - pad + offset[1]), layer)

def paste_round(canvas, img, xy, r):
    canvas.paste(img, xy, rmask(img.size, r))

def fit(img, w, h):
    s = min(w / img.width, h / img.height)
    return img.resize((round(img.width * s), round(img.height * s)), Image.LANCZOS)

def cover(img, w, h):
    return ImageOps.fit(img, (w, h), Image.LANCZOS)

def text_c(d, cx, y, s, font, fill, spacing=0):
    if spacing:
        s = spaced_width_draw(d, cx, y, s, font, fill, spacing); return
    w = d.textlength(s, font=font)
    d.text((cx - w / 2, y), s, font=font, fill=fill)

def spaced_width(d, s, font, sp):
    return sum(d.textlength(ch, font=font) for ch in s) + sp * (len(s) - 1)

def spaced_width_draw(d, cx, y, s, font, fill, sp, anchor="c"):
    w = spaced_width(d, s, font, sp)
    x = cx - w / 2 if anchor == "c" else cx
    for ch in s:
        d.text((x, y), ch, font=font, fill=fill); x += d.textlength(ch, font=font) + sp

def noise(size, amount, blur=0, seed=1):
    random.seed(seed)
    n = Image.effect_noise(size, amount).convert("L")
    return n.filter(ImageFilter.GaussianBlur(blur)) if blur else n

def texture(img, strength=10, blur=0.6, seed=1):
    n = noise(img.size, 60, blur, seed)
    n = n.point(lambda v: 128 + (v - 128) * strength / 60)
    return ImageChops.overlay(img, Image.merge("RGB", (n, n, n)))

def lerp(a, b, t): return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))

def profile_color(stops, t):
    for (t0, c0), (t1, c1) in zip(stops, stops[1:]):
        if t0 <= t <= t1: return lerp(c0, c1, (t - t0) / (t1 - t0 or 1))
    return stops[-1][1]

def bevel_ring(d, box, thick, stops, light=(1.12, 1.04, 0.86, 0.74)):
    """Moulding: `stops` is the colour across the profile (outer→inner). Top/left catch light."""
    x0, y0, x1, y1 = box
    for i in range(thick):
        c = profile_color(stops, i / max(1, thick - 1))
        sides = [((x0 + i, y0 + i), (x1 - i, y0 + i), (x1 - i - 1, y0 + i + 1), (x0 + i + 1, y0 + i + 1)),  # top
                 ((x0 + i, y0 + i), (x0 + i + 1, y0 + i + 1), (x0 + i + 1, y1 - i - 1), (x0 + i, y1 - i)),  # left
                 ((x1 - i, y0 + i), (x1 - i, y1 - i), (x1 - i - 1, y1 - i - 1), (x1 - i - 1, y0 + i + 1)),  # right
                 ((x0 + i, y1 - i), (x1 - i, y1 - i), (x1 - i - 1, y1 - i - 1), (x0 + i + 1, y1 - i - 1))]  # bottom
        for poly, k in zip(sides, light):
            d.polygon(poly, fill=tuple(min(255, round(v * k)) for v in c))

def vgrad(size, top, bottom):
    g = Image.linear_gradient("L").resize(size)
    return Image.composite(Image.new("RGB", size, bottom), Image.new("RGB", size, top), g)

def radial(size, center, radius, inner, outer):
    g = Image.radial_gradient("L").resize((radius * 2, radius * 2))
    m = Image.new("L", size, 255); m.paste(g, (center[0] - radius, center[1] - radius))
    return Image.composite(Image.new("RGB", size, outer), Image.new("RGB", size, inner), m)

def save(img, name):
    img.convert("RGB").save(os.path.join(OUT, name + ".jpg"), quality=90)
    print("wrote", name, img.size)

# ================= TRADITIONAL =================
def polaroid():
    m = round(W * 0.06); bottom = round(W * 0.30)
    c = Image.new("RGB", (W + 2 * m, H + m + bottom), (246, 243, 236))
    c = texture(c, 6, 0.8)
    c.paste(PHOTO, (m, m))
    # thin inner shade where the print meets the emulsion
    inner = Image.new("L", (W, H), 0); ImageDraw.Draw(inner).rectangle([0, 0, W - 1, H - 1], outline=90, width=3)
    c.paste((0, 0, 0), (m, m), inner.filter(ImageFilter.GaussianBlur(2)))
    d = ImageDraw.Draw(c)
    f = F("script", W * 0.075)
    d.text((m + W * 0.04, m + H + bottom * 0.28), "first spring walk ♡", font=f, fill=(38, 52, 110))
    d.text((m + W * 0.72, m + H + bottom * 0.36), "30.08.26", font=F("script", W * 0.05), fill=(38, 52, 110))
    return c

def museum():
    frame = round(W * 0.075); mat = round(W * 0.16); label = round(W * 0.10)
    cw, ch = W + 2 * (frame + mat), H + 2 * (frame + mat) + label
    c = Image.new("RGB", (cw, ch), (242, 237, 227))
    c = texture(c, 5, 1.2, seed=3)
    d = ImageDraw.Draw(c)
    walnut = [(0, (60, 38, 24)), (0.15, (98, 64, 40)), (0.35, (130, 88, 56)), (0.55, (84, 54, 33)), (0.8, (70, 45, 28)), (1, (40, 25, 15))]
    bevel_ring(d, (0, 0, cw - 1, ch - 1), frame, walnut)
    # wood grain: stretched noise, multiplied into the moulding only
    grain = noise((cw // 8, ch), 90, 0, seed=7).resize((cw, ch)).filter(ImageFilter.GaussianBlur(1))
    ring = Image.new("L", (cw, ch), 255); ImageDraw.Draw(ring).rectangle([frame, frame, cw - frame - 1, ch - frame - 1], fill=0)
    grained = ImageChops.multiply(c, Image.merge("RGB", [grain.point(lambda v: 200 + v // 5)] * 3))
    c = Image.composite(grained, c, ring); d = ImageDraw.Draw(c)
    px, py = frame + mat, frame + mat
    # bevel-cut mat: bright white core shows around the window, shaded on the lit side
    b = round(W * 0.012)
    d.polygon([(px - b, py - b), (px + W + b, py - b), (px + W, py), (px, py)], fill=(222, 216, 204))
    d.polygon([(px - b, py - b), (px, py), (px, py + H), (px - b, py + H + b)], fill=(232, 227, 216))
    d.polygon([(px + W + b, py - b), (px + W + b, py + H + b), (px + W, py + H), (px + W, py)], fill=(252, 250, 245))
    d.polygon([(px - b, py + H + b), (px + W + b, py + H + b), (px + W, py + H), (px, py + H)], fill=(255, 253, 249))
    c.paste(PHOTO, (px, py))
    ly = py + H + mat * 0.45
    spaced_width_draw(d, cw / 2, ly, MODEL.upper(), F("cormorant", W * 0.032), (70, 60, 50), W * 0.008)
    text_c(d, cw / 2, ly + W * 0.055, EXIF_LINE + "  ·  " + DATE, F("cormorant", W * 0.026), (120, 108, 95))
    return c

def gilded():
    liner = round(W * 0.05)
    rings = [  # (thickness ratio, profile)
        (0.030, [(0, (70, 48, 18)), (0.5, (150, 110, 45)), (1, (95, 66, 22))]),
        (0.055, [(0, (120, 86, 30)), (0.3, (236, 196, 110)), (0.55, (200, 156, 70)), (1, (110, 76, 25))]),
        (0.040, None),  # bead course
        (0.060, [(0, (90, 62, 20)), (0.25, (184, 140, 60)), (0.5, (250, 215, 130)), (0.75, (170, 125, 50)), (1, (60, 40, 12))]),
        (0.018, [(0, (40, 28, 10)), (1, (120, 90, 40))]),
    ]
    total = sum(round(W * t) for t, _ in rings) + liner
    cw, ch = W + 2 * total, H + 2 * total
    c = Image.new("RGB", (cw, ch), (0, 0, 0)); d = ImageDraw.Draw(c)
    o = 0
    for t, prof in rings:
        k = round(W * t)
        if prof is None:
            d.rectangle([o, o, cw - 1 - o, ch - 1 - o], fill=(92, 64, 22))
            r = k * 0.36; step = k * 0.95
            def bead(x, y):
                d.ellipse([x - r, y - r, x + r, y + r], fill=(150, 108, 42))
                d.ellipse([x - r * 0.75, y - r * 0.8, x + r * 0.45, y + r * 0.4], fill=(226, 184, 98))
                d.ellipse([x - r * 0.45, y - r * 0.55, x - r * 0.05, y - r * 0.15], fill=(255, 236, 170))
            m = o + k / 2
            n = int((cw - 2 * m) / step)
            for j in range(n + 1):
                x = m + j * (cw - 2 * m) / n; bead(x, m); bead(x, ch - m)
            n = int((ch - 2 * m) / step)
            for j in range(n + 1):
                y = m + j * (ch - 2 * m) / n; bead(m, y); bead(cw - m, y)
        else:
            bevel_ring(d, (o, o, cw - 1 - o, ch - 1 - o), k, prof)
        o += k
    # linen liner
    lin = Image.new("RGB", (cw - 2 * o, ch - 2 * o), (232, 224, 205))
    lin = texture(lin, 14, 0.4, seed=5)
    c.paste(lin, (o, o))
    shadow(c, (o + liner, o + liner, o + liner + W, o + liner + H), 0, 8, 0.35, (0, 3))
    c.paste(PHOTO, (o + liner, o + liner))
    # gold leaf sparkle
    sparkle = noise(c.size, 40, 0, seed=11).point(lambda v: 255 if v > 205 else 0).filter(ImageFilter.GaussianBlur(0.6))
    ring = Image.new("L", c.size, 0); ImageDraw.Draw(ring).rectangle([0, 0, cw, ch], fill=90); ImageDraw.Draw(ring).rectangle([o, o, cw - o, ch - o], fill=0)
    c.paste((255, 240, 190), (0, 0), ImageChops.multiply(sparkle, ring))
    return c

# ================= FILM =================
AMBER = (232, 164, 58)

def film35():
    mm = W / 24.0  # 24mm across the frame (portrait strip)
    side = round(5.5 * mm); gap = round(2.0 * mm); tail = round(6 * mm)
    cw, ch = W + 2 * side, H + 2 * tail
    c = Image.new("RGB", (cw, ch), (22, 19, 17))
    c = texture(c, 8, 0.8)
    d = ImageDraw.Draw(c)
    # neighbouring frames peeking in at the ends
    top = PHOTO.crop((0, H - (tail - gap), W, H)).filter(ImageFilter.GaussianBlur(3)); top = ImageEnhance.Brightness(top).enhance(0.7)
    bot = PHOTO.crop((0, 0, W, tail - gap)).filter(ImageFilter.GaussianBlur(3)); bot = ImageEnhance.Brightness(bot).enhance(0.7)
    c.paste(top, (side, 0)); c.paste(bot, (side, tail + H + gap))
    c.paste(PHOTO, (side, tail))
    hw, hh, pitch, edge = 1.98 * mm, 2.8 * mm, 4.75 * mm, 1.0 * mm
    y = -pitch / 2
    while y < ch:
        for x in (edge, cw - edge - hw):
            d.rounded_rectangle([x, y, x + hw, y + hh], hw * 0.18, fill=(238, 236, 230))
        y += pitch
    # rotated edge print
    def edge_text(s, x, y, size, rot):
        f = F("futura-cond", size)
        tw = int(d.textlength(s, font=f)) + 8
        t = Image.new("L", (tw, int(size * 1.4)), 0); ImageDraw.Draw(t).text((4, 0), s, font=f, fill=255)
        t = t.rotate(rot, expand=True)
        c.paste(AMBER, (int(x), int(y)), t)
    ts = 1.5 * mm; tx = edge + hw + 0.35 * mm
    edge_text("MK 400  SAFETY FILM", tx, tail + H * 0.12, ts, 270)
    edge_text("14", tx, tail + H * 0.72, ts, 270)
    edge_text("14A", cw - tx - ts * 1.4, tail + H * 0.2, ts, 270)
    edge_text("15", cw - tx - ts * 1.4, tail + H * 0.75, ts, 270)
    # DX-style bar code
    bx = cw - tx - ts * 1.2
    for j in range(14):
        if (j * 7) % 3: d.rectangle([bx, tail + H * 0.42 + j * mm * 0.6, bx + ts * 0.9, tail + H * 0.42 + j * mm * 0.6 + mm * 0.35], fill=AMBER)
    return c

def medium_format():
    b = round(W * 0.075)
    cw, ch = W + 2 * b + round(W * 0.14), H + 2 * b + round(W * 0.14)
    c = Image.new("RGB", (cw, ch), (250, 250, 248))  # lightbox
    d = ImageDraw.Draw(c)
    ox, oy = round(W * 0.07), round(W * 0.07)
    # film base with a slightly irregular (filed carrier) outline
    random.seed(4)
    fx0, fy0, fx1, fy1 = ox, oy, ox + W + 2 * b, oy + H + 2 * b
    d.rectangle([fx0, fy0, fx1, fy1], fill=(14, 13, 12))
    ix0, iy0 = ox + b, oy + b
    rough = Image.new("L", (W + 40, H + 40), 0); rd = ImageDraw.Draw(rough)
    pts = []
    def edge(a, bb, n):
        for k in range(n):
            t = k / n; pts.append((a[0] + (bb[0] - a[0]) * t + random.uniform(-3, 3), a[1] + (bb[1] - a[1]) * t + random.uniform(-3, 3)))
    edge((20, 20), (W + 20, 20), 60); edge((W + 20, 20), (W + 20, H + 20), 80); edge((W + 20, H + 20), (20, H + 20), 60); edge((20, H + 20), (20, 20), 80)
    rd.polygon(pts, fill=255); rough = rough.filter(ImageFilter.GaussianBlur(1.2))
    ph = Image.new("RGB", rough.size, (14, 13, 12)); ph.paste(PHOTO, (20, 20))
    c.paste(ph, (ix0 - 20, iy0 - 20), rough)
    # light leak along the rebate
    leak = Image.new("RGB", c.size, (0, 0, 0))
    ImageDraw.Draw(leak).ellipse([fx1 - b * 2, iy0 - H * 0.05, fx1 + b * 2, iy0 + H * 0.45], fill=(255, 110, 30))
    leak = leak.filter(ImageFilter.GaussianBlur(b * 0.9))
    lm = Image.new("L", c.size, 0); ImageDraw.Draw(lm).rectangle([fx0, fy0, fx1, fy1], fill=200); ImageDraw.Draw(lm).rectangle([ix0, iy0, ix0 + W, iy0 + H], fill=0)
    c = Image.composite(ImageChops.screen(c, leak), c, lm); d = ImageDraw.Draw(c)
    # V notch (film identification) + rebate text
    n = b * 0.5
    d.polygon([(fx0, iy0 + H * 0.3), (fx0 + n, iy0 + H * 0.3 + n * 0.6), (fx0, iy0 + H * 0.3 + n * 1.2)], fill=(250, 250, 248))
    f = F("futura-cond", b * 0.36)
    d.text((ix0 + W * 0.04, fy0 + b * 0.3), "MK PRO 400H", font=f, fill=(232, 210, 150))
    d.text((ix0 + W * 0.55, fy0 + b * 0.3), "6", font=f, fill=(232, 210, 150))
    d.text((ix0 + W * 0.04, fy1 - b * 0.72), "6    MK PRO 400H    30-08-26", font=f, fill=(232, 210, 150))
    return c

def slide_mount():
    side = round(H * 50 / 36)
    c = Image.new("RGB", (side, side), (236, 231, 219))
    c = texture(c, 10, 1.0, seed=9)
    d = ImageDraw.Draw(c)
    x0, y0 = (side - W) // 2, (side - H) // 2
    r = round(W * 0.03)
    # embossed rim around the window
    for i, col in enumerate([(210, 204, 190), (220, 214, 200), (228, 223, 210)]):
        k = round(W * 0.012) * (3 - i)
        d.rounded_rectangle([x0 - k, y0 - k, x0 + W + k, y0 + H + k], r + k, fill=col)
    paste_round(c, PHOTO, (x0, y0), r)
    f = F("courier-bold", side * 0.022)
    d.text((x0, y0 - side * 0.075), "30 AUG 2026", font=f, fill=(90, 84, 76))
    d.text((x0 + W - d.textlength("№ 14", font=f), y0 - side * 0.075), "№ 14", font=f, fill=(90, 84, 76))
    text_c(d, side / 2, y0 + H + side * 0.045, "MARKEPI TRANSPARENCY  ·  " + MODEL.upper(), F("courier-bold", side * 0.017), (120, 112, 100))
    # rounded mount corners on a dark table
    bg = Image.new("RGB", (side + 120, side + 120), (34, 33, 36))
    shadow(bg, (60, 60, 60 + side, 60 + side), side * 0.04, 25, 0.6, (0, 14))
    bg.paste(c, (60, 60), rmask(c.size, round(side * 0.04)))
    return bg

# ================= MODERN =================
def blurred_bg(size, dim=0.82, blur=70):
    bg = cover(PHOTO, *size).filter(ImageFilter.GaussianBlur(blur))
    return ImageEnhance.Brightness(bg).enhance(dim)

def ambient():
    cw, ch = 1600, 2000
    c = blurred_bg((cw, ch))
    p = fit(PHOTO, cw * 0.74, ch * 0.74)
    x, y = (cw - p.width) // 2, round(ch * 0.08)
    r = round(cw * 0.035)
    shadow(c, (x, y, x + p.width, y + p.height), r, 50, 0.5, (0, 28))
    paste_round(c, p, (x, y), r)
    d = ImageDraw.Draw(c)
    ty = y + p.height + ch * 0.045
    text_c(d, cw / 2, ty, MODEL, F("hn-bold", cw * 0.036), (255, 255, 255))
    text_c(d, cw / 2, ty + cw * 0.058, EXIF_LINE, F("hn", cw * 0.026), (255, 255, 255, 190))
    return c

def palette(img, n=6):
    q = img.resize((120, 160)).quantize(n, method=Image.Quantize.MEDIANCUT)
    pal = q.getpalette()[: n * 3]
    cols = [tuple(pal[i:i + 3]) for i in range(0, n * 3, 3)]
    counts = sorted(q.getcolors(), reverse=True)
    return [cols[i] for _, i in counts]

def mesh_gradient():
    cw, ch = 1600, 2000
    cols = palette(PHOTO)
    sat = lambda c: max(c) - min(c)
    deep = min(cols, key=lambda c: sum(c) - sat(c))           # navy of the jacket
    warm = max(cols, key=lambda c: c[0] - c[2] + sum(c) / 6)  # skin / hat pink
    mid = sorted(cols, key=lambda c: -sat(c))[0]
    c = Image.new("RGB", (cw, ch), lerp(deep, (0, 0, 0), 0.35))
    blobs = Image.new("RGB", (cw, ch), (0, 0, 0)); bd = ImageDraw.Draw(blobs)
    for (cx, cy, r, col) in [(0.1, 0.05, 0.75, warm), (0.95, 0.55, 0.6, mid), (0.2, 1.0, 0.6, lerp(deep, (255, 255, 255), 0.25))]:
        bd.ellipse([cx * cw - r * cw, cy * ch - r * cw, cx * cw + r * cw, cy * ch + r * cw], fill=col)
    blobs = ImageEnhance.Color(blobs.filter(ImageFilter.GaussianBlur(260))).enhance(1.8)
    m = Image.new("L", (cw, ch), 0).point(lambda _: 200)
    c = Image.composite(blobs, c, ImageChops.multiply(m, blobs.convert("L").point(lambda v: min(255, v * 3))))
    c = texture(c, 5, 0.5)  # grain kills gradient banding
    p = fit(PHOTO, cw * 0.72, ch * 0.72)
    x, y = (cw - p.width) // 2, round(ch * 0.07)
    r = round(cw * 0.05)
    shadow(c, (x, y, x + p.width, y + p.height), r, 70, 0.45, (0, 40), color=lerp(deep, (0, 0, 0), 0.6))
    paste_round(c, p, (x, y), r)
    # EXIF pills
    d = ImageDraw.Draw(c, "RGBA")
    f = F("hn-med", cw * 0.026)
    pad, gap, hgt = cw * 0.022, cw * 0.018, cw * 0.058
    widths = [d.textlength(s, font=f) + 2 * pad for s in EXIF]
    tx = (cw - sum(widths) - gap * (len(EXIF) - 1)) / 2
    py = y + p.height + ch * 0.05
    for s, w in zip(EXIF, widths):
        d.rounded_rectangle([tx, py, tx + w, py + hgt], hgt / 2, fill=(255, 255, 255, 46), outline=(255, 255, 255, 90), width=2)
        d.text((tx + pad, py + hgt * 0.2), s, font=f, fill=(255, 255, 255, 235)); tx += w + gap
    text_c(d, cw / 2, py + hgt + ch * 0.028, MODEL.upper(), F("avenir-demi", cw * 0.022), (255, 255, 255, 170))
    return c

def glass_card():
    cw, ch = 1600, 2000
    c = blurred_bg((cw, ch), 0.9, 60)
    p = fit(PHOTO, cw * 0.80, ch * 0.80)
    x, y = (cw - p.width) // 2, round(ch * 0.05)
    r = round(cw * 0.04)
    shadow(c, (x, y, x + p.width, y + p.height), r, 50, 0.4, (0, 24))
    paste_round(c, p, (x, y), r)
    # frosted card overlapping the photo's lower edge — true glass: blur what's underneath
    cx0, cx1 = round(cw * 0.14), round(cw * 0.86)
    cy0 = y + p.height - round(ch * 0.07); cy1 = cy0 + round(ch * 0.15)
    rr = round(cw * 0.035)
    shadow(c, (cx0, cy0, cx1, cy1), rr, 40, 0.3, (0, 18))
    under = c.crop((cx0, cy0, cx1, cy1)).filter(ImageFilter.GaussianBlur(28))
    under = Image.blend(under, Image.new("RGB", under.size, (255, 255, 255)), 0.28)
    c.paste(under, (cx0, cy0), rmask(under.size, rr))
    d = ImageDraw.Draw(c, "RGBA")
    d.rounded_rectangle([cx0, cy0, cx1, cy1], rr, outline=(255, 255, 255, 140), width=2)
    d.text((cx0 + cw * 0.045, cy0 + ch * 0.028), MODEL, font=F("hn-bold", cw * 0.034), fill=(20, 24, 40))
    d.text((cx0 + cw * 0.045, cy0 + ch * 0.075), DATE, font=F("hn", cw * 0.026), fill=(20, 24, 40, 170))
    cols = ["24mm", "f/1.8", "1/783s", "ISO 64"]
    colx = cx0 + (cx1 - cx0) * 0.52; step = (cx1 - colx - cw * 0.04) / 2
    for i, s in enumerate(cols):
        d.text((colx + (i % 2) * step, cy0 + ch * (0.03 + 0.05 * (i // 2))), s, font=F("hn-med", cw * 0.03), fill=(20, 24, 40, 220))
    return c

def stack():
    cw, ch = 1600, 2000
    c = radial((cw, ch), (cw // 2, ch // 3), round(ch * 0.9), (240, 236, 229), (205, 198, 186))
    c = texture(c, 5, 0.8)
    b = round(W * 0.045)
    card = Image.new("RGB", (W + 2 * b, H + 2 * b + round(W * 0.06)), (252, 251, 248)); card.paste(PHOTO, (b, b))
    ImageDraw.Draw(card).text((b, H + b + b * 0.35), MODEL + "   " + EXIF_LINE, font=F("hn", W * 0.024), fill=(120, 116, 110))
    card = card.resize((round(card.width * 0.9), round(card.height * 0.9)), Image.LANCZOS)
    def drop(img, angle, dx, dy, op):
        rgba = img.convert("RGBA").rotate(angle, Image.BICUBIC, expand=True)
        a = rgba.split()[3]
        x, y = (cw - rgba.width) // 2 + dx, (ch - rgba.height) // 2 + dy
        sh = Image.new("L", (rgba.width + 200, rgba.height + 200), 0); sh.paste(a.point(lambda v: v * op), (100, 100))
        sh = sh.filter(ImageFilter.GaussianBlur(30))
        c.paste((40, 32, 24), (x - 100 + 10, y - 100 + 26), sh)
        c.paste(rgba, (x, y), rgba)
    blank = Image.new("RGB", card.size, (246, 244, 240)); blank.paste(ImageEnhance.Brightness(PHOTO.resize((card.width - 2 * b, card.height - 2 * b - round(W * 0.054))).filter(ImageFilter.GaussianBlur(10))).enhance(1.4), (b, b))
    drop(blank, -7, -40, 10, 0.35)
    drop(blank, 4.5, 30, -10, 0.35)
    drop(card, -1.2, 0, 0, 0.55)
    return c

def neon():
    cw, ch = 1600, 2000
    c = Image.new("RGB", (cw, ch), (9, 9, 16))
    p = fit(PHOTO, cw * 0.72, ch * 0.72)
    x, y = (cw - p.width) // 2, round(ch * 0.08)
    r = round(cw * 0.045); sw = 10
    import numpy as np
    yy, xx = np.mgrid[0:ch, 0:cw]
    t = ((xx - x) / p.width * 0.55 + (yy - y) / p.height * 0.45).clip(0, 1)
    stops = [(0, (0, 229, 255)), (0.5, (190, 60, 255)), (1, (255, 110, 70))]
    lut = np.array([profile_color(stops, i / 255) for i in range(256)], dtype=np.uint8)
    grad = Image.fromarray(lut[(t * 255).astype(np.uint8)])
    ring = Image.new("L", (cw, ch), 0)
    ImageDraw.Draw(ring).rounded_rectangle([x - 18, y - 18, x + p.width + 18, y + p.height + 18], r + 18, outline=255, width=sw)
    glow = ImageChops.multiply(grad, Image.merge("RGB", [ring.filter(ImageFilter.GaussianBlur(40))] * 3))
    glow2 = ImageChops.multiply(grad, Image.merge("RGB", [ring.filter(ImageFilter.GaussianBlur(12))] * 3))
    c = ImageChops.add(c, ImageEnhance.Brightness(glow).enhance(2.2))
    c = ImageChops.add(c, ImageEnhance.Brightness(glow2).enhance(1.6))
    c.paste(grad, (0, 0), ring)
    paste_round(c, p, (x, y), r)
    d = ImageDraw.Draw(c)
    ty = y + p.height + ch * 0.07
    spaced_width_draw(d, cw / 2, ty, MODEL.upper(), F("menlo", cw * 0.026), (235, 240, 255), cw * 0.008)
    spaced_width_draw(d, cw / 2, ty + cw * 0.05, "  /  ".join(EXIF).upper(), F("menlo", cw * 0.02), (150, 160, 200), cw * 0.004)
    return c

# ================= ARTWORK =================
def deckled():
    pw, ph = round(W * 1.34), round(H * 1.36)
    random.seed(21)
    # deckle: many small jagged steps plus a slow wobble
    pts = []
    def side(a, b, n, nx, ny):
        for k in range(n):
            t = k / n
            j = random.uniform(-7, 7) + 5 * math.sin(t * 17 + random.random())
            pts.append((a[0] + (b[0] - a[0]) * t + nx * j, a[1] + (b[1] - a[1]) * t + ny * j))
    side((0, 0), (pw, 0), 260, 0, 1); side((pw, 0), (pw, ph), 320, -1, 0); side((pw, ph), (0, ph), 260, 0, -1); side((0, ph), (0, 0), 320, 1, 0)
    m = Image.new("L", (pw + 60, ph + 60), 0); ImageDraw.Draw(m).polygon([(px + 30, py + 30) for px, py in pts], fill=255)
    m = m.filter(ImageFilter.GaussianBlur(1.5))
    paper = Image.new("RGB", m.size, (244, 239, 227)); paper = texture(paper, 16, 1.4, seed=13)
    # cold-press tooth
    tooth = noise(m.size, 80, 3, seed=17).point(lambda v: 128 + (v - 128) // 3)
    paper = ImageChops.overlay(paper, Image.merge("RGB", [tooth] * 3))
    pd = ImageDraw.Draw(paper)
    ox, oy = (pw - W) // 2 + 30, round(W * 0.16) + 30
    paper.paste(PHOTO, (ox, oy))
    pd.text((ox, oy + H + W * 0.04), "Sunday, blue jacket", font=F("sacramento", W * 0.085), fill=(70, 70, 90))
    t = MODEL + " — " + DATE
    pd.text((ox + W - pd.textlength(t, font=F("cormorant", W * 0.03)), oy + H + W * 0.085), t, font=F("cormorant", W * 0.03), fill=(110, 104, 96))
    cw, ch = m.width + 240, m.height + 240
    c = Image.new("RGB", (cw, ch), (46, 44, 42)); c = texture(c, 10, 1)
    sh = m.point(lambda v: v * 0.6).filter(ImageFilter.GaussianBlur(26))
    c.paste((0, 0, 0), (120 + 14, 120 + 26), sh)
    c.paste(paper, (120, 120), m)
    return c

def gallery_wall():
    cw, ch = 1600, 2000
    c = vgrad((cw, ch), (214, 207, 196), (176, 168, 156))
    spot = radial((cw, ch), (cw // 2, round(ch * 0.02)), round(ch * 0.8), (255, 248, 232), (0, 0, 0))
    c = ImageChops.screen(c, ImageEnhance.Brightness(spot).enhance(0.35))
    c = texture(c, 6, 1.5)
    p = fit(PHOTO, cw * 0.5, ch * 0.5)
    mat, fr = round(p.width * 0.16), round(p.width * 0.028)
    fw, fh = p.width + 2 * (mat + fr), p.height + 2 * (mat + fr)
    x, y = (cw - fw) // 2, round(ch * 0.14)
    shadow(c, (x, y, x + fw, y + fh), 0, 45, 0.55, (28, 50), color=(40, 30, 20))
    shadow(c, (x, y, x + fw, y + fh), 0, 8, 0.4, (4, 8))
    d = ImageDraw.Draw(c)
    bevel_ring(d, (x, y, x + fw - 1, y + fh - 1), fr, [(0, (40, 40, 42)), (0.5, (18, 18, 20)), (1, (8, 8, 9))])
    d.rectangle([x + fr, y + fr, x + fw - fr - 1, y + fh - fr - 1], fill=(250, 249, 246))
    # the mat throws a shadow onto the photo from the top-left light
    ix, iy = x + fr + mat, y + fr + mat
    c.paste(p, (ix, iy))
    sm = Image.new("L", p.size, 0); ImageDraw.Draw(sm).rectangle([0, 0, p.width, 6], fill=110); ImageDraw.Draw(sm).rectangle([0, 0, 5, p.height], fill=80)
    c.paste((0, 0, 0), (ix, iy), sm.filter(ImageFilter.GaussianBlur(3)))
    # museum label
    lx, ly, lw, lh = x + fw + round(cw * 0.04), y + fh - round(ch * 0.1), round(cw * 0.17), round(ch * 0.1)
    shadow(c, (lx, ly, lx + lw, ly + lh), 0, 6, 0.3, (3, 5))
    d.rectangle([lx, ly, lx + lw, ly + lh], fill=(250, 249, 245))
    d.text((lx + lw * 0.1, ly + lh * 0.13), "Untitled (blue)", font=F("hn-bold", cw * 0.014), fill=(30, 30, 30))
    d.text((lx + lw * 0.1, ly + lh * 0.36), "2026", font=F("hn", cw * 0.012), fill=(80, 80, 80))
    d.text((lx + lw * 0.1, ly + lh * 0.58), MODEL, font=F("hn", cw * 0.0105), fill=(100, 100, 100))
    d.text((lx + lw * 0.1, ly + lh * 0.76), "24mm, f/1.8", font=F("hn", cw * 0.0105), fill=(100, 100, 100))
    # floor line / bench hint
    d.rectangle([0, round(ch * 0.9), cw, ch], fill=(120, 108, 94))
    c.paste(vgrad((cw, ch - round(ch * 0.9)), (104, 92, 78), (70, 60, 50)), (0, round(ch * 0.9)))
    return c

def swiss():
    cw, ch = 1600, 2000
    c = Image.new("RGB", (cw, ch), (244, 242, 236))
    d = ImageDraw.Draw(c)
    m = round(cw * 0.07)
    p = fit(PHOTO, cw * 0.62, ch * 0.62)
    c.paste(p, (m, m))
    red = (225, 45, 35)
    d.text((m - cw * 0.012, m + p.height + ch * 0.005), "30.08", font=F("hn-cblack", cw * 0.235), fill=red)
    col = m + p.width + cw * 0.04
    rows = [("CAMERA", MODEL), ("LENS", "24mm"), ("APERTURE", "f/1.8"), ("SHUTTER", "1/783s"), ("ISO", "64"), ("YEAR", "2026")]
    yy = m
    for k, v in rows:
        d.line([col, yy, cw - m, yy], fill=(20, 20, 20), width=3)
        d.text((col, yy + cw * 0.01), k, font=F("hn-bold", cw * 0.013), fill=(20, 20, 20))
        d.text((col, yy + cw * 0.032), v, font=F("hn", cw * 0.021), fill=(20, 20, 20))
        yy += ch * 0.07
    d.rectangle([col, ch - m - cw * 0.06, col + cw * 0.06, ch - m], fill=red)
    return c

GROUPS = [
    ("Traditional", [("polaroid", "Instant print", polaroid), ("museum", "Walnut & mat", museum), ("gilded", "Gilded ornate", gilded)]),
    ("Film camera", [("film35", "35mm strip", film35), ("medium_format", "Medium-format negative", medium_format), ("slide", "Slide mount", slide_mount)]),
    ("Modern & effects", [("ambient", "Ambient blur", ambient), ("mesh", "Photo-palette gradient", mesh_gradient), ("glass", "Frosted glass card", glass_card), ("stack", "Print stack (depth)", stack), ("neon", "Neon glow", neon)]),
    ("Artwork", [("deckled", "Deckled fine-art paper", deckled), ("wall", "Gallery wall", gallery_wall), ("swiss", "Swiss poster", swiss)]),
]

if __name__ == "__main__":
    only = set(sys.argv[1:])
    for _, items in GROUPS:
        for key, _, fn in items:
            if not only or key in only: save(fn(), key)
