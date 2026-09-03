#!/usr/bin/env python3
# gda_perchannel_smoothness.py — OWNER PLAYTEST #4 objective gate (WORLD-CROP per-channel).
#
# Owner playtest #4: the yellow-sun <-> green-sun handoff is a brutal COLOUR shift (yellow -> green) that
# the earlier LUMINANCE-only metric missed. This measures the handoff smoothness PER-CHANNEL (R,G,B) so a
# hue jump shows up.
#
# CRITICAL FIX vs the first attempt-8 version: it measured the WHOLE frame. Over a tod.fast sweep the SKY +
# distant WATER (upper ~half of the frame) are drawn by the STOCK sky/ocean renderers — NOT the realtime
# sun/green-sun lighting path — and they undergo large stock dawn/dusk colour transitions that dominate a
# whole-frame mean. That pollutes the per-channel step with sky motion the crossfade cannot and must not
# touch. So we apply the SAME WORLD CROP the owner-accepted luminance analysis (gda_itemAB_analyze.py) uses
# — drop the top sky band + bottom HUD + side edges — to isolate the LIT GEOMETRY (rocks/huts/ground), which
# is exactly the surface whose yellow<->green handoff the owner sees.
#
# Metrics per frames dir (static camera => the only in-crop change is the LIGHTING on geometry):
#   - per-channel R,G,B mean over the world crop, per frame
#   - per-channel MAX frame-to-frame step (a brutal handoff = one big single-frame step)
#   - opponent (R-G, G-B) MAX step = the yellow<->green colour-shift metric
#   - BRUTAL per-channel step count: single-frame steps > 25% of that channel's full-cycle range
#     (capture-phase-robust — same basis as the accepted luminance "brutal step" count, so two DIFFERENT
#      captures at unaligned tod phases are still comparable: it asks "does ANY single frame jump hard?")
import sys, os, glob
try:
    from PIL import Image
    import numpy as np
except Exception as e:
    print("need PIL+numpy:", e); sys.exit(2)

# WORLD crop identical to the owner-accepted gda_itemAB_analyze.py (sky + HUD + edges excluded).
CY0, CY1, CX0, CX1 = 0.30, 0.90, 0.08, 0.92

def frame_means(d):
    fs = sorted(glob.glob(os.path.join(d, "*.png")))
    out = []
    for f in fs:
        a = np.asarray(Image.open(f).convert("RGB"), dtype=np.float32)
        H, W, _ = a.shape
        c = a[int(CY0*H):int(CY1*H), int(CX0*W):int(CX1*W), :] / 255.0
        out.append((os.path.basename(f), c.reshape(-1, 3).mean(axis=0)))  # mean R,G,B in [0,1] over crop
    return out

def analyze(d, label):
    fm = frame_means(d)
    n = len(fm)
    if n < 3:
        print(f"[{label}] {d}: only {n} frames — insufficient"); return None
    R = np.array([m[1] for m in fm])              # n x 3
    names = [m[0] for m in fm]
    dR = np.abs(np.diff(R, axis=0))               # (n-1) x 3 per-channel abs step
    dLum = np.abs(np.diff(R @ np.array([0.2126, 0.7152, 0.0722])))  # luminance step
    rng = R.max(axis=0) - R.min(axis=0)           # per-channel full-cycle range (3,)
    # BRUTAL per-channel steps: single-frame delta > 25% of that channel's whole-cycle range.
    brutal = int(np.sum(dR > (0.25 * rng)[None, :]))
    print(f"\n===== [{label}] {d}  ({n} frames, WORLD crop y[{CY0:.2f}:{CY1:.2f}] x[{CX0:.2f}:{CX1:.2f}]) =====")
    for ci, cn in enumerate("RGB"):
        col = dR[:, ci]
        i = int(np.argmax(col))
        print(f"  chan {cn}: max step = {col.max()*255:6.2f}/255 (frame {names[i]}->{names[i+1]}), "
              f"mean = {col.mean()*255:5.2f}, p95 = {np.percentile(col,95)*255:5.2f}, "
              f"cycle-range = {rng[ci]*255:6.1f}")
    im = int(np.argmax(dR.max(axis=1)))
    worst = dR[im]
    print(f"  >>> WORST any-channel step = {worst.max()*255:.2f}/255 at {names[im]}->{names[im+1]} "
          f"(R={worst[0]*255:.1f} G={worst[1]*255:.1f} B={worst[2]*255:.1f})")
    print(f"  luminance: max step = {dLum.max()*255:.2f}/255, mean = {dLum.mean()*255:.2f}/255 "
          f"(accepted à-coups metric, for cross-ref)")
    opp = np.abs(np.diff(np.stack([R[:, 0]-R[:, 1], R[:, 1]-R[:, 2]], axis=1), axis=0))
    print(f"  opponent (R-G, G-B) max step = {opp.max()*255:.2f}/255  <-- the yellow<->green colour-shift metric")
    print(f"  BRUTAL per-channel steps (single-frame > 25% of that channel's cycle range) = {brutal}")
    return {"n": n, "perchan_max": float(dR.max())*255, "lum_max": float(dLum.max())*255,
            "opp_max": float(opp.max())*255, "perchan_p95": float(np.percentile(dR, 95))*255,
            "brutal": brutal}

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
        print("\n===== A/B SUMMARY (WORLD-crop per-channel max frame-to-frame step, /255) =====")
        for lab, r in res:
            print(f"  {lab:22s} perchan_max={r['perchan_max']:6.2f}  opp(colour)_max={r['opp_max']:6.2f}  "
                  f"lum_max={r['lum_max']:6.2f}  p95={r['perchan_p95']:5.2f}  brutal_perchan_steps={r['brutal']}")
