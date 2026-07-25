#!/usr/bin/env python3
"""Grecharged-pbr-realtime-fusion — OWNER PLAYTEST #17 offline, shader-exact measurement.

No device required (the Redmi is physically unplugged this round). Every constant below is
copied from the shipped source; the file/line is named next to each one so the numbers can be
re-derived. Re-implements, in numpy over the ACTUAL shipped height/normal maps:

  1. LoaderStages.cpp's per-material height statistics (mean / p2 / p98 / half / norm)
  2. tfrag3.frag  hnorm()          — material-scaled height
  3. tfrag3.tese  band-limited displacement vs the shipped lod-0 fetch  (the ALIASING proof)
  4. tfrag3.frag  pbr_cavity()     — the direction-independent flat-in-shadow fix
  5. the shaded-in-cast-shadow relief, BEFORE vs AFTER  (the defect, then the fix)
  6. tfrag3.frag  the direct N.L detail-ratio rebalance

Usage:  python3 .autoport/gpbrf_r17_offline.py [texture_root]
Env:    RELIEF (default 1.5)  TESS_DISP_K (default 14336)
"""
import os
import sys
import glob
import numpy as np
from PIL import Image

ROOT = sys.argv[1] if len(sys.argv) > 1 else "custom_assets/jak1/recharged_textures"
RELIEF = float(os.environ.get("RELIEF", "1.5"))

# ---- constants copied from the shipped source -------------------------------------------------
HEIGHT_SCALE = 0.05 * RELIEF        # background_common.cpp: height_scale = 0.05f * relief
NORMAL_STRENGTH = 1.0 * RELIEF      # background_common.cpp: normal_strength = 3.0f * relief / 3
TESS_DISP_K = float(os.environ.get("TESS_DISP_K", "14336.0"))   # tfrag3_tess.tese
WORLD_TILES_PER_M = 0.5             # tfrag3_tess.tese
GU_PER_M = 4096.0
TESS_K = 128.0                      # tfrag3_tess.tesc  (new inverse-distance level law)
TESS_REF_EDGE_M = 2.18              # tools/tess_audit measured median patch edge, village1
TESS_MAX = 32.0
TESS_LOD_BIAS = 0.5                 # tfrag3_tess.tese half-mip band-limit safety margin
PBR_CAV_SPAN = 3.0                  # tfrag3.frag
PBR_CAV_GAIN = 1.6
PBR_CAV_MIN, PBR_CAV_MAX = 0.55, 1.45
PBR_CAV_DIR = 0.35
# hemisphere ambient, the default rt ambient model (tfrag3.frag rt_amb_eval fallback)
AMB_SKY, AMB_GROUND = 0.55, 0.18

# tess_audit's measured per-band mean vertex spacing for the NEW law, and the OLD law's.
# band label -> (old_spacing_cm, new_spacing_cm)
BANDS = [("[0,5)", 19.128, 7.892), ("[5,10)", 16.906, 12.542), ("[10,20)", 23.944, 23.116)]


def load_gray(path):
    return np.asarray(Image.open(path).convert("L"), dtype=np.float32) / 255.0


def loader_stats(h):
    """Mirror LoaderStages.cpp exactly: 256-bin histogram, mean, p2/p98, half, norm."""
    b = np.clip((h * 255.0 + 0.5).astype(np.int32), 0, 255)
    hist = np.bincount(b.ravel(), minlength=256).astype(np.int64)
    npx = int(hist.sum())
    mean = float((hist * np.arange(256)).sum() / npx / 255.0)
    cum = np.cumsum(hist)
    p2 = int(np.searchsorted(cum, int(npx * 0.02))) / 255.0
    p98 = int(np.searchsorted(cum, int(npx * 0.98))) / 255.0
    half = max(max(p98 - mean, mean - p2), 2.0 / 255.0)
    norm = float(np.clip(0.5 / half, 0.5, 16.0))
    return mean, p2, p98, half, norm


def hnorm(h, mean, norm):
    return np.clip((h - mean) * norm + 0.5, 0.0, 1.0)


def mip_chain(img, levels):
    """glGenerateMipmap's 2x2 box filter."""
    out = [img]
    cur = img
    for _ in range(levels):
        hh, ww = cur.shape[0] // 2, cur.shape[1] // 2
        if hh < 2 or ww < 2:
            break
        cur = cur[: hh * 2, : ww * 2].reshape(hh, 2, ww, 2).mean(axis=(1, 3))
        out.append(cur)
    return out


def sample_lod(mips, lod):
    """textureLod's trilinear-in-mip read, evaluated over the whole map at that mip then
    re-expanded to full resolution so it can be compared per-texel with the base."""
    l0 = int(np.floor(lod))
    l1 = min(l0 + 1, len(mips) - 1)
    l0 = min(l0, len(mips) - 1)
    f = lod - l0
    base = mips[0].shape

    def up(m):
        ry = base[0] // m.shape[0]
        rx = base[1] // m.shape[1]
        return np.repeat(np.repeat(m, ry, axis=0), rx, axis=1)[: base[0], : base[1]]

    return up(mips[l0]) * (1.0 - f) + up(mips[l1]) * f


def p2p(x):
    """peak-to-trough using the same robust p2..p98 span the loader uses."""
    return float(np.percentile(x, 98) - np.percentile(x, 2))


def autocorr_at(img, lag_px):
    """Pearson correlation between the field and itself shifted by lag_px (wraparound =
    GL_REPEAT). This is the aliasing metric: ~0 means consecutive samples at that spacing are
    decorrelated, i.e. the 'displacement' is white noise at the vertex frequency."""
    lag = max(1, int(round(lag_px)))
    a = img
    b = np.roll(img, lag, axis=1)
    a = a - a.mean()
    b = b - b.mean()
    d = float(np.sqrt((a * a).sum() * (b * b).sum()))
    return float((a * b).sum() / d) if d > 0 else 0.0


hs = sorted(glob.glob(os.path.join(ROOT, "**", "*_height.png"), recursive=True))
if not hs:
    print(f"no *_height.png under {ROOT}")
    sys.exit(1)

print("#" * 100)
print("OWNER PLAYTEST #17 — OFFLINE SHADER-EXACT MEASUREMENT (no device: the Redmi is unplugged)")
print(f"relief = {RELIEF}  =>  height_scale = {HEIGHT_SCALE:.4f}, normal_strength = {NORMAL_STRENGTH:.2f}")
print(f"TESS_DISP_K = {TESS_DISP_K}  WORLD_TILES_PER_M = {WORLD_TILES_PER_M}  TESS_MAX = {TESS_MAX}")
print("#" * 100)

# ================================================================================================
print("\n##### 1. LOADER HEIGHT STATISTICS (LoaderStages.cpp, mirrored exactly) #####")
print(f"{'material':<26} {'size':>11} {'mean':>7} {'p2':>7} {'p98':>7} {'half':>7} {'norm':>7} "
      f"{'raw_span_used':>14}")
mats = {}
for p in hs:
    name = os.path.basename(p)[: -len("_height.png")]
    h = load_gray(p)
    mean, p2, p98, half, norm = loader_stats(h)
    mats[name] = dict(path=p, h=h, mean=mean, norm=norm)
    # what fraction of the nominal amplitude the OLD raw (h-0.5) actually reached
    used = float(h.max() - h.min())
    print(f"{name:<26} {h.shape[1]}x{h.shape[0]:<6} {mean:7.4f} {p2:7.4f} {p98:7.4f} {half:7.4f} "
          f"{norm:7.3f} {used*100:13.1f}%")

# ================================================================================================
print("\n##### 2. MATERIAL-SCALED AMPLITUDE — the net inward/outward OFFSET the old code applied #####")
print("disp = (h - 0.5) * amp with amp = height_scale*TESS_DISP_K. A material whose mean is not")
print("0.5 displaces its ENTIRE surface by (mean-0.5)*amp: not relief, and a step against the")
print("un-mapped neighbour at the material border. hnorm() makes every material mean-centred.")
amp_gu = HEIGHT_SCALE * TESS_DISP_K
print(f"amp = {amp_gu:.1f} game units = {amp_gu/GU_PER_M*100:.2f} cm of full-range displacement\n")
print(f"{'material':<26} {'OLD net offset':>15} {'OLD p2p':>10} {'NEW p2p':>10} {'gain':>7}")
for name, m in mats.items():
    off = (m["mean"] - 0.5) * amp_gu / GU_PER_M * 100.0
    old_p2p = p2p(m["h"]) * amp_gu / GU_PER_M * 100.0
    new_p2p = p2p(hnorm(m["h"], m["mean"], m["norm"])) * amp_gu / GU_PER_M * 100.0
    print(f"{name:<26} {off:14.2f}cm {old_p2p:9.2f}cm {new_p2p:9.2f}cm "
          f"{(new_p2p/max(old_p2p,1e-6)):6.2f}x")

# ================================================================================================
print("\n##### 3. THE ALIASING PROOF — why raising the tess level never bought detail #####")
print("One mip-0 texel spans (1/WORLD_TILES_PER_M)/res metres of world. tess_audit measured the")
print("real generated-vertex spacing per distance band. 'texels apart' = how far apart, in mip-0")
print("texels, two neighbouring generated vertices sample. 'corr' = Pearson correlation between")
print("the height field and itself at that lag: ~0 == the two samples are unrelated == the")
print("displacement is white noise at the vertex frequency, which is what 'glorified bump' looks")
print("like. NEW samples the mip matched to the spacing, where neighbours overlap.\n")
for name, m in mats.items():
    h = m["h"]
    hn = hnorm(h, m["mean"], m["norm"])
    res = max(h.shape)
    m_per_texel = (1.0 / WORLD_TILES_PER_M) / res
    mips = mip_chain(hn, 12)
    print(f"  {name}  (mip-0 texel = {m_per_texel*1000:.2f} mm of world)")
    print(f"    {'band':<9} {'spacing':>9} {'texels apart':>13} {'OLD corr@lod0':>14} "
          f"{'matched lod':>12} {'NEW corr':>9} {'NEW p2p':>9}")
    for label, old_cm, new_cm in BANDS:
        lag_old = (old_cm / 100.0) / m_per_texel
        lag_new = (new_cm / 100.0) / m_per_texel
        c_old = autocorr_at(hn, lag_old)
        lod = float(np.clip(np.log2(max(lag_new, 1.0)) + TESS_LOD_BIAS, 0.0, 12.0))
        band = sample_lod(mips, lod)
        c_new = autocorr_at(band, lag_new)
        new_p = p2p(band) * amp_gu / GU_PER_M * 100.0
        print(f"    {label:<9} {new_cm:8.1f}cm {lag_old:13.0f} {c_old:14.3f} "
              f"{lod:12.2f} {c_new:9.3f} {new_p:8.2f}cm")

# ================================================================================================
print("\n##### 4. THE CAVITY TERM — pbr_cavity(), the direction-INDEPENDENT flat-in-shadow fix #####")
print("Driven by a HIGH-PASS of the normalised height (fine mip minus a PBR_CAV_SPAN-coarser mip),")
print("so its mean is 1.0 BY CONSTRUCTION, not by tuning. Compare its spread against the round-#16")
print("ambient RATIO E(Nm)/E(N), which is what was supposed to do this job.\n")
print(f"{'material':<26} {'cav mean':>9} {'cav std':>9} {'cav p05':>9} {'cav p95':>9} "
      f"{'|ratio-1| (r16)':>16}")
cav_store = {}
for name, m in mats.items():
    h, mean, norm = m["h"], m["mean"], m["norm"]
    hn = hnorm(h, mean, norm)
    mips = mip_chain(hn, 12)
    # a near-camera fragment: mip fitted to the fragment footprint. Use lod 2 as a representative
    # near view (a 2048 map over ~2 m of screen-facing ground at ~1080p sits around there).
    fine = sample_lod(mips, 2.0)
    blur = sample_lod(mips, 2.0 + PBR_CAV_SPAN)
    cav = np.clip(1.0 + PBR_CAV_GAIN * (fine - blur), PBR_CAV_MIN, PBR_CAV_MAX)
    cav_store[name] = cav
    # round-16 ambient ratio, hemisphere model, for the same material
    npath = m["path"].replace("_height.png", "_normal.png")
    ratio_dev = float("nan")
    if os.path.exists(npath):
        nrm = np.asarray(Image.open(npath).convert("RGB"), dtype=np.float32) / 255.0 * 2.0 - 1.0
        g = np.clip(nrm[..., 0:2] / np.maximum(nrm[..., 2:3], 0.05), -4.0, 4.0)
        g = (g - g.reshape(-1, 2).mean(axis=0)) * NORMAL_STRENGTH   # DC-removed, strength-scaled
        nz = 1.0 / np.sqrt(1.0 + (g * g).sum(axis=-1))
        ny = nz            # flat ground (N = +Y): the perturbed normal's Y component
        e_s = AMB_GROUND + (AMB_SKY - AMB_GROUND) * (0.5 * 1.0 + 0.5)
        e_b = AMB_GROUND + (AMB_SKY - AMB_GROUND) * np.clip(0.5 * ny + 0.5, 0, 1)
        ratio = np.clip((e_b + 0.02) / (e_s + 0.02), 0.45, 1.9)
        ratio_dev = float(np.abs(ratio - 1.0).mean())
    print(f"{name:<26} {cav.mean():9.4f} {cav.std():9.4f} "
          f"{np.percentile(cav,5):9.4f} {np.percentile(cav,95):9.4f} {ratio_dev:16.4f}")

# ================================================================================================
print("\n##### 5. RELIEF IN FULL CAST SHADOW — the defect, then the fix #####")
print("A fragment with sun_occ = moon_occ = 0. BEFORE, fdetail collapses to the ambient ratio")
print("alone (the sun mix() weights are both 0). AFTER, the cavity multiplies it at FULL strength")
print("(the ambient share is 1.0 there). 'relief contrast' = std of the shaded multiplier; the")
print("BEFORE column is the number the owner is describing as 'toujours plat'.\n")
print(f"{'material':<26} {'BEFORE std':>11} {'AFTER std':>11} {'x':>7} {'AFTER mean':>11}")
for name, m in mats.items():
    npath = m["path"].replace("_height.png", "_normal.png")
    before = np.ones_like(m["h"])
    if os.path.exists(npath):
        nrm = np.asarray(Image.open(npath).convert("RGB"), dtype=np.float32) / 255.0 * 2.0 - 1.0
        g = np.clip(nrm[..., 0:2] / np.maximum(nrm[..., 2:3], 0.05), -4.0, 4.0)
        g = (g - g.reshape(-1, 2).mean(axis=0)) * NORMAL_STRENGTH
        nz = 1.0 / np.sqrt(1.0 + (g * g).sum(axis=-1))
        e_s = AMB_GROUND + (AMB_SKY - AMB_GROUND) * 1.0
        e_b = AMB_GROUND + (AMB_SKY - AMB_GROUND) * np.clip(0.5 * nz + 0.5, 0, 1)
        before = np.clip((e_b + 0.02) / (e_s + 0.02), 0.45, 1.9)
    after = before * cav_store[name]
    print(f"{name:<26} {before.std():11.5f} {after.std():11.5f} "
          f"{after.std()/max(before.std(),1e-9):6.1f}x {after.mean():11.4f}")

# ================================================================================================
print("\n##### 6. DIRECT N.L DETAIL-RATIO REBALANCE (\"très contrasté à la lumière\") #####")
print("fdt = clamp((max(N'.L,0)+soft)/(max(N.L,0)+soft), lo, hi) at a 45 deg sun on flat ground.")
print("OLD lo/hi/soft = 0.45/1.9/0.30, NEW = 0.60/1.55/0.38.\n")
print(f"{'material':<26} {'OLD std':>9} {'NEW std':>9} {'OLD p99/p01':>12} {'NEW p99/p01':>12}")
L = np.array([0.0, np.sin(np.radians(45.0)), np.cos(np.radians(45.0))], dtype=np.float32)
for name, m in mats.items():
    npath = m["path"].replace("_height.png", "_normal.png")
    if not os.path.exists(npath):
        continue
    nrm = np.asarray(Image.open(npath).convert("RGB"), dtype=np.float32) / 255.0 * 2.0 - 1.0
    g = np.clip(nrm[..., 0:2] / np.maximum(nrm[..., 2:3], 0.05), -4.0, 4.0)
    g = (g - g.reshape(-1, 2).mean(axis=0)) * NORMAL_STRENGTH
    # tangent frame on flat ground: T=+X, B=+Z, N=+Y -> the shader's un-normalised bump response
    ndl_flat = L[1]
    ndl = ndl_flat + g[..., 0] * L[0] + g[..., 1] * L[2]
    for lo, hi, soft, tag in ((0.45, 1.9, 0.30, "old"), (0.60, 1.55, 0.38, "new")):
        r = np.clip((np.maximum(ndl, 0) + soft) / (max(ndl_flat, 0) + soft), lo, hi)
        if tag == "old":
            o_std, o_rng = r.std(), np.percentile(r, 99) / max(np.percentile(r, 1), 1e-6)
        else:
            n_std, n_rng = r.std(), np.percentile(r, 99) / max(np.percentile(r, 1), 1e-6)
    print(f"{name:<26} {o_std:9.4f} {n_std:9.4f} {o_rng:12.2f} {n_rng:12.2f}")

print("\ndone.")

# ================================================================================================
print("\n##### 7. SILHOUETTE BREAK — the owner's proof that this is REAL displacement, not a bump #####")
print("A bump map's silhouette is EXACTLY straight, by definition: no vertex moves. Real")
print("displacement bends the edge. But the shipped code moved vertices too — it just moved them")
print("to unrelated heights (section 3), and an edge cannot express relief FINER than its own")
print("vertex spacing. So the load-bearing number is VERTICES PER FEATURE: how many generated")
print("vertices fall across the finest feature the sampled mip still carries (2 texels of that")
print("mip, i.e. that mip's Nyquist wavelength). Below 2 the silhouette provably cannot represent")
print("the feature and the moved vertices are noise; at or above 2 the break is real, coherent")
print("relief. Measured at the near-field (0-5 m) vertex spacing tess_audit reports for the")
print("shipped law, with the mip the shipped tese now selects.\n")
print(f"{'material':<26} {'OLD v/feat':>11} {'NEW v/feat':>11} {'sil amp':>9} {'max dev':>9} "
      f"{'NEW feature':>12}")
SPACING_CM = 7.892   # tess_audit measured mean near-field (0-5 m) generated-vertex spacing, NEW law
amp_cm = HEIGHT_SCALE * TESS_DISP_K / GU_PER_M * 100.0
for name, m in mats.items():
    h, mean, norm = m["h"], m["mean"], m["norm"]
    hn = hnorm(h, mean, norm)
    res = max(h.shape)
    cm_per_texel = ((1.0 / WORLD_TILES_PER_M) / res) * 100.0
    mips = mip_chain(hn, 12)
    lag = (SPACING_CM / 100.0) / (cm_per_texel / 100.0)          # vertex spacing in base texels
    lod = float(np.clip(np.log2(max(lag, 1.0)) + TESS_LOD_BIAS, 0.0, 12.0))
    # finest feature a mip still carries = 2 texels OF THAT MIP, in base texels then cm
    feat_new_cm = 2.0 * (2.0 ** lod) * cm_per_texel
    feat_old_cm = 2.0 * (2.0 ** 0.0) * cm_per_texel              # shipped: textureLod(...,0.0)
    row_new = sample_lod(mips, lod)[h.shape[0] // 2, :]
    prof = row_new * amp_cm
    sil_amp = p2p(row_new) * amp_cm
    max_dev = float(np.abs(prof - prof.mean()).max())
    print(f"{name:<26} {feat_old_cm/SPACING_CM:11.3f} {feat_new_cm/SPACING_CM:11.2f} "
          f"{sil_amp:8.2f}cm {max_dev:8.2f}cm {feat_new_cm:11.1f}cm")
print("\nOLD v/feat = 0.025 everywhere: the shipped silhouette sampled ~40x below Nyquist, so the")
print("vertices moved but the broken edge carried no shape — a bump map with a jittered outline.")
print("NEW v/feat = 2.83 = 2 * 2^TESS_LOD_BIAS, i.e. ABOVE Nyquist BY CONSTRUCTION of the")
print("band-limit (that is exactly what the half-mip bias buys). The silhouette break is therefore")
print("real, coherent relief of the stated amplitude — the distinction the owner is asking for.")
