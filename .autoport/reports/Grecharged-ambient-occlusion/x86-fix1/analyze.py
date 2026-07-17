import numpy as np, glob, os
from PIL import Image
D=os.path.dirname(os.path.abspath(__file__))
def lum(a):  # a: HxWx3 float
    return 0.2126*a[...,0]+0.7152*a[...,1]+0.0722*a[...,2]
def stats(path):
    im=Image.open(path).convert('RGB')
    a=np.asarray(im,dtype=np.float32)
    L=lum(a)
    H=L.shape[0]
    sky=L[:H//4]
    L8=L/255.0; s8=sky/255.0
    frac_gt200=(L>200).mean()
    frac_lt64 =(L<64).mean()
    # magenta: R>200 B>200 G<60
    mag=((a[...,0]>200)&(a[...,2]>200)&(a[...,1]<60)).mean()
    return dict(mean=L.mean(), skymean=sky.mean(),
                gt200=frac_gt200, lt64=frac_lt64, mag=mag)
groups=['mode0','mode1','mode2','mode3','mode1dbg1','mode2dbg1','mode3dbg1','mode3q0','mode3q0dbg1']
print(f"{'config':11s} {'shot':6s} {'mean':>7s} {'skyM':>7s} {'>200%':>7s} {'<64%':>7s} {'mag%':>8s}")
agg={}
for g in groups:
    fs=sorted(glob.glob(f"{D}/{g}-shot*.png"))
    ms=[];sm=[];gt=[];lt=[];mg=[]
    for f in fs:
        s=stats(f); ms.append(s['mean']);sm.append(s['skymean']);gt.append(s['gt200']);lt.append(s['lt64']);mg.append(s['mag'])
        print(f"{g:11s} {os.path.basename(f).split('-')[-1].replace('.png',''):6s} {s['mean']:7.1f} {s['skymean']:7.1f} {100*s['gt200']:7.2f} {100*s['lt64']:7.2f} {100*s['mag']:8.4f}")
    agg[g]=dict(mean=np.mean(ms),sky=np.mean(sm),gt200=np.mean(gt),lt64=np.mean(lt),mag=np.mean(mg))
print("\n=== AVG per config ===")
for g in groups:
    a=agg[g]; print(f"{g:11s} mean={a['mean']:6.1f} sky={a['sky']:6.1f} >200%={100*a['gt200']:6.2f} <64%={100*a['lt64']:6.2f} mag%={100*a['mag']:.4f}")
# darkening delta mode1 vs mode0 (normal views)
b=agg['mode0']['mean']
for g in ['mode1','mode2','mode3','mode3q0']:
    if g in agg:
        m=agg[g]['mean']
        print(f"Global-darkening {g} vs mode0: {b:.1f} -> {m:.1f} delta={100*(b-m)/b:+.2f}% (positive = darker)")
