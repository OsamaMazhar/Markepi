# lumakey.py in.png out.png — white-on-black art → pure white with luminance as alpha, cropped to content
import sys, numpy as np
from PIL import Image
src=Image.open(sys.argv[1]).convert('RGBA'); bg=Image.new('RGBA',src.size,(0,0,0,255)); bg.alpha_composite(src); im=np.asarray(bg.convert('RGB')).astype(float)
a=im.max(axis=2); a=np.clip((a-25)/(230-25),0,1)*255
out=np.zeros(im.shape[:2]+(4,),np.uint8); out[...,:3]=255; out[...,3]=a.astype(np.uint8)
ys,xs=np.where(a>8); pad=8
Image.fromarray(out[max(ys.min()-pad,0):ys.max()+pad, max(xs.min()-pad,0):xs.max()+pad]).save(sys.argv[2])
