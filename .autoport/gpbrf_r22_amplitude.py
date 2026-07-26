#!/usr/bin/env python3
"""gpbrf_r22_amplitude.py — ROUND 22 DEFECT B: is the relief slider audible?

Mean absolute per-pixel LUMA difference (0-255) between two device stills of the SAME
vantage, plus the share of pixels moving more than a threshold.  A pair captured with an
IDENTICAL configuration is the NOISE FLOOR: without it a "1.8/255 delta" is unfalsifiable,
because the water, the idle actors, the foliage and the H.264 round-trip all move pixels
with the settings held still.

--mask <mode-30 program-tag frame> --classes a,b,c restricts every statistic to the pixels
that program-tag frame assigns to those programs, which is how you separate "the slider
moved the displaced surfaces" from "the sea moved".

Usage:
  gpbrf_r22_amplitude.py [--mask prog.png --classes tfrag3_tess,tfrag3] LABEL a.png b.png ...
"""
import argparse
import sys

import numpy as np
from PIL import Image

W = np.array([0.299, 0.587, 0.114], dtype=np.float32)

# Must stay identical to gpbrf_r22_coverage.py's table.
TAGS = [
    ("tfrag3_tess", (255, 255, 0)),
    ("tfrag3", (255, 0, 0)),
    ("etie_base", (0, 255, 0)),
    ("tie_wind", (0, 255, 255)),
    ("shrub", (0, 0, 255)),
    ("hfrag", (255, 128, 0)),
    ("merc2", (255, 0, 255)),
    ("generic", (128, 0, 255)),
    ("emerc", (128, 255, 0)),
]


def luma(p):
    return (np.asarray(Image.open(p).convert("RGB"), dtype=np.float32) * W).sum(axis=2)


def build_mask(path, classes, tol=48.0):
    a = np.asarray(Image.open(path).convert("RGB"), dtype=np.float32)
    h, w, _ = a.shape
    flat = a.reshape(-1, 3)
    ref = np.array([t[1] for t in TAGS], dtype=np.float32)
    d = np.linalg.norm(flat[:, None, :] - ref[None, :, :], axis=2)
    best = np.argmin(d, axis=1)
    bd = d[np.arange(flat.shape[0]), best]
    lab = np.where(bd <= tol, best, -1).reshape(h, w)
    want = [i for i, t in enumerate(TAGS) if t[0] in classes]
    m = np.zeros(lab.shape, dtype=bool)
    for i in want:
        m |= lab == i
    return m


def main():
    ap = argparse.ArgumentParser(add_help=False)
    ap.add_argument("--mask")
    ap.add_argument("--classes", default="tfrag3_tess,tfrag3")
    ap.add_argument("rest", nargs="*")
    args = ap.parse_args()
    rest = args.rest
    if not rest or len(rest) % 3:
        sys.exit(__doc__)

    mask = None
    if args.mask:
        cls = [c.strip() for c in args.classes.split(",") if c.strip()]
        mask = build_mask(args.mask, cls)
        print(f"MASK {args.mask} classes={cls} -> {int(mask.sum())} px "
              f"({100.0*mask.mean():.2f}% of frame)")
    print(f"{'pair':<24} {'mean|dL|':>9} {'p50':>7} {'p95':>7} {'max':>6} "
          f"{'%>4/255':>9} {'%>8/255':>9} {'pixels':>10}")
    print("-" * 88)
    for i in range(0, len(rest), 3):
        label, pa, pb = rest[i], rest[i + 1], rest[i + 2]
        a, b = luma(pa), luma(pb)
        if a.shape != b.shape:
            print(f"{label:<24} SIZE MISMATCH {a.shape} vs {b.shape}")
            continue
        d = np.abs(a - b)
        if mask is not None:
            if mask.shape != d.shape:
                print(f"{label:<24} MASK SHAPE MISMATCH")
                continue
            d = d[mask]
        if d.size == 0:
            print(f"{label:<24} EMPTY MASK")
            continue
        print(f"{label:<24} {d.mean():>9.3f} {np.percentile(d,50):>7.2f} "
              f"{np.percentile(d,95):>7.2f} {d.max():>6.1f} "
              f"{100.0*(d>4).mean():>8.2f}% {100.0*(d>8).mean():>8.2f}% {d.size:>10}")


if __name__ == "__main__":
    main()
