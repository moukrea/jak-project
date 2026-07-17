#!/usr/bin/env python3
"""Grecharged-ambient-occlusion floor-wash triage metrics.

Measures mean grey level of fixed screen regions on an AO debug-view (term) or
composite screenshot at the TRAINING spawn vantage (OG_LEVEL_WARP training-start
-1187.4 16.2 932.3, follow-cam at spawn). Jak stands center-frame (~40-60% width),
so floor patches are split LEFT/RIGHT of him.
  floor    — open flat ground, mean of two side patches flanking Jak (wash zone)
  nearfloor— bottom side strips closest to camera (least grazing at this cam)
  farfloor — floor band just below the cliff bases (most grazing)
  cliffbase— base-of-cliff contact band, left (true contact AO must survive here)
  wall     — upper-left cliff face (non-grazing, ~white in term)
  sky      — top-center (must be 1.0 in term views)
Usage: ao_floor_metrics.py <png> [<png>...]
"""
import sys

import numpy as np
from PIL import Image


def region(im, y0, y1, x0, x1):
    h, w = im.shape
    return im[int(h * y0) : int(h * y1), int(w * x0) : int(w * x1)]


for path in sys.argv[1:]:
    im = np.asarray(Image.open(path).convert("L"), dtype=np.float32) / 255.0
    floor_l = region(im, 0.72, 0.90, 0.18, 0.36)
    floor_r = region(im, 0.72, 0.90, 0.64, 0.82)
    near_l = region(im, 0.90, 1.00, 0.12, 0.34)
    near_r = region(im, 0.90, 1.00, 0.66, 0.88)
    farfloor = region(im, 0.60, 0.68, 0.30, 0.70)
    cliffbase = region(im, 0.48, 0.58, 0.02, 0.14)
    wall = region(im, 0.10, 0.35, 0.02, 0.18)
    sky = region(im, 0.0, 0.06, 0.40, 0.60)
    name = path.split("/")[-2] + "/" + path.split("/")[-1]
    fl = (floor_l.mean() + floor_r.mean()) / 2.0
    nf = (near_l.mean() + near_r.mean()) / 2.0
    print(
        f"AOFLOOR {name} floor={fl:.3f} nearfloor={nf:.3f} farfloor={farfloor.mean():.3f} "
        f"cliffbase={cliffbase.mean():.3f} wall={wall.mean():.3f} sky={sky.mean():.3f}"
    )
