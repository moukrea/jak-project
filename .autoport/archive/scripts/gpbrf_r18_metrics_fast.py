#!/usr/bin/env python3
"""gpbrf_r18_metrics_fast.py — drift-CANCELLED round-18 numbers.

The main pass showed the honest problem: at the owner's vantage the follow-camera drifts slowly, so
two identically-configured cells captured ~6 minutes apart differ by MORE (mean |dL| 0.0179 raw /
0.0117 hardened on the GROUND crop) than the parallax A/B itself. Jak never moves (pos_dump identical
before and after), so the drift is camera-only and SLOW — which makes it cancellable.

The fast pass interleaves A-B-A-C-A (pomOFF / pomLEGACY / pomOFF / pomNEW / pomOFF) and T-N-T-N
(tessLEGACY / tessNEW / tessLEGACY / tessNEW) with ~15 s between neighbours. Then, for a measurement
X flanked by references R1 and R2:

    SIGNAL = mean |X - (R1+R2)/2|     — any drift LINEAR in time between R1 and R2 cancels exactly
    FLOOR  = mean |R1 - R2| / 2       — the residual (non-linear) drift over the SAME interval,
                                        halved because the midpoint estimate averages two frames

SIGNAL/FLOOR > 1 is the resolvable-effect criterion. Each cell is the temporal MEDIAN of ~12 frames
of its own 4 s capture (kills per-frame animation), differenced only over pixels that are STATIC in
every cell (temporal std < 0.010) — this is what removes the ocean, the wind-blown foliage, Jak's
idle animation and the scrolling clouds without hand-drawn regions. GROUND = rows 55-95%,
UPPER = rows 20-50% (walls / mid-distance, the "is it ground-specific?" control), WHOLE = full frame.

Usage: gpbrf_r18_metrics_fast.py <r18/fast dir>
"""
import os
import shutil
import subprocess
import sys

import numpy as np
from PIL import Image

FPS = 3
STD_MAX = 0.010
BLACK = 8.0 / 255.0
CELLS = ('a1_pomOFF', 'b1_pomLEGACY', 'a2_pomOFF', 'c1_pomNEW', 'a3_pomOFF',
         't1_tessLEGACY', 't2_tessNEW', 't3_tessLEGACY', 't4_tessNEW')
d = sys.argv[1] if len(sys.argv) > 1 else '.'
TMP = '/tmp/r18_fast_fr'


def stack(mp4):
    shutil.rmtree(TMP, ignore_errors=True)
    os.makedirs(TMP)
    subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', mp4, '-vf', f'fps={FPS}',
                    f'{TMP}/f_%03d.png'], check=True)
    out = []
    for f in sorted(os.listdir(TMP)):
        a = np.asarray(Image.open(os.path.join(TMP, f)).convert('RGB'), dtype=np.float32) / 255.0
        out.append(a[..., 0] * 0.2126 + a[..., 1] * 0.7152 + a[..., 2] * 0.0722)
    shutil.rmtree(TMP, ignore_errors=True)
    return np.stack(out)


med, tstd, nfr = {}, {}, {}
for c in CELLS:
    p = os.path.join(d, c + '.mp4')
    if not os.path.isfile(p):
        continue
    st = stack(p)
    nfr[c] = st.shape[0]
    med[c] = np.median(st, axis=0)
    tstd[c] = st.std(axis=0)
    del st
if not med:
    sys.exit('no fast-pass mp4s')

ref0 = med[CELLS[0]]
H, W = ref0.shape
static = np.ones((H, W), dtype=bool)
for c in med:
    static &= tstd[c] < STD_MAX
static &= np.outer(np.percentile(ref0, 99, axis=1) > BLACK,
                   np.percentile(ref0, 99, axis=0) > BLACK) & (ref0 > BLACK)

g0, g1 = int(round(0.55 * H)), int(round(0.95 * H))
u0, u1 = int(round(0.20 * H)), int(round(0.50 * H))
BANDS = {'GROUND': (g0, g1), 'UPPER': (u0, u1), 'WHOLE': (0, H)}

print('=== ROUND-18 DRIFT-CANCELLED A/B (interleaved pass, temporal median, static-pixel mask) ===')
print(f'    frame {W}x{H};  frames/cell: ' + ', '.join(f'{c}={nfr[c]}' for c in med))
print(f'    STATIC pixels (temporal std < {STD_MAX} in ALL {len(med)} cells): '
      f'{100.0 * static.mean():.1f}% of frame')
print(f'    GROUND rows [{g0},{g1})   UPPER rows [{u0},{u1})')
print()


def band_mask(band):
    r0, r1 = BANDS[band]
    m = np.zeros_like(static)
    m[r0:r1, :] = static[r0:r1, :]
    return m


def triple(x, r1, r2, band):
    """returns (signal, p95signal, floor, npx) for X flanked by references R1,R2."""
    if x not in med or r1 not in med or r2 not in med:
        return None
    m = band_mask(band)
    mid = 0.5 * (med[r1] + med[r2])
    sig = np.abs(med[x] - mid)[m]
    flo = np.abs(med[r1] - med[r2])[m] * 0.5
    return (float(sig.mean()), float(np.percentile(sig, 95)), float(flo.mean()),
            float(np.percentile(flo, 95)), int(m.sum()))


TRIPLES = (
    ('pomLEGACY  vs pomOFF', 'b1_pomLEGACY', 'a1_pomOFF', 'a2_pomOFF'),
    ('pomNEW     vs pomOFF', 'c1_pomNEW', 'a2_pomOFF', 'a3_pomOFF'),
    ('tessNEW    vs tessLEGACY', 't2_tessNEW', 't1_tessLEGACY', 't3_tessLEGACY'),
    ('tessLEGACY vs tessNEW', 't3_tessLEGACY', 't2_tessNEW', 't4_tessNEW'),
)
hdr = (f'{"measurement":26s} {"crop":6s} {"SIGNAL mean":>11s} {"SIGNAL p95":>10s} '
       f'{"FLOOR mean":>10s} {"FLOOR p95":>9s} {"S/F":>6s} {"npx":>9s}')
print(hdr)
print('-' * len(hdr))
res = {}
for label, x, r1, r2 in TRIPLES:
    for band in ('GROUND', 'UPPER', 'WHOLE'):
        r = triple(x, r1, r2, band)
        if r is None:
            print(f'{label:26s} {band:6s} {"(missing cell)":>11s}')
            continue
        res[(label, band)] = r
        sf = r[0] / r[2] if r[2] > 0 else float('nan')
        print(f'{label:26s} {band:6s} {r[0]:11.5f} {r[1]:10.5f} {r[2]:10.5f} {r[3]:9.5f} '
              f'{sf:6.2f} {r[4]:9d}')
    print()

# direct legacy-vs-new comparisons at matched drift (adjacent cells)
print('--- direct adjacent-cell differences (no drift model, ~15 s apart) ---')
hdr2 = f'{"pair":30s} {"crop":6s} {"mean|dL|":>10s} {"p95|dL|":>10s}'
print(hdr2)
print('-' * len(hdr2))
DIRECT = (('b1_pomLEGACY - a1_pomOFF', 'b1_pomLEGACY', 'a1_pomOFF'),
          ('c1_pomNEW - a2_pomOFF', 'c1_pomNEW', 'a2_pomOFF'),
          ('c1_pomNEW - b1_pomLEGACY', 'c1_pomNEW', 'b1_pomLEGACY'),
          ('a2_pomOFF - a1_pomOFF (floor)', 'a2_pomOFF', 'a1_pomOFF'),
          ('a3_pomOFF - a2_pomOFF (floor)', 'a3_pomOFF', 'a2_pomOFF'),
          ('t2_tessNEW - t1_tessLEGACY', 't2_tessNEW', 't1_tessLEGACY'),
          ('t3_tessLEGACY - t1_tessLEGACY (floor)', 't3_tessLEGACY', 't1_tessLEGACY'),
          ('t4_tessNEW - t2_tessNEW (floor)', 't4_tessNEW', 't2_tessNEW'))
for label, a, b in DIRECT:
    if a not in med or b not in med:
        print(f'{label:30s} (missing)')
        continue
    for band in ('GROUND', 'UPPER'):
        m = band_mask(band)
        dl = np.abs(med[a] - med[b])[m]
        print(f'{label:30s} {band:6s} {dl.mean():10.5f} {np.percentile(dl, 95):10.5f}')
print()
print('=== READING ===')
for label, _, _, _ in TRIPLES:
    g, u = res.get((label, 'GROUND')), res.get((label, 'UPPER'))
    if not g:
        continue
    sf = g[0] / g[2] if g[2] > 0 else float('nan')
    verdict = 'RESOLVED above the drift floor' if sf > 1.5 else (
        'marginal (1.0-1.5x floor)' if sf > 1.0 else 'NOT resolvable at this vantage')
    gu = (g[0] / u[0]) if u and u[0] > 0 else float('nan')
    print(f'  {label:26s} GROUND signal {g[0]:.5f} vs floor {g[2]:.5f} = {sf:.2f}x -> {verdict}; '
          f'GROUND/UPPER = {gu:.2f}x')
