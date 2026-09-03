#!/usr/bin/env python3
"""gpbrf_r20_scale.py — AT WHAT SPATIAL SCALE DOES THE DISPLACEMENT ACT? (the decisive test)

The round-20 claim is one sentence: the tessellation used to sample the height map in a world
projection at a hardcoded 0.5 tiles/m, so it displaced a feature 2.0/tile_m times SMALLER than the
one the material actually paints; it now samples at the material's MEASURED density, so the
displaced feature and the painted feature are the same size.

That claim is about a RATIO OF SPATIAL SCALES, so it is tested as one. The prediction is exact and
comes from numbers measured elsewhere (the offline audit and the on-device loader log), not from
this script: with the LEGACY law the geometry acts at

    lag_legacy = lag_painted * (2.0 m / tile_m)

and with the round-20 law it acts at lag_painted itself.

METHOD, and why it is not a differencing metric. Differencing a displaced frame against a flat one
does NOT isolate the geometry: displacing a surface also moves whatever is painted on it, so the
difference carries the painted period whatever the height field does. (Measured, first attempt:
both laws came back at ratio ~1.0. Worthless.) So nothing is differenced here. Each cell's OWN
autocorrelation is evaluated at the two lags the prediction names:

    A(lag_painted)  — how much pattern sits at the material's authored feature scale
    A(lag_legacy)   — how much pattern sits at the scale the old constant would have produced

and the two are compared BETWEEN cells. A law that acts at a scale puts energy at that scale.

lag_painted is measured from the reference cell (displacement OFF), where the only pattern present
is the authored-uv one (the height-derived cavity term and the roughness map, both sampled at
tex_coord) — no geometry at all, since displacement is off.

Usage:
  gpbrf_r20_scale.py <dir> --ref F_flat --cells F_tess,F_leg --tile-m 4.858
                     [--band name,lo,hi ...] [--x0 F] [--x1 F]
"""
import os
import subprocess
import sys
import tempfile

import numpy as np
from PIL import Image

FPS = 3
HP_SIGMA = 60.0
MIN_LAG = 4
MAX_LAG_FRAC = 0.45


def frames_of(base):
    mp4 = base + ".mp4"
    if os.path.exists(mp4) and os.path.getsize(mp4) > 20000:
        with tempfile.TemporaryDirectory() as td:
            subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", mp4,
                            "-vf", f"fps={FPS}", os.path.join(td, "f_%03d.png")], check=False)
            fs = sorted(f for f in os.listdir(td) if f.endswith(".png"))
            if len(fs) >= 3:
                arr = []
                for f in fs:
                    a = np.asarray(Image.open(os.path.join(td, f)).convert("RGB"), dtype=np.float64)
                    arr.append(0.2126 * a[:, :, 0] + 0.7152 * a[:, :, 1] + 0.0722 * a[:, :, 2])
                return np.median(np.stack(arr, 0), axis=0)
    png = base + ".png"
    if os.path.exists(png):
        a = np.asarray(Image.open(png).convert("RGB"), dtype=np.float64)
        return 0.2126 * a[:, :, 0] + 0.7152 * a[:, :, 1] + 0.0722 * a[:, :, 2]
    return None


def gauss1d(x, sigma):
    n = int(sigma * 4) | 1
    k = np.exp(-0.5 * ((np.arange(n) - n // 2) / sigma) ** 2)
    k /= k.sum()
    return np.convolve(np.pad(x, n // 2, mode="edge"), k, mode="valid")[:len(x)]


def autocorr(sig):
    s = sig - gauss1d(sig, HP_SIGMA)
    s = s - s.mean()
    rms = float(s.std())
    if rms < 1e-9:
        return None, rms
    s = s * np.hanning(len(s))
    n = 1 << int(np.ceil(np.log2(len(s) * 2)))
    f = np.fft.rfft(s, n)
    ac = np.fft.irfft(f * np.conj(f), n)[:len(s)]
    if ac[0] <= 0:
        return None, rms
    return ac / ac[0], rms


def first_peak(ac, lo=MIN_LAG, hi=None):
    hi = hi or int(len(ac) * MAX_LAG_FRAC)
    seg = ac[lo:hi]
    for i in range(1, len(seg) - 1):
        if seg[i] > seg[i - 1] and seg[i] >= seg[i + 1] and seg[i] > 0.05:
            return i + lo, seg[i]
    j = int(np.argmax(seg))
    return j + lo, seg[j]


def at(ac, lag):
    """Autocorrelation at a (fractional) lag, taking the local max over +-15% to be robust to the
    projected period varying slightly across the band."""
    if ac is None or lag <= MIN_LAG:
        return float("nan")
    lo = max(MIN_LAG, int(lag * 0.85))
    hi = min(len(ac) - 1, int(lag * 1.15) + 1)
    if hi <= lo:
        return float("nan")
    return float(np.max(ac[lo:hi]))


def band_signal(img, lo, hi, x0, x1):
    h, w = img.shape
    band = img[int(h * lo):int(h * hi), int(w * x0):int(w * x1)]
    if band.shape[1] < 64:
        return None
    return band.mean(axis=0)


def main():
    args = sys.argv[1:]
    d = args[0]
    ref, cells, tile_m, x0, x1 = None, [], None, 0.0, 1.0
    bands = []
    i = 1
    while i < len(args):
        a = args[i]
        if a == "--ref":
            ref = args[i + 1]; i += 2
        elif a == "--cells":
            cells = args[i + 1].split(","); i += 2
        elif a == "--tile-m":
            tile_m = float(args[i + 1]); i += 2
        elif a == "--x0":
            x0 = float(args[i + 1]); i += 2
        elif a == "--x1":
            x1 = float(args[i + 1]); i += 2
        elif a == "--band":
            nm, lo, hi = args[i + 1].split(","); bands.append((nm, float(lo), float(hi))); i += 2
        else:
            i += 1
    if not bands:
        bands = [("near", 0.82, 0.92), ("mid", 0.70, 0.80)]
    ratio = 2.0 / tile_m

    print("=== SPATIAL SCALE OF THE DISPLACEMENT (round 20 vs the legacy constant) ===")
    print(f"dir={d} ref={ref} cells={cells} x-window={x0:.2f}..{x1:.2f}")
    print(f"material tile = {tile_m:.3f} m  =>  the LEGACY law acts at {ratio:.3f} x the painted lag")
    print("A(painted) / A(legacy) = autocorrelation of the cell's OWN signal at those two lags.")
    print("A law that acts at a scale puts energy at that scale: the legacy cell must gain at")
    print("A(legacy) relative to the reference and to the round-20 cell.")
    print()

    imgs = {c: frames_of(os.path.join(d, c)) for c in [ref] + cells}
    for nm, lo, hi in bands:
        sref = band_signal(imgs[ref], lo, hi, x0, x1) if imgs.get(ref) is not None else None
        if sref is None:
            print(f"band {nm}: reference missing")
            continue
        acr, rmsr = autocorr(sref)
        if acr is None:
            print(f"band {nm}: reference has no signal (rms {rmsr:.2f})")
            continue
        lag0, v0 = first_peak(acr)
        lagL = lag0 * ratio
        print(f"--- band {nm} (rows {lo:.2f}-{hi:.2f}) ---")
        print(f"  painted lag from {ref}: {lag0} px (peak {v0:.3f})   legacy lag would be "
              f"{lagL:.1f} px")
        print(f"  {'cell':10s} {'rms':>7s} {'A(painted)':>11s} {'A(legacy)':>10s} "
              f"{'A(leg)-A(leg)_ref':>18s}")
        base_leg = at(acr, lagL)
        print(f"  {ref:10s} {rmsr:7.2f} {at(acr, lag0):11.3f} {base_leg:10.3f} {0.0:18.3f}")
        for c in cells:
            if imgs.get(c) is None:
                print(f"  {c:10s} MISSING")
                continue
            s = band_signal(imgs[c], lo, hi, x0, x1)
            ac, rms = autocorr(s)
            if ac is None:
                print(f"  {c:10s} {rms:7.2f}  (no signal)")
                continue
            ap, al = at(ac, lag0), at(ac, lagL)
            print(f"  {c:10s} {rms:7.2f} {ap:11.3f} {al:10.3f} {al - base_leg:18.3f}")
        print()
    return 0


if __name__ == "__main__" and "--centroid" not in sys.argv:
    sys.exit(main())


# ------------------------------------------------------------------------------------------------
# SECOND ESTIMATOR — SPECTRAL CENTROID. Added because the two-lag autocorrelation above needs a
# clean periodic peak, and on a low-contrast surface (the flat-base wall runs at rms 1.6-3.9 luma
# levels) there is not always one. The centroid needs no peak: it asks "where does the energy sit"
# and answers with a single number, which is exactly the question this round is about.
#
# With the FLAT base and the normal map isolated off, the ONLY difference between the two
# tessellation cells is the height lookup rate and the amplitude — and note the uv is NOT touched by
# displacement (the tese passes tc_texcoord through unchanged), so the fragment-stage cavity pattern
# is identical in all three cells and cancels in (cell - flat). What is left is the geometry.
#
#   PREDICTION: centroid_period(LEGACY) / centroid_period(ROUND 20) = 2.0 m / tile_m.
# ------------------------------------------------------------------------------------------------
def centroid_main():
    args = sys.argv[1:]
    d = args[0]
    ref, cells, tile_m, x0, x1 = None, [], 1.0, 0.0, 1.0
    bands = []
    i = 1
    while i < len(args):
        a = args[i]
        if a == "--ref":
            ref = args[i + 1]; i += 2
        elif a == "--cells":
            cells = args[i + 1].split(","); i += 2
        elif a == "--tile-m":
            tile_m = float(args[i + 1]); i += 2
        elif a == "--x0":
            x0 = float(args[i + 1]); i += 2
        elif a == "--x1":
            x1 = float(args[i + 1]); i += 2
        elif a == "--band":
            nm, lo, hi = args[i + 1].split(","); bands.append((nm, float(lo), float(hi))); i += 2
        else:
            i += 1
    if not bands:
        bands = [("near", 0.82, 0.92)]
    imgs = {c: frames_of(os.path.join(d, c)) for c in [ref] + cells}
    print("=== SPECTRAL CENTROID OF WHAT THE DISPLACEMENT ADDS ===")
    print(f"predicted centroid-period ratio LEGACY/ROUND20 = 2.0/{tile_m:.3f} = {2.0/tile_m:.3f}")
    print("(i.e. the legacy law should put its energy at a period that many times SHORTER)")
    print(f"{'band':12s} {'cell':10s} {'energy':>9s} {'centroid_px':>12s} {'ratio_vs_first':>15s}")
    for nm, lo, hi in bands:
        first = None
        for c in cells:
            if imgs.get(c) is None or imgs.get(ref) is None:
                continue
            diff = imgs[c] - imgs[ref]
            s = band_signal(diff, lo, hi, x0, x1)
            if s is None:
                continue
            s = s - gauss1d(s, HP_SIGMA)
            s = (s - s.mean()) * np.hanning(len(s))
            n = 1 << int(np.ceil(np.log2(len(s) * 2)))
            P = np.abs(np.fft.rfft(s, n)) ** 2
            f = np.fft.rfftfreq(n, d=1.0)
            # restrict to periods 5..250 px: below 5 px is encoder noise, above 250 px is lighting
            m = (f > 1.0 / 250.0) & (f < 1.0 / 5.0)
            if P[m].sum() <= 0:
                continue
            fc = float((f[m] * P[m]).sum() / P[m].sum())
            per = 1.0 / fc if fc > 0 else float("nan")
            e = float(P[m].sum() / len(s))
            if first is None:
                first = per
            print(f"{nm:12s} {c:10s} {e:9.1f} {per:12.2f} {per/first:15.3f}")
    return 0


if __name__ == "__main__" and "--centroid" in sys.argv:
    sys.exit(centroid_main())
