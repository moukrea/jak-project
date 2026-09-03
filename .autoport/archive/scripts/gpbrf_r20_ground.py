#!/usr/bin/env python3
"""gpbrf_r20_ground.py — GROUND-BAND delta, DRIFT-CANCELLED, from the mp4 captures (round 20).

Same metric, same conditioning and the same honesty about its own noise floor as
gpbrf_r19_ground2.py, which established that a single still cannot measure this at 5-10 fps with
animated foliage, a live follow-camera and a video encoder in the path:

  1. TEMPORAL MEDIAN over the ~12 frames of each 4 s capture.
  2. TEMPORAL STATIC MASK: a pixel animated in ANY cell is dropped.
  3. DRIFT CANCELLATION: the tessellation cell is captured twice, first and last, so
        SIGNAL = mean | X - (tess1 + tess2)/2 |     and     FLOOR = mean | tess1 - tess2 | / 2.
     A result is only a result when SIGNAL/FLOOR is comfortably above 1.

What is new in round 20 is the third cell: the LEGACY law (bisect bit 67108864 restores
WORLD_TILES_PER_M 0.5 + TESS_DISP_K 14336) is captured in the SAME boot at the SAME vantage, so the
before/after of this round is measured, not remembered. Both are reported against displacement-OFF.

GROUND band = the bottom 55-95% of the frame, Rec.709 luma on the 0-255 scale.

Usage:  gpbrf_r20_ground.py <device-dir>
"""
import os
import subprocess
import sys
import tempfile

import numpy as np
from PIL import Image

GROUND_LO, GROUND_HI = 0.55, 0.95
FPS = 3
STD_MAX = 4.0      # 0-255 levels of temporal std above which a pixel is "animated"
CHANGED_EPS = 1.0  # 0-255 levels
BLACK_EPS = 6.0


def frames_of(mp4):
    if not os.path.exists(mp4):
        return None
    with tempfile.TemporaryDirectory() as td:
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", mp4,
                        "-vf", f"fps={FPS}", os.path.join(td, "f_%03d.png")], check=False)
        fs = sorted(f for f in os.listdir(td) if f.endswith(".png"))
        if len(fs) < 3:
            return None
        arr = []
        for f in fs:
            a = np.asarray(Image.open(os.path.join(td, f)).convert("RGB"), dtype=np.float64)
            arr.append(0.2126 * a[:, :, 0] + 0.7152 * a[:, :, 1] + 0.0722 * a[:, :, 2])
    return np.stack(arr, axis=0)


class Cell:
    def __init__(self, d, name):
        st = frames_of(os.path.join(d, name + ".mp4"))
        self.name = name
        self.ok = st is not None
        if self.ok:
            self.med = np.median(st, axis=0)
            self.std = st.std(axis=0)
            self.n = st.shape[0]


def band(y):
    h = y.shape[0]
    return y[int(h * GROUND_LO):int(h * GROUND_HI), :]


def analyse(tag, tess, off, pom, tess2, leg=None):
    cells = [tess, off, pom, tess2] + ([leg] if leg is not None else [])
    if not all(c.ok for c in cells):
        print(f"boot {tag}: SKIP (missing {[c.name for c in cells if not c.ok]})")
        return None
    shapes = {c.med.shape for c in cells}
    if len(shapes) != 1:
        print(f"boot {tag}: SKIP (shape mismatch {shapes})")
        return None
    med = {c.name: band(c.med) for c in cells}
    std = {c.name: band(c.std) for c in cells}
    mask = np.ones_like(med[tess.name], dtype=bool)
    for c in cells:
        mask &= std[c.name] < STD_MAX
        mask &= med[c.name] > BLACK_EPS
    ref = 0.5 * (med[tess.name] + med[tess2.name])
    floor_img = np.abs(med[tess.name] - med[tess2.name]) * 0.5
    floor = float(floor_img[mask].mean())
    print(f"boot {tag}: frames/cell={[c.n for c in cells]}  static pixels={mask.mean()*100:5.2f}% "
          f"({int(mask.sum())} of {mask.size})")
    print(f"  DRIFT FLOOR |tess - tess2|/2                 = {floor:6.3f}/255")
    out = {"floor": floor}
    pairs = [(off, "displacement-OFF"), (pom, "parallax")]
    if leg is not None:
        pairs.append((leg, "LEGACY-law tess"))
    for c, label in pairs:
        d = np.abs(med[c.name] - ref)[mask]
        mean = float(d.mean())
        changed = float((d >= CHANGED_EPS).mean() * 100.0)
        p95 = float(np.percentile(d, 95))
        ratio = mean / floor if floor > 1e-9 else float("inf")
        print(f"  tessellation vs {label:17s} mean={mean:6.3f}/255  p95={p95:6.3f}  "
              f"changed={changed:5.2f}%  signal/floor={ratio:5.2f}x")
        out[c.name] = (mean, changed, ratio)
    return out



def main():
    d = sys.argv[1] if len(sys.argv) > 1 else "."
    print("##### GROUND BAND DELTA, DRIFT-CANCELLED (rows %.0f-%.0f%%, Rec.709 luma 0-255) #####"
          % (GROUND_LO * 100, GROUND_HI * 100))
    print()
    print("--- boot R: the REAL recharged materials, round-20 uv-density + feature-size laws ---")
    R = analyse("R", Cell(d, "R_tess"), Cell(d, "R_off"), Cell(d, "R_pom"), Cell(d, "R_tess2"),
                Cell(d, "R_tessleg"))
    print()
    print("--- boot C: the in-build CHECKERBOARD, same metric (the pattern is synthetic here, so")
    print("    the absolute numbers are only comparable within this boot) ---")
    C = analyse("C", Cell(d, "C_tess"), Cell(d, "C_off"), Cell(d, "C_pom"), Cell(d, "C_tess2"),
                Cell(d, "C_tessleg"))
    for tag, res, off_k, leg_k, pom_k in (("R", R, "R_off", "R_tessleg", "R_pom"),
                                          ("C", C, "C_off", "C_tessleg", "C_pom")):
        if not res:
            continue
        o = res.get(off_k)
        l = res.get(leg_k)
        p = res.get(pom_k)
        print()
        print(f"--- verdict, boot {tag} ---")
        if o:
            print(f"  round-20 tessellation vs displacement-OFF: {o[0]:.2f}/255  {o[1]:.1f}% px  "
                  f"({o[2]:.2f}x its own drift floor)")
        if p:
            print(f"  parallax        vs displacement-OFF: {p[0]:.2f}/255  {p[1]:.1f}% px")
        if l:
            print(f"  round-20 tessellation vs the LEGACY law (same boot, same vantage): "
                  f"{l[0]:.2f}/255  {l[1]:.1f}% px  ({l[2]:.2f}x floor)")
            print("  (a large legacy-vs-new delta means the two laws displace visibly differently;")
            print("   WHICH of them matches the painted feature is what gpbrf_r20_checker.py decides.)")


if __name__ == "__main__":
    main()
