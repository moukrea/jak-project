#!/usr/bin/env python3
"""gpbrf_polish_offline.py — shader-exact offline measurement of the three PBR-polish fixes.

Runs the EXACT arithmetic the shaders run (same constants, same conventions) over the REAL shipped
_height / _normal PNGs, and reports what each fix changes as a number. Offline, so it isolates the
term from camera, TOD and capture noise; the device A/B (gpbrf_polish_ab.sh) is the complementary
in-situ proof.

Constants mirrored from the source, verbatim:
  tfrag3_tess.tese : TESS_DISP_K = 14336.0, WORLD_TILES_PER_M = 0.5, MS_M = 0.25, disp = (h-0.5)*amp
  background_common.cpp : height_scale = 0.05 * relief, normal_strength = 1.0 * relief, relief = 1.5
  tfrag3.frag : g = nraw.xy / max(nraw.z, 0.05) - u_pbr_normal_dc ; fg = g * normal_strength
                pbr_micro_shadow: 6 steps, K = 3.0, floor = 0.35, ray = h0 + t*(1-h0)
  1 game unit = 1/4096 m
"""
import glob
import os
import sys

import numpy as np
from PIL import Image

RELIEF = float(os.environ.get('RELIEF', '1.5'))
HEIGHT_SCALE = 0.05 * RELIEF
NORMAL_STRENGTH = 1.0 * RELIEF
TESS_DISP_K = 14336.0
WORLD_TILES_PER_M = 0.5
MS_M = 0.25
GU_PER_M = 4096.0

root = sys.argv[1] if len(sys.argv) > 1 else 'custom_assets/jak1/recharged_textures'


def load_gray(p):
    return np.asarray(Image.open(p).convert('L'), dtype=np.float32) / 255.0


def load_rgb(p):
    return np.asarray(Image.open(p).convert('RGB'), dtype=np.float32) / 255.0


def shift(a, dy, dx):
    return np.roll(np.roll(a, dy, axis=0), dx, axis=1)   # maps upload GL_REPEAT on both axes


print('=== PBR POLISH — shader-exact offline measurement on the shipped material maps ===')
print(f'    relief = {RELIEF}  =>  height_scale = {HEIGHT_SCALE:.4f}, normal_strength = '
      f'{NORMAL_STRENGTH:.2f}')
print()

heights = sorted(glob.glob(os.path.join(root, '**', '*_height.png'), recursive=True))
if not heights:
    sys.exit(f'no *_height.png under {root}')

# ------------------------------------------------------------------ DEFECT 3b : tessellation normal
print('--- DEFECT 3b: the tess-eval emitted the UNDISPLACED normal, so real moved vertices were')
print('    SHADED AS FLAT ("un bump map glorifie"). Below: the normal the fixed tese now derives')
print('    from the same world height field, and the shading variation it creates where there was')
print('    EXACTLY ZERO before (a flat normal has no variation by definition).')
hdr = (f'{"material":34s} {"peak-to-trough":>14s} {"tilt mean":>9s} {"tilt p95":>8s} '
       f'{"tilt>5deg":>9s} {"N.L spread":>10s}')
print(hdr)
print('-' * len(hdr))
tot = []
for p in heights:
    h = load_gray(p)
    name = os.path.basename(p).replace('_height.png', '')
    amp_gu = HEIGHT_SCALE * TESS_DISP_K              # game units for a full 0->1 height swing
    ptt_cm = (h.max() - h.min()) * amp_gu / GU_PER_M * 100.0
    # the tese's central difference: MS_M metres in world == MS_M*WORLD_TILES_PER_M tiles of huv
    px_per_tile = h.shape[0]
    step_px = max(1, int(round(MS_M * WORLD_TILES_PER_M * px_per_tile)))
    du = (shift(h, 0, -step_px) - shift(h, 0, step_px))
    dv = (shift(h, -step_px, 0) - shift(h, step_px, 0))
    k = amp_gu / (2.0 * MS_M * GU_PER_M)             # == the shader's `k`
    su, sv = du * k, dv * k
    # flat ground (N = +Y): N' = normalize(N - Tu*su - Tv*sv), Tu/Tv the two in-plane world axes
    nz = 1.0 / np.sqrt(1.0 + su * su + sv * sv)
    tilt = np.degrees(np.arccos(np.clip(nz, -1.0, 1.0)))
    # sun at 45 deg elevation: how much N.L now varies across the surface (was identically flat)
    L = np.array([np.cos(np.radians(45.0)), np.sin(np.radians(45.0)), 0.0])
    ndl = np.clip((-su * nz) * L[0] + nz * L[1] + (-sv * nz) * L[2], 0.0, 1.0)
    print(f'{name:34s} {ptt_cm:12.1f}cm {tilt.mean():8.1f}d {np.percentile(tilt,95):7.1f}d '
          f'{100.0*(tilt>5).mean():8.1f}% {ndl.std():10.4f}')
    tot.append((tilt.mean(), 100.0 * (tilt > 5).mean(), ndl.std()))
a = np.array(tot)
print(f'{"ALL MATERIALS":34s} {"":14s} {a[:,0].mean():8.1f}d {"":8s} {a[:,1].mean():8.1f}% '
      f'{a[:,2].mean():10.4f}')
print(f'    BEFORE the fix these three columns were 0.0d / 0.0% / 0.0000 by construction — v_normal')
print(f'    was the interpolated flat normal, unaffected by any displacement.')
print()

# ------------------------------------------------------------------ DEFECT 3a : height self-shadow
print('--- DEFECT 3a: the height field never occluded a light. Below: the self-shadow term the')
print('    fixed shader computes (6 steps, K=3.0, floor 0.35), sun at 30 deg elevation.')
hdr = f'{"material":34s} {"mean vis":>9s} {"p05 vis":>8s} {"shadowed >5%":>13s} {"std":>7s}'
print(hdr)
print('-' * len(hdr))
for p in heights:
    h = load_gray(p)
    name = os.path.basename(p).replace('_height.png', '')
    hs_uv = HEIGHT_SCALE * 1.0                        # u_pbr_uv_tile = 1
    el = np.radians(30.0)
    Lt = np.array([np.cos(el), 0.0, np.sin(el)])      # tangent-space light, marching along +u
    sd = (Lt[:2] / max(Lt[2], 0.08)) * hs_uv
    n = np.linalg.norm(sd)
    if n > 0.08:
        sd = sd * (0.08 / n)
    npx = h.shape[1]
    occ = np.zeros_like(h)
    for i in range(1, 7):
        t = i / 6.0
        off = sd * t
        hs = shift(h, int(round(-off[1] * npx)), int(round(-off[0] * npx)))
        ray = h + t * (1.0 - h)
        occ = np.maximum(occ, (hs - ray) * (1.0 - t))
    vis = np.clip(1.0 - occ * 3.0, 0.35, 1.0)
    print(f'{name:34s} {vis.mean():9.4f} {np.percentile(vis,5):8.4f} '
          f'{100.0*(vis<0.95).mean():12.1f}% {vis.std():7.4f}')
print('    BEFORE the fix this term did not exist: visibility was identically 1.0 everywhere, so the')
print('    relief cast nothing and read as shading rather than as geometry.')
print()

# ------------------------------------------------------------------ DEFECT 2 : indirect relief
print('--- DEFECT 2: in cast shadow fdetail collapsed to EXACTLY 1.0 (both mix() weights are')
print('    sun_occ/moon_occ) and famb_spec is matte-gated to 0 on rough dielectrics, so a shadowed')
print('    fragment had ZERO normal dependence. Below: the indirect relief ratio E(Nm)/E(N) the fix')
print('    now applies there, using the hemisphere ambient (sky 0.55 / ground 0.18, flat ground).')
hdr = (f'{"material":34s} {"DC removed":>20s} {"ratio mean":>10s} {"p05":>7s} {"p95":>7s} '
       f'{"std":>7s}')
print(hdr)
print('-' * len(hdr))
sky, ground = 0.55, 0.18
for p in sorted(glob.glob(os.path.join(root, '**', '*_normal.png'), recursive=True)):
    nm = load_rgb(p) * 2.0 - 1.0
    name = os.path.basename(p).replace('_normal.png', '')
    g = np.clip(nm[..., :2] / np.maximum(nm[..., 2:3], 0.05), -4.0, 4.0)
    dc = g.reshape(-1, 2).mean(axis=0)
    fg = np.clip((g - dc) * NORMAL_STRENGTH, -8.0, 8.0)
    # Nm = normalize(fg.x*T + fg.y*B + N); flat ground => N=+Y, T=+X, B=+Z
    inv = 1.0 / np.sqrt(fg[..., 0] ** 2 + fg[..., 1] ** 2 + 1.0)
    ny = inv                                            # the y component of the perturbed normal
    e_m = ground + (sky - ground) * np.clip(ny * 0.5 + 0.5, 0.0, 1.0)
    e_s = ground + (sky - ground) * 1.0                 # E(N) with N.y = 1
    r = np.clip((np.maximum(e_m, 0) + 0.02) / (np.maximum(e_s, 0) + 0.02), 0.45, 1.9)
    print(f'{name:34s} ({dc[0]:+.3f},{dc[1]:+.3f}) {r.mean():10.4f} {np.percentile(r,5):7.4f} '
          f'{np.percentile(r,95):7.4f} {r.std():7.4f}')
print('    BEFORE the fix this ratio was not computed at all: the shadowed value was identically')
print('    1.0000 with std 0.0000 — that identity IS "completement plat dans l\'ombre".')
