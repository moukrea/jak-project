#!/usr/bin/env python3
"""Match each DEVICE held-beat screencap to the nearest-camera-pose x86 ORACLE
still, then report (a) camera-pose distance at the beat and (b) frame_compare
pixel divergence. Used for the water/green-glow lighting check at static beats.

Device stills are named  <tag>_f<frame>.png  and their pose is looked up in the
device GCINE-CAM log. x86 stills are named autoport_f<frame>.png and their pose
is looked up in the x86 shots GCINE-CAM log.

Usage:
  gcine_beat_match.py --x86log L --x86dir D --devlog L --devdir D [--out DIR]
"""
import argparse
import glob
import math
import os
import re
import subprocess
import sys

ANSI = re.compile(r"\x1b\[[0-9;]*m")
NUM = r"(-?[0-9.eE+]+)"
L = re.compile(r"GCINE-CAM f=(\d+) lvl=(\S+) px=" + NUM + " py=" + NUM + " pz=" + NUM)


def poses(path):
    d = {}
    for ln in open(path, errors="replace"):
        if "GCINE-CAM" not in ln:
            continue
        m = L.search(ANSI.sub("", ln))
        if m:
            d[int(m.group(1))] = (m.group(2), float(m.group(3)), float(m.group(4)), float(m.group(5)))
    return d


def fnum(path):
    m = re.search(r"_f(\d+)\.png$", path) or re.search(r"autoport_f(\d+)\.png$", path)
    return int(m.group(1)) if m else None


def dist3(a, b):
    return math.sqrt(sum((x - y) ** 2 for x, y in zip(a, b)))


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--x86log", required=True)
    ap.add_argument("--x86dir", required=True)
    ap.add_argument("--devlog", required=True)
    ap.add_argument("--devdir", required=True)
    ap.add_argument("--out", default="")
    ap.add_argument("--fc", default=os.path.join(os.path.dirname(__file__), "frame_compare.py"))
    args = ap.parse_args(argv)

    xp = poses(args.x86log)
    dp = poses(args.devlog)
    x86shots = []
    for p in sorted(glob.glob(os.path.join(args.x86dir, "*.png"))):
        fn = fnum(p)
        if fn in xp:
            x86shots.append((p, fn, xp[fn]))
    dev = []
    for p in sorted(glob.glob(os.path.join(args.devdir, "*.png"))):
        if ".diff." in p:
            continue
        fn = fnum(p)
        if fn is not None:
            dev.append((p, fn))
    print(f"# x86 stills with pose: {len(x86shots)}   device beat stills: {len(dev)}")
    if args.out:
        os.makedirs(args.out, exist_ok=True)
    for dpng, dfn in dev:
        dpose = dp.get(dfn)
        if dpose is None:
            print(f"\n[{os.path.basename(dpng)}] frame {dfn}: NO device pose in log — skip")
            continue
        dlvl, *dxyz = dpose
        # nearest x86 still by 3D position among same level (fallback any level)
        cands = [s for s in x86shots if s[2][0] == dlvl] or x86shots
        if not cands:
            print(f"\n[{os.path.basename(dpng)}]: no x86 candidates")
            continue
        best = min(cands, key=lambda s: dist3(s[2][1:], dxyz))
        bp, bfn, bpose = best
        posed = dist3(bpose[1:], dxyz)
        print(f"\n[{os.path.basename(dpng)}] dev f{dfn} lvl={dlvl} pos=({dxyz[0]:.0f},{dxyz[1]:.0f},{dxyz[2]:.0f})")
        print(f"   nearest x86: {os.path.basename(bp)} f{bfn} pos=({bpose[1]:.0f},{bpose[2]:.0f},{bpose[3]:.0f})  pose_dist={posed:.1f}")
        diffout = os.path.join(args.out, os.path.basename(dpng).replace(".png", ".diff.png")) if args.out else None
        cmd = [sys.executable, args.fc, bp, dpng, "--threshold", "56", "--tolerance", "1.0"]
        if diffout:
            cmd += ["--diff", diffout]
        r = subprocess.run(cmd, capture_output=True, text=True)
        print("   " + (r.stdout.strip() or r.stderr.strip()))


if __name__ == "__main__":
    main(sys.argv[1:])
