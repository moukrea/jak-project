#!/usr/bin/env python3
"""gpbrf_r22_coverage.py — ROUND 22 DEFECT A: per-PIXEL screen coverage breakdown.

The owner's complaint is "la plupart des endroits n'ont toujours pas de displacement du
tout".  A per-MATERIAL percentage cannot answer that: 14 materials out of 24 tells you
nothing about how much of the SCREEN is displaced.  This classifies a real device frame
pixel by pixel.

Two frames of the SAME vantage are required:
  * mode 30 (PROGRAM TAG)      — every world/actor program paints a flat identifying colour
  * mode 31 (DISPLACEMENT TAG) — white where the fragment actually receives displacement

The tag colours are chosen with a minimum pairwise L2 distance of 127/255 so they survive
the H.264 round-trip that `screenrecord` forces on us (screencap is black on the GL
surface — see feedback_device_capture_positioning).  Anything further than TOL from every
tag is counted as UNCLASSIFIED rather than being snapped to the nearest tag: a silently
mis-snapped pixel would inflate exactly the number the owner is judging.

Usage:
  gpbrf_r22_coverage.py --prog tag30.png --disp tag31.png [--label NAME] [--tol 48]
"""
import argparse
import sys

try:
    from PIL import Image
except ImportError:
    sys.exit("PIL/Pillow required: python3 -m pip install --user Pillow")

import numpy as np

# (name, rgb, is_world) — is_world marks the static-world programs that CAN be displaced.
# Actors (merc2/generic/emerc) are tracked separately: the owner requires the actor share to
# be quantified even though they are excluded from the displacement port.
TAGS = [
    ("tfrag3_tess", (255, 255, 0), True),   # yellow — tessellated tfrag draw
    ("tfrag3", (255, 0, 0), True),          # red    — plain tfrag3 (incl. TIE non-envmap)
    ("etie_base", (0, 255, 0), True),       # green
    ("tie_wind", (0, 255, 255), True),      # cyan
    ("shrub", (0, 0, 255), True),           # blue
    ("hfrag", (255, 128, 0), True),         # orange
    ("merc2", (255, 0, 255), False),        # magenta — actors
    ("generic", (128, 0, 255), False),      # violet  — actors
    ("emerc", (128, 255, 0), False),        # lime    — actors
]


def classify(img, tol):
    """Return (labels, dist) where labels indexes TAGS or -1 for unclassified."""
    a = np.asarray(img.convert("RGB"), dtype=np.float32)
    h, w, _ = a.shape
    flat = a.reshape(-1, 3)
    ref = np.array([t[1] for t in TAGS], dtype=np.float32)
    # (N, T) euclidean distance to every tag
    d = np.linalg.norm(flat[:, None, :] - ref[None, :, :], axis=2)
    best = np.argmin(d, axis=1)
    bd = d[np.arange(flat.shape[0]), best]
    labels = np.where(bd <= tol, best, -1)
    return labels.reshape(h, w), bd.reshape(h, w)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--prog", required=True, help="mode-30 program-tag frame")
    ap.add_argument("--disp", required=True, help="mode-31 displacement-tag frame")
    ap.add_argument("--label", default="")
    ap.add_argument("--tol", type=float, default=48.0)
    ap.add_argument("--disp-thresh", type=float, default=128.0,
                    help="luma above which a mode-31 pixel counts as displaced")
    args = ap.parse_args()

    pimg = Image.open(args.prog)
    dimg = Image.open(args.disp)
    if pimg.size != dimg.size:
        sys.exit(f"size mismatch: prog {pimg.size} vs disp {dimg.size}")

    labels, _ = classify(pimg, args.tol)
    dv = np.asarray(dimg.convert("RGB"), dtype=np.float32).mean(axis=2)
    displaced = dv >= args.disp_thresh

    total = labels.size
    print(f"=== PER-PIXEL SCREEN COVERAGE {args.label} ===")
    print(f"frame {pimg.size[0]}x{pimg.size[1]} = {total} pixels, tag tolerance {args.tol:.0f}/255")
    print()
    print(f"{'program':<14} {'pixels':>9} {'% screen':>9} {'displaced':>10} {'% of prog':>10}")
    print("-" * 58)

    world_px = 0
    world_disp = 0
    actor_px = 0
    for i, (name, _rgb, is_world) in enumerate(TAGS):
        m = labels == i
        n = int(m.sum())
        if n == 0:
            continue
        nd = int((m & displaced).sum())
        if is_world:
            world_px += n
            world_disp += nd
        else:
            actor_px += n
        print(f"{name:<14} {n:>9} {100.0*n/total:>8.2f}% {nd:>10} "
              f"{(100.0*nd/n if n else 0):>9.2f}%")

    unc = int((labels == -1).sum())
    print("-" * 58)
    print(f"{'UNCLASSIFIED':<14} {unc:>9} {100.0*unc/total:>8.2f}%"
          "   (sky, water, sprites, HUD, blended)")
    print()
    print(f"WORLD pixels (displaceable programs) : {world_px} "
          f"({100.0*world_px/total:.2f}% of screen)")
    print(f"ACTOR pixels (merc2/generic/emerc)   : {actor_px} "
          f"({100.0*actor_px/total:.2f}% of screen)")
    if world_px:
        pct = 100.0 * world_disp / world_px
        print()
        print(f"HEADLINE: displacement coverage {pct:.2f}% of world pixels "
              f"({world_disp}/{world_px})")
    else:
        print("HEADLINE: no world pixels classified — capture is invalid")


if __name__ == "__main__":
    main()
