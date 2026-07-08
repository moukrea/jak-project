#!/usr/bin/env python3
"""Grecharged-hud-jak1 item-5 (position/scale parity) measurement.

Usage: rhud2_measure.py <shown.png> <hidden.png> <label> [quadrant]
Diffs the two frames, keeps changed pixels in the given screen quadrant
(tl = top-left for the heart, br = bottom-right for the gauge, all = whole
frame), and prints the bounding box + center of the changed region in both
pixels and the game's 512x448 2D space, so the recharged element can be
compared 1:1 against the stock element captured the same way.
"""
import sys

import numpy as np
from PIL import Image


def region(shown, hidden, quad):
    a = np.asarray(Image.open(shown).convert("RGB"), dtype=np.int16)
    b = np.asarray(Image.open(hidden).convert("RGB"), dtype=np.int16)
    if a.shape != b.shape:
        raise SystemExit(f"shape mismatch {a.shape} vs {b.shape}")
    d = np.abs(a - b).sum(axis=2)
    h, w = d.shape
    mask = d > 40  # ignore scene shimmer
    if quad == "tl":
        mask[:, w // 2 :] = False
        mask[h // 2 :, :] = False
    elif quad == "br":
        mask[:, : w // 2] = False
        mask[: h // 2, :] = False
    return mask, w, h


def main():
    shown, hidden, label = sys.argv[1], sys.argv[2], sys.argv[3]
    quad = sys.argv[4] if len(sys.argv) > 4 else "all"
    mask, w, h = region(shown, hidden, quad)
    ys, xs = np.nonzero(mask)
    if len(xs) < 50:
        print(f"{label}: NO significant change ({len(xs)} px)")
        return
    x0, x1, y0, y1 = xs.min(), xs.max(), ys.min(), ys.max()
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    # pixel -> 512x448 2D canvas (canvas stretches to the full window)
    gx, gy = cx * 512 / w, cy * 448 / h
    gw, gh = (x1 - x0) * 512 / w, (y1 - y0) * 448 / h
    print(
        f"{label}: px bbox=({x0},{y0})-({x1},{y1}) center=({cx:.0f},{cy:.0f}) "
        f"npx={len(xs)} | 512x448-space center=({gx:.1f},{gy:.1f}) size=({gw:.1f}x{gh:.1f})"
    )


if __name__ == "__main__":
    main()
