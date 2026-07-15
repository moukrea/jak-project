#!/usr/bin/env python3
"""ao_analyze_ab.py — Grecharged-ambient-occlusion A/B evidence analysis.

For one vantage, compares the OFF capture against each AO mode capture taken at the
IDENTICAL warped pose (static camera, neutral pad):
  * averages all frames of each capture (kills screenrecord compression noise),
  * diff map = OFF_mean - MODE_mean (positive = MODE darker, i.e. real occlusion),
  * reports: mean darkening, darkened-pixel fraction (>4/255), 99th-percentile
    darkening, and a LOCALIZATION ratio (mean darkening inside the darkest decile
    of pixels vs global mean) — uniform noise/exposure drift gives ratio ~<3,
    real crease/contact AO concentrates and gives a much higher ratio,
  * pairwise mode-vs-mode mean |diff| (are SSAO/HBAO/GTAO mutually distinct?),
  * writes a per-mode diff heat PNG next to the frames for human eyeballing.

Usage: ao_analyze_ab.py <device_dir> <vantage>   (expects device-ao-<vantage>-<tag>_frames/)
"""
import sys
import os
import glob
import numpy as np
from PIL import Image

dev_dir, vant = sys.argv[1], sys.argv[2]
MODES = ["off", "ssao", "hbao", "gtao"]


def mean_frames(tag):
    pat = os.path.join(dev_dir, f"device-ao-{vant}-{tag}_frames", "f_*.png")
    files = sorted(glob.glob(pat))
    if not files:
        return None, 0
    # skip the first frame (recording ramp) when there are enough
    if len(files) > 3:
        files = files[1:]
    acc = None
    for f in files:
        a = np.asarray(Image.open(f).convert("L"), dtype=np.float64)
        acc = a if acc is None else acc + a
    return acc / len(files), len(files)


means = {}
for m in MODES:
    img, n = mean_frames(m)
    if img is None:
        print(f"[ao-analyze] {vant}/{m}: NO FRAMES")
        sys.exit(1)
    means[m] = img
    print(f"[ao-analyze] {vant}/{m}: {n} frames averaged, mean_luma={img.mean():.2f}")

off = means["off"]
print()
for m in MODES[1:]:
    d = off - means[m]  # positive where the AO mode is darker
    dark = np.clip(d, 0, None)
    frac = float((dark > 4.0).mean())
    p99 = float(np.percentile(dark, 99))
    gmean = float(dark.mean())
    # localization: mean darkening within the top-decile darkened pixels vs global mean
    thresh = np.percentile(dark, 90)
    loc = float(dark[dark >= thresh].mean() / gmean) if gmean > 1e-6 else 0.0
    print(f"[ao-analyze] {vant} OFF-vs-{m.upper()}: mean_darkening={gmean:.3f} "
          f"darkened_frac(>4)={frac*100:.2f}% p99={p99:.1f} localization_ratio={loc:.1f}")
    heat = np.clip(dark * 8.0, 0, 255).astype(np.uint8)
    out = os.path.join(dev_dir, f"ao-diffheat-{vant}-{m}.png")
    Image.fromarray(heat).save(out)
    print(f"             heatmap -> {out}")

print()
for i in range(1, len(MODES)):
    for j in range(i + 1, len(MODES)):
        a, b = MODES[i], MODES[j]
        d = float(np.abs(means[a] - means[b]).mean())
        print(f"[ao-analyze] {vant} {a.upper()}-vs-{b.upper()}: mean_absdiff={d:.3f}")
