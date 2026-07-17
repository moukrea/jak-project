#!/usr/bin/env python3
"""Vantage-agnostic composite A/B metrics between two x86-floor shot dirs.

Usage: ao_ab_quick.py <off_dir> <mode_dir>
Aligns shot1 of each (same warp pose), prints:
  global_delta   — mean luminance drop over the whole frame (wash indicator, want small)
  p95_darkening  — 95th percentile per-pixel darkening (visibility indicator, want big)
  frac_gt5       — fraction of pixels darkened >5% (localization: creases only => small
                   but nonzero; a wash => large)
Uses shot1+shot2 averaged per dir. Values in percent of full scale.
"""
import sys

import numpy as np
from PIL import Image


def load(d):
    ims = []
    for s in ("shot1", "shot2"):
        ims.append(np.asarray(Image.open(f"{d}/{s}.png").convert("L"), dtype=np.float32) / 255.0)
    a = np.mean(ims, axis=0)
    return a


off = load(sys.argv[1])
mode = load(sys.argv[2])
if off.shape != mode.shape:
    print("SHAPE MISMATCH", off.shape, mode.shape)
    sys.exit(1)
dark = off - mode  # positive = darkened by AO
print(
    f"AOQUICK global_delta={100*dark.mean():+.2f}% p95_darkening={100*np.percentile(dark,95):+.2f}% "
    f"frac_gt5={100*(dark>0.05).mean():.1f}% frac_gt10={100*(dark>0.10).mean():.1f}%"
)
