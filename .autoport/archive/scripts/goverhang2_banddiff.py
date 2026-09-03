#!/usr/bin/env python3
"""goverhang2_banddiff.py — localized lip-band pixel diff (Grecharged-grass-overhang2).

Same objective method as round 1: whole-frame diffs drown in breeze noise, so we
measure the changed-pixel fraction inside a TIGHT crop around the lip faces, and
compare an ON-vs-OFF (or default-vs-tuned) pair against a cross-boot ON-vs-ON
noise floor at the same vantage.

Usage: goverhang2_banddiff.py A.png B.png x y w h thr out_overlay.png
Prints: band=WxH changed=N frac=F (pixels whose max-channel abs delta > thr)
"""
import sys

import numpy as np
from PIL import Image

def main():
    a_path, b_path = sys.argv[1], sys.argv[2]
    x, y, w, h = (int(v) for v in sys.argv[3:7])
    thr = int(sys.argv[7])
    out = sys.argv[8] if len(sys.argv) > 8 else None
    a = np.asarray(Image.open(a_path).convert("RGB"), dtype=np.int16)[y:y + h, x:x + w]
    b = np.asarray(Image.open(b_path).convert("RGB"), dtype=np.int16)[y:y + h, x:x + w]
    if a.shape != b.shape:
        print(f"ERROR shape mismatch {a.shape} vs {b.shape}")
        sys.exit(2)
    d = np.abs(a - b).max(axis=2)
    changed = int((d > thr).sum())
    total = d.size
    print(f"band={w}x{h}@{x},{y} thr={thr} changed={changed} total={total} "
          f"frac={changed / total:.4f}")
    if out:
        overlay = np.asarray(Image.open(a_path).convert("RGB"), dtype=np.uint8).copy()
        mask = np.zeros(overlay.shape[:2], dtype=bool)
        mask[y:y + h, x:x + w] = d > thr
        overlay[mask] = [255, 0, 255]
        # draw the band rectangle
        overlay[y:y + h, x] = [255, 255, 0]
        overlay[y:y + h, min(x + w - 1, overlay.shape[1] - 1)] = [255, 255, 0]
        overlay[y, x:x + w] = [255, 255, 0]
        overlay[min(y + h - 1, overlay.shape[0] - 1), x:x + w] = [255, 255, 0]
        Image.fromarray(overlay).save(out)

if __name__ == "__main__":
    main()
