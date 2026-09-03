#!/usr/bin/env python3
# glp2_measure.py — Grecharged-lightprobes playtest#1/#1b OBJECTIVE metrics.
# Modes (all operate on frame dirs produced by glp_capture.sh / glp2_walk_capture.sh):
#   luma <dir>...                 mean world-crop luma + RGB (same as glp_measure.py)
#   contrast <dir>...             detail/contrast metrics: luma std + Sobel gradient energy
#   gridfft <dir> [cellpx]       ground-band FFT periodicity check (probe damier). Reports the
#                                 strongest spatial peak in the 30..400 px period band vs broadband.
#   flicker <dir>...              temporal instability: mean + p95 of |frame[i+1]-frame[i]| world crop
#   shadowcontrast <dir>...       bottom-decile vs top-decile luma ratio in the ground crop (cast
#                                 shadow visibility: LOWER ratio = shadow clearly darker than lit)
import sys, os, glob
import numpy as np
from PIL import Image

def frames(d, lo_frac=0.35, hi_frac=0.85):
    fs = sorted(glob.glob(os.path.join(d, "*.png")))
    n = len(fs)
    if n == 0:
        return []
    lo, hi = int(n * lo_frac), max(int(n * lo_frac) + 1, int(n * hi_frac))
    return fs[lo:hi] if hi > lo else fs

def world_crop(im):
    h, w, _ = im.shape
    return im[int(h*0.25):int(h*0.75), int(w*0.20):int(w*0.80), :]

def ground_crop(im):
    # lower-middle band: the flat ground in front of the camera (below horizon, above HUD)
    h, w, _ = im.shape
    return im[int(h*0.55):int(h*0.85), int(w*0.15):int(w*0.85), :]

def luma(c):
    return 0.299*c[...,0] + 0.587*c[...,1] + 0.114*c[...,2]

def mode_luma(dirs):
    for d in dirs:
        fs = frames(d)
        if not fs:
            print(f"{os.path.basename(d):30s} NO FRAMES"); continue
        L=R=G=B=0.0
        for f in fs:
            c = world_crop(np.asarray(Image.open(f).convert("RGB")).astype(np.float64))
            r,g,b = c[...,0].mean(), c[...,1].mean(), c[...,2].mean()
            L += 0.299*r+0.587*g+0.114*b; R+=r; G+=g; B+=b
        n=len(fs)
        print(f"{os.path.basename(d):30s} frames={n:3d} luma={L/n:7.3f} R={R/n:6.2f} G={G/n:6.2f} B={B/n:6.2f}")

def mode_contrast(dirs):
    for d in dirs:
        fs = frames(d)
        if not fs:
            print(f"{os.path.basename(d):30s} NO FRAMES"); continue
        stds, grads = [], []
        for f in fs:
            c = luma(world_crop(np.asarray(Image.open(f).convert("RGB")).astype(np.float64)))
            stds.append(c.std())
            gx = np.abs(np.diff(c, axis=1)).mean()
            gy = np.abs(np.diff(c, axis=0)).mean()
            grads.append(gx + gy)
        print(f"{os.path.basename(d):30s} frames={len(fs):3d} luma_std={np.mean(stds):7.3f} grad_energy={np.mean(grads):7.4f}")

def mode_gridfft(dirs):
    # Detect a periodic probe-cell pattern on the GROUND: average the ground-crop luma rows into a
    # 1-D horizontal profile, detrend, FFT; report the strongest peak with period 30..400 px and its
    # ratio over the broadband median. A visible ~4m damier shows as a dominant narrow peak (ratio>6).
    for d in dirs:
        fs = frames(d)
        if not fs:
            print(f"{os.path.basename(d):30s} NO FRAMES"); continue
        ratios, periods = [], []
        for f in fs:
            c = luma(ground_crop(np.asarray(Image.open(f).convert("RGB")).astype(np.float64)))
            prof = c.mean(axis=0)
            prof = prof - np.convolve(prof, np.ones(101)/101, mode="same")  # detrend low-freq
            prof = prof[50:-50]
            if prof.size < 200:
                continue
            sp = np.abs(np.fft.rfft(prof * np.hanning(prof.size)))
            fr = np.fft.rfftfreq(prof.size)
            band = (fr > 1/400.0) & (fr < 1/30.0)
            if not band.any():
                continue
            peak = sp[band].max()
            med = np.median(sp[band]) + 1e-9
            ratios.append(peak / med)
            periods.append(1.0 / fr[band][np.argmax(sp[band])])
        if not ratios:
            print(f"{os.path.basename(d):30s} TOO NARROW"); continue
        print(f"{os.path.basename(d):30s} frames={len(ratios):3d} peak/med={np.mean(ratios):6.2f} "
              f"(max {np.max(ratios):6.2f}) dom_period_px={np.median(periods):6.1f}")

def mode_flicker(dirs):
    # Temporal instability on consecutive frames (same capture => same motion protocol between
    # compared dirs; the DIFFERENCE between probe-ON and probe-OFF isolates probe-induced flicker).
    for d in dirs:
        fs = frames(d, 0.15, 0.95)
        if len(fs) < 3:
            print(f"{os.path.basename(d):30s} NO FRAMES"); continue
        deltas = []
        prev = None
        for f in fs:
            c = luma(world_crop(np.asarray(Image.open(f).convert("RGB")).astype(np.float64)))
            if prev is not None and prev.shape == c.shape:
                deltas.append(np.abs(c - prev).mean())
            prev = c
        deltas = np.array(deltas)
        print(f"{os.path.basename(d):30s} pairs={len(deltas):3d} d_mean={deltas.mean():7.3f} "
              f"d_p95={np.percentile(deltas,95):7.3f} d_std={deltas.std():7.3f}")

def mode_pairdiff(dirs):
    # OWNER #3 gate: per-pixel |diff| between the time-AVERAGED frame of dir A and dir B (both static
    # captures at the SAME deterministic warp vantage). Discriminates the probe-fed MODEL tiers
    # (Hemisphere/SH/IBL differ in the DIRECTIONAL distribution, not necessarily the crop mean —
    # a whole-crop mean can cancel; a per-pixel diff cannot). Reports mean + p95 |dLuma| and mean |dRGB|.
    if len(dirs) < 2:
        print("pairdiff needs >= 2 dirs"); return
    def avg_img(d):
        fs = frames(d)
        if not fs:
            return None
        acc = None
        for f in fs:
            c = world_crop(np.asarray(Image.open(f).convert("RGB")).astype(np.float64))
            acc = c if acc is None else acc + c
        return acc / len(fs)
    imgs = {d: avg_img(d) for d in dirs}
    for i in range(len(dirs)):
        for j in range(i + 1, len(dirs)):
            a, b = imgs[dirs[i]], imgs[dirs[j]]
            na, nb = os.path.basename(dirs[i]), os.path.basename(dirs[j])
            if a is None or b is None or a.shape != b.shape:
                print(f"{na} vs {nb}: NO FRAMES / SHAPE MISMATCH"); continue
            dl = np.abs(luma(a) - luma(b))
            drgb = np.abs(a - b).mean()
            print(f"{na:22s} vs {nb:22s} dLuma_mean={dl.mean():7.3f} dLuma_p95={np.percentile(dl,95):7.3f} dRGB_mean={drgb:7.3f}")

def _gauss1d(sigma):
    r = max(1, int(3.0 * sigma))
    x = np.arange(-r, r + 1, dtype=np.float64)
    k = np.exp(-0.5 * (x / sigma) ** 2)
    return k / k.sum()

def _blur(img, sigma):
    k = _gauss1d(sigma)
    p = len(k) // 2
    a = np.pad(img, ((p, p), (0, 0)), mode="reflect")
    a = np.apply_along_axis(lambda v: np.convolve(v, k, mode="valid"), 0, a)
    a = np.pad(a, ((0, 0), (p, p)), mode="reflect")
    return np.apply_along_axis(lambda v: np.convolve(v, k, mode="valid"), 1, a)

def _paths(d):
    # accept a frame DIR or a single still PNG
    if os.path.isfile(d):
        return [d]
    return frames(d)

def mode_richness(dirs):
    # REOPEN mandate (owner: realtime much flatter than baked): quantify the SPATIAL-FREQUENCY
    # richness of the shading. Per input (dir or single png), on the world-crop luma:
    #   - grad_norm: mean |gradient| / mean luma (exposure-independent local-contrast energy)
    #   - DoG band CONTRAST (std of difference-of-gaussians / mean luma), 3 bands:
    #       high  = luma - blur(s=2)          (~2-8 px structures: texture/albedo detail)
    #       meso  = blur(s=2) - blur(s=8)     (~8-32 px: crevice AO / contact shading — the
    #                                          baked meso-lighting band the probe SH low-passes away)
    #       mid   = blur(s=8) - blur(s=32)    (~32-128 px: macro shading / form)
    # Compare baked (rt OFF) vs realtime (rt ON) at the SAME vantage: if baked shows markedly higher
    # meso/mid contrast, the probe-SH-replaces-baked low-pass hypothesis is CONFIRMED (measured).
    for d in dirs:
        fs = _paths(d)
        if not fs:
            print(f"{os.path.basename(d):30s} NO FRAMES"); continue
        crop = ground_crop if os.environ.get("GROUND") == "1" else world_crop
        gn, hi, me, mi = [], [], [], []
        for f in fs:
            c = luma(crop(np.asarray(Image.open(f).convert("RGB")).astype(np.float64)))
            m = c.mean() + 1e-9
            gx = np.abs(np.diff(c, axis=1)).mean(); gy = np.abs(np.diff(c, axis=0)).mean()
            gn.append((gx + gy) / m * 100.0)
            b2, b8, b32 = _blur(c, 2.0), _blur(c, 8.0), _blur(c, 32.0)
            hi.append((c - b2).std() / m * 100.0)
            me.append((b2 - b8).std() / m * 100.0)
            mi.append((b8 - b32).std() / m * 100.0)
        print(f"{os.path.basename(d):30s} n={len(fs):3d} grad_norm={np.mean(gn):6.3f} "
              f"band_high={np.mean(hi):6.3f} band_meso={np.mean(me):6.3f} band_mid={np.mean(mi):6.3f}"
              f"  (percent local contrast per band)")

def mode_aodarken(dirs):
    # REOPEN AO-burn gate: signed comparison of AO-ON vs AO-OFF statics at the SAME vantage.
    # AO must ONLY DARKEN (multiply <= 1): mean signed dLuma <= 0, ~no pixels brighter ON than
    # OFF, and the darkening must be HUE-PRESERVING (per-channel darkening ratios ~equal; the
    # old per-channel (1-dst) blend crushed B far harder than R = the saturated-warm 'burn').
    if len(dirs) != 2:
        print("aodarken needs exactly 2 inputs: <ao_on> <ao_off>"); return
    def avg_img(d):
        fs = _paths(d)
        if not fs:
            return None
        acc = None
        for f in fs:
            c = world_crop(np.asarray(Image.open(f).convert("RGB")).astype(np.float64))
            acc = c if acc is None else acc + c
        return acc / len(fs)
    on, off = avg_img(dirs[0]), avg_img(dirs[1])
    if on is None or off is None or on.shape != off.shape:
        print("NO FRAMES / SHAPE MISMATCH"); return
    dl = luma(on) - luma(off)
    pos = dl[dl > 0]
    brighter_frac = (dl > 2.0).mean() * 100.0
    # hue preservation among clearly darkened pixels: per-channel ratio spread R vs B
    dark = dl < -2.0
    ratio_spread = float("nan")
    if dark.any():
        eps = 1e-6
        rr = on[..., 0][dark] / np.maximum(off[..., 0][dark], eps)
        rb = on[..., 2][dark] / np.maximum(off[..., 2][dark], eps)
        ratio_spread = np.abs(np.clip(rr, 0, 2) - np.clip(rb, 0, 2)).mean()
    print(f"{os.path.basename(dirs[0]):22s} vs {os.path.basename(dirs[1]):22s} "
          f"dLuma_mean={dl.mean():7.3f} pos_p99={np.percentile(pos, 99) if pos.size else 0.0:6.3f} "
          f"brighter_frac%={brighter_frac:6.3f} dark_frac%={(dark.mean()*100):6.2f} "
          f"hue_ratio_spread_RvsB={ratio_spread:6.4f}")

def mode_shadowcontrast(dirs):
    # Cast-shadow visibility on the ground: ratio of the darkest-decile mean to the brightest-decile
    # mean of the ground crop. A clearly visible cast shadow keeps the ratio LOW; a washed-out
    # shadow pushes it toward 1.0.
    for d in dirs:
        fs = frames(d)
        if not fs:
            print(f"{os.path.basename(d):30s} NO FRAMES"); continue
        ratios = []
        for f in fs:
            c = luma(ground_crop(np.asarray(Image.open(f).convert("RGB")).astype(np.float64))).ravel()
            lo = np.quantile(c, 0.10); hi = np.quantile(c, 0.90)
            dark = c[c <= lo].mean(); lit = c[c >= hi].mean() + 1e-9
            ratios.append(dark / lit)
        print(f"{os.path.basename(d):30s} frames={len(fs):3d} shadow/lit={np.mean(ratios):6.3f} "
              f"(min {np.min(ratios):6.3f})")

if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    mode, dirs = sys.argv[1], sys.argv[2:]
    {"luma": mode_luma, "contrast": mode_contrast, "gridfft": mode_gridfft,
     "flicker": mode_flicker, "shadowcontrast": mode_shadowcontrast,
     "pairdiff": mode_pairdiff, "richness": mode_richness,
     "aodarken": mode_aodarken}[mode](dirs)
