import os, sys; sys.path.insert(0,'image'); import krea_m5 as k
HERE = os.path.dirname(os.path.abspath(__file__))
for line in open(os.path.join(HERE,'prompts.txt')):
    n,p=line.strip().split('|',1)
    k.generate(p, os.path.join(HERE,'bg'+n+'.jpg'), size=(768,1664), seed=int(n)*7)
    print('done',n,flush=True)
