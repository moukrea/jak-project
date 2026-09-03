#!/usr/bin/env python3
"""gda_sunoff_analyze.py — objective, albedo-separated proof of sun-OFF ambient FORM.

The owner core gate: with the sun OFF the ambient alone must sculpt relief (faces at different
orientations differ) on the DEFAULT colored render. lit = albedo*base(N) when the sun is off, so the
frame mixes high-freq ALBEDO texture with the low-freq SHADING gradient we care about. We separate them
by frequency: downsample (a low-pass) strips the high-freq albedo texture and keeps the geometry-scale
shading gradient. The spatial std of that low-pass luma over non-sky geometry = the amount of directional
FORM. contrast=0.9 (form) must beat contrast=0 (flat).
"""
import sys, glob, os
import numpy as np
from PIL import Image

ROOT = ".autoport/reports/Grecharged-directional-ambient/device"
DS = 24  # low-pass: downsample factor (strips albedo texture, keeps geometry-scale shading)

def luma(rgb):
    return 0.2126*rgb[...,0] + 0.7152*rgb[...,1] + 0.0722*rgb[...,2]

def load(tag):
    fs = sorted(glob.glob(f"{ROOT}/frames_{tag}/*.png"))
    return fs

def geo_mask(rgb, L):
    # exclude sky (bright + blue-dominant) and pure black background
    sky = (L > 0.5) & (rgb[...,2] >= rgb[...,0])
    blk = L < 0.012
    return ~(sky | blk)

def frame_stats(fp):
    im = Image.open(fp).convert("RGB")
    rgb = np.asarray(im, np.float32)/255.0
    L = luma(rgb)
    m = geo_mask(rgb, L)
    if m.mean() < 0.03:
        return None
    H, W = L.shape
    # low-pass by area-averaging downsample (BILINEAR on a shrunk image)
    small = np.asarray(Image.fromarray((L*255).astype(np.uint8)).resize((max(1,W//DS), max(1,H//DS)), Image.BILINEAR), np.float32)/255.0
    msmall = np.asarray(Image.fromarray((m*255).astype(np.uint8)).resize((max(1,W//DS), max(1,H//DS)), Image.BILINEAR), np.float32)/255.0
    cell = msmall > 0.5
    if cell.sum() < 8:
        return None
    lp = small[cell]
    return dict(
        blur_std=float(lp.std()),                      # low-freq shading spread = FORM
        blur_range=float(np.percentile(lp,95)-np.percentile(lp,5)),
        raw_std=float(L[m].std()),                     # albedo-confounded (reference)
        geo_frac=float(m.mean()),
        bright_mean=float(L[L>0.6].mean()) if (L>0.6).any() else 0.0,
        bright_frac=float((L>0.6).mean()),
    )

def agg(tag):
    fs = load(tag)
    rows = [s for f in fs if (s:=frame_stats(f))]
    if not rows:
        return None
    keys = rows[0].keys()
    out = {k: float(np.mean([r[k] for r in rows])) for k in keys}
    out["n"] = len(rows)
    return out

def show(tag, s):
    if s is None:
        print(f"  {tag:14s}  (no frames / no geometry)"); return
    print(f"  {tag:14s} n={s['n']:2d}  blur_std={s['blur_std']:.4f}  blur_range={s['blur_range']:.4f}  "
          f"raw_std={s['raw_std']:.4f}  geo={s['geo_frac']:.2f}  brightMean={s['bright_mean']:.3f} brightFrac={s['bright_frac']:.3f}")

print("=== SUN-OFF FORM (low-freq shading spread over non-sky geometry; higher = more directional form) ===")
c0 = agg("sunoff_c0"); c9 = agg("sunoff_c9"); sh = agg("sunoff_sh")
show("sunoff_c0", c0); show("sunoff_c9", c9); show("sunoff_sh", sh)
if c0 and c9:
    r = c9['blur_std']/max(c0['blur_std'],1e-6)
    print(f"\n  FORM RATIO (sunoff contrast0.9 / contrast0) blur_std = {r:.2f}x   "
          f"range {c9['blur_range']:.4f} vs {c0['blur_range']:.4f}")
    print(f"  VERDICT: {'PASS — sun-OFF ambient sculpts FORM (contrast lifts low-freq shading spread)' if r>=1.5 else 'WEAK — form gain < 1.5x'}")

print("\n=== GOLDEN RULE (sun ON full; contrast must NOT change SUNLIT brightness) ===")
s0 = agg("sunon_c0"); s9 = agg("sunon_c9")
show("sunon_c0", s0); show("sunon_c9", s9)
if s0 and s9:
    d = abs(s9['bright_mean']-s0['bright_mean'])
    print(f"  sunlit bright-mean delta contrast0.9 vs 0 = {d:.4f}  "
          f"({'PASS — sunlit unchanged (golden rule)' if d<0.02 else 'CHECK'})")
