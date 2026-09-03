#!/usr/bin/env python3
"""Matched-phase frame aligner for the Gtitle-pixelmatch beat.

The title flythrough orbits the camera AND cycles day<->night AND blinks
"PRESS START", and the device's slow loader desyncs frame counts, so no fixed
frame number aligns the device and the pristine oracle. This brute-forces the
alignment: it downscales every oracle frame and every device frame to a small
thumbnail (after normalizing to the golden's 2400x1080 and zeroing the phone's
touch-overlay rects so they don't bias the match), then for every (oracle,
device) pair computes a cheap visual distance and reports the closest pairs.

The winning pair is the matched-phase (golden, device-title) to feed the REAL
gate (frame_compare.py at full res + mask + calibrated threshold). This script
only PICKS the pair; it does not decide MATCH/MISMATCH.
"""
import argparse, os, sys, glob
from PIL import Image, ImageChops, ImageDraw

GOLD_W, GOLD_H = 2400, 1080

def parse_rects(specs):
    rects = []
    for s in specs:
        x, y, w, h = (int(v.strip()) for v in s.split(","))
        rects.append((x, y, w, h))
    return rects

def load_thumb(path, rects, tw, th):
    img = Image.open(path); img.load()
    if img.mode != "RGB":
        img = img.convert("RGB")
    if img.size != (GOLD_W, GOLD_H):
        img = img.resize((GOLD_W, GOLD_H), Image.LANCZOS)
    if rects:
        d = ImageDraw.Draw(img)
        for (x, y, w, h) in rects:
            d.rectangle([x, y, x + w - 1, y + h - 1], fill=(0, 0, 0))
    return img.resize((tw, th), Image.LANCZOS)

def maxdelta_score(a, b):
    # per-pixel max(|dR|,|dG|,|dB|) summed -> mean per-pixel channel-max distance
    diff = ImageChops.difference(a, b)
    r, g, bb = diff.split()
    m = ImageChops.lighter(ImageChops.lighter(r, g), bb)
    hist = m.histogram()
    total = sum(hist)
    if total == 0:
        return 0.0
    weighted = sum(i * c for i, c in enumerate(hist))
    return weighted / total

def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--oracle-dir", required=True)
    ap.add_argument("--device-dir", required=True)
    ap.add_argument("--oracle-glob", default="f*.png")
    ap.add_argument("--device-glob", default="d*.png")
    ap.add_argument("--ignore-rect", action="append", default=[])
    ap.add_argument("--thumb", default="120x54")
    ap.add_argument("--top", type=int, default=15)
    ap.add_argument("--device-min-bytes", type=int, default=200000,
                    help="skip tiny device frames (black/early-boot)")
    args = ap.parse_args(argv)

    rects = parse_rects(args.ignore_rect)
    tw, th = (int(v) for v in args.thumb.split("x"))

    ofiles = sorted(glob.glob(os.path.join(args.oracle_dir, args.oracle_glob)))
    dfiles = sorted(glob.glob(os.path.join(args.device_dir, args.device_glob)))
    dfiles = [f for f in dfiles if os.path.getsize(f) >= args.device_min_bytes]
    if not ofiles or not dfiles:
        sys.stderr.write(f"no frames (oracle={len(ofiles)} device={len(dfiles)})\n")
        return 2
    sys.stderr.write(f"loading {len(ofiles)} oracle + {len(dfiles)} device thumbs ({tw}x{th})...\n")

    othumbs = [(os.path.basename(f), load_thumb(f, rects, tw, th)) for f in ofiles]
    dthumbs = [(os.path.basename(f), load_thumb(f, rects, tw, th)) for f in dfiles]

    pairs = []
    for dn, dt in dthumbs:
        best = None
        for on, ot in othumbs:
            s = maxdelta_score(ot, dt)
            if best is None or s < best[0]:
                best = (s, on)
        pairs.append((best[0], best[1], dn))
    pairs.sort(key=lambda p: p[0])

    print(f"# top {args.top} matched pairs (score = mean per-pixel channel-max delta, lower=closer)")
    print(f"# {'score':>8}  {'oracle':>14}  device")
    for s, on, dn in pairs[:args.top]:
        print(f"{s:10.4f}  {on:>14}  {dn}")
    s, on, dn = pairs[0]
    print(f"\nBEST_ORACLE={on}\nBEST_DEVICE={dn}\nBEST_SCORE={s:.4f}")
    return 0

if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
