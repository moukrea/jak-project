#!/usr/bin/env python3
# glp_measure.py — Grecharged-lightprobes A/B frame measure.
# For each frame dir, compute the WORLD-crop (center, HUD/letterbox excluded) mean luma + per-channel
# RGB, averaged over the middle frames (skip the first/last few = load/fade). Prints one line per dir.
# Usage: glp_measure.py <framedir1> <framedir2> ...
import sys, os, glob
import numpy as np
from PIL import Image

def measure(d):
    fs = sorted(glob.glob(os.path.join(d, "*.png")))
    if not fs:
        return None
    # middle frames (drop first/last 20%) = steady, post-load
    n = len(fs)
    lo, hi = int(n * 0.35), max(int(n * 0.35) + 1, int(n * 0.85))
    fs = fs[lo:hi] if hi > lo else fs
    accL, accR, accG, accB, cnt = 0.0, 0.0, 0.0, 0.0, 0
    for f in fs:
        im = np.asarray(Image.open(f).convert("RGB")).astype(np.float64)
        h, w, _ = im.shape
        # center world crop: middle 60% width, 25%..75% height (excludes top sky glare + bottom HUD)
        y0, y1 = int(h * 0.25), int(h * 0.75)
        x0, x1 = int(w * 0.20), int(w * 0.80)
        c = im[y0:y1, x0:x1, :]
        r, g, b = c[..., 0].mean(), c[..., 1].mean(), c[..., 2].mean()
        lum = 0.299 * r + 0.587 * g + 0.114 * b
        accL += lum; accR += r; accG += g; accB += b; cnt += 1
    if cnt == 0:
        return None
    return dict(n=cnt, lum=accL / cnt, r=accR / cnt, g=accG / cnt, b=accB / cnt)

for d in sys.argv[1:]:
    m = measure(d)
    tag = os.path.basename(d.rstrip("/"))
    if m is None:
        print(f"{tag:28s}  NO FRAMES")
    else:
        print(f"{tag:28s}  frames={m['n']:3d}  luma={m['lum']:7.3f}  "
              f"R={m['r']:6.2f} G={m['g']:6.2f} B={m['b']:6.2f}")
