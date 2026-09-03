#!/usr/bin/env python3
"""gpbrf_r19_ground.py — GROUND-BAND delta between displacement modes, in the supervisor's units.

The supervisor's 2026-07-25 device measurement that reopened this phase reported, on the GROUND
band at the owner's vantage:

    tessellation vs displacement-OFF : mean 0.77/255, 4.6% of pixels
    parallax     vs displacement-OFF : mean 2.27/255, 14.5% of pixels

Its harness did not survive, so this reproduces the metric explicitly and, more importantly,
measures BOTH configurations inside one comparison so the conclusion does not depend on a number
nobody can re-derive:

    boot A = pre-subdivision OFF, 6 cm target  (what the supervisor measured)
    boot B = pre-subdivision ON,  2.5 cm target (round 19)

Units, stated so they can be checked: Rec.709 luma on the 0-255 scale, letterbox/black columns and
rows excluded, GROUND band = the bottom 55-95% of the frame height (the same crop the round-18
metrics used, where the owner's grass/sand is). "pixels changed" = |dL| >= 1.0 of 255, i.e. at
least one display level.

Every pair is reported against the DRIFT FLOOR of that same boot: the reference cell is captured
twice, first and last, and |dL| between those two is everything the follow-cam, the foliage and the
encoder contribute on their own. A signal below its own floor is not a signal.

Usage:  gpbrf_r19_ground.py <device-dir>
        expects <dir>/{A_tess,A_off,A_tess2,B_tess,B_off,B_tess2}.png (missing cells are skipped)
"""
import sys
import os
import numpy as np
from PIL import Image

GROUND_LO, GROUND_HI = 0.55, 0.95  # fraction of frame height
CHANGED_EPS = 1.0                  # 0-255 levels
BLACK_EPS = 6.0                    # a row/column this dark everywhere is letterbox, not content


def luma(path):
    a = np.asarray(Image.open(path).convert("RGB"), dtype=np.float64)
    return 0.2126 * a[:, :, 0] + 0.7152 * a[:, :, 1] + 0.0722 * a[:, :, 2]


def ground_crop(y):
    h, w = y.shape
    r0, r1 = int(h * GROUND_LO), int(h * GROUND_HI)
    return y[r0:r1, :]


def content_mask(*ys):
    """Columns/rows that are black in EVERY image are letterbox; drop them from the statistic."""
    m = np.zeros_like(ys[0], dtype=bool)
    for y in ys:
        m |= y > BLACK_EPS
    return m


def pair(name, a_path, b_path):
    if not (os.path.exists(a_path) and os.path.exists(b_path)):
        print(f"{name:28s} SKIP (missing cell)")
        return None
    ya, yb = ground_crop(luma(a_path)), ground_crop(luma(b_path))
    if ya.shape != yb.shape:
        print(f"{name:28s} SKIP (size mismatch {ya.shape} vs {yb.shape})")
        return None
    m = content_mask(ya, yb)
    d = np.abs(ya - yb)[m]
    if d.size == 0:
        print(f"{name:28s} SKIP (no content pixels)")
        return None
    mean = float(d.mean())
    p95 = float(np.percentile(d, 95))
    changed = float((d >= CHANGED_EPS).mean() * 100.0)
    print(f"{name:28s} mean={mean:6.3f}/255  p95={p95:6.3f}  changed={changed:5.2f}%  n={d.size}")
    return mean, changed, p95


def main():
    d = sys.argv[1] if len(sys.argv) > 1 else "."
    p = lambda n: os.path.join(d, n + ".png")
    print("##### GROUND BAND DELTA (rows %.0f-%.0f%% of frame height, Rec.709 luma 0-255) #####"
          % (GROUND_LO * 100, GROUND_HI * 100))
    print()
    out = {}
    print("--- boot A: pre-subdivision OFF, 6 cm target (the supervisor's configuration) ---")
    out["A_floor"] = pair("A drift floor tess vs tess", p("A_tess"), p("A_tess2"))
    out["A_tess"] = pair("A tess vs displacement-OFF", p("A_tess"), p("A_off"))
    out["A_pom"] = pair("A parallax vs disp-OFF", p("A_pom"), p("A_off"))
    print()
    print("--- boot B: pre-subdivision ON (1.6 m), 2.5 cm target (round 19) ---")
    out["B_floor"] = pair("B drift floor tess vs tess", p("B_tess"), p("B_tess2"))
    out["B_tess"] = pair("B tess vs displacement-OFF", p("B_tess"), p("B_off"))
    out["B_pom"] = pair("B parallax vs disp-OFF", p("B_pom"), p("B_off"))
    print()
    print("--- verdict (signal / its own boot's drift floor) ---")
    for boot in ("A", "B"):
        f = out.get(boot + "_floor")
        for k, label in ((boot + "_tess", "tessellation"), (boot + "_pom", "parallax")):
            v = out.get(k)
            if not v or not f:
                continue
            ratio = v[0] / f[0] if f[0] > 1e-9 else float("inf")
            print(f"  boot {boot} {label:12s}: mean {v[0]:6.3f}/255 ({v[1]:5.2f}% px) "
                  f"vs floor {f[0]:6.3f} -> {ratio:5.2f}x")
    a, b = out.get("A_tess"), out.get("B_tess")
    if a and b:
        print()
        print(f"  GROUND BAND DELTA tess vs displacement-OFF: pre-subdivision OFF "
              f"{a[0]:.2f}/255 {a[1]:.1f}% px -> ON {b[0]:.2f}/255 {b[1]:.1f}% px "
              f"({b[0] / a[0] if a[0] > 1e-9 else float('inf'):.2f}x mean, "
              f"{b[1] / a[1] if a[1] > 1e-9 else float('inf'):.2f}x area)")


if __name__ == "__main__":
    main()
