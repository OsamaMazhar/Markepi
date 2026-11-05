"""Does TrustMark P scale to 48 MP / 100 MP images?  Measures runtime, peak RSS,
output size, and whether the payload still decodes after a WhatsApp-style pass."""
import os, time, resource, gc, json
import numpy as np
from PIL import Image
from trustmark import TrustMark

OUT = "/tmp/wmlarge"; os.makedirs(OUT, exist_ok=True)
SRC = "/tmp/refimage-sample/IMG_0104.jpeg"
SECRET = "MKP7F3A"

def rss_mb():
    # macOS: ru_maxrss is bytes
    return round(resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / 1e6, 1)

def reset_peak():
    # there is no portable reset; track deltas from a baseline instead
    return rss_mb()

def long_edge(im, px):
    w, h = im.size; s = px/max(w, h)
    return im if s >= 1 else im.resize((round(w*s), round(h*s)), Image.LANCZOS)

base = Image.open(SRC).convert("RGB")
tm = TrustMark(verbose=False, model_type="P", device="cpu", loadRemover=False)
print(f"baseline RSS {rss_mb()} MB", flush=True)

results = []
for label, (W, H) in [("24MP (6048x4032)", (6048, 4032)),
                      ("48MP (8064x6048)", (8064, 6048)),
                      ("100MP (12288x8192)", (12288, 8192))]:
    gc.collect()
    before = rss_mb()
    big = base.resize((W, H), Image.LANCZOS)
    t0 = time.time()
    stego = tm.encode(big, SECRET, WM_STRENGTH=0.8)
    enc = time.time() - t0
    after_enc = rss_mb()
    out_jpg = f"{OUT}/stego_{W}x{H}.jpg"
    stego.save(out_jpg, "JPEG", quality=95)
    mb = os.path.getsize(out_jpg)/1e6

    # whatsapp-style pass + decode from the full-size file
    t0 = time.time()
    wa = long_edge(Image.open(out_jpg).convert("RGB"), 1600)
    wa.save(f"{OUT}/wa_{W}x{H}.jpg", "JPEG", quality=60)
    got, present, schema = tm.decode(Image.open(f"{OUT}/wa_{W}x{H}.jpg").convert("RGB"), MODE="text")
    dec = time.time() - t0

    row = dict(label=label, encode_s=round(enc, 1), decode_s=round(dec, 1),
               rss_before=before, rss_after_encode=after_enc, rss_peak=rss_mb(),
               stego_jpg_mb=round(mb, 1), wa_kb=round(os.path.getsize(f"{OUT}/wa_{W}x{H}.jpg")/1024),
               decoded=got, match=bool(present and got == SECRET))
    print(row, flush=True)
    results.append(row)
    del big, stego; gc.collect()

json.dump(results, open(f"{OUT}/large.json", "w"), indent=1)
print("done", flush=True)
