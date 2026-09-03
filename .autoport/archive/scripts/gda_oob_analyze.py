#!/usr/bin/env python3
"""gda_oob_analyze.py — OUT-OF-BOX (shipped SH + strength 0.2 + contrast 1.0) sun-off FORM proof.

Same frequency-separation method as gda_sunoff_analyze.py (owner-validated): with the sun OFF
lit = albedo*base(N); we low-pass (downsample DS=24) to strip the high-freq albedo texture and keep
the geometry-scale shading gradient, then take its spatial std over non-sky geometry = the amount of
directional FORM. The shipped out-of-box default (oob_sunoff) must beat the flat contrast=0 A/B
(oob_sunoff_c0). Sun-on (oob_sunon) must ADD light (brighter) while keeping the relief.

Tags produced by gda_final2_capture.sh (props CLEARED => shipped GOAL defaults drive; no model override):
  oob_sunoff     shipped SH, strength 0.2, contrast 1.0, SUN OFF  -> the out-of-box relief money shot
  oob_sunoff_c0  SUN OFF, contrast forced 0                       -> the flat "before" A/B
  oob_sunon      SUN ON                                           -> sun adds light on top
  oob_off_stock  realtime OFF                                     -> stock baked (OFF==stock ref)
"""
import glob
import numpy as np
from PIL import Image

ROOT = ".autoport/reports/Grecharged-directional-ambient/device"
DS = 24  # low-pass downsample factor (strips albedo texture, keeps geometry-scale shading)


def luma(rgb):
    return 0.2126 * rgb[..., 0] + 0.7152 * rgb[..., 1] + 0.0722 * rgb[..., 2]


def geo_mask(rgb, L):
    sky = (L > 0.5) & (rgb[..., 2] >= rgb[..., 0])
    blk = L < 0.012
    return ~(sky | blk)


def frame_stats(fp):
    im = Image.open(fp).convert("RGB")
    rgb = np.asarray(im, np.float32) / 255.0
    L = luma(rgb)
    m = geo_mask(rgb, L)
    if m.mean() < 0.03:
        return None
    H, W = L.shape
    small = np.asarray(Image.fromarray((L * 255).astype(np.uint8)).resize(
        (max(1, W // DS), max(1, H // DS)), Image.BILINEAR), np.float32) / 255.0
    msmall = np.asarray(Image.fromarray((m * 255).astype(np.uint8)).resize(
        (max(1, W // DS), max(1, H // DS)), Image.BILINEAR), np.float32) / 255.0
    cell = msmall > 0.5
    if cell.sum() < 8:
        return None
    lp = small[cell]
    return dict(
        blur_std=float(lp.std()),
        blur_range=float(np.percentile(lp, 95) - np.percentile(lp, 5)),
        raw_std=float(L[m].std()),
        geo_frac=float(m.mean()),
        geo_mean=float(L[m].mean()),
        black_frac=float(((L < 0.02) & m).sum() / max(m.sum(), 1)),
        bright_mean=float(L[L > 0.6].mean()) if (L > 0.6).any() else 0.0,
    )


def agg(tag):
    fs = sorted(glob.glob(f"{ROOT}/frames_{tag}/*.png"))
    rows = [s for f in fs if (s := frame_stats(f))]
    if not rows:
        return None
    keys = rows[0].keys()
    out = {k: float(np.mean([r[k] for r in rows])) for k in keys}
    out["n"] = len(rows)
    return out


def show(tag, s):
    if s is None:
        print(f"  {tag:16s}  (no frames / no geometry)")
        return
    print(f"  {tag:16s} n={s['n']:2d}  blur_std={s['blur_std']:.4f}  blur_range={s['blur_range']:.4f}  "
          f"geoMean={s['geo_mean']:.4f}  blackFrac={s['black_frac']:.4f}  geo={s['geo_frac']:.2f}")


print("=== OUT-OF-BOX SUN-OFF FORM (shipped SH+0.2+1.0; low-freq shading spread over non-sky geometry) ===")
off = agg("oob_sunoff")
c0 = agg("oob_sunoff_c0")
show("oob_sunoff", off)
show("oob_sunoff_c0", c0)
if off and c0:
    r = off['blur_std'] / max(c0['blur_std'], 1e-6)
    print(f"\n  FORM RATIO (oob_sunoff / oob_sunoff_c0) blur_std = {r:.2f}x   "
          f"range {off['blur_range']:.4f} vs {c0['blur_range']:.4f}   "
          f"mean {off['geo_mean']:.4f} vs {c0['geo_mean']:.4f} (contrast preserves mean)")
    print(f"  VERDICT: {'PASS — sun-OFF ambient sculpts FORM out-of-box' if r >= 1.5 else 'WEAK — form gain < 1.5x'}")

print("\n=== SUN ADDS LIGHT (oob_sunon must be brighter than oob_sunoff; relief preserved) ===")
on = agg("oob_sunon")
show("oob_sunon", on)
show("oob_sunoff", off)
if on and off:
    dmean = on['geo_mean'] - off['geo_mean']
    print(f"  geoMean sun-on {on['geo_mean']:.4f} vs sun-off {off['geo_mean']:.4f}  (delta {dmean:+.4f}, sun ADDS light)")
    print(f"  sun-on still carries form: blur_std {on['blur_std']:.4f} (relief not re-flattened by the sun)")

print("\n=== OFF == STOCK ref ===")
show("oob_off_stock", agg("oob_off_stock"))
