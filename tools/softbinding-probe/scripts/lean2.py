"""Memory-lean but numerically exact TrustMark-P embedder (strip-streamed bilinear),
mimicking what an iOS implementation should do: no full-frame float buffers."""
import resource, time, os, gc
import numpy as np, torch
from PIL import Image
from trustmark import TrustMark

def rss(): return round(resource.getrusage(resource.RUSAGE_SELF).ru_maxrss/1e6, 1)

def _idx(n_out, n_src):
    s = (np.arange(n_out) + 0.5) * (n_src / n_out) - 0.5
    i0 = np.floor(s).astype(np.int32)
    f = (s - i0).astype(np.float32)
    np.clip(i0, 0, n_src - 1, out=i0)
    i1 = np.clip(i0 + 1, 0, n_src - 1)
    return i0, i1, f

def lean_encode(tm, secret, cover_pil, eff_strength=1.25, strip=256):
    W, H = cover_pil.size
    side = min(W, H); left, top = (W - side)//2, (H - side)//2
    small = cover_pil.crop((left, top, left + side, top + side)).resize((256, 256), Image.BILINEAR)
    x = (torch.from_numpy(np.asarray(small).astype(np.float32)/255.)
         .permute(2, 0, 1).unsqueeze(0)*2 - 1)
    with torch.no_grad():
        st, _ = tm.encoder(x, secret)
    res = st.clamp(-1, 1) - x
    res = res - res.mean(dim=(2, 3), keepdim=True)
    r = res[0].numpy().astype(np.float32)          # (3,256,256)

    x0, x1, fx = _idx(side, 256)
    out = np.array(cover_pil, dtype=np.uint8)
    for y0 in range(0, side, strip):
        n = min(strip, side - y0)
        # strip-local vertical source coords, computed in GLOBAL output space
        ys = (np.arange(y0, y0 + n) + 0.5) * (256.0 / side) - 0.5
        iy0 = np.floor(ys).astype(np.int32); fy = (ys - iy0).astype(np.float32)
        np.clip(iy0, 0, 255, out=iy0); iy1 = np.clip(iy0 + 1, 0, 255)
        v = r[:, iy0, :] * (1 - fy)[None, :, None] + r[:, iy1, :] * fy[None, :, None]
        h = v[:, :, x0] * (1 - fx)[None, None, :] + v[:, :, x1] * fx[None, None, :]
        block = h.transpose(1, 2, 0)
        reg = out[top + y0:top + y0 + n, left:left + side].astype(np.float32)
        reg += block * (eff_strength * 127.5)
        out[top + y0:top + y0 + n, left:left + side] = np.clip(reg, 0, 255).astype(np.uint8)
        del v, h, block, reg
    return Image.fromarray(out)

if __name__ == "__main__":
    tm = TrustMark(verbose=False, model_type="P", device="cpu", loadRemover=False)
    secret = torch.from_numpy(tm.ecc.encode_text(["MKP7F3A"])).float().unsqueeze(0)
    src = Image.open("/tmp/refimage-sample/IMG_0104.jpeg").convert("RGB")
    print(f"baseline {rss()} MB", flush=True)

    for label, (W, H) in [("12MP (4032x3024)", (4032, 3024)),
                          ("24MP (6048x4032)", (6048, 4032)),
                          ("48MP (8064x6048)", (8064, 6048))]:
        gc.collect()
        cover = src.resize((W, H), Image.LANCZOS); gc.collect()
        base = rss(); t0 = time.time()
        out = lean_encode(tm, secret, cover)
        dt = time.time() - t0; peak = rss()
        f = f"/tmp/wmlarge/lean2_{W}.jpg"; out.save(f, "JPEG", quality=95)
        # parity vs the reference implementation (on a 3MP proxy of the same content)
        direct = tm.decode(out, MODE="text")
        im = Image.open(f).convert("RGB"); w, h = im.size; s = 1600/max(w, h)
        wa = im.resize((round(w*s), round(h*s)), Image.LANCZOS)
        waf = f"/tmp/wmlarge/lean2_wa_{W}.jpg"; wa.save(waf, "JPEG", quality=60)
        got, present, _ = tm.decode(Image.open(waf).convert("RGB"), MODE="text")
        print(f"{label:18} encode {dt:4.1f}s peak {peak:7.1f} MB (+{peak-base:.0f}) "
              f"file {os.path.getsize(f)/1e6:5.1f}MB  direct={'PASS' if direct[1] else 'FAIL'}  "
              f"wa={'PASS' if present and got == 'MKP7F3A' else 'FAIL'}", flush=True)
        del cover, out, im, wa; gc.collect()
