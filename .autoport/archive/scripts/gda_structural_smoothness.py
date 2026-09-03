#!/usr/bin/env python3
# gda_structural_smoothness.py — OWNER PLAYTEST #5 objective gate (STRUCTURAL per-pixel + per-channel).
#
# Owner playtest #5 (CORRECTED diagnosis): the brutal sun<->green-sun handoff is the shading ORIENTATION
# snapping ~180deg (the key light AND the ambient's directional bias), NOT a colour/mean step. A MEAN or a
# per-channel-MEAN metric AVERAGES AWAY an orientation flip (the bright side moves from one wall to the
# opposite wall — the frame mean barely changes while every pixel changes). So the correct metric is a
# STRUCTURAL, per-pixel one, measured frame-to-frame across the sunset->dark->green-rise transition:
#   (1) per-pixel MEAN-ABS diff:  mean over the world crop of |f[i+1]-f[i]|  (abs BEFORE the mean =>
#       an orientation flip does NOT cancel; a real spike at the handoff shows up here even when the mean is
#       flat).
#   (2) block-SSIM structural change:  1 - meanSSIM(f[i], f[i+1])  over 8x8 windows (structural similarity;
#       an orientation flip destroys local structure => 1-SSIM spikes).
# Also carries the PLAYTEST #4 per-channel (R,G,B) + opponent(R-G,G-B) mean step for the colour-crossfade
# gate (so a single sweep proves both the #5 orientation smoothness and the #4 per-channel smoothness).
#
# The camera is STATIC (level.warp + neutral stick) and the sun is PINNED per hour-step, so between two
# consecutive pinned-hour frames the ONLY change is the LIGHTING on the geometry => the structural step IS
# the lighting-orientation change. WORLD crop (sky/HUD/edges excluded) identical to the owner-accepted
# gda_itemAB_analyze.py / gda_perchannel_smoothness.py, so this isolates the lit rocks/huts/ground.
#
# usage: gda_structural_smoothness.py <frames_dir> [label] [<frames_dir2> [label2] ...]
import sys, os, glob
try:
    from PIL import Image
    import numpy as np
except Exception as e:
    print("need PIL+numpy:", e); sys.exit(2)

CY0, CY1, CX0, CX1 = 0.30, 0.90, 0.08, 0.92   # WORLD crop (sky + HUD + edges excluded)
BLK = 8                                        # SSIM window
C1 = (0.01) ** 2                               # SSIM constants on the [0,1] scale
C2 = (0.03) ** 2

def load_crop(f):
    a = np.asarray(Image.open(f).convert("RGB"), dtype=np.float32)
    H, W, _ = a.shape
    return a[int(CY0*H):int(CY1*H), int(CX0*W):int(CX1*W), :] / 255.0   # (h,w,3) in [0,1]

def block_ssim(g0, g1):
    # mean SSIM over non-overlapping BLK x BLK windows of two grayscale [0,1] frames.
    h, w = g0.shape
    h -= h % BLK; w -= w % BLK
    if h < BLK or w < BLK:
        return 1.0
    a = g0[:h, :w].reshape(h//BLK, BLK, w//BLK, BLK).transpose(0, 2, 1, 3).reshape(-1, BLK*BLK)
    b = g1[:h, :w].reshape(h//BLK, BLK, w//BLK, BLK).transpose(0, 2, 1, 3).reshape(-1, BLK*BLK)
    ma, mb = a.mean(1), b.mean(1)
    va, vb = a.var(1), b.var(1)
    cov = ((a - ma[:, None]) * (b - mb[:, None])).mean(1)
    ssim = ((2*ma*mb + C1) * (2*cov + C2)) / ((ma*ma + mb*mb + C1) * (va + vb + C2))
    return float(ssim.mean())

def analyze(d, label):
    fs = sorted(glob.glob(os.path.join(d, "*.png")))
    if len(fs) < 3:
        print(f"[{label}] {d}: only {len(fs)} frames — insufficient"); return None
    crops = [load_crop(f) for f in fs]
    names = [os.path.basename(f) for f in fs]
    gray = [c @ np.array([0.299, 0.587, 0.114], dtype=np.float32) for c in crops]
    n = len(crops)
    means = np.stack([c.reshape(-1, 3).mean(0) for c in crops])   # n x 3 (R,G,B)
    # BRIGHTNESS/COLOUR-NORMALIZED frames: divide each frame by its own per-channel crop mean so every frame
    # has unit mean per channel. This REMOVES the TOD brightness/colour ENVELOPE (day->night level + hue
    # shift, which is IDENTICAL in the ambfade A/B and is NOT what the fix touches) and leaves ONLY the
    # SPATIAL PATTERN = the shading ORIENTATION. An orientation SNAP survives this normalization (the bright
    # side jumps to a different wall => the normalized pattern changes) while a pure level/colour ramp cancels.
    norm = [crops[i] / np.maximum(means[i][None, None, :], 1e-4) for i in range(n)]
    perpix = np.zeros(n-1); ssimc = np.zeros(n-1); npix = np.zeros(n-1)
    for i in range(n-1):
        perpix[i] = float(np.abs(crops[i+1] - crops[i]).mean())    # per-pixel mean-abs diff (structural, RAW)
        npix[i] = float(np.abs(norm[i+1] - norm[i]).mean())        # per-pixel mean-abs diff (BRIGHTNESS-NORMALIZED = orientation)
        ssimc[i] = 1.0 - block_ssim(gray[i], gray[i+1])            # structural change 1-SSIM
    dchan = np.abs(np.diff(means, axis=0))                          # (n-1) x 3 per-channel mean step
    opp = np.abs(np.diff(np.stack([means[:,0]-means[:,1], means[:,1]-means[:,2]], axis=1), axis=0))
    ip = int(np.argmax(perpix)); iss = int(np.argmax(ssimc)); inn = int(np.argmax(npix))
    # outlier check: is the worst structural step an OUTLIER vs the typical (median) step?
    med = float(np.median(perpix)) if np.median(perpix) > 1e-6 else 1e-6
    nmed = float(np.median(npix)) if np.median(npix) > 1e-6 else 1e-6
    print(f"\n===== [{label}] {d}  ({n} frames, WORLD crop, STRUCTURAL per-pixel) =====")
    print(f"  [RAW] per-pixel MEAN-ABS diff: MAX step = {perpix.max()*255:6.2f}/255 "
          f"({names[ip]}->{names[ip+1]}), median = {med*255:5.2f}, p95 = {np.percentile(perpix,95)*255:5.2f}, "
          f"MAX/median outlier = {perpix.max()/med:4.1f}x  (dominated by the TOD brightness envelope)")
    print(f"  [ORIENT] BRIGHTNESS-NORMALIZED per-pixel MEAN-ABS diff (isolates the shading ORIENTATION): "
          f"MAX = {npix.max()*1000:6.2f}e-3 ({names[inn]}->{names[inn+1]}), median = {nmed*1000:5.2f}e-3, "
          f"p95 = {np.percentile(npix,95)*1000:5.2f}e-3, MAX/median outlier = {npix.max()/nmed:4.1f}x")
    print(f"  block-SSIM structural change (1-SSIM): MAX = {ssimc.max():.4f} ({names[iss]}->{names[iss+1]}), "
          f"median = {np.median(ssimc):.4f}, p95 = {np.percentile(ssimc,95):.4f}")
    for ci, cn in enumerate("RGB"):
        col = dchan[:, ci]; j = int(np.argmax(col))
        print(f"  per-channel {cn}: max mean step = {col.max()*255:6.2f}/255 ({names[j]}->{names[j+1]})")
    print(f"  opponent (R-G,G-B) max step = {opp.max()*255:.2f}/255  <-- yellow<->green colour-shift metric")
    return {"perpix_max": float(perpix.max())*255, "perpix_med": med*255,
            "perpix_ratio": float(perpix.max()/med), "ssim_max": float(ssimc.max()),
            "npix_max": float(npix.max())*1000, "npix_ratio": float(npix.max()/nmed),
            "perchan_max": float(dchan.max())*255, "opp_max": float(opp.max())*255, "n": n}

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("usage: gda_structural_smoothness.py <frames_dir> [label] ..."); sys.exit(1)
    args = sys.argv[1:]; res = []; i = 0
    while i < len(args):
        d = args[i]
        lab = args[i+1] if i+1 < len(args) and not os.path.isdir(args[i+1]) else os.path.basename(d.rstrip('/'))
        r = analyze(d, lab)
        if r: res.append((lab, r))
        i += 2 if (i+1 < len(args) and not os.path.isdir(args[i+1])) else 1
    if len(res) >= 2:
        print("\n===== A/B SUMMARY (WORLD-crop STRUCTURAL per-pixel + per-channel, /255) =====")
        for lab, r in res:
            print(f"  {lab:26s} RAW perpix_max={r['perpix_max']:6.2f}  ORIENT(norm)_max={r['npix_max']:6.2f}e-3 "
                  f"(outlier {r['npix_ratio']:4.1f}x)  1-SSIM_max={r['ssim_max']:.4f}  "
                  f"perchan_max={r['perchan_max']:6.2f}  opp_max={r['opp_max']:6.2f}")
        print("  (ORIENT(norm) is the brightness-normalized per-pixel diff = the shading-orientation metric; "
              "lower = smoother orientation. RAW/perchan/opp are dominated by the shared TOD/direct-sun envelope.)")
