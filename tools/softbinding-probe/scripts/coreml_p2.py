"""Round 2: fp16 decoder (shipping size) + encoder via the inner module."""
import os, time, json
import numpy as np, torch
import coremltools as ct
from PIL import Image
from trustmark import TrustMark

OUT = "/tmp/coremlP"
os.makedirs(OUT, exist_ok=True)
res = json.load(open(f"{OUT}/conversion.json"))

tm = TrustMark(verbose=False, model_type="P", device="cpu", loadRemover=False)
secret = torch.from_numpy(tm.ecc.encode_text(["MKP7F3A"])).float().unsqueeze(0)

def size_of(p):
    if os.path.isdir(p):
        return round(sum(os.path.getsize(os.path.join(dp, fn)) for dp, _, fns in os.walk(p) for fn in fns)/1e6, 1)
    return round(os.path.getsize(p)/1e6, 1)

# ---- decoder, fp16 ----
dec = tm.decoder.decoder.eval()
sample = torch.randn(1, 3, 224, 224)
with torch.no_grad():
    ref = dec(sample)
tr = torch.jit.trace(dec, sample)
ml = ct.convert(tr, inputs=[ct.TensorType(name="image", shape=(1, 3, 224, 224))],
                minimum_deployment_target=ct.target.iOS18, convert_to="mlprogram",
                compute_precision=ct.precision.FLOAT16)
ml.save(f"{OUT}/decoder_P_fp16.mlpackage")
o = ml.predict({"image": sample.numpy()})
cm = torch.from_numpy(np.asarray(list(o.values())[0]))
res["decoder_fp16"] = dict(size_mb=size_of(f"{OUT}/decoder_P_fp16.mlpackage"),
                           sign_agreement=float(((cm > 0) == (ref > 0)).float().mean()),
                           max_abs_diff=float((cm - ref).abs().max()))
print("decoder fp16:", res["decoder_fp16"], flush=True)

# ---- encoder via inner module ----
enc = tm.encoder.encoder.eval()
cover = Image.open("/tmp/wmrunP/cover.png").convert("RGB").resize((256, 256), Image.BILINEAR)
x = (torch.from_numpy(np.asarray(cover).astype(np.float32)/255.).permute(2, 0, 1).unsqueeze(0)*2-1)
with torch.no_grad():
    ref_e = enc(x, secret)
ref_e = ref_e[0] if isinstance(ref_e, (tuple, list)) else ref_e
print("torch encoder out", tuple(ref_e.shape), flush=True)
try:
    tr_e = torch.jit.trace(enc, (x, secret))
    ml_e = ct.convert(tr_e, inputs=[ct.TensorType(name="image", shape=(1, 3, 256, 256)),
                                    ct.TensorType(name="secret", shape=(1, 100))],
                      minimum_deployment_target=ct.target.iOS18, convert_to="mlprogram")
    ml_e.save(f"{OUT}/encoder_P.mlpackage")
    o = ml_e.predict({"image": x.numpy(), "secret": secret.numpy()})
    cm = torch.from_numpy(np.asarray(list(o.values())[0]))
    res["encoder"] = dict(ok=True, size_mb=size_of(f"{OUT}/encoder_P.mlpackage"),
                          coreml_shape=list(cm.shape),
                          max_abs_diff=float((cm - ref_e).abs().max()),
                          corr=float(np.corrcoef(cm.flatten().numpy(), ref_e.flatten().numpy())[0, 1]))
    print("encoder:", res["encoder"], flush=True)
except Exception as e:
    res["encoder"] = dict(ok=False, error=f"{type(e).__name__}: {e}")
    print("encoder FAILED:", e, flush=True)

json.dump(res, open(f"{OUT}/conversion.json", "w"), indent=1)
print("done", flush=True)
