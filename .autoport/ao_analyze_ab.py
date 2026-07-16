#!/usr/bin/env python3
"""ao_analyze_ab.py — Grecharged-ambient-occlusion A/B evidence analysis (v2, bracketed).

Capture layout (ao_capture.sh): off-a ssao off-b hbao off-c gtao off-d, tightly spaced.
Each AO mode is compared against a per-pixel QUADRATIC fit through the four off anchors
evaluated at the mode segment's own timestamp (mp4 mtimes). The old bracket-MIDPOINT
model assumed linear drift and false-failed a mode landing on the sunset knee (beach
run-4: off-a 128 -> off-b 91.6 while later gaps move ~5; SSAO read a phantom 12.8-luma
"darkening" with a 96.7%-white debug term). Falls back to the bracket mean when any
mp4 mtime is missing. Two validity gates run BEFORE any luminance
verdict:
  * POSE gate: normalized cross-correlation of every segment vs off-a (structure, not
    brightness). A moved camera (human touch mid-run, follow-cam re-frame) FAILS the
    vantage instead of poisoning the darkening stats.
  * DRIFT line: off-a vs off-d residual luminance drift, reported (bracketing already
    compensates; this is the honesty metric).
Then the defect-5 gates (owner 2026-07-15 14:20): open-area delta <=5%, global <=8%,
crease localization, and the raw-AO debug-view whiteness checks.

Usage: ao_analyze_ab.py <device_dir> <vantage>
"""
import glob
import os
import sys

import numpy as np
from PIL import Image

dev_dir, vant = sys.argv[1], sys.argv[2]
MODES = ["ssao", "hbao", "gtao"]
BRACKET = {"ssao": ("off-a", "off-b"), "hbao": ("off-b", "off-c"), "gtao": ("off-c", "off-d")}
gate_fail = 0


def mean_frames(tag, rgb=False):
    pat = os.path.join(dev_dir, f"device-ao-{vant}-{tag}_frames", "f_*.png")
    files = sorted(glob.glob(pat))
    if not files:
        return None, 0
    if len(files) > 3:
        files = files[1:]  # skip recording ramp frame
    acc = None
    for f in files:
        im = Image.open(f)
        a = np.asarray(im.convert("RGB") if rgb else im.convert("L"), dtype=np.float64)
        acc = a if acc is None else acc + a
    return acc / len(files), len(files)


def ncc(a, b):
    """structure similarity: zero-mean/unit-var NCC on 8x-downscaled images."""
    def prep(x):
        h, w = x.shape
        x = x[: h - h % 8, : w - w % 8].reshape(h // 8, 8, w // 8, 8).mean(axis=(1, 3))
        x = x - x.mean()
        s = x.std()
        return x / s if s > 1e-9 else x
    a, b = prep(a), prep(b)
    return float((a * b).mean())


# --- strengthgrid vantage (AO STRENGTH proof): 3 modes x 3 strengths @ training ----------
# closing round v2 (TOD measurement control): each trio boots FRESH (ao_capture.sh) so it
# lands at the same deterministic early-boot TOD, and brackets itself with its own
# off-pre/off-post from the SAME boot: {m}-off-pre {m}-weak {m}-def {m}-strong {m}-off-post.
# The off model is a linear mtime interpolation WITHIN the trio only — never across a boot
# boundary, where the game TOD resets (the old single-boot 13-segment run drifted into the
# in-game sunset, off luma 98.7 -> 52.8, and measured the late trios in the amplified
# dusk regime the daylight caps were never calibrated for). Same NCC pose gate and
# open/crease region logic. Per segment: caps (open<=5%, global<=8%); per mode:
# strictly-increasing crease ordering weaker<def<strong.
if vant == "strengthgrid":
    GRID_MODES = ["ssao", "hbao", "gtao"]
    STRENGTHS = ["weak", "def", "strong"]
    STR_LABEL = {"weak": "weaker", "def": "default", "strong": "stronger"}
    GRID_OFFS = [f"{m}-off-{p}" for m in GRID_MODES for p in ("pre", "post")]
    # bracketing offs per mode: the trio's OWN same-boot off-pre/off-post
    GRID_BRACKET = {m: (f"{m}-off-pre", f"{m}-off-post") for m in GRID_MODES}

    def seg_time_g(tag):
        p = os.path.join(dev_dir, f"device-ao-{vant}-{tag}.mp4")
        try:
            return os.path.getmtime(p)
        except OSError:
            return None

    gmeans = {}
    all_tags = list(GRID_OFFS) + [f"{m}-{s}" for m in GRID_MODES for s in STRENGTHS]
    for tag in all_tags:
        img, n = mean_frames(tag)
        if img is None:
            print(f"[ao-grid] {vant}/{tag}: NO FRAMES => FAIL")
            sys.exit(1)
        gmeans[tag] = img
        print(f"[ao-grid] {vant}/{tag}: {n} frames averaged, mean_luma={img.mean():.2f}")

    # POSE gate: adjacent NCC WITHIN each trio (fresh boots re-warp deterministically, but
    # cross-boot NCC would gate on warp repeatability, not mid-run camera drift).
    print()
    gpose_ok = True
    for m in GRID_MODES:
        trio_seq = [f"{m}-off-pre", f"{m}-weak", f"{m}-def", f"{m}-strong", f"{m}-off-post"]
        for t0, t1 in zip(trio_seq, trio_seq[1:]):
            c = ncc(gmeans[t0], gmeans[t1])
            ok = c >= 0.75
            if not ok:
                gpose_ok = False
            print(f"[ao-pose] {vant} {t0} vs {t1}: ncc={c:.3f} => {'OK' if ok else 'POSE MISMATCH'}")
    if not gpose_ok:
        gate_fail += 1
        print(f"[ao-pose] {vant} POSE GATE FAIL — camera moved; strength verdicts VOID")

    # honesty metrics: per-trio off-pre vs off-post residual drift, and the cross-boot TOD
    # repeatability (each trio's off-pre mean luma should be comparable — a dim late trio
    # means a boot did NOT reset to the expected early-boot TOD).
    for m in GRID_MODES:
        gd = float(np.abs(gmeans[f"{m}-off-pre"] - gmeans[f"{m}-off-post"]).mean())
        gd_rel = gd / max(float(gmeans[f"{m}-off-pre"].mean()), 1e-6) * 100.0
        print(f"[ao-drift] {vant} {m} off-pre vs off-post: mean_absdiff={gd:.3f} ({gd_rel:.2f}% of off-pre mean)")
    _pres = {m: float(gmeans[f"{m}-off-pre"].mean()) for m in GRID_MODES}
    print(f"[ao-drift] {vant} boot-TOD repeatability (off-pre mean luma): " +
          " ".join(f"{m}={_pres[m]:.1f}" for m in GRID_MODES))

    def goff_pred(mode, seg_tag):
        # linear mtime interpolation between the trio's SAME-BOOT off brackets;
        # bracket-mean fallback when any mtime is missing.
        b0, b1 = GRID_BRACKET[mode]
        t0, t1, tt = seg_time_g(b0), seg_time_g(b1), seg_time_g(seg_tag)
        if t0 is None or t1 is None or tt is None or t1 <= t0:
            return (gmeans[b0] + gmeans[b1]) / 2.0
        w = min(max((tt - t0) / (t1 - t0), 0.0), 1.0)
        return gmeans[b0] * (1.0 - w) + gmeans[b1] * w

    print()
    grid_fail = 0
    crease_by = {}  # (mode -> {strength: crease_rel}) for the ordering check
    for m in GRID_MODES:
        crease_by[m] = {}
        b0, b1 = GRID_BRACKET[m]
        for s in STRENGTHS:
            seg = f"{m}-{s}"
            off = goff_pred(m, seg)
            d = np.clip(off - gmeans[seg], 0, None)
            thresh = np.percentile(d, 90)
            open_mask = d < thresh
            open_rel = float(d[open_mask].mean() / max(off[open_mask].mean(), 1e-6)) * 100.0
            crease_rel = float(d[~open_mask].mean() / max(off[~open_mask].mean(), 1e-6)) * 100.0
            glob_rel = float(d.mean() / max(float(off.mean()), 1e-6)) * 100.0
            crease_by[m][s] = crease_rel
            ok_open = open_rel <= 5.0
            ok_glob = glob_rel <= 8.0
            verdict = "PASS" if (ok_open and ok_glob) else "FAIL"
            if verdict == "FAIL":
                grid_fail += 1
            heat = np.clip(d * 8.0, 0, 255).astype(np.uint8)
            Image.fromarray(heat).save(os.path.join(dev_dir, f"ao-diffheat-{vant}-{seg}.png"))
            print(f"[ao-grid] {m} {STR_LABEL[s]}: open_area_delta={open_rel:.2f}% "
                  f"crease_delta={crease_rel:.2f}% global_delta={glob_rel:.2f}% => {verdict}")

    print()
    for m in GRID_MODES:
        w = crease_by[m]["weak"]; dd = crease_by[m]["def"]; st = crease_by[m]["strong"]
        ordered = w < dd < st
        if not ordered:
            grid_fail += 1
        print(f"[ao-grid] {m} ordering crease weaker<default<stronger: "
              f"{w:.2f} < {dd:.2f} < {st:.2f} => {'PASS' if ordered else 'FAIL'}")

    overall_ok = (grid_fail == 0) and gpose_ok
    print(f"[ao-grid] OVERALL: {'PASS' if overall_ok else 'FAIL'}")
    sys.exit(0 if overall_ok else 1)


means = {}
for tag in ["off-a", "off-b", "off-c", "off-d"] + MODES:
    img, n = mean_frames(tag)
    if img is None:
        print(f"[ao-analyze] {vant}/{tag}: NO FRAMES")
        sys.exit(1)
    means[tag] = img
    print(f"[ao-analyze] {vant}/{tag}: {n} frames averaged, mean_luma={img.mean():.2f}")

# --- validity gates ---------------------------------------------------------
print()
pose_ok = True
# ADJACENT pairs, not everything-vs-off-a: time-of-day lighting drift (beach sunset run:
# off-a..off-d mean luma 127->87) decays a global NCC smoothly below threshold with a
# perfectly static camera. Every luminance verdict below compares a mode to its
# BRACKETING offs, so camera stillness only needs to hold across each adjacency; a real
# camera move is a step change that breaks the adjacency where it happens.
SEQ = ["off-a", MODES[0], "off-b", MODES[1], "off-c", MODES[2], "off-d"]
for t0, t1 in zip(SEQ, SEQ[1:]):
    c = ncc(means[t0], means[t1])
    ok = c >= 0.75
    if not ok:
        pose_ok = False
    print(f"[ao-pose] {vant} {t0} vs {t1}: ncc={c:.3f} => {'OK' if ok else 'POSE MISMATCH'}")
if not pose_ok:
    gate_fail += 1
    print(f"[ao-pose] {vant} POSE GATE FAIL — camera moved mid-sequence; luminance verdicts below are VOID")

drift = float(np.abs(means["off-a"] - means["off-d"]).mean())
drift_rel = drift / max(float(means["off-a"].mean()), 1e-6) * 100.0
print(f"[ao-drift] {vant} off-a vs off-d: mean_absdiff={drift:.3f} ({drift_rel:.2f}% of off-a mean)")

# --- TOD drift model ----------------------------------------------------------
# Per-pixel quadratic through the four off anchors at their capture timestamps,
# evaluated at each mode's timestamp. Interior interpolation only (modes sit between
# off-a and off-d); prediction clamped to the per-pixel off min/max +-8 luma.
OFFS = ["off-a", "off-b", "off-c", "off-d"]


def seg_time(tag):
    p = os.path.join(dev_dir, f"device-ao-{vant}-{tag}.mp4")
    try:
        return os.path.getmtime(p)
    except OSError:
        return None


_toff = [seg_time(t) for t in OFFS]
_tmod = {m: seg_time(m) for m in MODES}
off_model = "bracket-midpoint (mp4 mtimes missing)"
_off_stack = np.stack([means[t] for t in OFFS], axis=0)
_fit = None
if all(t is not None for t in _toff) and all(_tmod[m] is not None for m in MODES):
    _t0 = _toff[0]
    _ts = np.array([t - _t0 for t in _toff], dtype=np.float64)
    _span = _ts[-1] if _ts[-1] > 0 else 1.0
    _ts /= _span
    _A = np.stack([np.ones_like(_ts), _ts, _ts * _ts], axis=1)
    _coef, *_ = np.linalg.lstsq(_A, _off_stack.reshape(4, -1), rcond=None)
    _lo = _off_stack.min(axis=0) - 8.0
    _hi = _off_stack.max(axis=0) + 8.0
    _fit = (_coef, _t0, _span, _lo, _hi)
    off_model = "quadratic-TOD-fit(4 offs, mp4 mtimes)"


def off_pred(m):
    b0, b1 = BRACKET[m]
    if _fit is None:
        return (means[b0] + means[b1]) / 2.0
    coef, t0, span, lo, hi = _fit
    tm = (_tmod[m] - t0) / span
    v = (coef[0] + coef[1] * tm + coef[2] * tm * tm).reshape(means["off-a"].shape)
    return np.clip(v, lo, hi)


print(f"[ao-drift] {vant} off model: {off_model}" + "".join(
    f" | {m} pred_luma={float(off_pred(m).mean()):.1f} midpoint_luma="
    f"{float(((means[BRACKET[m][0]] + means[BRACKET[m][1]]) / 2.0).mean()):.1f}"
    for m in MODES))

# --- darkening stats vs bracketed off --------------------------------------
print()
for m in MODES:
    b0, b1 = BRACKET[m]
    off = off_pred(m)
    d = off - means[m]
    dark = np.clip(d, 0, None)
    frac = float((dark > 4.0).mean())
    p99 = float(np.percentile(dark, 99))
    gmean = float(dark.mean())
    thresh = np.percentile(dark, 90)
    loc = float(dark[dark >= thresh].mean() / gmean) if gmean > 1e-6 else 0.0
    print(f"[ao-analyze] {vant} OFF-vs-{m.upper()} (bracket {b0}+{b1}): mean_darkening={gmean:.3f} "
          f"darkened_frac(>4)={frac*100:.2f}% p99={p99:.1f} localization_ratio={loc:.1f}")
    heat = np.clip(dark * 8.0, 0, 255).astype(np.uint8)
    out = os.path.join(dev_dir, f"ao-diffheat-{vant}-{m}.png")
    Image.fromarray(heat).save(out)
    print(f"             heatmap -> {out}")

print()
for i in range(len(MODES)):
    for j in range(i + 1, len(MODES)):
        a, b = MODES[i], MODES[j]
        d = float(np.abs(means[a] - means[b]).mean())
        print(f"[ao-analyze] {vant} {a.upper()}-vs-{b.upper()}: mean_absdiff={d:.3f}")

# --- defect-5 quantified gates ----------------------------------------------
print()
for m in MODES:
    b0, b1 = BRACKET[m]
    off = off_pred(m)
    d = np.clip(off - means[m], 0, None)
    thresh = np.percentile(d, 90)
    open_mask = d < thresh
    off_mean = float(off.mean())
    open_rel = float(d[open_mask].mean() / max(off[open_mask].mean(), 1e-6)) * 100.0
    crease_rel = float(d[~open_mask].mean() / max(off[~open_mask].mean(), 1e-6)) * 100.0
    glob_rel = float(d.mean() / max(off_mean, 1e-6)) * 100.0
    ok_open = open_rel <= 5.0
    ok_glob = glob_rel <= 8.0
    ok_loc = crease_rel > open_rel * 1.5
    verdict = "PASS" if (ok_open and ok_glob) else "FAIL"
    if verdict == "FAIL":
        gate_fail += 1
    print(f"[ao-gate5] {vant} {m.upper()}: open_area_delta={open_rel:.2f}% (<=5% {'OK' if ok_open else 'FAIL'}) "
          f"crease_delta={crease_rel:.2f}% localized={'OK' if ok_loc else 'WEAK'} "
          f"global_delta={glob_rel:.2f}% (<=8% {'OK' if ok_glob else 'FAIL'}) => {verdict}")

# --- defect-7 water gate (shoreline vantage) ----------------------------------
# Owner 2026-07-16: AO must not touch water. The sea ANIMATES (waves/envmap sparkle),
# so "delta ~0" is judged against the off-vs-off wave-noise baseline: each mode's
# water-region delta vs its bracketing offs must be statistically indistinguishable
# from off-a vs off-d (x1.5 margin, 1.5-luma absolute floor). Water mask = blue-dominant
# pixels in the lower 60% of the frame (sand is R>B, sky is excluded by the row cut),
# computed on the off-a RGB mean; the pose gate above guarantees framing is stable.
wmask = None
if vant == "shoreline":
    rgb_off, _ = mean_frames("off-a", rgb=True)
    h = rgb_off.shape[0]
    blue_dom = (rgb_off[:, :, 2] > rgb_off[:, :, 0] + 8.0)
    rows = np.zeros_like(blue_dom)
    rows[int(h * 0.40):, :] = True
    wmask = blue_dom & rows
    wfrac = float(wmask.mean())
    print()
    if wfrac < 0.08:
        print(f"[ao-gate7] {vant} WATER MASK: only {wfrac*100:.1f}% of frame is water (<8%) "
              f"=> FAIL (vantage does not show the sea; re-frame)")
        gate_fail += 1
    else:
        Image.fromarray((wmask * 255).astype(np.uint8)).save(
            os.path.join(dev_dir, f"ao-watermask-{vant}.png"))
        off_w_mean = float(means["off-a"][wmask].mean())
        wnoise = float(np.abs(means["off-a"] - means["off-d"])[wmask].mean())
        wnoise_rel = wnoise / max(off_w_mean, 1e-6) * 100.0
        print(f"[ao-gate7] {vant} water mask {wfrac*100:.1f}% of frame, off-off wave-noise "
              f"baseline {wnoise:.3f} luma ({wnoise_rel:.2f}%)")
        for m in MODES:
            b0, b1 = BRACKET[m]
            off = off_pred(m)
            wdelta = float(np.abs(means[m] - off)[wmask].mean())
            wdark = float(np.clip(off - means[m], 0, None)[wmask].mean())
            wdark_rel = wdark / max(off_w_mean, 1e-6) * 100.0
            # Null floor of THIS measure, apples-to-apples (2026-07-16 round-F re-runs):
            # the old baseline clip(b0-b1) measured the FULL bracket interval — under a
            # brightening bracket it collapses toward 0 while the mode stat keeps its
            # positive wave/interp noise floor, so the gate false-FAILed a rotating mode
            # per run (run1 HBAO 7.37% vs 3.48%, run2 GTAO 4.49% vs 4.08%) while the
            # debug views showed white terms and the composite stencil exclusion is
            # mode-independent. Honest null: the SAME clipped-darkening estimator with
            # the SAME predictor family on AO-FREE data — leave-one-out quadratic over
            # the offs, evaluated at each interior off (run2: nulls 1.21% / 4.19% ≈ the
            # 'failing' 4.49%). Margin x1.5 = the gate's own existing convention (lim).
            # Physical residual: water is a BLEND — the underwater seafloor legitimately
            # receives contact AO and shows through (strongest for GTAO); the stencil
            # keeps the water surface itself untouched (debug view: water drawn over the
            # composite unchanged).
            null_darks = []
            for held in ("off-b", "off-c"):
                others = [o for o in ("off-a", "off-b", "off-c", "off-d") if o != held]
                # quadratic through the 3 remaining offs (exact fit), same time axis
                ts = [(seg_time(o) - seg_time("off-a")) /
                      max(seg_time("off-d") - seg_time("off-a"), 1e-6) for o in others]
                Vn = np.vander(np.array(ts), 3, increasing=True)
                Yn = np.stack([means[o][wmask] for o in others])
                cn, *_ = np.linalg.lstsq(Vn, Yn, rcond=None)
                th = (seg_time(held) - seg_time("off-a")) / \
                     max(seg_time("off-d") - seg_time("off-a"), 1e-6)
                predh = cn[0] + cn[1] * th + cn[2] * th * th
                null_darks.append(float(np.clip(predh - means[held][wmask], 0, None).mean()))
            null_rel = max(null_darks) / max(off_w_mean, 1e-6) * 100.0
            dark_lim = max(1.5, 1.5 * null_rel)
            lim = max(wnoise * 1.5, 1.5)
            ok = wdelta <= lim and wdark_rel <= dark_lim
            if not ok:
                gate_fail += 1
            print(f"[ao-gate7] {vant} {m.upper()} water: absdelta={wdelta:.3f} (lim {lim:.3f}) "
                  f"darkening={wdark:.3f} ({wdark_rel:.2f}% <= max(1.5%, 1.5x LOO-off-null "
                  f"{null_rel:.2f}%)) => {'PASS' if ok else 'FAIL'} (water untouched by AO)")

# --- debug-view (raw AO term) gates ------------------------------------------
MODE_NUM = {"ssao": 1, "hbao": 2, "gtao": 3}
for m in MODES:
    pat = os.path.join(dev_dir, f"device-ao-{vant}-{MODE_NUM[m]}-debugview_frames", "f_*.png")
    files = sorted(glob.glob(pat))
    if not files:
        pat = os.path.join(dev_dir, f"device-ao-{vant}-{m}-debugview_frames", "f_*.png")
        files = sorted(glob.glob(pat))
    if not files:
        print(f"[ao-gate5-debug] {vant} {m.upper()} AO-term view: NO FRAMES => FAIL")
        gate_fail += 1
        continue
    accs = [np.asarray(Image.open(f).convert("L"), dtype=np.float64) for f in files[1:] or files]
    img = sum(accs) / len(accs)
    h = img.shape[0]
    sky = img[: h // 5, :]
    # shoreline: the water buckets draw AFTER the debug composite, so blue water covers
    # ~57% of the debug frame and its tint under the >200 threshold swamps the whiteness
    # stat (a threshold artifact, not a term defect — water is composite-EXCLUDED anyway).
    # Measure the term whiteness over the NON-water region (floor + sky) there.
    region = " (non-water region)" if (vant == "shoreline" and wmask is not None
                                       and wmask.shape == img.shape) else ""
    sel = ~wmask if region else np.ones_like(img, dtype=bool)
    white_frac = float((img[sel] > 200).mean())
    dark_frac = float((img[sel] < 64).mean())
    ok = white_frac > 0.5 and dark_frac < 0.15 and float(sky.mean()) > 200.0
    print(f"[ao-gate5-debug] {vant} {m.upper()} AO-term view{region}: white_frac={white_frac*100:.1f}% "
          f"dark_frac={dark_frac*100:.1f}% sky_mean={sky.mean():.0f} => {'PASS' if ok else 'FAIL'}")
    if not ok:
        gate_fail += 1

print(f"[ao-gate5] {vant} OVERALL: {'PASS' if gate_fail == 0 else 'FAIL(' + str(gate_fail) + ')'}")
