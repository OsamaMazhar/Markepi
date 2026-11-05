"""TrustMark P: quality, coverage, and survival through a messaging-app pipeline.

Notes baked in from the source:
  * variant P forces a CENTRE SQUARE region (aspect_ratio_lim = 0), so on a 4:3
    photo only the central square is watermarked.
  * python multiplies WM_STRENGTH by 1.25 for P, so strength 1.0 == effective 1.25.
"""
import os, time, json
from PIL import Image
import numpy as np

SRC = "/tmp/refimage-sample/IMG_0104.jpeg"
OUT = "/tmp/wmrunP"
os.makedirs(OUT, exist_ok=True)

def long_edge(im, px):
    w, h = im.size
    s = px / max(w, h)
    return im.copy() if s >= 1 else im.resize((round(w*s), round(h*s)), Image.LANCZOS)

def center_crop(im, pct):
    w, h = im.size
    dx, dy = int(w*pct/2), int(h*pct/2)
    return im.crop((dx, dy, w-dx, h-dy))

def jpeg(im, path, q):
    im.save(path, "JPEG", quality=q)     # no exif/icc passed -> metadata stripped
    return os.path.getsize(path)

def psnr(a, b):
    a = np.asarray(a, float); b = np.asarray(b, float)
    mse = ((a-b)**2).mean()
    return 99.0 if mse == 0 else 10*np.log10(255.0**2/mse)

ATTACKS = [
    ("none (q95 re-save)",   lambda im, p: jpeg(im, p, 95)),
    ("wa 1600 q60",          lambda im, p: jpeg(long_edge(im, 1600), p, 60)),
    ("wa 1080 q55",          lambda im, p: jpeg(long_edge(im, 1080), p, 55)),
    ("wa HD 1600 q80",       lambda im, p: jpeg(long_edge(im, 1600), p, 80)),
    ("heavy 1600 q40",       lambda im, p: jpeg(long_edge(im, 1600), p, 40)),
    ("screenshot 1179 q80",  lambda im, p: jpeg(long_edge(im, 1179), p, 80)),
    ("crop10% 1600 q60",     lambda im, p: jpeg(long_edge(center_crop(im, .10), 1600), p, 60)),
    ("crop25% 1600 q60",     lambda im, p: jpeg(long_edge(center_crop(im, .25), 1600), p, 60)),
]

cover = long_edge(Image.open(SRC).convert("RGB"), 3024)
cover.save(f"{OUT}/cover.png")
print(f"cover {cover.size}", flush=True)

from trustmark import TrustMark
SECRET = "MKP7F3A"   # 7 ASCII chars = 56 bits, fits BCH_5's 61 protected data bits

results = {"cover": list(cover.size), "payload": SECRET}
for strength in (1.0, 0.8):
    tm = TrustMark(verbose=False, model_type="P", device="cpu", loadRemover=False)
    stego_path = f"{OUT}/stego_s{strength}.png"
    t0 = time.time()
    stego = tm.encode(cover, SECRET, WM_STRENGTH=strength)
    enc = time.time()-t0
    stego.save(stego_path)
    stego = stego.convert("RGB")

    # coverage: where did the residual land?
    a = np.asarray(cover, np.int16); b = np.asarray(stego, np.int16)
    diff = np.abs(a - b).sum(axis=2)
    w, h = cover.size
    s = min(w, h)
    left, top = (w - s)//2, (h - s)//2
    outside = diff.copy(); outside[top:top+s, left:left+s] = 0
    inside = diff[top:top+s, left:left+s]
    cov = dict(psnr_full=round(psnr(cover, stego), 2),
               mean_diff_inside=round(float(inside.mean()), 3),
               mean_diff_outside=round(float(outside.mean()), 3),
               pct_pixels_touched=round(float((diff > 0).mean()*100), 1))

    print(f"\n=== P strength {strength} (effective {strength*1.25:.2f})  encode {enc:.1f}s", flush=True)
    print(f"    PSNR {cov['psnr_full']} dB | mean|diff| inside {cov['mean_diff_inside']} outside {cov['mean_diff_outside']} | {cov['pct_pixels_touched']}% pixels touched", flush=True)

    rows = []
    for name, atk in ATTACKS:
        path = f"{OUT}/p{strength}_{abs(hash(name))}.jpg"
        size = atk(stego, path)
        im2 = Image.open(path).convert("RGB")
        t0 = time.time()
        got, present, schema = tm.decode(im2, MODE="text")
        dt = time.time()-t0
        ok = bool(present) and got == SECRET
        rows.append(dict(attack=name, kb=round(size/1024), dims=f"{im2.size[0]}x{im2.size[1]}",
                         decoded=got if present else None, present=bool(present), match=ok,
                         decode_s=round(dt, 2)))
        print(f"  {name:22} {im2.size[0]:>4}x{im2.size[1]:<4} {size/1024:6.0f}KB present={present!s:5} got={got!r:12} {'PASS' if ok else 'FAIL'} {dt:.2f}s", flush=True)

    results[f"P@{strength}"] = dict(encode_s=round(enc, 1), coverage=cov, rows=rows)

json.dump(results, open(f"{OUT}/results.json", "w"), indent=1)
print("\nwrote", f"{OUT}/results.json", flush=True)
