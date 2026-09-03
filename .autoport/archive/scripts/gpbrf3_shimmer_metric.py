#!/usr/bin/env python3
"""gpbrf3_shimmer_metric.py — REOPEN #3 shimmer (specular aliasing) temporal metric.

Sparkle = bright pixels that flicker frame-to-frame under camera motion. Metric over a
moving capture's frame directory: for each consecutive pair, mean |delta-luma| restricted
to the first frame's top-decile-luma pixels (the spec band), plus the per-frame p95 luma
temporal std. Lower after the Toksvig-from-mip fix = shimmer reduced.

Usage: gpbrf3_shimmer_metric.py <frames_dir_glob_pngs> [label]
"""
import glob
import sys

import numpy as np
from PIL import Image


def main():
    frames = sorted(glob.glob(sys.argv[1] + '/*.png'))
    label = sys.argv[2] if len(sys.argv) > 2 else sys.argv[1]
    if len(frames) < 3:
        print(f"SHIMMER {label}: only {len(frames)} frames — need >=3")
        return
    prev = None
    deltas, p95s = [], []
    for f in frames:
        im = np.asarray(Image.open(f).convert('RGB'), dtype=np.float32)
        lum = im @ np.array([0.299, 0.587, 0.114], dtype=np.float32)
        p95s.append(np.percentile(lum, 95))
        if prev is not None and prev.shape == lum.shape:
            thr = np.percentile(prev, 90)
            band = prev >= thr
            deltas.append(float(np.abs(lum - prev)[band].mean()))
        prev = lum
    print(f"SHIMMER {label}: frames={len(frames)} "
          f"specband_frame_delta mean={np.mean(deltas):.2f} max={np.max(deltas):.2f} "
          f"p95_luma mean={np.mean(p95s):.2f} temporal_std={np.std(p95s):.2f}")


if __name__ == '__main__':
    main()
