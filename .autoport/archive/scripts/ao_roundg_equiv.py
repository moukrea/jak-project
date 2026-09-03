#!/usr/bin/env python3
"""ao_roundg_equiv.py — round G ladder-shift equivalence proof (owner 2026-07-16 22:20).

Compares the NEW-ladder strengthgrid run (device/) against the archived ROUND-F
old-ladder run (device/roundg-baseline/), both captured by ao_capture.sh strengthgrid
at the same training warp pose with per-trio fresh boots + same-boot off brackets.

Gates:
  * SSAO untouched: every strength's off-normalized crease delta matches the baseline
    rung-for-rung (new weak==old weak, new def==old def, new strong==old strong).
  * HBAO/GTAO shifted one notch DOWN: new Default matches OLD WEAKER, new Stronger
    matches OLD DEFAULT — and each is CLOSER to its target rung than to the adjacent
    old rung (rung discrimination, robust to cross-boot noise).
  * Pose gate: cross-build NCC >= 0.75 on every compared pair (same warp pose).
  * Direct-pixel check (the "byte-similar" mandate): mean abs luma diff of each
    equivalence pair <= 2x the cross-build noise floor + 1.0 (floor = mean abs diff of
    the two builds' own off-pre segments, which are IDENTICAL renders by construction).

Usage: ao_roundg_equiv.py <device_dir>   (baseline at <device_dir>/roundg-baseline)
"""
import glob
import os
import sys

import numpy as np
from PIL import Image

dev_dir = sys.argv[1]
base_dir = os.path.join(dev_dir, "roundg-baseline")
MODES = ["ssao", "hbao", "gtao"]
STRENGTHS = ["weak", "def", "strong"]
fail = 0


def mean_frames(d, tag):
    files = sorted(glob.glob(os.path.join(d, f"device-ao-strengthgrid-{tag}_frames", "f_*.png")))
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
    def prep(x):
        h, w = x.shape
        x = x[: h - h % 8, : w - w % 8].reshape(h // 8, 8, w // 8, 8).mean(axis=(1, 3))
        x = x - x.mean()
        s = x.std()
        return x / s if s > 1e-9 else x
    a, b = prep(a), prep(b)
    return float((a * b).mean())


def seg_time(d, tag):
    try:
        return os.path.getmtime(os.path.join(d, f"device-ao-strengthgrid-{tag}.mp4"))
    except OSError:
        return None


def load_grid(d, label):
    m = {}
    for mode in MODES:
        for tag in [f"{mode}-off-pre", f"{mode}-off-post"] + [f"{mode}-{s}" for s in STRENGTHS]:
            img, n = mean_frames(d, tag)
            if img is None:
                print(f"[roundg-equiv] {label}/{tag}: NO FRAMES => FAIL")
                sys.exit(1)
            m[tag] = img
    return m


def off_pred(d, grid, mode, seg_tag):
    b0, b1 = f"{mode}-off-pre", f"{mode}-off-post"
    t0, t1, tt = seg_time(d, b0), seg_time(d, b1), seg_time(d, seg_tag)
    if t0 is None or t1 is None or tt is None or t1 <= t0:
        return (grid[b0] + grid[b1]) / 2.0
    w = min(max((tt - t0) / (t1 - t0), 0.0), 1.0)
    return grid[b0] * (1.0 - w) + grid[b1] * w


def crease_rel(d, grid, mode, s):
    seg = f"{mode}-{s}"
    off = off_pred(d, grid, mode, seg)
    dd = np.clip(off - grid[seg], 0, None)
    thresh = np.percentile(dd, 90)
    cr = float(dd[dd >= thresh].mean() / max(off[dd >= thresh].mean(), 1e-6)) * 100.0
    op = float(dd[dd < thresh].mean() / max(off[dd < thresh].mean(), 1e-6)) * 100.0
    gl = float(dd.mean() / max(float(off.mean()), 1e-6)) * 100.0
    return cr, op, gl


new = load_grid(dev_dir, "new")
old = load_grid(base_dir, "old")

# cross-build noise floor: off-pre segments render the IDENTICAL scene on both builds
floors = {}
for mode in MODES:
    t = f"{mode}-off-pre"
    floors[mode] = float(np.abs(new[t] - old[t]).mean())
    c = ncc(new[t], old[t])
    print(f"[roundg-noise] {mode} off-pre new-vs-old: mean_absdiff={floors[mode]:.2f} "
          f"luma, ncc={c:.3f}{' POSE MISMATCH' if c < 0.75 else ''}")
    if c < 0.75:
        fail += 1

print()
cr = {}
for run, d, grid in (("new", dev_dir, new), ("old", base_dir, old)):
    for mode in MODES:
        for s in STRENGTHS:
            cr[(run, mode, s)] = crease_rel(d, grid, mode, s)
            c, o, g = cr[(run, mode, s)]
            print(f"[roundg-grid] {run} {mode} {s}: crease={c:.2f}% open={o:.2f}% global={g:.2f}%")

# (target_old_rung, wrong_adjacent_old_rung) per new rung
PAIRS = {
    "ssao": [("weak", "weak", "def"), ("def", "def", "weak"), ("strong", "strong", "def")],
    "hbao": [("def", "weak", "def"), ("strong", "def", "strong")],
    "gtao": [("def", "weak", "def"), ("strong", "def", "strong")],
}
print()
for mode, plist in PAIRS.items():
    for new_s, tgt_s, wrong_s in plist:
        cn = cr[("new", mode, new_s)][0]
        ct = cr[("old", mode, tgt_s)][0]
        cw = cr[("old", mode, wrong_s)][0]
        tol = max(1.5, 0.25 * ct)
        close = abs(cn - ct) <= tol
        # rung discrimination only meaningful when the two old rungs actually differ
        disc = (abs(cn - ct) <= abs(cn - cw)) or (abs(ct - cw) < 1.0)
        ok = close and disc
        if not ok:
            fail += 1
        print(f"[roundg-equiv] {mode}: new {new_s} ({cn:.2f}%) vs old {tgt_s} ({ct:.2f}%) "
              f"|d|={abs(cn-ct):.2f} tol={tol:.2f} (adjacent old {wrong_s}={cw:.2f}%) "
              f"=> {'PASS' if ok else 'FAIL'}")
        # direct-pixel "byte-similar" check for the shifted modes' equivalence pairs
        if mode != "ssao" or new_s == tgt_s:
            a, b = new[f"{mode}-{new_s}"], old[f"{mode}-{tgt_s}"]
            dpix = float(np.abs(a - b).mean())
            cap = 2.0 * floors[mode] + 1.0
            pok = dpix <= cap
            if not pok:
                fail += 1
            print(f"[roundg-pixel] {mode} new-{new_s} vs old-{tgt_s}: mean_absdiff="
                  f"{dpix:.2f} luma (noise-floor cap {cap:.2f}) => {'PASS' if pok else 'FAIL'}")

print(f"\n[roundg-equiv] OVERALL: {'PASS' if fail == 0 else f'FAIL ({fail} gate(s))'}")
sys.exit(0 if fail == 0 else 1)
