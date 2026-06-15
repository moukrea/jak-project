#!/usr/bin/env python3
"""Fast (numpy) matched-phase frame aligner for the Gtitle-pixelmatch beat.

Same idea as gtitle_match.py but vectorized + thumbnail-cached so we can iterate.
Downscales every frame to a small thumbnail (normalized to 2400x1080, touch-overlay
rects zeroed), caches the thumbnail stack to .npy, then for each device frame finds
the oracle frame minimizing mean per-pixel channel-max delta. Prints the closest
pairs. The winner feeds the REAL gate (frame_compare at full res).
"""
import argparse, os, sys, glob, hashlib
import numpy as np
from PIL import Image, ImageDraw

GOLD_W, GOLD_H = 2400, 1080

def parse_rects(specs):
    out = []
    for s in specs:
        x, y, w, h = (int(v.strip()) for v in s.split(","))
        out.append((x, y, w, h))
    return out

def stack_for(dirpath, globpat, rects, tw, th, min_bytes):
    files = sorted(glob.glob(os.path.join(dirpath, globpat)))
    files = [f for f in files if os.path.getsize(f) >= min_bytes]
    key = hashlib.md5((dirpath + globpat + str(rects) + f"{tw}x{th}" + str(len(files))).encode()).hexdigest()[:12]
    cache = os.path.join("/var/tmp", f"apthumb_{os.path.basename(dirpath.rstrip('/'))}_{key}.npz")
    if os.path.exists(cache):
        d = np.load(cache, allow_pickle=True)
        return list(d["names"]), d["arr"]
    arr = np.empty((len(files), th, tw, 3), dtype=np.uint8)
    names = []
    for i, f in enumerate(files):
        im = Image.open(f).convert("RGB")
        if im.size != (GOLD_W, GOLD_H):
            im = im.resize((GOLD_W, GOLD_H), Image.LANCZOS)
        if rects:
            dr = ImageDraw.Draw(im)
            for (x, y, w, h) in rects:
                dr.rectangle([x, y, x + w - 1, y + h - 1], fill=(0, 0, 0))
        arr[i] = np.asarray(im.resize((tw, th), Image.LANCZOS), dtype=np.uint8)
        names.append(os.path.basename(f))
    np.savez_compressed(cache, names=np.array(names), arr=arr)
    return names, arr

def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--oracle-dir", required=True)
    ap.add_argument("--device-dir", required=True)
    ap.add_argument("--oracle-glob", default="f*.png")
    ap.add_argument("--device-glob", default="r*.png")
    ap.add_argument("--ignore-rect", action="append", default=[])
    ap.add_argument("--thumb", default="160x72")
    ap.add_argument("--top", type=int, default=15)
    ap.add_argument("--device-min-bytes", type=int, default=100000)
    args = ap.parse_args(argv)

    rects = parse_rects(args.ignore_rect)
    tw, th = (int(v) for v in args.thumb.split("x"))
    onames, O = stack_for(args.oracle_dir, args.oracle_glob, rects, tw, th, 1)
    dnames, D = stack_for(args.device_dir, args.device_glob, rects, tw, th, args.device_min_bytes)
    sys.stderr.write(f"oracle {len(onames)} x device {len(dnames)} ({tw}x{th})\n")
    # Flatten to vectors; find closest oracle per device via an L2 distance matrix
    # computed with BLAS: ||o-d||^2 = ||o||^2 + ||d||^2 - 2 o.d  (one matmul).
    # L2 over RGB thumbnails is a fast, reliable pose/lighting-similarity proxy;
    # the WINNER is then verified by the real frame_compare at full res.
    Of = O.reshape(len(onames), -1).astype(np.float32)   # (No,F)
    Df = D.reshape(len(dnames), -1).astype(np.float32)    # (Nd,F)
    on2 = (Of * Of).sum(axis=1)                            # (No,)
    dn2 = (Df * Df).sum(axis=1)                            # (Nd,)
    # dist2[i,j] for oracle i, device j
    cross = Of @ Df.T                                      # (No,Nd)
    dist2 = on2[:, None] + dn2[None, :] - 2.0 * cross
    np.maximum(dist2, 0, out=dist2)
    F = Of.shape[1]
    rms = np.sqrt(dist2 / F)                               # per-pixel-channel RMS delta
    ki = np.argmin(rms, axis=0)                            # best oracle per device
    best = [(float(rms[ki[j], j]), onames[ki[j]], dnames[j]) for j in range(len(dnames))]
    best.sort(key=lambda x: x[0])
    print(f"# top {args.top} matched pairs (score=mean per-pixel chan-max delta, lower=closer)")
    print(f"# {'score':>8}  {'oracle':>14}  device")
    for s, on, dn in best[:args.top]:
        print(f"{s:10.4f}  {on:>14}  {dn}")
    s, on, dn = best[0]
    print(f"\nBEST_ORACLE={on}\nBEST_DEVICE={dn}\nBEST_SCORE={s:.4f}")
    return 0

if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
