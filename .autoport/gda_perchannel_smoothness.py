#!/usr/bin/env python3
# gda_perchannel_smoothness.py — OWNER PLAYTEST #4 objective gate.
# Measure the yellow<->green sun handoff smoothness PER-CHANNEL (R,G,B), not just luminance.
# For a static-camera tod.fast sweep, the only frame-to-frame change is the LIGHTING, so a whole-frame
# per-channel mean is a robust scene-tone signal. A brutal handoff shows as a LARGE single-frame per-
# channel step; a smooth crossfade shows small, gradual steps. Reports the max per-channel step for each
# frames dir passed, so OLD (attempt-7 narrow ramp) vs NEW (attempt-8 wide ramp + shadow-conf) can be A/B'd.
import sys, os, glob
try:
    from PIL import Image
    import numpy as np
except Exception as e:
    print("need PIL+numpy:", e); sys.exit(2)

def frame_means(d):
    fs = sorted(glob.glob(os.path.join(d, "*.png")))
    out = []
    for f in fs:
        im = Image.open(f).convert("RGB")
        a = np.asarray(im, dtype=np.float32) / 255.0
        out.append((os.path.basename(f), a.reshape(-1,3).mean(axis=0)))  # mean R,G,B in [0,1]
    return out

def analyze(d, label):
    fm = frame_means(d)
    n = len(fm)
    if n < 3:
        print(f"[{label}] {d}: only {n} frames — insufficient"); return None
    R = np.array([m[1] for m in fm])              # n x 3
    names = [m[0] for m in fm]
    dR = np.abs(np.diff(R, axis=0))               # (n-1) x 3 per-channel abs step
    dLum = np.abs(np.diff(R @ np.array([0.2126,0.7152,0.0722])))  # luminance step
    # per-channel max step + where
    print(f"\n===== [{label}] {d}  ({n} frames) =====")
    for ci,cn in enumerate("RGB"):
        col = dR[:,ci]
        i = int(np.argmax(col))
        print(f"  chan {cn}: max step = {col.max()*255:6.2f}/255 (frame {names[i]}->{names[i+1]}), "
              f"mean step = {col.mean()*255:5.2f}/255, p95 = {np.percentile(col,95)*255:5.2f}/255")
    im = int(np.argmax(dR.max(axis=1)))
    worst = dR[im]
    print(f"  >>> WORST any-channel step = {worst.max()*255:.2f}/255 at {names[im]}->{names[im+1]} "
          f"(R={worst[0]*255:.1f} G={worst[1]*255:.1f} B={worst[2]*255:.1f})")
    print(f"  luminance: max step = {dLum.max()*255:.2f}/255, mean = {dLum.mean()*255:.2f}/255 "
          f"(accepted à-coups metric, for cross-ref)")
    # also report the max HUE-ish swing: max step in the (R-G) and (G-B) opponent channels catches a
    # yellow->green shift the per-channel maxes might individually understate.
    opp = np.abs(np.diff(np.stack([R[:,0]-R[:,1], R[:,1]-R[:,2]], axis=1), axis=0))
    print(f"  opponent (R-G, G-B) max step = {opp.max()*255:.2f}/255  <-- the yellow<->green colour-shift metric")
    return {"n":n, "perchan_max":float(dR.max())*255, "lum_max":float(dLum.max())*255,
            "opp_max":float(opp.max())*255, "perchan_p95":float(np.percentile(dR,95))*255}

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("usage: gda_perchannel_smoothness.py <frames_dir> [label] [<frames_dir2> [label2] ...]"); sys.exit(1)
    args = sys.argv[1:]
    res = []
    i = 0
    while i < len(args):
        d = args[i]; lab = args[i+1] if i+1 < len(args) and not os.path.isdir(args[i+1]) else os.path.basename(d.rstrip('/'))
        r = analyze(d, lab)
        if r: res.append((lab, r))
        i += 2 if (i+1 < len(args) and not os.path.isdir(args[i+1])) else 1
    if len(res) >= 2:
        print("\n===== A/B SUMMARY (per-channel max frame-to-frame step, /255) =====")
        for lab,r in res:
            print(f"  {lab:22s} perchan_max={r['perchan_max']:6.2f}  opp(colour)_max={r['opp_max']:6.2f}  "
                  f"lum_max={r['lum_max']:6.2f}  p95={r['perchan_p95']:5.2f}")
