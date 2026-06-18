#!/usr/bin/env python3
"""Matched-phase frame selector for the OpenGOAL -> Android graphics harness.

Given an ORACLE reference PNG (a specific beat captured from the pristine
upstream v0.3.3 build) and a directory of device BURST frames (dense screencaps
taken across the boot/intro window), pick the burst frame that best matches the
oracle BEAT and copy it to OUT.

WHY: the device and the oracle progress through the intro at different speeds
(the Android loader is slower), so a fixed wall-clock screencap lands on the
WRONG beat (e.g. the attract flythrough instead of the blue-starburst title
card). Matching by visual nearest-frame aligns the BEAT so the downstream
pixel/halo metrics compare apples to apples.

This is an HONEST selector, not a cheat: it only chooses WHICH device frame to
grade (the one showing the same beat as the oracle). The actual grading
(frame_compare diff + halo excess) is done separately and still flags any defect
ON the selected frame. A defect that is an ADDITIVE overlay (e.g. a sun-glow
halo) does not pull the beat-match away from the correct frame -- the dominant
scene structure (gold logo on blue rays) still selects the starburst frame,
and the halo metric then measures the extra brightness on it.

Metric: mean absolute per-channel difference on a small thumbnail (default
64x28), optionally masking rectangles (the device touch overlay the oracle
lacks). Lower = closer.

Usage:
  pick_best_frame.py ORACLE.png BURSTDIR OUT.png
        [--size WxH] [--topk N] [--glob 'f*.png']
        [--ignore-rect X,Y,W,H ...]   # in ORACLE pixel coords (repeatable)
        [--min-dist-report]           # just print ranking, do not copy

Exit 0 on success (OUT written), 2 on usage/load error, 1 if no candidate.
"""
import argparse
import glob
import os
import shutil
import sys

try:
    from PIL import Image
    import numpy as np
except Exception as e:  # pragma: no cover
    sys.stderr.write(f"pick_best_frame: numpy+Pillow required: {e}\n")
    sys.exit(2)


def parse_size(s):
    w, h = s.lower().split("x")
    return int(w), int(h)


def thumb(path, size, mask_rects_oracle, oracle_wh):
    """Load -> RGB -> resize to `size` -> float32 array. Mask rects (given in
    oracle pixel coords) are zeroed in BOTH oracle and candidate so the
    touch-overlay region does not influence the match."""
    img = Image.open(path)
    img.load()
    if img.mode != "RGB":
        img = img.convert("RGB")
    img = img.resize(size, Image.LANCZOS)
    a = np.asarray(img, dtype=np.float32)
    if mask_rects_oracle:
        ow, oh = oracle_wh
        tw, th = size
        sx, sy = tw / float(ow), th / float(oh)
        for (x, y, w, h) in mask_rects_oracle:
            x0 = max(0, int(x * sx)); y0 = max(0, int(y * sy))
            x1 = min(tw, int((x + w) * sx)); y1 = min(th, int((y + h) * sy))
            if x1 > x0 and y1 > y0:
                a[y0:y1, x0:x1, :] = 0.0
    return a


def main(argv):
    ap = argparse.ArgumentParser(description="Pick the burst frame matching the oracle beat.")
    ap.add_argument("oracle")
    ap.add_argument("burstdir")
    ap.add_argument("out")
    ap.add_argument("--size", default="64x28", type=parse_size)
    ap.add_argument("--topk", default=5, type=int)
    ap.add_argument("--glob", default="*.png")
    ap.add_argument("--ignore-rect", action="append", default=[], metavar="X,Y,W,H")
    ap.add_argument("--min-dist-report", action="store_true")
    args = ap.parse_args(argv)

    try:
        ow, oh = Image.open(args.oracle).size
    except Exception as e:
        sys.stderr.write(f"pick_best_frame: cannot open oracle {args.oracle}: {e}\n")
        return 2

    rects = []
    for spec in args.ignore_rect:
        try:
            x, y, w, h = (int(v.strip()) for v in spec.split(","))
            rects.append((x, y, w, h))
        except Exception:
            sys.stderr.write(f"pick_best_frame: bad --ignore-rect '{spec}'\n")
            return 2

    cands = sorted(glob.glob(os.path.join(args.burstdir, args.glob)))
    if not cands:
        sys.stderr.write(f"pick_best_frame: no candidates in {args.burstdir}/{args.glob}\n")
        return 1

    try:
        oref = thumb(args.oracle, args.size, rects, (ow, oh))
    except Exception as e:
        sys.stderr.write(f"pick_best_frame: cannot thumbnail oracle: {e}\n")
        return 2

    scored = []
    for c in cands:
        try:
            ca = thumb(c, args.size, rects, (ow, oh))
        except Exception:
            continue
        d = float(np.mean(np.abs(oref - ca)))
        scored.append((d, c))
    if not scored:
        sys.stderr.write("pick_best_frame: no readable candidates\n")
        return 1
    scored.sort(key=lambda t: t[0])

    print(f"pick_best_frame: oracle={os.path.basename(args.oracle)} "
          f"candidates={len(scored)} size={args.size[0]}x{args.size[1]} "
          f"masks={len(rects)}")
    for i, (d, c) in enumerate(scored[:max(1, args.topk)]):
        print(f"  #{i+1} dist={d:8.3f}  {os.path.basename(c)}")

    best_d, best_c = scored[0]
    if args.min_dist_report:
        print(f"BEST {best_d:.3f} {best_c}")
        return 0
    try:
        shutil.copyfile(best_c, args.out)
    except Exception as e:
        sys.stderr.write(f"pick_best_frame: cannot copy {best_c} -> {args.out}: {e}\n")
        return 2
    print(f"pick_best_frame: BEST dist={best_d:.3f} {os.path.basename(best_c)} -> {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
