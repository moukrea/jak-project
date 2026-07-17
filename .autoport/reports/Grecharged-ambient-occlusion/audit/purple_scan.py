import os, glob, numpy as np
from PIL import Image
frames = sorted(glob.glob(os.path.join(os.path.dirname(__file__),'frames','f_*.png')))
print("total frames:", len(frames))
flagged=[]
rows=[]
for fp in frames:
    im = Image.open(fp).convert('RGB')
    a = np.asarray(im).astype(np.int32)
    R,G,B = a[...,0],a[...,1],a[...,2]
    # purple/magenta untextured: R>100, B>100, G < 0.6*min(R,B)
    minRB = np.minimum(R,B)
    mask = (R>100)&(B>100)&(G < 0.6*minRB)
    frac = mask.mean()
    n=os.path.basename(fp)
    rows.append((n,frac))
    if frac>0.03: flagged.append((n,frac))
for n,frac in rows:
    print(f"{n} purple_frac={frac*100:.2f}%")
print("=== FLAGGED (>3%) ===")
if flagged:
    for n,frac in flagged: print(f"{n} {frac*100:.2f}%")
else:
    print("NONE")
fr=[f for _,f in rows]
print(f"=== max={max(fr)*100:.2f}% mean={np.mean(fr)*100:.3f}% ===")
