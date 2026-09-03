#!/usr/bin/env python3
"""gda_sunon_coherence_analyze.py — prove the NEW ADDITIVE sun composite is COHERENT (attempt-5).

Owner: sun-OFF relief ACCEPTED; the WIP sun looked "bizarre" because the OLD screen blend
  lit = albedo*(base + (1-base)*sun)  ->  albedo   as sun_scalar -> 1
i.e. the ambient relief COLLAPSED to a flat albedo on the LIT side. The fix is true additive
  lit = albedo*base + albedo*sun_color*sun_scalar   (C1 soft-shoulder tone-map, knee 0.8).

Coherence requires, measured on the DEFAULT colored render, out-of-box (shipped SH+0.2+1.0):
  1. sun-OFF sculpts relief   (blur_std sunoff >> blur_std flat-A/B)          — accepted, re-verify
  2. sun ON ADDS light        (geo_mean sunon > geo_mean sunoff)             — lit side brighter
  3. sun ON PRESERVES relief  (blur_std sunon comparable to/greater than sunoff, NOT collapsed)
  4. sun ON NOT blown out     (near-white frac low; not a flat white blob)
Same frequency-separation method as the owner-validated gda_oob_analyze.py: low-pass (downsample
DS=24) strips high-freq albedo texture, leaving the geometry-scale SHADING gradient = FORM.
"""
import glob
import numpy as np
from PIL import Image

ROOT = ".autoport/reports/Grecharged-directional-ambient/device"
DS = 24


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
        blur_std=float(lp.std()),                       # low-freq shading spread = FORM/relief
        blur_range=float(np.percentile(lp, 95) - np.percentile(lp, 5)),
        geo_mean=float(L[m].mean()),                    # brightness of geometry
        geo_frac=float(m.mean()),
        blown_frac=float(((L > 0.92) & m).sum() / max(m.sum(), 1)),   # near-white blowout on geometry
        black_frac=float(((L < 0.02) & m).sum() / max(m.sum(), 1)),
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
    print(f"  {tag:16s} n={s['n']:2d}  blur_std={s['blur_std']:.4f}  geoMean={s['geo_mean']:.4f}  "
          f"blownFrac={s['blown_frac']:.4f}  blackFrac={s['black_frac']:.4f}  geo={s['geo_frac']:.2f}")


off = agg("oob_sunoff"); c0 = agg("oob_sunoff_c0"); on = agg("oob_sunon"); stock = agg("oob_off_stock")

print("=== (1) SUN-OFF sculpts relief (shipped SH out-of-box, DEFAULT render) ===")
show("oob_sunoff", off); show("oob_sunoff_c0", c0)
if off and c0:
    r = off['blur_std'] / max(c0['blur_std'], 1e-6)
    print(f"    form ratio (sunoff / flat-A_B) = {r:.2f}x   "
          f"{'PASS' if r >= 1.4 else 'WEAK'} (>=1.4 => ambient sculpts sun-off)")

print("\n=== (2)+(3)+(4) SUN-ON COHERENCE: adds light, preserves relief, not blown ===")
show("oob_sunon", on); show("oob_sunoff", off)
if on and off:
    dmean = on['geo_mean'] - off['geo_mean']
    relief_keep = on['blur_std'] / max(off['blur_std'], 1e-6)
    print(f"    (2) sun ADDS light : geoMean {off['geo_mean']:.4f} -> {on['geo_mean']:.4f}  "
          f"(delta {dmean:+.4f})  {'PASS' if dmean > 0.01 else 'FAIL'} (lit side brighter)")
    print(f"    (3) relief PRESERVED: blur_std {off['blur_std']:.4f} -> {on['blur_std']:.4f}  "
          f"(ratio {relief_keep:.2f}x)  {'PASS' if relief_keep >= 0.85 else 'FAIL — sun re-flattened relief!'} "
          f"(old screen blend collapsed this toward flat albedo)")
    print(f"    (4) NOT blown out  : sun-on blownFrac(near-white) = {on['blown_frac']:.4f}  "
          f"{'PASS' if on['blown_frac'] < 0.08 else 'CHECK — too much near-white'} (<0.08 => tonemap holds)")

print("\n=== OFF == STOCK ref (realtime off) ===")
show("oob_off_stock", stock)
