"""Can TrustMark P be converted to CoreML (and therefore run on iOS 18)?
No MLX port exists upstream, so we test the practical native path instead:
PyTorch -> TorchScript -> CoreML, then compare outputs numerically.
"""
import os, time, json
import numpy as np, torch
import coremltools as ct
from PIL import Image

OUT = "/tmp/coremlP"
os.makedirs(OUT, exist_ok=True)

from trustmark import TrustMark
tm = TrustMark(verbose=False, model_type="P", device="cpu", loadRemover=False)
print("models loaded", flush=True)

sec = tm.ecc.encode_text(["MKP7F3A9"])
secret = torch.from_numpy(sec).float()
print("secret tensor", secret.shape, flush=True)

cover = Image.open("/tmp/wmrunP/cover.png").convert("RGB").resize((256, 256), Image.BILINEAR)
x = (torch.from_numpy(np.asarray(cover).astype(np.float32) / 255.0)
     .permute(2, 0, 1).unsqueeze(0) * 2 - 1)

# ---------- decoder ----------
dec = tm.decoder.decoder.eval()
sample = torch.randn(1, 3, 224, 224)
with torch.no_grad():
    ref_dec = dec(sample)
print("torch decoder out", tuple(ref_dec.shape), flush=True)

t0 = time.time()
tr_dec = torch.jit.trace(dec, sample)
print(f"traced decoder in {time.time()-t0:.1f}s", flush=True)
res = {}
try:
    ml_dec = ct.convert(
        tr_dec, inputs=[ct.TensorType(name="image", shape=(1, 3, 224, 224))],
        minimum_deployment_target=ct.target.iOS18, convert_to="mlprogram",
    )
    ml_dec.save(f"{OUT}/decoder_P.mlpackage")
    print("converted decoder_P.mlpackage", flush=True)
    spec_out = ml_dec.predict({"image": sample.numpy()})
    k = list(spec_out.keys())[0]
    cm = torch.from_numpy(np.asarray(spec_out[k]))
    res["decoder"] = dict(ok=True, torch_shape=list(ref_dec.shape), coreml_shape=list(cm.shape),
                          max_abs_diff=float((cm - ref_dec).abs().max()),
                          sign_agreement=float(((cm > 0) == (ref_dec > 0)).float().mean()))
    print("decoder parity:", res["decoder"], flush=True)
except Exception as e:
    res["decoder"] = dict(ok=False, error=f"{type(e).__name__}: {e}")
    print("decoder conversion FAILED:", e, flush=True)

# ---------- encoder ----------
enc = tm.encoder.eval()
with torch.no_grad():
    ref_enc, _ = enc(x, secret.unsqueeze(0))
print("torch encoder out", tuple(ref_enc.shape), flush=True)
try:
    tr_enc = torch.jit.trace(enc, (x, secret.unsqueeze(0)))
    ml_enc = ct.convert(
        tr_enc,
        inputs=[ct.TensorType(name="image", shape=(1, 3, 256, 256)),
                ct.TensorType(name="secret", shape=(1, int(secret.shape[0])))],
        minimum_deployment_target=ct.target.iOS18, convert_to="mlprogram",
    )
    ml_enc.save(f"{OUT}/encoder_P.mlpackage")
    print("converted encoder_P.mlpackage", flush=True)
    o = ml_enc.predict({"image": x.numpy(), "secret": secret.unsqueeze(0).numpy()})
    cm = torch.from_numpy(np.asarray(list(o.values())[0]))
    res["encoder"] = dict(ok=True, torch_shape=list(ref_enc.shape), coreml_shape=list(cm.shape),
                          max_abs_diff=float((cm - ref_enc).abs().max()))
    print("encoder parity:", res["encoder"], flush=True)
except Exception as e:
    res["encoder"] = dict(ok=False, error=f"{type(e).__name__}: {e}")
    print("encoder conversion FAILED:", e, flush=True)

json.dump(res, open(f"{OUT}/conversion.json", "w"), indent=1)
for f in sorted(os.listdir(OUT)):
    p = os.path.join(OUT, f)
    if os.path.isdir(p):
        sz = sum(os.path.getsize(os.path.join(dp, fn)) for dp, _, fns in os.walk(p) for fn in fns)
        print(f"{f}: {sz/1e6:.1f} MB")
print("done", flush=True)
