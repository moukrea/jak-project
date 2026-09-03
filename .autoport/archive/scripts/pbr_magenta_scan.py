#!/usr/bin/env python3
"""Grecharged-pbr-materials hardening proof: magenta scan over capture frames.

Owner symptom class: "beaucoup de violet" = unbound/incomplete PBR sampler units
reading as fuchsia on Adreno. Scan every frame of a run for near-fuchsia pixels
(strict criterion so village1's own purple accents / warp glow don't false-positive:
r>200, b>200, g<60). Report per-run totals; the PASS claim is DIFFERENTIAL — the
PBR-ON run must not add magenta beyond the stock run's baseline.

Usage: pbr_magenta_scan.py <frames_dir> [<frames_dir> ...]
"""
import sys
import os
import numpy as np
from PIL import Image

def scan_dir(d):
    total_px = 0
    magenta_px = 0
    worst = (0, None)  # (count, fname)
    frames = sorted(f for f in os.listdir(d) if f.endswith(".png"))
    for f in frames:
        a = np.asarray(Image.open(os.path.join(d, f)).convert("RGB"), dtype=np.uint8)
        m = (a[:, :, 0] > 200) & (a[:, :, 2] > 200) & (a[:, :, 1] < 60)
        c = int(m.sum())
        total_px += a.shape[0] * a.shape[1]
        magenta_px += c
        if c > worst[0]:
            worst = (c, f)
    ppm = 1e6 * magenta_px / total_px if total_px else 0.0
    return len(frames), magenta_px, ppm, worst

def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    for d in sys.argv[1:]:
        n, cnt, ppm, worst = scan_dir(d)
        print(f"MAGENTA-SCAN dir={d} frames={n} magenta_px={cnt} ppm={ppm:.2f} "
              f"worst_frame={worst[1]} worst_px={worst[0]}")
    return 0

if __name__ == "__main__":
    sys.exit(main())
