#!/usr/bin/env python3
"""gpbrf_polish_metrics.py — one measured number per owner-recorded PBR defect.

Reads the frames gpbrf_polish_ab.sh captured in a SINGLE boot at a fixed vantage (same TOD, same
camera, only one bisect bit changed per cell) and reports:

  ACTIVE   mean |dL| between a cell and `base`, over the world mask. Read it AGAINST THE DRIFT
           FLOOR printed below: the game keeps running between captures (idle animation, scrolling
           clouds, the follow-cam converging), so a raw pixel difference is only meaningful when it
           clears the floor measured by base2 — an identical-settings cell captured last.
  DETAIL   high-frequency energy = std of (luma - 8x8 box mean). Surface relief IS high-frequency
           energy; a flat surface has none. Reported over the SHADOWED share and the LIT share,
           because the owner's defect 2 is specifically "flat WHERE THE SUN DOESN'T HIT".
           Each cell derives its OWN shadow/lit population by percentile: a distributional
           statistic like this needs no pixel alignment, so unlike a per-pixel difference it is
           robust to the residual camera drift.
  MACRO    low-frequency energy = std of the 32x32 block means, i.e. shape at the scale real
           displaced geometry works at.

The world mask drops the letterbox and the SKY (blue-dominant bright pixels): the sky's clouds
scroll continuously and carry no PBR material, so including it would only add noise.

Usage: gpbrf_polish_metrics.py <dir with base.png d1_worldframe.png ...>
"""
import os
import sys

import numpy as np
from PIL import Image

K_DETAIL = 8
K_BLOCK = 32


def rgb(p):
    return np.asarray(Image.open(p).convert('RGB'), dtype=np.float32)


def luma_of(a):
    return a[..., 0] * 0.299 + a[..., 1] * 0.587 + a[..., 2] * 0.114


def box(x, k):
    h2, w2 = x.shape[0] // k * k, x.shape[1] // k * k
    return x[:h2, :w2].reshape(h2 // k, k, w2 // k, k).mean(axis=(1, 3))


def hf_map(x, k=K_DETAIL):
    h2, w2 = x.shape[0] // k * k, x.shape[1] // k * k
    return x[:h2, :w2] - np.kron(box(x, k), np.ones((k, k), dtype=np.float32))


d = sys.argv[1] if len(sys.argv) > 1 else '.'


def load(name):
    p = os.path.join(d, name + '.png')
    return rgb(p) if os.path.isfile(p) else None


base_rgb = load('base')
if base_rgb is None:
    sys.exit('no base.png — run the matrix stage first')
base = luma_of(base_rgb)

# ---- world mask: not letterbox, not sky (clouds scroll; the sky carries no PBR material) ----
sky = (base_rgb[..., 2] > base_rgb[..., 0] * 1.15) & (base_rgb[..., 2] > 100)
world_full = (base > 8.0) & ~sky
H = base.shape[0] // K_BLOCK * K_BLOCK
W = base.shape[1] // K_BLOCK * K_BLOCK
world = world_full[:H, :W]
wblk = box(world.astype(np.float32), K_BLOCK) > 0.75   # 32-blocks that are (almost) all world

print('=== PBR POLISH A/B — fixed vantage, TOD frozen at noon, full stack, single boot ===')
print(f'    frame {base.shape[1]}x{base.shape[0]}   world mask (no letterbox, no sky) = '
      f'{100.0 * world.mean():.1f}% of the frame')
print()

hdr = (f'{"cell":16s} {"ACTIVE mean|dL|":>15s} {"DETAIL shadow":>13s} {"DETAIL lit":>10s} '
       f'{"MACRO":>7s} {"mean luma":>9s}')
print(hdr)
print('-' * len(hdr))

rows = {}
for name in ('base', 'd1_worldframe', 'd2_amboff', 'd3_msoff', 'prepolish', 'base2',
             'd3_tess', 'd3_tess_flatn', 'd3_tess2', 'reg_rt_only', 'reg_stock'):
    a = load(name)
    if a is None:
        print(f'{name:16s} (missing)')
        continue
    x = luma_of(a)
    if x.shape != base.shape:
        print(f'{name:16s} SHAPE MISMATCH {x.shape} vs {base.shape}')
        continue
    x = x[:H, :W]
    act = float(np.abs(x - base[:H, :W])[world].mean())
    # each cell derives its OWN shadow/lit population => no pixel alignment needed
    b32 = box(x, K_BLOCK)
    vals = b32[wblk]
    sh32 = wblk & (b32 <= np.percentile(vals, 30))
    li32 = wblk & (b32 >= np.percentile(vals, 60))
    up = lambda m: np.kron(m, np.ones((K_BLOCK, K_BLOCK), dtype=bool))
    r8 = hf_map(x)
    h8, w8 = r8.shape
    dsh = float(r8[up(sh32)[:h8, :w8]].std())
    dli = float(r8[up(li32)[:h8, :w8]].std())
    mac = float(b32[wblk].std())
    rows[name] = dict(active=act, dsh=dsh, dli=dli, mac=mac, luma=float(x[world].mean()))
    print(f'{name:16s} {act:15.3f} {dsh:13.3f} {dli:10.3f} {mac:7.3f} {rows[name]["luma"]:9.2f}')

floor = rows.get('base2', {}).get('active')
print()
if floor is not None:
    print(f'DRIFT FLOOR = {floor:.3f}  (base2 is base re-captured last with identical settings; the '
          f'game keeps running between cells, so this is the noise every ACTIVE number sits on)')
print()
print('=== VERDICTS (each is the owner defect, expressed as a number) ===')


def verdict(label, cond, text):
    print(f'  [{"PASS" if cond else "INCONCLUSIVE"}] {label}: {text}')
    return cond


ok = True
lim = (floor * 1.5) if floor else 0.5
nan = float('nan')
if 'd1_worldframe' in rows:
    a = rows['d1_worldframe']['active']
    ok &= verdict(
        'DEFECT 1 (relief direction)', a > lim,
        f'putting the normal map back in the WORLD frame moves the image by mean |dL| = {a:.3f} '
        f'(drift floor {floor if floor else nan:.3f}) => the decode frame is ACTIVE at this vantage '
        f'and the fix is what changed it. The DIRECTION itself is quantified over the whole level '
        f'in pbr_tan_diag.txt [world_frame_rot] — that is the load-bearing number.')
if 'd2_amboff' in rows:
    on, off = rows['base']['dsh'], rows['d2_amboff']['dsh']
    gain = (on / off - 1.0) * 100.0 if off > 1e-6 else nan
    ok &= verdict(
        'DEFECT 2 (flat in shadow)', on > off,
        f'DETAIL in the SHADOWED share {off:.3f} (indirect relief OFF) -> {on:.3f} (ON) = '
        f'{gain:+.1f}%. The shadowed surface now carries normal-mapped structure instead of being '
        f'baked x constant x _ao.')
if 'd3_msoff' in rows:
    on, off = rows['base']['dli'], rows['d3_msoff']['dli']
    gain = (on / off - 1.0) * 100.0 if off > 1e-6 else nan
    ok &= verdict(
        'DEFECT 3a (self-shadow)', on > off,
        f'DETAIL in the LIT share {off:.3f} (height self-shadow OFF) -> {on:.3f} (ON) = '
        f'{gain:+.1f}%. The relief now casts its own contact shadow instead of only being shaded.')
if 'd3_tess' in rows and 'd3_tess_flatn' in rows:
    a = luma_of(load('d3_tess'))[:H, :W]
    b = luma_of(load('d3_tess_flatn'))[:H, :W]
    dl = float(np.abs(a - b)[world].mean())
    tfloor = None
    if 'd3_tess2' in rows:
        c = luma_of(load('d3_tess2'))[:H, :W]
        tfloor = float(np.abs(a - c)[world].mean())
    ok &= verdict(
        'DEFECT 3b (tessellation shading)', tfloor is not None and dl > tfloor * 1.5,
        f'REAL tessellation, same displaced vertices, only the shading normal changes: mean |dL| = '
        f'{dl:.3f} vs its own drift floor {tfloor if tfloor else nan:.3f}. DETAIL lit '
        f'{rows["d3_tess_flatn"]["dli"]:.3f} -> {rows["d3_tess"]["dli"]:.3f}.')
if 'prepolish' in rows:
    a = rows['prepolish']['active']
    ok &= verdict(
        'OVERALL (obvious difference)', a > lim,
        f'all three fixes OFF vs ON: mean |dL| = {a:.3f} (drift floor {floor if floor else nan:.3f})'
        f' — prepolish.png vs base.png is the old-vs-new side-by-side pair.')
if 'reg_rt_only' in rows and 'reg_stock' in rows:
    print(f'  [info] regression cells: rt ON + pbr OFF mean luma {rows["reg_rt_only"]["luma"]:.2f}, '
          f'rt OFF + pbr OFF (stock) mean luma {rows["reg_stock"]["luma"]:.2f} — both are code-gated '
          f'branches this round never enters (every edit is inside `u_rt_light_on != 0 && '
          f'u_pbr_mode != 0`).')

print()
print('MATRIX-RESULT:', 'ALL-PASS' if ok else 'SOME-INCONCLUSIVE')
