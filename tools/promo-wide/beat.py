import sys,subprocess,numpy as np
f,bpm=sys.argv[1],float(sys.argv[2])
raw=subprocess.check_output(["ffmpeg","-v","error","-i",f,"-ac","1","-ar","22050","-f","f32le","-"])
x=np.frombuffer(raw,dtype=np.float32); sr=22050;hop=256
n=len(x)//hop; e=np.sqrt(np.mean(x[:n*hop].reshape(n,hop)**2,axis=1)); fps=sr/hop
on=np.maximum(0,np.diff(np.log(e+1e-4)))
bp=60/bpm*fps
ps=np.arange(0,bp,0.5)
sc=[on[np.round(np.arange(p,len(on)-1,bp)).astype(int)].sum() for p in ps]
print('phase s',round(ps[int(np.argmax(sc))]/fps,3),'strength',round(max(sc)/np.mean(sc),2))
print(' '.join(f"{s}:{e[int(s*fps):int((s+2)*fps)].mean():.3f}" for s in range(0,30,2)))
