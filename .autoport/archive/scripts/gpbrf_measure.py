#!/usr/bin/env python3
"""gpbrf_measure.py — objective metrics for the pbr-realtime-fusion device captures.

All stats are computed on the center crop (30%..70% of both axes) — the pinned
sage-wall vantage frames the test material there. Metrics:
  stats <img>                 mean / std / p99 luminance + local-contrast (laplacian std)
  pair <a> <b>                per-pixel mean abs diff + the two stats lines
  glow <night> <noemis>       emissive proof: top-percentile luminance + bright-pixel count
                              in the night capture vs the no-emissive control
"""
import sys
import numpy as np
from PIL import Image


def crop_lum(path):
    im = np.asarray(Image.open(path).convert('RGB'), dtype=np.float32)
    h, w, _ = im.shape
    c = im[int(h * .30):int(h * .70), int(w * .30):int(w * .70)]
    lum = c @ np.array([0.299, 0.587, 0.114], dtype=np.float32)
    return c, lum


def lap_std(lum):
    k = lum[1:-1, 1:-1] * 4 - lum[:-2, 1:-1] - lum[2:, 1:-1] - lum[1:-1, :-2] - lum[1:-1, 2:]
    return float(np.std(k))


def stats(path):
    c, lum = crop_lum(path)
    sat = c.max(axis=2) - c.min(axis=2)
    print(f"STATS {path}: mean={lum.mean():.2f} std={lum.std():.2f} "
          f"p99={np.percentile(lum, 99):.2f} lapstd={lap_std(lum):.2f} sat={sat.mean():.2f}")


def pair(a, b):
    ca, la = crop_lum(a)
    cb, lb = crop_lum(b)
    if ca.shape != cb.shape:
        print(f"PAIR {a} vs {b}: SHAPE MISMATCH {ca.shape} {cb.shape}")
        return
    d = np.abs(ca - cb).mean()
    print(f"PAIR {a} vs {b}: meanabsdiff={d:.2f} "
          f"dmean={lb.mean()-la.mean():+.2f} dstd={lb.std()-la.std():+.2f} "
          f"dp99={np.percentile(lb,99)-np.percentile(la,99):+.2f} "
          f"dlapstd={lap_std(lb)-lap_std(la):+.2f}")
    stats(a)
    stats(b)


def glow(night, noemis):
    _, ln = crop_lum(night)
    _, lc = crop_lum(noemis)
    thr = np.percentile(lc, 99.5) + 15  # brighter than anything the control shows
    n_bright = int((ln > thr).sum())
    c_bright = int((lc > thr).sum())
    print(f"GLOW night={night} control={noemis}: thr={thr:.1f} "
          f"bright_px_night={n_bright} bright_px_control={c_bright} "
          f"top0.5%_night={np.percentile(ln,99.5):.1f} top0.5%_control={np.percentile(lc,99.5):.1f} "
          f"mean_night={ln.mean():.1f} mean_control={lc.mean():.1f}")


if __name__ == '__main__':
    cmd = sys.argv[1]
    if cmd == 'stats':
        stats(sys.argv[2])
    elif cmd == 'pair':
        pair(sys.argv[2], sys.argv[3])
    elif cmd == 'glow':
        glow(sys.argv[2], sys.argv[3])
    else:
        sys.exit('unknown cmd')
