# Modern, minimal frames. Photo first: borders are a few % of the short edge,
# one caption block, real metadata (as EXIFTokenParser formats it) + maker mark.
import os, sys, colorsys
from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageEnhance, ImageOps
from frames import PHOTO, W, H, HERE, rmask, shadow, paste_round, fit, cover, texture, lerp, palette

OUT = os.path.join(HERE, "modern"); os.makedirs(OUT, exist_ok=True)

MODEL = "iPhone 15 Pro Max"
SETTINGS = ["121mm", "f/1.8", "1/783", "ISO 64"]
SET_LINE = "   ".join(SETTINGS)
DATE, TIME, PLACE = "30 Aug 2026", "15:19", "Netherlands"

def sf(size, weight="Regular"):
    f = ImageFont.truetype("/System/Library/Fonts/SFNS.ttf", round(size))
    f.set_variation_by_name(weight); return f

def cam(size):
    return ImageFont.truetype("/System/Library/Fonts/SFCamera.ttf", round(size))

def logo(color, h):
    im = Image.open(os.path.join(HERE, f"apple-{color}.png")).convert("RGBA")
    return im.resize((round(im.width * h / im.height), round(h)), Image.LANCZOS)

def tinted_logo(rgb, h):
    a = logo("white", h).split()[3]
    im = Image.new("RGBA", a.size, rgb + (255,)); im.putalpha(a); return im

def put(c, im, x, y): c.paste(im, (round(x), round(y)), im); return im.width

def tw(d, s, f): return d.textlength(s, font=f)

def save(img, name):
    img.convert("RGB").save(os.path.join(OUT, name + ".jpg"), quality=92); print("wrote", name, img.size)

S = min(W, H)  # short edge: every border is a share of it

def row_caption(c, x0, x1, y, h, ink, sub, mark):
    """Left: mark + model / date.  Right: settings / place.  Two quiet lines."""
    d = ImageDraw.Draw(c)
    f1, f2 = sf(h * 0.42, "Semibold"), sf(h * 0.32)
    lg = mark if isinstance(mark, Image.Image) else logo(mark, h * 0.62)
    put(c, lg, x0, y + (h - lg.height) / 2 - h * 0.02)
    tx = x0 + lg.width + h * 0.32
    d.text((tx, y), MODEL, font=f1, fill=ink)
    d.text((tx, y + h * 0.56), f"{DATE}  {TIME}", font=f2, fill=sub)
    d.text((x1 - tw(d, SET_LINE, f1), y), SET_LINE, font=f1, fill=ink)
    d.text((x1 - tw(d, PLACE, f2), y + h * 0.56), PLACE, font=f2, fill=sub)

# 1 ── Float: rounded photo lifted off a warm paper-white card
def float_card():
    side, bottom = round(S * 0.07), round(S * 0.19)
    c = Image.new("RGB", (W + 2 * side, H + side + bottom), (246, 245, 241))
    r = round(S * 0.028)
    shadow(c, (side, side, side + W, side + H), r, 30, 0.22, (0, 14))
    paste_round(c, PHOTO, (side, side), r)
    row_caption(c, side, side + W, side + H + bottom * 0.33, S * 0.062, (28, 28, 30), (140, 138, 134), "black")
    return c

# 2 ── Tone: the border takes the photo's own deepest colour
def tone():
    cols = palette(PHOTO, 8)
    deep = min(cols, key=lambda q: sum(q) - 1.5 * (max(q) - min(q)))
    h_, l, s_ = colorsys.rgb_to_hls(*[v / 255 for v in deep])
    bg = tuple(round(v * 255) for v in colorsys.hls_to_rgb(h_, 0.20, min(0.45, s_)))
    ink = tuple(round(v * 255) for v in colorsys.hls_to_rgb(h_, 0.92, 0.35))
    sub = tuple(round(v * 255) for v in colorsys.hls_to_rgb(h_, 0.68, 0.30))
    side, bottom = round(S * 0.045), round(S * 0.15)
    c = Image.new("RGB", (W + 2 * side, H + side + bottom), bg)
    c.paste(PHOTO, (side, side))
    row_caption(c, side, side + W, side + H + bottom * 0.30, S * 0.06, ink, sub, tinted_logo(ink, S * 0.06 * 0.62))
    return c

# 3 ── Swatch: the photo's palette as the caption
def swatch():
    side, bottom = round(S * 0.045), round(S * 0.15)
    c = Image.new("RGB", (W + 2 * side, H + side + bottom), (255, 255, 255))
    c.paste(PHOTO, (side, side))
    d = ImageDraw.Draw(c)
    cols = sorted(palette(PHOTO, 6)[:5], key=lambda q: sum(q))
    rr = S * 0.026; y = side + H + bottom * 0.5
    for i, col in enumerate(cols):
        cx = side + rr + i * rr * 2.35
        d.ellipse([cx - rr, y - rr, cx + rr, y + rr], fill=col)
    h = S * 0.06; f1, f2 = sf(h * 0.42, "Semibold"), sf(h * 0.32)
    x1 = side + W; ty = y - h * 0.5
    d.text((x1 - tw(d, MODEL, f1), ty), MODEL, font=f1, fill=(28, 28, 30))
    d.text((x1 - tw(d, SET_LINE, f2), ty + h * 0.56), SET_LINE, font=f2, fill=(140, 140, 144))
    lg = logo("black", h * 0.62)
    put(c, lg, x1 - max(tw(d, MODEL, f1), tw(d, SET_LINE, f2)) - lg.width - h * 0.35, ty + h * 0.12)
    return c

# 4 ── Spine: a slim side rail carries the caption, read bottom-to-top
def spine():
    b, rail = round(S * 0.04), round(S * 0.11)
    c = Image.new("RGB", (W + b + rail, H + 2 * b), (250, 250, 248))
    c.paste(PHOTO, (b, b))
    d = ImageDraw.Draw(c)
    h = rail * 0.34
    s = f"{MODEL}     {SET_LINE}     {DATE}"
    f = sf(h * 0.62, "Medium")
    strip = Image.new("RGBA", (round(tw(d, s, f)) + 10, round(h)), (0, 0, 0, 0))
    sd = ImageDraw.Draw(strip)
    x = 0
    for part, col in ((MODEL, (28, 28, 30)), ("     " + SET_LINE, (135, 135, 140)), ("     " + DATE, (135, 135, 140))):
        sd.text((x, 0), part, font=f, fill=col); x += tw(sd, part, f)
    strip = strip.rotate(90, expand=True)
    rx = b + W + (rail - strip.width) / 2
    put(c, strip, rx, b + H - strip.height)
    lg = logo("black", rail * 0.3)
    put(c, lg, b + W + (rail - lg.width) / 2, b)
    return c

# 5 ── Noir: black, even, quiet white type
def noir():
    side, bottom = round(S * 0.035), round(S * 0.13)
    c = Image.new("RGB", (W + 2 * side, H + side + bottom), (10, 10, 11))
    paste_round(c, PHOTO, (side, side), round(S * 0.012))
    row_caption(c, side, side + W, side + H + bottom * 0.30, S * 0.058, (242, 242, 244), (130, 130, 136), "white")
    return c

# 6 ── Ambient: the photo, blurred, is its own backdrop (4:5 for feeds)
def ambient():
    cw, ch = 1600, 2000
    bg = ImageEnhance.Brightness(cover(PHOTO, cw, ch).filter(ImageFilter.GaussianBlur(80))).enhance(0.72)
    c = texture(bg, 3, 0.6)
    p = fit(PHOTO, cw * 0.84, ch * 0.80)
    x, y = (cw - p.width) // 2, round((ch - p.height) * 0.30)
    r = round(cw * 0.026)
    shadow(c, (x, y, x + p.width, y + p.height), r, 50, 0.4, (0, 22))
    paste_round(c, p, (x, y), r)
    row_caption(c, x, x + p.width, y + p.height + (ch - y - p.height) * 0.33, cw * 0.05, (255, 255, 255), (215, 215, 222), "white")
    return c

# 7 ── Aura: a soft gradient mixed from the photo's own colours (4:5)
def aura():
    cw, ch = 1600, 2000
    cols = palette(PHOTO, 8)
    sat = lambda q: max(q) - min(q)
    deep = min(cols, key=lambda q: sum(q) - 2 * sat(q))
    warm = max(cols, key=lambda q: q[0] - q[2] + sum(q) / 6)
    c = Image.new("RGB", (cw, ch), lerp(deep, (10, 14, 30), 0.5)); d = ImageDraw.Draw(c)
    for cx, cy, r, col in [(0.05, 0.0, 0.7, warm), (1.0, 0.45, 0.55, deep), (0.15, 1.0, 0.6, lerp(deep, (130, 160, 255), 0.35))]:
        d.ellipse([cx * cw - r * cw, cy * ch - r * cw, cx * cw + r * cw, cy * ch + r * cw], fill=col)
    c = texture(ImageEnhance.Color(c.filter(ImageFilter.GaussianBlur(320))).enhance(1.4), 4, 0.5)
    p = fit(PHOTO, cw * 0.84, ch * 0.80)
    x, y = (cw - p.width) // 2, round((ch - p.height) * 0.30)
    r = round(cw * 0.026)
    shadow(c, (x, y, x + p.width, y + p.height), r, 70, 0.5, (0, 34), color=lerp(deep, (0, 0, 0), 0.7))
    paste_round(c, p, (x, y), r)
    row_caption(c, x, x + p.width, y + p.height + (ch - y - p.height) * 0.33, cw * 0.05, (255, 255, 255), (220, 220, 232), "white")
    return c

# 8 ── Readout: camera-UI type, like the viewfinder's own labels
def readout():
    side, bottom = round(S * 0.035), round(S * 0.11)
    c = Image.new("RGB", (W + 2 * side, H + side + bottom), (255, 255, 255))
    c.paste(PHOTO, (side, side))
    d = ImageDraw.Draw(c)
    h = S * 0.030; f = cam(h); y = side + H + (bottom - h) / 2 - h * 0.1
    items = SETTINGS
    lg = logo("black", h * 0.95)
    put(c, lg, side, y + h * 0.02)
    d.text((side + lg.width + h * 0.6, y), MODEL.upper(), font=f, fill=(20, 20, 20))
    # settings as evenly spaced readouts, right-aligned
    x = side + W
    for s in reversed(items):
        w = tw(d, s, f); x -= w
        d.text((x, y), s, font=f, fill=(245, 166, 35) if s == "f/1.8" else (20, 20, 20))
        x -= h * 1.3
    return c

STYLES = [("float", "Float", float_card), ("tone", "Tone", tone), ("swatch", "Swatch", swatch), ("spine", "Spine", spine),
          ("noir", "Noir", noir), ("readout", "Readout", readout), ("ambient", "Ambient", ambient), ("aura", "Aura", aura)]

if __name__ == "__main__":
    only = set(sys.argv[1:])
    for key, _, fn in STYLES:
        if not only or key in only: save(fn(), key)
