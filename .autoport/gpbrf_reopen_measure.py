#!/usr/bin/env python3
"""gpbrf_reopen_measure.py — REOPEN (plastic-shine/industry-BRDF) metrics.

Pure-wall crop (x .26-.48, y .30-.58 — the vil1-sages-stonewall-01 test material
only at the pinned vantage), EMISSIVE-DOT MASKED (teal test), and 8x8 block-mean
luminance to sit above the h.264 temporal noise floor (attempt-2 gotcha).

  wall <img>            dot-masked wall stats: mean/std/p99/lapstd/sat
  bdiff <a> <b>         dot-masked 8x8 block-mean abs diff between wall crops
  floor <f0> <f1>       same metric on two frames of the SAME capture = noise floor
"""
import sys
import numpy as np
from PIL import Image

WX0, WX1, WY0, WY1 = .26, .48, .30, .58


def wall_crop(path):
    im = np.asarray(Image.open(path).convert('RGB'), dtype=np.float32)
    h, w, _ = im.shape
    c = im[int(h * WY0):int(h * WY1), int(w * WX0):int(w * WX1)]
    lum = c @ np.array([0.299, 0.587, 0.114], dtype=np.float32)
    # emissive-dot mask: bright teal texels (G>R+40, B>R, lum>120) excluded
    dots = (c[:, :, 1] > c[:, :, 0] + 40) & (c[:, :, 2] > c[:, :, 0]) & (lum > 120)
    return c, lum, ~dots


def blockmean(lum, mask, n=8):
    h, w = lum.shape
    h8, w8 = h - h % n, w - w % n
    l8 = lum[:h8, :w8].reshape(h8 // n, n, w8 // n, n)
    m8 = mask[:h8, :w8].reshape(h8 // n, n, w8 // n, n).astype(np.float32)
    s = (l8 * m8).sum(axis=(1, 3))
    cnt = np.maximum(m8.sum(axis=(1, 3)), 1.0)
    return s / cnt, m8.sum(axis=(1, 3)) > (n * n * 0.5)


def lap_std(lum):
    k = lum[1:-1, 1:-1] * 4 - lum[:-2, 1:-1] - lum[2:, 1:-1] - lum[1:-1, :-2] - lum[1:-1, 2:]
    return float(np.std(k))


def wall(path):
    c, lum, m = wall_crop(path)
    lm = lum[m]
    sat = (c.max(axis=2) - c.min(axis=2))[m]
    print(f"WALL {path}: mean={lm.mean():.2f} std={lm.std():.2f} "
          f"p99={np.percentile(lm, 99):.2f} p999={np.percentile(lm, 99.9):.2f} "
          f"lapstd={lap_std(lum):.2f} sat={sat.mean():.2f} masked_dots={int((~m).sum())}")


def bdiff(a, b):
    _, la, ma = wall_crop(a)
    _, lb, mb = wall_crop(b)
    if la.shape != lb.shape:
        print(f"BDIFF {a} vs {b}: SHAPE MISMATCH")
        return
    ba, va = blockmean(la, ma)
    bb, vb = blockmean(lb, mb)
    v = va & vb
    d = np.abs(ba - bb)[v]
    print(f"BDIFF {a} vs {b}: blockmeandiff={d.mean():.3f} blockp99={np.percentile(d, 99):.3f} "
          f"blocks={int(v.sum())}")


if __name__ == '__main__':
    cmd = sys.argv[1]
    if cmd == 'wall':
        wall(sys.argv[2])
    elif cmd in ('bdiff', 'floor'):
        bdiff(sys.argv[2], sys.argv[3])
    else:
        sys.exit('unknown cmd')
