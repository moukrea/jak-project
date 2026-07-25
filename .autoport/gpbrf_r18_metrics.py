#!/usr/bin/env python3
"""gpbrf_r18_metrics.py — round-18 GROUND-specific numbers for the owner's playtest #18 defects.

Reads the stills gpbrf_r18_ab.sh captured in ONE boot at a fixed vantage (same TOD, same camera,
resolution PINNED — dynamic render scale off — and only the two live props changed per cell) and
reports per-pair luma differences over three crops:

  GROUND  rows 55%-95% of the frame height, full width. The vantage looks ALONG the ground, so this
          is where the owner's "le parallax s'étale à plat au SOL" and "la tessellation manque de
          relief au SOL" live. Every headline number is this crop.
  UPPER   rows 20%-50%: walls / mid-distance. Present so a GROUND change can be shown to be
          GROUND-SPECIFIC and not a global dimming.
  WHOLE   the full masked frame (required for the tess pair).

luma L = 0.2126 R + 0.7152 G + 0.0722 B on float [0,1] (Rec.709, as mandated).

MASK: pure-black letterbox ROWS and COLS (p99 luma < 8/255 over the reference cell) are dropped
whole, then per-pixel L(ref) <= 8/255 pixels are dropped too — the same criterion
gpbrf_polish_metrics.py used. Coverage is printed so the reader can see what was measured.

Usage: gpbrf_r18_metrics.py <dir with pomOFF.png pomLEGACY.png ...>
"""
import os
import sys

import numpy as np
from PIL import Image

BLACK = 8.0 / 255.0
K_DETAIL = 8

CELLS = ('pomOFF', 'pomLEGACY', 'pomNEW', 'tessLEGACY', 'tessNEW', 'pomOFF2', 'xtra_ambrel')


def luma(path):
    a = np.asarray(Image.open(path).convert('RGB'), dtype=np.float64) / 255.0
    return a[..., 0] * 0.2126 + a[..., 1] * 0.7152 + a[..., 2] * 0.0722


def box(x, k):
    h2, w2 = x.shape[0] // k * k, x.shape[1] // k * k
    return x[:h2, :w2].reshape(h2 // k, k, w2 // k, k).mean(axis=(1, 3))


def hf_std(x):
    """high-frequency energy = std of (luma - 8x8 box mean). Relief IS high-frequency energy."""
    k = K_DETAIL
    h2, w2 = x.shape[0] // k * k, x.shape[1] // k * k
    r = x[:h2, :w2] - np.kron(box(x, k), np.ones((k, k)))
    return float(r.std())


d = sys.argv[1] if len(sys.argv) > 1 else '.'
img = {}
for c in CELLS:
    p = os.path.join(d, c + '.png')
    if os.path.isfile(p):
        img[c] = luma(p)

if 'pomOFF' not in img:
    sys.exit('no pomOFF.png — run the cells stage first')
ref = img['pomOFF']
H, W = ref.shape
for c, a in list(img.items()):
    if a.shape != ref.shape:
        print(f'!! {c}: SHAPE MISMATCH {a.shape} vs {ref.shape} — dropped')
        del img[c]

# ---- letterbox: whole rows/cols that are essentially pure black in the reference ----
row_ok = np.percentile(ref, 99, axis=1) > BLACK
col_ok = np.percentile(ref, 99, axis=0) > BLACK
valid = np.outer(row_ok, col_ok) & (ref > BLACK)

crops = {}
g0, g1 = int(round(0.55 * H)), int(round(0.95 * H))
u0, u1 = int(round(0.20 * H)), int(round(0.50 * H))
for name, (r0, r1) in (('GROUND', (g0, g1)), ('UPPER', (u0, u1)), ('WHOLE', (0, H))):
    m = np.zeros_like(valid)
    m[r0:r1, :] = valid[r0:r1, :]
    crops[name] = m

print('=== PBR ROUND-18 DEVICE A/B — GROUND-focused luma metrics ===')
print(f'    frame {W}x{H}   GROUND rows [{g0},{g1})   UPPER rows [{u0},{u1})')
print('    mask coverage: ' + '  '.join(
    f'{n}={100.0 * crops[n].sum() / (H * W):.1f}% of frame ({crops[n].sum()} px)' for n in crops))
print(f'    cells present: {", ".join(sorted(img))}')
missing = [c for c in CELLS if c not in img]
if missing:
    print(f'    !! MISSING CELLS: {", ".join(missing)}')
print()

# ---- per-cell context ----
hdr = f'{"cell":14s} {"mean L GROUND":>13s} {"mean L UPPER":>12s} {"HFdetail GROUND":>15s}'
print(hdr)
print('-' * len(hdr))
for c in CELLS:
    if c not in img:
        print(f'{c:14s} {"(missing)":>13s}')
        continue
    x = img[c]
    gm = crops['GROUND']
    sub = x[g0:g1, :]
    print(f'{c:14s} {x[gm].mean():13.5f} {x[crops["UPPER"]].mean():12.5f} {hf_std(sub):15.5f}')
print()


def pair(a, b, crop):
    if a not in img or b not in img:
        return None
    m = crops[crop]
    dl = np.abs(img[a] - img[b])[m]
    return float(dl.mean()), float(np.percentile(dl, 95)), int(dl.size)


PAIRS = (
    ('pomLEGACY - pomOFF', 'pomLEGACY', 'pomOFF', 'legacy un-faded parallax vs POM off'),
    ('pomNEW - pomOFF', 'pomNEW', 'pomOFF', 'round-18 faded+capped parallax vs POM off'),
    ('pomOFF2 - pomOFF', 'pomOFF2', 'pomOFF', 'DRIFT FLOOR (identical settings, captured last)'),
    ('pomNEW - pomLEGACY', 'pomNEW', 'pomLEGACY', 'the round-18 change itself'),
    ('tessNEW - tessLEGACY', 'tessNEW', 'tessLEGACY', 'world-edge-length law vs distance-only law'),
    ('xtra_ambrel - pomOFF2', 'xtra_ambrel', 'pomOFF2',
     'EXTRA: bit 262144 also kills round-17 ambient relief — this sizes that side effect alone'),
)

hdr = f'{"pair":22s} {"crop":6s} {"mean|dL|":>10s} {"p95|dL|":>10s} {"npx":>9s}'
print(hdr)
print('-' * len(hdr))
res = {}
for label, a, b, _ in PAIRS:
    for crop in ('GROUND', 'UPPER', 'WHOLE'):
        r = pair(a, b, crop)
        if r is None:
            print(f'{label:22s} {crop:6s} {"(missing cell)":>10s}')
            continue
        res[(label, crop)] = r
        print(f'{label:22s} {crop:6s} {r[0]:10.5f} {r[1]:10.5f} {r[2]:9d}')
    print()

floor = res.get(('pomOFF2 - pomOFF', 'GROUND'))
print('=== READING (GROUND crop; every ACTIVE number sits on the drift floor) ===')
if floor:
    print(f'  DRIFT FLOOR      mean|dL| = {floor[0]:.5f}  p95 = {floor[1]:.5f}')
for label in ('pomLEGACY - pomOFF', 'pomNEW - pomOFF', 'tessNEW - tessLEGACY'):
    r = res.get((label, 'GROUND'))
    ru = res.get((label, 'UPPER'))
    if not r:
        continue
    ratio = (r[0] / floor[0]) if floor and floor[0] > 0 else float('nan')
    gu = (r[0] / ru[0]) if ru and ru[0] > 0 else float('nan')
    print(f'  {label:22s} mean|dL| = {r[0]:.5f} = {ratio:6.2f}x the drift floor;'
          f'  GROUND/UPPER = {gu:.2f}x')
print()
print('NOTE: these are DISPLACEMENT-MAGNITUDE numbers, not a beauty verdict. How far the parallax')
print('moves the ground texture is measurable; whether the result looks like depth is the owner call.')
