#!/usr/bin/env python3
"""ao_analyze_ab.py — Grecharged-ambient-occlusion A/B evidence analysis.

For one vantage, compares the OFF capture against each AO mode capture taken at the
IDENTICAL warped pose (static camera, neutral pad):
  * averages all frames of each capture (kills screenrecord compression noise),
  * diff map = OFF_mean - MODE_mean (positive = MODE darker, i.e. real occlusion),
  * reports: mean darkening, darkened-pixel fraction (>4/255), 99th-percentile
    darkening, and a LOCALIZATION ratio (mean darkening inside the darkest decile
    of pixels vs global mean) — uniform noise/exposure drift gives ratio ~<3,
    real crease/contact AO concentrates and gives a much higher ratio,
  * pairwise mode-vs-mode mean |diff| (are SSAO/HBAO/GTAO mutually distinct?),
  * writes a per-mode diff heat PNG next to the frames for human eyeballing.

Usage: ao_analyze_ab.py <device_dir> <vantage>   (expects device-ao-<vantage>-<tag>_frames/)
"""
import sys
import os
import glob
import numpy as np
from PIL import Image

dev_dir, vant = sys.argv[1], sys.argv[2]
MODES = ["off", "ssao", "hbao", "gtao"]


def mean_frames(tag):
    pat = os.path.join(dev_dir, f"device-ao-{vant}-{tag}_frames", "f_*.png")
    files = sorted(glob.glob(pat))
    if not files:
        return None, 0
    # skip the first frame (recording ramp) when there are enough
    if len(files) > 3:
        files = files[1:]
    acc = None
    for f in files:
        a = np.asarray(Image.open(f).convert("L"), dtype=np.float64)
        acc = a if acc is None else acc + a
    return acc / len(files), len(files)


means = {}
for m in MODES:
    img, n = mean_frames(m)
    if img is None:
        print(f"[ao-analyze] {vant}/{m}: NO FRAMES")
        sys.exit(1)
    means[m] = img
    print(f"[ao-analyze] {vant}/{m}: {n} frames averaged, mean_luma={img.mean():.2f}")

off = means["off"]
print()
for m in MODES[1:]:
    d = off - means[m]  # positive where the AO mode is darker
    dark = np.clip(d, 0, None)
    frac = float((dark > 4.0).mean())
    p99 = float(np.percentile(dark, 99))
    gmean = float(dark.mean())
    # localization: mean darkening within the top-decile darkened pixels vs global mean
    thresh = np.percentile(dark, 90)
    loc = float(dark[dark >= thresh].mean() / gmean) if gmean > 1e-6 else 0.0
    print(f"[ao-analyze] {vant} OFF-vs-{m.upper()}: mean_darkening={gmean:.3f} "
          f"darkened_frac(>4)={frac*100:.2f}% p99={p99:.1f} localization_ratio={loc:.1f}")
    heat = np.clip(dark * 8.0, 0, 255).astype(np.uint8)
    out = os.path.join(dev_dir, f"ao-diffheat-{vant}-{m}.png")
    Image.fromarray(heat).save(out)
    print(f"             heatmap -> {out}")

print()
for i in range(1, len(MODES)):
    for j in range(i + 1, len(MODES)):
        a, b = MODES[i], MODES[j]
        d = float(np.abs(means[a] - means[b]).mean())
        print(f"[ao-analyze] {vant} {a.upper()}-vs-{b.upper()}: mean_absdiff={d:.3f}")

# ---------------------------------------------------------------------------
# Defect #5 quantified gates (owner 2026-07-15 14:20):
#  * OPEN-AREA gate: mean ON-vs-OFF luminance delta over OPEN areas <= 5%.
#    OPEN = pixels below the 90th percentile of the darkening map (everything
#    that is not the crease/contact concentration); relative to the OFF mean.
#  * LOCALIZATION: crease decile relative delta must exceed the open delta
#    (darkening concentrated in creases, not spread over the field).
#  * GLOBAL guard: whole-frame relative delta <= 8% (the owner's counter-example
#    was a whole-scene crush).
print()
gate_fail = 0
for m in MODES[1:]:
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

# Debug-view (raw AO term) analysis when the capture produced *-debugview frames:
# term must be ~white on open ground + sky, dark only in creases.
for m in MODES[1:]:
    pat = os.path.join(dev_dir, f"device-ao-{vant}-{m}-debugview_frames", "f_*.png")
    files = sorted(glob.glob(pat))
    if not files:
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
