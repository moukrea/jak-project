#!/usr/bin/env python3
# ao_band_metric.py — round F item 1: quantify HORIZONTAL banding in an AO capture.
# Horizontal shaded bands = structured variation of the ROW mean that column means do
# not share. Metric: detrended (gaussian-smoothed baseline removed) row-mean residual
# RMS vs the same for columns, on a central crop. Bands also show as a dominant
# autocorrelation peak at the low-res row pitch.
# Usage: ao_band_metric.py <img.png> [img2.png ...]
# Prints: BAND <file> rows=<rms> cols=<rms> ratio=<rows/cols> peak_lag=<px> peak=<corr>
# Calibration (x86 training-vantage debug AO term): isotropic High = rows 2.09 ratio
# 1.00-1.06; banded Low/Med = rows 3.9-4.2 ratio 1.88-2.17. PASS = ratio <= 1.5
# (directional asymmetry is the discriminator) AND rows-rms <= 3.0 (gross-band guard).
import sys

import numpy as np
from PIL import Image


def smooth(v, sigma):
    r = int(3 * sigma)
    x = np.arange(-r, r + 1)
    k = np.exp(-x * x / (2.0 * sigma * sigma))
    k /= k.sum()
    return np.convolve(np.pad(v, r, mode="reflect"), k, mode="valid")


def band_stats(path):
    a = np.asarray(Image.open(path).convert("L"), dtype=np.float64)
    h, w = a.shape
    # central crop: skip letterbox/HUD edges
    a = a[h // 6 : h * 5 // 6, w // 6 : w * 5 // 6]
    rows = a.mean(axis=1)
    cols = a.mean(axis=0)
    r_res = rows - smooth(rows, 15.0)
    c_res = cols - smooth(cols, 15.0)
    r_rms = float(np.sqrt((r_res**2).mean()))
    c_rms = float(np.sqrt((c_res**2).mean()))
    ratio = r_rms / max(c_rms, 1e-6)
    # autocorrelation of the row residual: banding = periodic peak at lag 2..32 px
    d = r_res - r_res.mean()
    ac = np.correlate(d, d, mode="full")[len(d) - 1 :]
    ac /= max(ac[0], 1e-9)
    lags = ac[2:33]
    peak_lag = int(np.argmax(lags)) + 2
    peak = float(lags.max())
    return r_rms, c_rms, ratio, peak_lag, peak


ok = True
for p in sys.argv[1:]:
    r_rms, c_rms, ratio, peak_lag, peak = band_stats(p)
    verdict = "PASS" if (ratio <= 1.5 and r_rms <= 3.0) else "BANDED"
    if verdict == "BANDED":
        ok = False
    print(
        f"BAND {p} rows={r_rms:.3f} cols={c_rms:.3f} ratio={ratio:.2f} "
        f"peak_lag={peak_lag} peak={peak:.2f} {verdict}"
    )
sys.exit(0 if ok else 1)
