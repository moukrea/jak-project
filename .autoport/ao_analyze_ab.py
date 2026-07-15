#!/usr/bin/env python3
"""ao_analyze_ab.py — Grecharged-ambient-occlusion A/B evidence analysis (v2, bracketed).

Capture layout (ao_capture.sh): off-a ssao off-b hbao off-c gtao off-d, tightly spaced.
Each AO mode is compared against the MEAN of its two bracketing off segments, so slow
time-of-day drift cancels to first order. Two validity gates run BEFORE any luminance
verdict:
  * POSE gate: normalized cross-correlation of every segment vs off-a (structure, not
    brightness). A moved camera (human touch mid-run, follow-cam re-frame) FAILS the
    vantage instead of poisoning the darkening stats.
  * DRIFT line: off-a vs off-d residual luminance drift, reported (bracketing already
    compensates; this is the honesty metric).
Then the defect-5 gates (owner 2026-07-15 14:20): open-area delta <=5%, global <=8%,
crease localization, and the raw-AO debug-view whiteness checks.

Usage: ao_analyze_ab.py <device_dir> <vantage>
"""
import glob
import os
import sys

import numpy as np
from PIL import Image

dev_dir, vant = sys.argv[1], sys.argv[2]
MODES = ["ssao", "hbao", "gtao"]
BRACKET = {"ssao": ("off-a", "off-b"), "hbao": ("off-b", "off-c"), "gtao": ("off-c", "off-d")}
gate_fail = 0


def mean_frames(tag):
    pat = os.path.join(dev_dir, f"device-ao-{vant}-{tag}_frames", "f_*.png")
    files = sorted(glob.glob(pat))
    if not files:
        return None, 0
    if len(files) > 3:
        files = files[1:]  # skip recording ramp frame
    acc = None
    for f in files:
        a = np.asarray(Image.open(f).convert("L"), dtype=np.float64)
        acc = a if acc is None else acc + a
    return acc / len(files), len(files)


def ncc(a, b):
    """structure similarity: zero-mean/unit-var NCC on 8x-downscaled images."""
    def prep(x):
        h, w = x.shape
        x = x[: h - h % 8, : w - w % 8].reshape(h // 8, 8, w // 8, 8).mean(axis=(1, 3))
        x = x - x.mean()
        s = x.std()
        return x / s if s > 1e-9 else x
    a, b = prep(a), prep(b)
    return float((a * b).mean())


means = {}
for tag in ["off-a", "off-b", "off-c", "off-d"] + MODES:
    img, n = mean_frames(tag)
    if img is None:
        print(f"[ao-analyze] {vant}/{tag}: NO FRAMES")
        sys.exit(1)
    means[tag] = img
    print(f"[ao-analyze] {vant}/{tag}: {n} frames averaged, mean_luma={img.mean():.2f}")

# --- validity gates ---------------------------------------------------------
print()
pose_ok = True
for tag in ["off-b", "off-c", "off-d"] + MODES:
    c = ncc(means["off-a"], means[tag])
    ok = c >= 0.75
    if not ok:
        pose_ok = False
    print(f"[ao-pose] {vant} off-a vs {tag}: ncc={c:.3f} => {'OK' if ok else 'POSE MISMATCH'}")
if not pose_ok:
    gate_fail += 1
    print(f"[ao-pose] {vant} POSE GATE FAIL — camera moved mid-sequence; luminance verdicts below are VOID")

drift = float(np.abs(means["off-a"] - means["off-d"]).mean())
drift_rel = drift / max(float(means["off-a"].mean()), 1e-6) * 100.0
print(f"[ao-drift] {vant} off-a vs off-d: mean_absdiff={drift:.3f} ({drift_rel:.2f}% of off-a mean)")

# --- darkening stats vs bracketed off --------------------------------------
print()
for m in MODES:
    b0, b1 = BRACKET[m]
    off = (means[b0] + means[b1]) / 2.0
    d = off - means[m]
    dark = np.clip(d, 0, None)
    frac = float((dark > 4.0).mean())
    p99 = float(np.percentile(dark, 99))
    gmean = float(dark.mean())
    thresh = np.percentile(dark, 90)
    loc = float(dark[dark >= thresh].mean() / gmean) if gmean > 1e-6 else 0.0
    print(f"[ao-analyze] {vant} OFF-vs-{m.upper()} (bracket {b0}+{b1}): mean_darkening={gmean:.3f} "
          f"darkened_frac(>4)={frac*100:.2f}% p99={p99:.1f} localization_ratio={loc:.1f}")
    heat = np.clip(dark * 8.0, 0, 255).astype(np.uint8)
    out = os.path.join(dev_dir, f"ao-diffheat-{vant}-{m}.png")
    Image.fromarray(heat).save(out)
    print(f"             heatmap -> {out}")

print()
for i in range(len(MODES)):
    for j in range(i + 1, len(MODES)):
        a, b = MODES[i], MODES[j]
        d = float(np.abs(means[a] - means[b]).mean())
        print(f"[ao-analyze] {vant} {a.upper()}-vs-{b.upper()}: mean_absdiff={d:.3f}")

# --- defect-5 quantified gates ----------------------------------------------
print()
for m in MODES:
    b0, b1 = BRACKET[m]
    off = (means[b0] + means[b1]) / 2.0
    d = np.clip(off - means[m], 0, None)
    thresh = np.percentile(d, 90)
    open_mask = d < thresh
    off_mean = float(off.mean())
    open_rel = float(d[open_mask].mean() / max(off[open_mask].mean(), 1e-6)) * 100.0
    crease_rel = float(d[~open_mask].mean() / max(off[~open_mask].mean(), 1e-6)) * 100.0
    glob_rel = float(d.mean() / max(off_mean, 1e-6)) * 100.0
    ok_open = open_rel <= 5.0
    ok_glob = glob_rel <= 8.0
    ok_loc = crease_rel > open_rel * 1.5
    verdict = "PASS" if (ok_open and ok_glob) else "FAIL"
    if verdict == "FAIL":
        gate_fail += 1
    print(f"[ao-gate5] {vant} {m.upper()}: open_area_delta={open_rel:.2f}% (<=5% {'OK' if ok_open else 'FAIL'}) "
          f"crease_delta={crease_rel:.2f}% localized={'OK' if ok_loc else 'WEAK'} "
          f"global_delta={glob_rel:.2f}% (<=8% {'OK' if ok_glob else 'FAIL'}) => {verdict}")

# --- debug-view (raw AO term) gates ------------------------------------------
MODE_NUM = {"ssao": 1, "hbao": 2, "gtao": 3}
for m in MODES:
    pat = os.path.join(dev_dir, f"device-ao-{vant}-{MODE_NUM[m]}-debugview_frames", "f_*.png")
    files = sorted(glob.glob(pat))
    if not files:
        pat = os.path.join(dev_dir, f"device-ao-{vant}-{m}-debugview_frames", "f_*.png")
        files = sorted(glob.glob(pat))
    if not files:
        print(f"[ao-gate5-debug] {vant} {m.upper()} AO-term view: NO FRAMES => FAIL")
        gate_fail += 1
        continue
    accs = [np.asarray(Image.open(f).convert("L"), dtype=np.float64) for f in files[1:] or files]
    img = sum(accs) / len(accs)
    h = img.shape[0]
    sky = img[: h // 5, :]
    white_frac = float((img > 200).mean())
    dark_frac = float((img < 64).mean())
    ok = white_frac > 0.5 and dark_frac < 0.15 and float(sky.mean()) > 200.0
    print(f"[ao-gate5-debug] {vant} {m.upper()} AO-term view: white_frac={white_frac*100:.1f}% "
          f"dark_frac={dark_frac*100:.1f}% sky_mean={sky.mean():.0f} => {'PASS' if ok else 'FAIL'}")
    if not ok:
        gate_fail += 1

print(f"[ao-gate5] {vant} OVERALL: {'PASS' if gate_fail == 0 else 'FAIL(' + str(gate_fail) + ')'}")
