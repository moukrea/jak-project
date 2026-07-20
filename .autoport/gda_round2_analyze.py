#!/usr/bin/env python3
# gda_round2_analyze.py — objective backing for the ROUND-2 device A/Bs.
#  * crease A/B (debug-2 world-normal viz): local incoherence of the normal field. The round-1
#    unconditional weld smears normals across hard block edges -> more high-frequency local variance
#    that does NOT correspond to real geometry edges (random patches). The crease fix keeps blocks
#    internally coherent (low local variance) with crisp steps at true edges.
#  * form A/B (debug-12 light fraction): spread of the light-fraction over the frame. The flat ~0.2
#    floor collapses shadowed faces to ONE value (a spike); the normal-varying ambient base spreads
#    them (form). We report the std and the fraction of pixels in the darkest occupied 0.02-wide bin.
import sys, glob, os
import numpy as np
from PIL import Image

def load_mid(tag, kind="mid"):
    d = f".autoport/reports/Grecharged-directional-ambient/device/frames_{tag}"
    fs = sorted(glob.glob(f"{d}/*.png"))
    if not fs:
        return None, None
    # pick a middle frame (settled, mid look-around)
    f = fs[len(fs)//2]
    return np.asarray(Image.open(f).convert("RGB"), dtype=np.float32)/255.0, f

def local_var(gray, win=7):
    # mean local variance via box filter (separable), a cheap high-frequency-energy proxy
    from numpy.lib.stride_tricks import sliding_window_view
    H,W = gray.shape
    if H<win or W<win: return float("nan")
    sw = sliding_window_view(gray, (win,win))
    return float(sw.var(axis=(-1,-2)).mean())

def crease_ab():
    print("== CREASE A/B (debug-2 world-normal viz; higher local-var = more smeared/incoherent) ==")
    for tag in ("crease_fix_stone_nrm","crease_weld_stone_nrm"):
        img,f = load_mid(tag)
        if img is None: print(f"  {tag}: NO FRAMES"); continue
        g = img.mean(axis=2)
        print(f"  {tag}: local_var(7x7)={local_var(g):.5f}  distinct_norm_dirs={distinct_dirs(img)}  ({os.path.basename(f)})")
    print("  (fix should show LOWER whole-frame local-var noise + crisper edges; eyeball is primary)")

def distinct_dirs(img, q=12):
    # quantize normal-viz colors; count distinct buckets (a proxy for how many normal directions appear)
    qi = np.floor(img*q).astype(np.int32)
    keys = qi[...,0]*q*q + qi[...,1]*q + qi[...,2]
    return int(np.unique(keys).size)

def form_ab():
    print("== FORM A/B (debug-12 light fraction; base=spread/form, flat=spike) ==")
    for tag in ("form_base_dbg12","form_flat_dbg12"):
        img,f = load_mid(tag)
        if img is None: print(f"  {tag}: NO FRAMES"); continue
        g = img.mean(axis=2)
        # focus on the darker (shadowed) half where the ambient base is the only light
        sh = g[g < 0.5]
        if sh.size < 100:
            print(f"  {tag}: too few shadow px"); continue
        hist,edges = np.histogram(sh, bins=np.arange(0,0.5001,0.02))
        peak = hist.max()/sh.size
        print(f"  {tag}: shadow_px={sh.size} std={sh.std():.4f} range=[{sh.min():.3f},{sh.max():.3f}] "
              f"peak_bin_frac={peak:.3f}  ({os.path.basename(f)})")
    print("  (base should show HIGHER std + LOWER peak_bin_frac = faces spread by normal = form)")

if __name__ == "__main__":
    crease_ab()
    form_ab()
