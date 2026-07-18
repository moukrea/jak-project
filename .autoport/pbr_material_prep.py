#!/usr/bin/env python3
"""Grecharged-pbr-materials: prepare the punchy owner-mandate material set.

Takes a raw ambientCG 1K-PNG material and produces the game-side
<tex>{,_normal,_roughness,_ao,_height}.png set, post-processed to meet the
supervisor's punch gates (stock ambientCG assets don't reach them raw):
  - height: 16-bit Displacement renormalized p0.5..p99.5 -> full 0..255
  - normal: x/y deviation strengthened (factor auto-raised until dev_mean > 35),
    z recomputed for unit length
  - roughness / ao / color: passthrough
Prints the final stats the mandate gates on.
"""
import sys

import numpy as np
from PIL import Image

SRC_DIR = sys.argv[1]  # e.g. .../material/candidates/Bricks059
NAME = sys.argv[2]  # e.g. Bricks059
OUT_DIR = sys.argv[3]  # e.g. custom_assets/jak1/texture_replacements/village1-vis-tfrag
TEX = sys.argv[4]  # e.g. vil1-sages-stonewall-01


def load(path):
    return Image.open(path)


base = f"{SRC_DIR}/{NAME}_1K-PNG"

# color / roughness / ao passthrough
for suf_in, suf_out in [("Color", ""), ("Roughness", "_roughness"), ("AmbientOcclusion", "_ao")]:
    img = load(f"{base}_{suf_in}.png").convert("RGB")
    img.save(f"{OUT_DIR}/{TEX}{suf_out}.png")

# height: 16-bit displacement -> float, percentile renormalize to full range
disp = np.array(load(f"{base}_Displacement.png"), dtype=np.float64)
if disp.max() > 255:
    disp /= 257.0  # 16-bit -> 0..255 scale
p_lo, p_hi = np.percentile(disp, [0.5, 99.5])
h = np.clip((disp - p_lo) / max(p_hi - p_lo, 1e-6) * 255.0, 0, 255)
Image.fromarray(h.astype(np.uint8)).convert("RGB").save(f"{OUT_DIR}/{TEX}_height.png")

# normal: strengthen xy until dev_mean > 35 (cap factor 6)
nrm = np.array(load(f"{base}_NormalGL.png").convert("RGB"), dtype=np.float64)
xy = (nrm[..., :2] - 128.0) / 127.0
factor = 2.5
while factor <= 6.0:
    sxy = np.clip(xy * factor, -1.0, 1.0)
    dev = np.mean(np.abs(sxy) * 127.0)
    if dev > 35.0:
        break
    factor += 0.5
z = np.sqrt(np.clip(1.0 - sxy[..., 0] ** 2 - sxy[..., 1] ** 2, 0.0, 1.0))
out = np.empty_like(nrm)
out[..., 0] = np.clip(sxy[..., 0] * 127.0 + 128.0, 0, 255)
out[..., 1] = np.clip(sxy[..., 1] * 127.0 + 128.0, 0, 255)
out[..., 2] = np.clip(z * 127.0 + 128.0, 0, 255)
Image.fromarray(out.astype(np.uint8)).save(f"{OUT_DIR}/{TEX}_normal.png")

# final stats (the gates)
n = np.array(load(f"{OUT_DIR}/{TEX}_normal.png").convert("RGB"), dtype=np.float64)
ndev = np.mean((np.abs(n[..., 0] - 128) + np.abs(n[..., 1] - 128)) / 2.0)
r = np.array(load(f"{OUT_DIR}/{TEX}_roughness.png").convert("L"), dtype=np.float64)
hh = np.array(load(f"{OUT_DIR}/{TEX}_height.png").convert("L"), dtype=np.float64)
h_p1, h_p99 = np.percentile(hh, [1, 99])
print(f"source={NAME} strengthen_factor={factor}")
print(f"normal_dev_mean={ndev:.2f} (gate >35)")
print(f"rough_std={r.std():.2f} (gate >30)")
print(f"height_p1={h_p1:.1f} (gate <=15) height_p99={h_p99:.1f} (gate >=240) "
      f"height_min={hh.min():.0f} height_max={hh.max():.0f} height_std={hh.std():.2f}")
ok = ndev > 35 and r.std() > 30 and h_p1 <= 15 and h_p99 >= 240
print("STATS:", "PASS" if ok else "FAIL")
sys.exit(0 if ok else 1)
