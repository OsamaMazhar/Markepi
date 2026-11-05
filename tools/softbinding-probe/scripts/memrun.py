import sys, resource, gc, time
import numpy as np, torch
from PIL import Image
sys.path.insert(0,'/tmp'); from lean2 import lean_encode
from trustmark import TrustMark
W,H=map(int,sys.argv[1].split('x'))
tm=TrustMark(verbose=False, model_type="P", device="cpu", loadRemover=False)
secret=torch.from_numpy(tm.ecc.encode_text(["MKP7F3A"])).float().unsqueeze(0)
src=Image.open("/tmp/refimage-sample/IMG_0104.jpeg").convert("RGB").resize((W,H), Image.LANCZOS)
gc.collect()
def rss(): return resource.getrusage(resource.RUSAGE_SELF).ru_maxrss/1e6
base=rss(); t0=time.time(); out=lean_encode(tm, secret, src); dt=time.time()-t0
print(f"{W}x{H}: encode {dt:.2f}s  peak {rss():.0f} MB  (baseline torch-loaded {base:.0f} MB, delta {rss()-base:.0f} MB)")
