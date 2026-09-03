#!/usr/bin/env python3
"""gda_itemAB_analyze.py — objective metrics for owner playtest #2 ITEM A + ITEM B.

ITEM B (day/night smoothness): over a tod.fast sweep at a STATIC camera, the only frame-to-frame change
is the lighting. A "brutal step" (snapshot-basis switch) is a single-frame JUMP in the world's mean
luminance. We measure the per-frame delta of the WORLD-crop mean luma (sky excluded) and report the MAX
single-frame step, both absolute and as a fraction of the full-cycle luma range. Compare smooth vs raw.

ITEM A: tone-match (mean RGB of rt-on vs stock-baked) and contrast (luma percentile spread) of a still.

Usage:
  gda_itemAB_analyze.py sweep    <frames_dir>
  gda_itemAB_analyze.py sweepcmp <raw_dir> <smooth_dir>
  gda_itemAB_analyze.py tone     <dir>              # mean RGB (world crop)
  gda_itemAB_analyze.py contrast <dir>              # luma spread + near-white frac
"""
import sys, os, glob
import numpy as np
from PIL import Image

# WORLD crop: drop the top sky band and the very bottom HUD strip; keep the lit geometry.
CY0, CY1, CX0, CX1 = 0.30, 0.90, 0.08, 0.92

def load_lumas(d):
    """Return (frames_rgb_mean list, luma_series np.array) over the world crop, one entry per frame."""
    files = sorted(glob.glob(os.path.join(d, "f_*.png")))
    if not files:
        raise SystemExit(f"no frames in {d}")
    lumas, rgbs = [], []
    for f in files:
        a = np.asarray(Image.open(f).convert("RGB"), dtype=np.float64)
        H, W, _ = a.shape
        crop = a[int(CY0*H):int(CY1*H), int(CX0*W):int(CX1*W), :]
        rgbs.append(crop.reshape(-1, 3).mean(0))
        L = 0.299*crop[..., 0] + 0.587*crop[..., 1] + 0.114*crop[..., 2]
        lumas.append(float(L.mean()))
    return np.array(rgbs), np.array(lumas), files

def sweep_metrics(d):
    rgbs, L, files = load_lumas(d)
    d1 = np.abs(np.diff(L))
    rng = float(L.max() - L.min())
    maxstep = float(d1.max()) if len(d1) else 0.0
    imax = int(np.argmax(d1)) if len(d1) else 0
    p99 = float(np.percentile(d1, 99)) if len(d1) else 0.0
    frac = (maxstep / rng) if rng > 1e-6 else 0.0
    # count "brutal" steps: single-frame deltas that are a big chunk (>25%) of the whole-cycle range
    brutal = int(np.sum(d1 > 0.25*rng)) if rng > 1e-6 else 0
    return dict(n=len(L), Lmin=float(L.min()), Lmax=float(L.max()), rng=rng,
                maxstep=maxstep, maxstep_at=imax, maxstep_frac=frac, p99=p99,
                brutal=brutal, mean_d=float(d1.mean()) if len(d1) else 0.0,
                worst_pair=(files[imax].split('/')[-1], files[imax+1].split('/')[-1]) if len(d1) else ('','') )

def print_sweep(tag, m):
    print(f"[{tag}] frames={m['n']}  world-luma cycle range=[{m['Lmin']:.1f}..{m['Lmax']:.1f}] (span {m['rng']:.1f})")
    print(f"        MAX single-frame step = {m['maxstep']:.2f} luma  = {100*m['maxstep_frac']:.1f}% of the cycle range")
    print(f"        p99 step = {m['p99']:.2f}   mean step = {m['mean_d']:.3f}   BRUTAL steps(>25% range) = {m['brutal']}")
    print(f"        worst step between {m['worst_pair'][0]} -> {m['worst_pair'][1]}")

def main():
    if len(sys.argv) < 3:
        print(__doc__); raise SystemExit(2)
    cmd = sys.argv[1]
    if cmd == "sweep":
        print_sweep(os.path.basename(sys.argv[2].rstrip('/')), sweep_metrics(sys.argv[2]))
    elif cmd == "sweepcmp":
        raw = sweep_metrics(sys.argv[2]); sm = sweep_metrics(sys.argv[3])
        print_sweep("RAW  (todsmooth 0, the BEFORE)", raw)
        print_sweep("SMOOTH (todsmooth 0.10, the FIX)", sm)
        if raw['maxstep'] > 1e-6:
            print(f"\n==> max-step REDUCED {raw['maxstep']:.2f} -> {sm['maxstep']:.2f} luma "
                  f"({raw['maxstep']/max(sm['maxstep'],1e-6):.2f}x smaller); "
                  f"brutal steps {raw['brutal']} -> {sm['brutal']}")
    elif cmd == "tone":
        rgbs, L, _ = load_lumas(sys.argv[2])
        m = rgbs.mean(0)
        print(f"[tone] {os.path.basename(sys.argv[2].rstrip('/'))}: mean RGB = "
              f"({m[0]:.1f}, {m[1]:.1f}, {m[2]:.1f})  luma={0.299*m[0]+0.587*m[1]+0.114*m[2]:.1f}  "
              f"warmth(R-B)={m[0]-m[2]:+.1f}")
    elif cmd == "contrast":
        rgbs, L, _ = load_lumas(sys.argv[2])
        # per-frame luma percentiles averaged; contrast proxy = P90/P10 and std
        files = sorted(glob.glob(os.path.join(sys.argv[2], "f_*.png")))
        p10s, p90s, stds, nw = [], [], [], []
        for f in files:
            a = np.asarray(Image.open(f).convert("RGB"), dtype=np.float64)
            H, W, _ = a.shape
            c = a[int(CY0*H):int(CY1*H), int(CX0*W):int(CX1*W), :]
            Ll = 0.299*c[..., 0] + 0.587*c[..., 1] + 0.114*c[..., 2]
            p10s.append(np.percentile(Ll, 10)); p90s.append(np.percentile(Ll, 90))
            stds.append(Ll.std()); nw.append(float((Ll > 245).mean()))
        p10, p90, sd, nwf = np.mean(p10s), np.mean(p90s), np.mean(stds), np.mean(nw)
        print(f"[contrast] {os.path.basename(sys.argv[2].rstrip('/'))}: P10={p10:.1f} P90={p90:.1f} "
              f"spread(P90-P10)={p90-p10:.1f}  ratio(P90/P10)={p90/max(p10,1e-6):.2f}  std={sd:.1f}  "
              f"near-white-frac={nwf:.4f}")
    else:
        print(__doc__); raise SystemExit(2)

if __name__ == "__main__":
    main()
