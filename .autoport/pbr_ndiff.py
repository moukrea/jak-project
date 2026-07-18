#!/usr/bin/env python3
"""Grecharged-pbr-materials critique-2 proof: quantify that the NORMAL MAP changes shading.

Compares the viz stills captured in ONE boot at the same vantage / pinned sun:
  mode0 (full PBR)  vs mode7 (full PBR, normal map DISABLED)  -> shading delta from N
  mode2 (geo normal) vs mode3 (final normal)                  -> the map's perturbation itself
A near-zero mode0-vs-mode7 delta means the normal map does NOT contribute (the owner's
"just a base-color swap" symptom); a clear delta plus a textured mode3 proves it does.

Usage: pbr_ndiff.py <viz_dir> [crop_frac=0.6]
Prints one line per pair: NDIFF pair=<a>-vs-<b> mean_abs=<v> p99=<v> over the center crop.
"""
import sys
import os
import numpy as np
from PIL import Image


def load(d, name, crop):
    p = os.path.join(d, name)
    a = np.asarray(Image.open(p).convert("RGB"), dtype=np.float32)
    h, w, _ = a.shape
    ch, cw = int(h * crop) // 2, int(w * crop) // 2
    return a[h // 2 - ch : h // 2 + ch, w // 2 - cw : w // 2 + cw]


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    d = sys.argv[1]
    crop = float(sys.argv[2]) if len(sys.argv) > 2 else 0.6
    pairs = [("mode0.png", "mode7.png"), ("mode2.png", "mode3.png")]
    # POM contribution (owner mandate 2026-07-18): mode8 = full PBR with the parallax
    # march disabled — a clear mode0-vs-mode8 delta proves the height map offsets UVs.
    if os.path.exists(os.path.join(d, "mode8.png")):
        pairs.append(("mode0.png", "mode8.png"))
    for a_name, b_name in pairs:
        a = load(d, a_name, crop)
        b = load(d, b_name, crop)
        if a.shape != b.shape:
            print(f"NDIFF pair={a_name}-vs-{b_name} ERROR shape {a.shape} vs {b.shape}")
            continue
        diff = np.abs(a - b).mean(axis=2)
        print(
            f"NDIFF pair={a_name}-vs-{b_name} crop={crop} mean_abs={diff.mean():.3f} "
            f"p99={np.percentile(diff, 99):.3f} max={diff.max():.1f}"
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
