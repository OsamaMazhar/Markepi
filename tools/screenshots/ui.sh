#!/bin/bash
# ui.sh <udid> [filter] — compact accessibility dump: type 'label' x,y wxh
timeout 90 axe describe-ui --udid "$1" 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
def w(n,dep=0):
    l=n.get('AXLabel') or ''; v=n.get('AXValue') or ''; f=n.get('frame',{})
    if l or v: print('  '*min(dep,6)+f\"{n.get('type')} '{l}' [{v}] {int(f.get('x',0))},{int(f.get('y',0))} {int(f.get('width',0))}x{int(f.get('height',0))}\")
    for c in n.get('children',[]) or []: w(c,dep+1)
for n in d: w(n)
" | grep -i -- "${2:-.}"
