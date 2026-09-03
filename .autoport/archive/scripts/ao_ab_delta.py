#!/usr/bin/env python3
"""Composite A/B region deltas between two x86-floor shot dirs (OFF vs a mode).

Usage: ao_ab_delta.py <off_dir> <mode_dir>
Averages shot1+shot2 per dir, prints per-region mean luminance and the
relative darkening delta (off-mode)/off in % — the crease vs open separation
the owner tunings gate on.
"""
import sys

import numpy as np
from PIL import Image


def region(im, y0, y1, x0, x1):
    h, w = im.shape
    return im[int(h * y0) : int(h * y1), int(w * x0) : int(w * x1)].mean()


REGIONS = {
    "floor": (0.72, 0.90, 0.18, 0.36, 0.64, 0.82),  # two side patches
    "nearfloor": (0.90, 1.00, 0.12, 0.34, 0.66, 0.88),
    "farfloor": (0.60, 0.68, 0.30, 0.70, None, None),
    "cliffbase": (0.48, 0.58, 0.02, 0.14, None, None),
    "wall": (0.10, 0.35, 0.02, 0.18, None, None),
}


def load(d):
    ims = []
    for s in ("shot1", "shot2"):
        ims.append(
            np.asarray(Image.open(f"{d}/{s}.png").convert("L"), dtype=np.float32) / 255.0
        )
    return ims


def means(d):
    out = {}
    for name, (y0, y1, x0, x1, x2, x3) in REGIONS.items():
        vals = []
        for im in load(d):
            v = region(im, y0, y1, x0, x1)
            if x2 is not None:
                v = (v + region(im, y0, y1, x2, x3)) / 2.0
            vals.append(v)
        out[name] = float(np.mean(vals))
    return out


off = means(sys.argv[1])
mode = means(sys.argv[2])
for name in REGIONS:
    o, m = off[name], mode[name]
    delta = 100.0 * (o - m) / max(o, 1e-6)
    print(f"AODELTA {name}: off={o:.3f} mode={m:.3f} delta={delta:+.1f}%")
