#!/usr/bin/env python3
"""gpbrf_r20_checker.py — THE CHECKERBOARD VERIFICATION, as a number.

The owner's method: put a synthetic CHECKERBOARD (base colour + a height map whose squares coincide
with the painted ones) on the PBR materials and look at whether the displaced geometry forms blocks
that follow the height. The supervisor ran it by hand on 2026-07-25 and found the displacement DOES
follow the height, but that the blocks were the wrong SIZE relative to the painted squares.

WHAT IS MEASURED: the dominant horizontal PERIOD of the ground pattern, in pixels, per depth band.
  * With the CHECKER base (testpattern 1), the OFF cell's period is the PAINTED period: one texture
    tile is (tile_m) across and holds `squares` cells, so the pattern repeats every 2 cells.
  * With the FLAT base (testpattern 3) and the normal map isolated off (bisect bit 64), a cell with
    displacement ON has NO painted and NO mapped spatial frequency left — the only thing that can
    vary across the ground is the DISPLACED GEOMETRY. The period measured there IS the displaced
    feature's period.
  * The two are then compared. Equal = the geometry displaces the feature that is painted.

WHY THE FLAT BASE IS NECESSARY (learned the hard way, first attempt at this measurement):
differencing a displaced frame against a flat one does NOT isolate the geometry, because displacing
a surface also MOVES the texture painted on it — so |tess - off| carries the painted period no
matter what the height field is doing. That measurement came back ~1.0 for both laws and was
worthless. Removing the albedo removes the confound at the source instead of trying to model it.

PERSPECTIVE: a ground pattern's projected period changes with depth, so every measurement is made in
NARROW horizontal bands where the depth, and therefore the projected period, is near constant.
X-WINDOW: the analysis is restricted to a horizontal window (default the right 65% of the frame) so
that ocean, sky and letterbox columns cannot contribute; at the owner's vantage the left ~35% of the
frame is sea.

Signal conditioning per band: column-mean over the band's rows, high-pass by subtracting a wide
Gaussian (kills lighting gradient and vignetting), Hann window, FFT autocorrelation. The reported
period is the first autocorrelation maximum past lag 3, with its height, so a band with no periodic
content shows up as such (low or negative prominence) instead of returning a random lag.

Usage:  gpbrf_r20_checker.py <device-dir> cell [cell ...] [--x0 F] [--x1 F] [--ref CELL]
        --ref CELL  = also print, for every other cell, the ratio of its period to CELL's.
"""
import os
import subprocess
import sys
import tempfile

import numpy as np
from PIL import Image

FPS = 3
BANDS = [("near", 0.82, 0.92), ("mid", 0.70, 0.80), ("far", 0.58, 0.68)]
HP_SIGMA = 60.0
MIN_LAG = 4
MAX_LAG_FRAC = 0.45


def frames_of(base):
    """Temporal median luma of a cell: <base>.mp4 preferred, <base>.png accepted."""
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


def dominant_period(sig):
    """(period_px, prominence, rms) of the first autocorrelation peak past MIN_LAG."""
    s = sig - gauss1d(sig, HP_SIGMA)
    s = s - s.mean()
    rms = float(s.std())
    if rms < 1e-9:
        return 0.0, 0.0, rms
    s = s * np.hanning(len(s))
    n = 1 << int(np.ceil(np.log2(len(s) * 2)))
    f = np.fft.rfft(s, n)
    ac = np.fft.irfft(f * np.conj(f), n)[:len(s)]
    if ac[0] <= 0:
        return 0.0, 0.0, rms
    ac = ac / ac[0]
    hi = int(len(s) * MAX_LAG_FRAC)
    seg = ac[MIN_LAG:hi]
    if len(seg) < 4:
        return 0.0, 0.0, rms
    best_i, best_v = -1, -2.0
    for i in range(1, len(seg) - 1):
        if seg[i] > seg[i - 1] and seg[i] >= seg[i + 1]:
            best_i, best_v = i, seg[i]
            break
    if best_i < 0:
        best_i = int(np.argmax(seg))
        best_v = seg[best_i]
    i = best_i
    if 0 < i < len(seg) - 1:
        d = seg[i - 1] - 2 * seg[i] + seg[i + 1]
        if abs(d) > 1e-12:
            i = i + 0.5 * (seg[i - 1] - seg[i + 1]) / d
    return float(i + MIN_LAG), float(best_v), rms


def band_signal(img, lo, hi, x0, x1):
    h, w = img.shape
    r0, r1 = int(h * lo), int(h * hi)
    c0, c1 = int(w * x0), int(w * x1)
    band = img[r0:r1, c0:c1]
    if band.shape[1] < 64:
        return None
    return band.mean(axis=0)


def main():
    args = sys.argv[1:]
    x0, x1, ref = 0.35, 1.0, None
    cells = []
    i = 0
    d = "."
    while i < len(args):
        a = args[i]
        if a == "--x0":
            x0 = float(args[i + 1]); i += 2
        elif a == "--x1":
            x1 = float(args[i + 1]); i += 2
        elif a == "--ref":
            ref = args[i + 1]; i += 2
        elif a == "--band":
            # --band name,lo,hi  (repeatable) replaces the default depth bands. Needed because the
            # surface that carries the pattern is not always the floor: at the hut vantage the PBR
            # material with the largest flat area on screen is the sages' STONE WALL, which lives in
            # the upper half of the frame.
            nm, lo, hi = args[i + 1].split(",")
            if not getattr(main, "_bands_reset", False):
                BANDS.clear()
                main._bands_reset = True
            BANDS.append((nm, float(lo), float(hi)))
            i += 2
        elif not cells and not os.path.isfile(os.path.join(a, "")) and i == 0:
            d = a; i += 1
        else:
            cells.append(a); i += 1

    print("=== GROUND PATTERN PERIOD (the owner's checkerboard, measured) ===")
    print(f"dir={d}  x-window={x0:.2f}..{x1:.2f} of frame width  bands={[b[0] for b in BANDS]}")
    print("period_px = dominant horizontal period of the ground pattern; prom = autocorrelation")
    print("peak height (0-1; <=0.05 means there is no periodic content, read the period as noise);")
    print("rms = high-passed contrast of the band in luma levels, i.e. HOW MUCH pattern there is.")
    print()

    imgs = {}
    for c in cells:
        im = frames_of(os.path.join(d, c))
        if im is None:
            print(f"  MISSING cell {c}")
        imgs[c] = im

    table = {}
    hdr = f"{'cell':14s}"
    for b, _, _ in BANDS:
        hdr += f"{b + '_px':>10s}{'prom':>7s}{'rms':>7s}"
    if ref:
        hdr += f"{'ratio_vs_' + ref:>22s}"
    print(hdr)
    for c in cells:
        if imgs[c] is None:
            continue
        row = f"{c:14s}"
        per = {}
        for b, lo, hi in BANDS:
            s = band_signal(imgs[c], lo, hi, x0, x1)
            if s is None:
                row += f"{0:10.1f}{0:7.2f}{0:7.2f}"
                continue
            p, v, r = dominant_period(s)
            per[b] = (p, v, r)
            row += f"{p:10.1f}{v:7.3f}{r:7.2f}"
        table[c] = per
        if ref and ref in table and c != ref:
            rr = []
            for b, _, _ in BANDS:
                pr = table[ref].get(b, (0, 0, 0))
                pc = per.get(b, (0, 0, 0))
                if pr[0] > 0 and pc[0] > 0 and pr[1] > 0.05 and pc[1] > 0.05:
                    rr.append(pc[0] / pr[0])
            row += f"{(np.median(rr) if rr else float('nan')):22.3f}"
        print(row)
    return 0


if __name__ == "__main__":
    sys.exit(main())
