#!/usr/bin/env python3
"""gpbrf3_bisect_metrics.py — REOPEN #3 term-bisection matrix.

One line per bisect mask: wall-crop (dot-masked, same region as gpbrf_reopen_measure)
and ground-crop (dock planks) stats + 8x8 block-mean delta vs the mask-0 baseline.
The culprit term = the mask whose capture loses the bright specular band (p95/p99 drop
and negative block-delta concentrated in the bright blocks) vs baseline.

Usage: gpbrf3_bisect_metrics.py <device_dir> <mask...>
Reads <device_dir>/bisect_m<mask>.png (+ bisect_spec0.png if present).
"""
import os
import sys

import numpy as np
from PIL import Image

# wall crop == gpbrf_reopen_measure.py (vil1-sages-stonewall-01 at the pinned vantage)
WALL = (.26, .48, .30, .58)
# dock planks below Jak ("ground" at this vantage), avoids Jak (x .46-.53 ends y~.78)
GROUND = (.30, .72, .82, .97)

MASK_NAMES = {
    0: 'baseline (full fused path)',
    1: 'yellow-sun GGX specular OFF',
    2: 'green-sun GGX specular OFF',
    4: 'ambient/IBL specular OFF',
    8: 'Fresnel-on-diffuse kd OFF',
    16: '_specular-map F0 OFF',
    32: 'emissive OFF',
    64: 'normal-map perturbation OFF',
    128: 'parallax/POM OFF',
    256: 'detail-relight ratio OFF',
    512: 'baked-modulation fmod OFF',
    1024: 'C1 shoulder tone map OFF',
}


def crop(img, box, dotmask):
    h, w, _ = img.shape
    x0, x1, y0, y1 = box
    c = img[int(h * y0):int(h * y1), int(w * x0):int(w * x1)]
    lum = c @ np.array([0.299, 0.587, 0.114], dtype=np.float32)
    if dotmask:  # emissive teal dots excluded (same rule as gpbrf_reopen_measure)
        dots = (c[:, :, 1] > c[:, :, 0] + 40) & (c[:, :, 2] > c[:, :, 0]) & (lum > 120)
        m = ~dots
    else:
        m = np.ones(lum.shape, bool)
    return lum, m


def blockmean(lum, mask, n=8):
    h, w = lum.shape
    h8, w8 = h - h % n, w - w % n
    l8 = lum[:h8, :w8].reshape(h8 // n, n, w8 // n, n)
    m8 = mask[:h8, :w8].reshape(h8 // n, n, w8 // n, n).astype(np.float32)
    s = (l8 * m8).sum(axis=(1, 3))
    cnt = np.maximum(m8.sum(axis=(1, 3)), 1.0)
    return s / cnt, m8.sum(axis=(1, 3)) > (n * n * 0.5)


def stats(lum, m):
    v = lum[m]
    return v.mean(), np.percentile(v, 95), np.percentile(v, 99)


def load(path):
    return np.asarray(Image.open(path).convert('RGB'), dtype=np.float32)


def main():
    d = sys.argv[1]
    masks = [int(x) for x in sys.argv[2:]]
    base = load(os.path.join(d, 'bisect_m0.png'))
    ref = {}
    for name, box, dm in (('wall', WALL, True), ('ground', GROUND, False)):
        lum, m = crop(base, box, dm)
        ref[name] = blockmean(lum, m)
    print(f"{'mask':>5} {'term':34} "
          f"{'w.mean':>7} {'w.p95':>7} {'w.p99':>7} {'w.bd':>6} {'w.bright_bd':>11} "
          f"{'g.mean':>7} {'g.p95':>7} {'g.p99':>7} {'g.bd':>6} {'g.bright_bd':>11}")
    rows = []
    for mk in masks:
        p = os.path.join(d, f'bisect_m{mk}.png')
        if not os.path.exists(p):
            print(f"{mk:>5} MISSING {p}")
            continue
        img = load(p)
        line = [f"{mk:>5} {MASK_NAMES.get(mk, '?'):34}"]
        for name, box, dm in (('wall', WALL, True), ('ground', GROUND, False)):
            lum, m = crop(img, box, dm)
            mn, p95, p99 = stats(lum, m)
            bm, bv = blockmean(lum, m)
            b0, v0 = ref[name]
            both = bv & v0
            bd = float(np.abs(bm - b0)[both].mean()) if both.any() else 0.0
            # bright-band delta: how much did the baseline's BRIGHTEST blocks change —
            # the plastic sheen lives there; a big negative value = the sheen died.
            thr = np.percentile(b0[v0], 90)
            bb = both & (b0 >= thr)
            bright_bd = float((bm - b0)[bb].mean()) if bb.any() else 0.0
            line.append(f"{mn:7.2f} {p95:7.2f} {p99:7.2f} {bd:6.2f} {bright_bd:11.2f}")
        print(' '.join(line))
        rows.append((mk, line))
    sp = os.path.join(d, 'bisect_spec0.png')
    if os.path.exists(sp):
        img = load(sp)
        line = [f"{'sp0':>5} {'OWNER DATAPOINT specint=0':34}"]
        for name, box, dm in (('wall', WALL, True), ('ground', GROUND, False)):
            lum, m = crop(img, box, dm)
            mn, p95, p99 = stats(lum, m)
            bm, bv = blockmean(lum, m)
            b0, v0 = ref[name]
            both = bv & v0
            bd = float(np.abs(bm - b0)[both].mean()) if both.any() else 0.0
            thr = np.percentile(b0[v0], 90)
            bb = both & (b0 >= thr)
            bright_bd = float((bm - b0)[bb].mean()) if bb.any() else 0.0
            line.append(f"{mn:7.2f} {p95:7.2f} {p99:7.2f} {bd:6.2f} {bright_bd:11.2f}")
        print(' '.join(line))


if __name__ == '__main__':
    main()
