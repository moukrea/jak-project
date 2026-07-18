#!/usr/bin/env python3
"""Grecharged-pbr-materials round-3 macro-shading gate (supervisor-owned metric).

Owner defect: dropping the baked vertex color made the WHOLE building read flatter than
stock — the curvature gradient, under-roof darkening and doorway occlusion vanished into
a constant ambient. The fix reintegrates the baked color as the PBR indirect/GI term.

This metric proves the MACRO light distribution returned: at the SAME vantage and TOD,
the ON frame's low-frequency luminance profile across the building must correlate with
the OFF (legacy baked) frame's. Binned profiles (not raw columns) so the swapped
material's different texels don't tank the score — macro shading is low-frequency.

  horizontal profile (per-column, binned) -> the curvature gradient along the round wall
  vertical   profile (per-row,    binned) -> the under-roof / top-to-bottom gradient
  mean ratio ON/OFF                        -> double-dose check (hot side must not blow out)

Usage: pbr_macro_profile.py <on.png> <off.png> [y0 y1 x0 x1 (band fracs, default
       0.30 0.65 0.10 0.90)] [--bins=N (default 48)]
Prints: MACRO corr_h=<v> corr_v=<v> bins=N mean_on=<v> mean_off=<v> ratio=<v> band=...
Gate (owner round-3 mandate): corr_h > 0.8 with ratio in [0.75, 1.35].
"""
import sys
import numpy as np
from PIL import Image


def lum(path):
    a = np.asarray(Image.open(path).convert("RGB"), dtype=np.float32)
    return 0.2126 * a[..., 0] + 0.7152 * a[..., 1] + 0.0722 * a[..., 2]


def binned(v, nbins):
    n = len(v) // nbins * nbins
    return v[:n].reshape(nbins, -1).mean(axis=1)


def pearson(a, b):
    a = a - a.mean()
    b = b - b.mean()
    d = np.sqrt((a * a).sum() * (b * b).sum())
    return float((a * b).sum() / d) if d > 1e-9 else 0.0


def main():
    nbins = 48
    argv = []
    for a in sys.argv[1:]:
        if a.startswith("--bins="):
            nbins = int(a.split("=", 1)[1])
        else:
            argv.append(a)
    if len(argv) not in (2, 6):
        print(__doc__)
        return 2
    on, off = lum(argv[0]), lum(argv[1])
    if on.shape != off.shape:
        print(f"MACRO ERROR shape {on.shape} vs {off.shape}")
        return 1
    band = argv[2:6] if len(argv) == 6 else ["0.30", "0.65", "0.10", "0.90"]
    y0, y1, x0, x1 = (float(x) for x in band)
    h, w = on.shape
    bon = on[int(h * y0) : int(h * y1), int(w * x0) : int(w * x1)]
    boff = off[int(h * y0) : int(h * y1), int(w * x0) : int(w * x1)]
    corr_h = pearson(binned(bon.mean(axis=0), nbins), binned(boff.mean(axis=0), nbins))
    corr_v = pearson(binned(bon.mean(axis=1), nbins), binned(boff.mean(axis=1), nbins))
    m_on, m_off = float(bon.mean()), float(boff.mean())
    ratio = m_on / m_off if m_off > 1e-6 else 0.0
    print(
        f"MACRO corr_h={corr_h:.3f} corr_v={corr_v:.3f} bins={nbins} "
        f"mean_on={m_on:.2f} mean_off={m_off:.2f} ratio={ratio:.3f} "
        f"band=y[{y0},{y1}]x[{x0},{x1}]"
    )
    ok = corr_h > 0.8 and 0.75 <= ratio <= 1.35
    print(f"MACRO {'PASS' if ok else 'FAIL'} (gate: corr_h>0.8, ratio in [0.75,1.35])")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
