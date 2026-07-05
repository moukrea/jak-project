#!/usr/bin/env python3
"""Gperf-particles2 — SYNTHETIC DEFECT INJECTOR (detector self-test).

The on-device known-bad controls (overlap ON / pingpong ON) do NOT reproduce the
owner's pop/flicker on the Redmi Adreno 618 (the bug is device-specific — same
class as the Snapdragon-only swamp crash), so they cannot, by themselves, prove
detect.py is SENSITIVE on this hardware. This tool injects a KNOWN defect of the
exact shape the owner reported into a REAL clean recording's frames, so detect.py
can be shown to fire on it (and stay quiet on the un-injected base). If the check
can't see an injected defect, it is worthless — this is the step v5 skipped.

Two defect modes, applied deterministically to a copy of a frames dir:

  --mode pop      : blank a central rectangle to BLACK for ONE frame every --period
                    frames (geometry "vanished then returned" = a transient revert).
  --mode flicker  : multiply every frame's RGB by an ALTERNATING (1 +/- amp) global
                    factor (a +/-amp luma sawtooth = TOD palette oscillation).

Usage:
  synthetic_inject.py <src_frames_dir> <dst_frames_dir> --mode pop|flicker
                      [--period 20] [--amp 0.12] [--rect 0.5]
"""
import argparse, glob, os, sys
import numpy as np
from PIL import Image


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("dst")
    ap.add_argument("--mode", required=True, choices=["pop", "flicker"])
    ap.add_argument("--period", type=int, default=20, help="pop: inject every N frames")
    ap.add_argument("--amp", type=float, default=0.12, help="flicker: +/- luma fraction")
    ap.add_argument("--rect", type=float, default=0.5, help="pop: central rect size (frac)")
    args = ap.parse_args()

    paths = sorted(glob.glob(os.path.join(args.src, "*.png")))
    if len(paths) < 5:
        sys.exit(f"[inject] need >=5 png in {args.src}, found {len(paths)}")
    os.makedirs(args.dst, exist_ok=True)

    injected = 0
    for k, p in enumerate(paths):
        im = np.asarray(Image.open(p).convert("RGB"), dtype=np.float32)
        if args.mode == "pop":
            # single-frame central black hole every `period` frames (skip frame 0)
            if k > 0 and k % args.period == 0:
                H, W, _ = im.shape
                rh, rw = int(H * args.rect), int(W * args.rect)
                y0, x0 = (H - rh) // 2, (W - rw) // 2
                im[y0:y0 + rh, x0:x0 + rw, :] = 0.0
                injected += 1
        else:  # flicker: alternating +/- amp global luma sawtooth
            factor = 1.0 + args.amp if (k % 2 == 0) else 1.0 - args.amp
            im = im * factor
            injected += 1
        out = np.clip(im, 0, 255).astype(np.uint8)
        Image.fromarray(out).save(os.path.join(args.dst, os.path.basename(p)))

    print(f"[inject] mode={args.mode} frames={len(paths)} injected={injected} "
          f"(period={args.period} amp={args.amp} rect={args.rect}) -> {args.dst}")


if __name__ == "__main__":
    main()
