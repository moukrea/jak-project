#!/usr/bin/env python3
"""Grecharged-pbr-materials round-5 shadow-attribution gate: shadow-mask IoU across a
camera-orbit clip.

Owner defect: shadows POP / drift as the camera orbits (casters camera-vis-culled in the
depth pass, view-dependent ortho fit). If the sun is PINNED and only the CAMERA moves, a
static-scene shadow should stay put on the ground. This measures the shadow mask's overlap
between CONSECUTIVE fps=5 orbit frames — a pinned shadow gives IoU near 1.0; a pop tanks it.

Only the ground/static band (rows 45%..95%) is considered, skipping sky + HUD. The shadow
mask is per-frame Otsu (auto) on that band, clamped away from degenerate splits.

Usage:
  pbr_shadow_iou.py <frames_dir> [--band 0.45,0.95] [--thresh auto|0..255] [--min-area 200]
                    [--no-align]
Prints a summary and 'IOU_GATE PASS' iff iou_p05 > 0.9 AND iou_min > 0.75, else FAIL.
Also writes per-pair values to <frames_dir>/iou_pairs.txt.

ALIGNMENT (default on): during an orbit the whole scene translates in screen space between
consecutive frames, which caps raw IoU well below 1 even for perfectly pinned shadows (and
drowned the fix-vs-control difference on the first capture). Each pair is first registered
by integer phase-correlation of the GRAYSCALE band (global camera motion estimate, capped
±24 px), the second mask is shifted back, and IoU is computed on the overlap region only.
What survives alignment is shadow-mask change BEYOND camera motion — pops and swims.
"""
import sys
import os
import glob
import numpy as np
from PIL import Image


def otsu(vals):
    # vals: 1-D uint8 array of the band pixels; returns the Otsu threshold.
    hist, _ = np.histogram(vals, bins=256, range=(0, 256))
    hist = hist.astype(np.float64)
    total = hist.sum()
    if total == 0:
        return 60
    idx = np.arange(256)
    w0 = np.cumsum(hist)
    w1 = total - w0
    sum_total = (idx * hist).sum()
    sum0 = np.cumsum(idx * hist)
    with np.errstate(divide="ignore", invalid="ignore"):
        m0 = sum0 / w0
        m1 = (sum_total - sum0) / w1
        between = w0 * w1 * (m0 - m1) ** 2
    between[~np.isfinite(between)] = 0
    return int(np.argmax(between))


def load_band(path, y0, y1):
    a = np.asarray(Image.open(path).convert("L"), dtype=np.uint8)
    a = a[::2, ::2]  # downscale x2 for speed
    h = a.shape[0]
    return a[int(h * y0):int(h * y1)]


def phase_shift(a, b, cap=24):
    # Integer (dy, dx) that best maps b onto a, via FFT phase correlation. cap bounds the
    # search to plausible per-frame camera motion (fps=5 orbit); larger peaks are noise.
    fa = np.fft.rfft2(a.astype(np.float32))
    fb = np.fft.rfft2(b.astype(np.float32))
    cross = fa * np.conj(fb)
    denom = np.abs(cross)
    denom[denom < 1e-9] = 1e-9
    corr = np.fft.irfft2(cross / denom, s=a.shape)
    peak = np.unravel_index(np.argmax(corr), corr.shape)
    dy = peak[0] if peak[0] <= a.shape[0] // 2 else peak[0] - a.shape[0]
    dx = peak[1] if peak[1] <= a.shape[1] // 2 else peak[1] - a.shape[1]
    if abs(dy) > cap or abs(dx) > cap:
        return 0, 0
    return int(dy), int(dx)


def shifted_overlap(ma, mb, dy, dx):
    # Shift mask mb by (dy, dx) and return the pair restricted to the valid overlap.
    h, w = ma.shape
    ya0, ya1 = max(0, dy), min(h, h + dy)
    yb0, yb1 = max(0, -dy), min(h, h - dy)
    xa0, xa1 = max(0, dx), min(w, w + dx)
    xb0, xb1 = max(0, -dx), min(w, w - dx)
    return ma[ya0:ya1, xa0:xa1], mb[yb0:yb1, xb0:xb1]


def main():
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        return 2
    d = args[0]
    band = (0.45, 0.95)
    thresh = "auto"
    min_area = 200
    align = True
    cap = 24
    i = 1
    while i < len(args):
        if args[i] == "--band":
            band = tuple(float(x) for x in args[i + 1].split(","))
            i += 2
        elif args[i] == "--thresh":
            thresh = args[i + 1]
            i += 2
        elif args[i] == "--min-area":
            min_area = int(args[i + 1])
            i += 2
        elif args[i] == "--cap":
            # Max plausible per-frame camera translation (px) the phase-correlation
            # aligner will trust. The default 24 saturates on a fast CLOSE orbit (per-frame
            # screen translation exceeds 24 px -> the estimate is discarded and the pair is
            # scored with ZERO camera-motion compensation, inflating apparent shadow swim).
            # A larger cap lets the aligner subtract real camera motion so the residual IoU
            # reflects genuine shadow drift only. Report both when they differ materially.
            cap = int(args[i + 1])
            i += 2
        elif args[i] == "--no-align":
            align = False
            i += 1
        else:
            print(f"unknown arg {args[i]}")
            return 2

    files = sorted(glob.glob(os.path.join(d, "*.png")))
    if len(files) < 2:
        print(f"IOU_GATE FAIL (need >=2 frames, found {len(files)})")
        return 1

    masks = []
    bands = []
    for f in files:
        b = load_band(f, band[0], band[1])
        bands.append(b)
        if thresh == "auto":
            t = otsu(b.ravel())
            t = max(25, min(110, t))
        else:
            t = int(thresh)
        m = b < t
        masks.append(m if m.sum() >= min_area else None)

    pairs = []
    empties = 0
    for k in range(len(masks) - 1):
        a, b = masks[k], masks[k + 1]
        if a is None or b is None:
            empties += 1
            continue
        if align:
            dy, dx = phase_shift(bands[k], bands[k + 1], cap=cap)
            a, b = shifted_overlap(a, b, dy, dx)
        inter = np.logical_and(a, b).sum()
        union = np.logical_or(a, b).sum()
        iou = inter / union if union else 0.0
        pairs.append((files[k], files[k + 1], iou))

    with open(os.path.join(d, "iou_pairs.txt"), "w") as fh:
        for pa, pb, iou in pairs:
            fh.write(f"{os.path.basename(pa)} {os.path.basename(pb)} {iou:.4f}\n")

    n_pairs = len(pairs)
    if n_pairs == 0:
        print(f"n_frames={len(files)} n_pairs=0 empties={empties}")
        print("IOU_GATE FAIL (no non-empty consecutive pairs)")
        return 1

    ious = np.array([p[2] for p in pairs])
    iou_min = float(ious.min())
    iou_p05 = float(np.percentile(ious, 5))
    iou_median = float(np.median(ious))
    iou_mean = float(ious.mean())
    print(
        f"n_frames={len(files)} n_pairs={n_pairs} iou_min={iou_min:.4f} "
        f"iou_p05={iou_p05:.4f} iou_median={iou_median:.4f} iou_mean={iou_mean:.4f} "
        f"empties={empties}"
    )
    if iou_p05 > 0.9 and iou_min > 0.75:
        print("IOU_GATE PASS")
        return 0
    print("IOU_GATE FAIL")
    return 1


if __name__ == "__main__":
    sys.exit(main())
