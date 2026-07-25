#!/usr/bin/env python3
"""gpbrf_r19_ground2.py — GROUND-BAND delta, DRIFT-CANCELLED, from the mp4 captures.

Why this exists. gpbrf_r19_ground.py's single-still |dL| is unusable here and says so honestly: the
DRIFT FLOOR (two captures of the SAME configuration, first and last) came out at 2.77/255 in boot A
and 5.51/255 in boot B, i.e. larger than or comparable to every signal. At 5-10 fps with animated
foliage, an animated ocean, a live follow-camera and a video encoder between the GPU and the file,
two identical configurations simply do not produce the same pixels. Round 18 hit exactly this and
solved it two ways; both are applied here.

  1. TEMPORAL MEDIAN. Each cell is a 4 s screenrecord, so it holds ~12 frames at fps=3. The median
     over them removes the encoder noise and most of the animation, which a single still cannot.
  2. TEMPORAL STATIC MASK. A pixel whose temporal standard deviation is high in ANY cell is animated
     (foliage, water, Jak's idle) and is dropped: it can never carry a displacement signal.
  3. DRIFT CANCELLATION. The reference configuration is captured TWICE, first (R1) and last (R2),
     with the cell under test between them. So
         SIGNAL = mean | X - (R1 + R2)/2 |     (the drift is common-mode and subtracts out)
         FLOOR  = mean | R1 - R2 | / 2         (everything that changed on its own, halved to the
                                                same time-baseline as the signal)
     A result is only a result when SIGNAL/FLOOR is comfortably above 1.

Here the reference captured twice is the TESSELLATION cell (tess, ..., tess2) and the cells under
test are displacement-OFF and parallax, so the tessellation-vs-OFF delta is measured as
|off - (tess+tess2)/2| — the same quantity, with the drift removed.

GROUND band = the bottom 55-95% of the frame, Rec.709 luma on the 0-255 scale.

Usage:  gpbrf_r19_ground2.py <device-dir>
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


def analyse(tag, tess, off, pom, tess2):
    cells = [tess, off, pom, tess2]
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
    for c, label in ((off, "displacement-OFF"), (pom, "parallax")):
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
    print("--- boot A: pre-subdivision OFF, 6 cm target (the supervisor's configuration) ---")
    A = analyse("A", Cell(d, "A_tess"), Cell(d, "A_off"), Cell(d, "A_pom"), Cell(d, "A_tess2"))
    print()
    print("--- boot B: pre-subdivision ON (1.6 m), 2.5 cm target (round 19) ---")
    B = analyse("B", Cell(d, "B_tess"), Cell(d, "B_off"), Cell(d, "B_pom"), Cell(d, "B_tess2"))
    if A and B:
        a, b = A["A_off"], B["B_off"]
        pa, pb = A["A_pom"], B["B_pom"]
        print()
        print("--- verdict ---")
        print(f"  GROUND BAND DELTA tess vs displacement-OFF: pre-subdivision OFF "
              f"{a[0]:.2f}/255 {a[1]:.1f}% px ({a[2]:.2f}x floor) -> ON {b[0]:.2f}/255 "
              f"{b[1]:.1f}% px ({b[2]:.2f}x floor) = {b[0]/a[0] if a[0]>1e-9 else float('inf'):.2f}x")
        print(f"  for scale, the parallax it replaces, same measurement: OFF-config {pa[0]:.2f}/255 "
              f"{pa[1]:.1f}% px -> ON-config {pb[0]:.2f}/255 {pb[1]:.1f}% px")


if __name__ == "__main__":
    main()
