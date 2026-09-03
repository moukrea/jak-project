#!/usr/bin/env python3
"""gpbrf_r18_metrics_robust.py — the SAME round-18 pairs, hardened against the two noise sources
that swamped the raw per-pixel table in metrics.txt.

WHY THIS EXISTS (measured, not assumed):
  1. ANIMATED CONTENT. The owner's vantage looks over the village1 hut deck at the OCEAN. In the raw
     table the drift floor (pomOFF2 - pomOFF, identical settings) came out 0.01787 mean |dL| on the
     GROUND crop — LARGER than either parallax delta. Splitting that difference by column band gives
     2.6-3.5 on the left (hut/deck) against 7.3-15.2 on the right (water) — i.e. the floor is the
     WATER, the wind-blown foliage, Jak's idle animation and the scrolling clouds, not shading.
  2. A 2-PIXEL CAMERA STEP. FFT phase correlation on the left (ocean-free) ground region says
     pomLEGACY/pomNEW/tessLEGACY sit at shift (0,0) from pomOFF while pomOFF2/tessNEW/xtra_ambrel sit
     at (dy=+2,dx=0): the follow-cam took a 2 px vertical step between tessLEGACY and tessNEW. The
     mandated tessNEW-tessLEGACY pair therefore straddles that step, and a 2 px shift lights up every
     high-contrast edge in the frame.

SO, PER CELL: temporal MEDIAN over ~12 frames of its own 4 s capture (kills per-frame animation
flicker), per-pixel temporal STD (identifies what moves), then:
  STATIC MASK = pixels whose temporal std is below STD_MAX in EVERY cell (water, foliage, Jak and the
                clouds drop out by construction, no hand-drawn regions),
  REGISTRATION = integer shift per cell from phase correlation on the static ground, applied before
                 differencing, with an 8 px margin so nothing wraps.
Both treatments are cell-symmetric: they cannot manufacture a difference between two cells, they can
only remove a difference that is common to both. The drift floor is recomputed under exactly the same
treatment and is printed next to every number.

Usage: gpbrf_r18_metrics_robust.py <r18 dir>
"""
import os
import shutil
import subprocess
import sys

import numpy as np
from PIL import Image

CELLS = ('pomOFF', 'pomLEGACY', 'pomNEW', 'tessLEGACY', 'tessNEW', 'pomOFF2', 'xtra_ambrel')
FPS = 3          # frames/s pulled out of each 4 s capture (~12 frames)
STD_MAX = 0.010  # luma [0,1] temporal std below which a pixel counts as static
MARGIN = 8       # px kept clear on every side so an integer shift cannot wrap
BLACK = 8.0 / 255.0
d = sys.argv[1] if len(sys.argv) > 1 else '.'
TMP = '/tmp/r18_robust'


def luma_stack(mp4):
    shutil.rmtree(TMP, ignore_errors=True)
    os.makedirs(TMP)
    subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', mp4, '-vf', f'fps={FPS}',
                    f'{TMP}/f_%03d.png'], check=True)
    fs = sorted(os.listdir(TMP))
    out = []
    for f in fs:
        a = np.asarray(Image.open(os.path.join(TMP, f)).convert('RGB'), dtype=np.float32) / 255.0
        out.append(a[..., 0] * 0.2126 + a[..., 1] * 0.7152 + a[..., 2] * 0.0722)
    shutil.rmtree(TMP, ignore_errors=True)
    return np.stack(out)


med, tstd, nfr = {}, {}, {}
for c in CELLS:
    p = os.path.join(d, c + '.mp4')
    if not os.path.isfile(p):
        continue
    st = luma_stack(p)
    nfr[c] = st.shape[0]
    med[c] = np.median(st, axis=0)
    tstd[c] = st.std(axis=0)
    del st

if 'pomOFF' not in med:
    sys.exit('no pomOFF.mp4')
ref = med['pomOFF']
H, W = ref.shape
print('=== PBR ROUND-18 A/B, HARDENED (temporal median + static mask + registration) ===')
print(f'    frame {W}x{H};  frames per cell: ' + ', '.join(f'{c}={nfr[c]}' for c in med))

static = np.ones((H, W), dtype=bool)
for c in med:
    static &= tstd[c] < STD_MAX
row_ok = np.percentile(ref, 99, axis=1) > BLACK
col_ok = np.percentile(ref, 99, axis=0) > BLACK
static &= np.outer(row_ok, col_ok) & (ref > BLACK)
print(f'    STATIC pixels (temporal std < {STD_MAX} in ALL cells, no letterbox): '
      f'{100.0 * static.mean():.1f}% of frame')

g0, g1 = int(round(0.55 * H)), int(round(0.95 * H))
u0, u1 = int(round(0.20 * H)), int(round(0.50 * H))
BANDS = {'GROUND': (g0, g1), 'UPPER': (u0, u1), 'WHOLE': (MARGIN, H - MARGIN)}


def phase_shift(a, b):
    """integer (dy,dx) that best aligns b onto a (both mean-removed), + correlation peak."""
    a = a - a.mean()
    b = b - b.mean()
    Fa, Fb = np.fft.rfft2(a), np.fft.rfft2(b)
    R = Fa * np.conj(Fb)
    R /= (np.abs(R) + 1e-12)
    c = np.fft.irfft2(R, s=a.shape)
    i = np.unravel_index(np.argmax(c), c.shape)
    dy = i[0] if i[0] < a.shape[0] // 2 else i[0] - a.shape[0]
    dx = i[1] if i[1] < a.shape[1] // 2 else i[1] - a.shape[1]
    return int(dy), int(dx), float(c.max())


# registration reference region: static ground, ocean-free by construction of the static mask
reg_ref = ref[g0:g1, :]
shifts = {}
for c in med:
    dy, dx, pk = phase_shift(reg_ref, med[c][g0:g1, :])
    if abs(dy) > MARGIN or abs(dx) > MARGIN:
        dy, dx = 0, 0   # implausible: refuse to shift rather than compare unrelated pixels
    shifts[c] = (dy, dx, pk)
print('    registration vs pomOFF (dy,dx,peak): ' +
      '  '.join(f'{c}=({shifts[c][0]},{shifts[c][1]},{shifts[c][2]:.2f})' for c in med))
print()


def cmp_pair(a, b, band):
    if a not in med or b not in med:
        return None
    r0, r1 = BANDS[band]
    r0 = max(r0, MARGIN)
    r1 = min(r1, H - MARGIN)
    dya, dxa, _ = shifts[a]
    dyb, dxb, _ = shifts[b]
    ys = slice(r0, r1)
    xs = slice(MARGIN, W - MARGIN)

    def take(img, dy, dx):
        return img[r0 + dy:r1 + dy, MARGIN + dx:W - MARGIN + dx]
    A = take(med[a], dya, dxa)
    B = take(med[b], dyb, dxb)
    M = (static[ys, xs] & take(static, dya, dxa) & take(static, dyb, dxb))
    if M.sum() < 1000:
        return None
    dl = np.abs(A - B)[M]
    return float(dl.mean()), float(np.percentile(dl, 95)), int(M.sum())


PAIRS = (
    ('pomLEGACY - pomOFF', 'pomLEGACY', 'pomOFF'),
    ('pomNEW - pomOFF', 'pomNEW', 'pomOFF'),
    ('pomOFF2 - pomOFF', 'pomOFF2', 'pomOFF'),
    ('pomNEW - pomLEGACY', 'pomNEW', 'pomLEGACY'),
    ('tessNEW - tessLEGACY', 'tessNEW', 'tessLEGACY'),
    ('xtra_ambrel - pomOFF2', 'xtra_ambrel', 'pomOFF2'),
)
hdr = f'{"pair":22s} {"crop":6s} {"mean|dL|":>10s} {"p95|dL|":>10s} {"npx":>9s}'
print(hdr)
print('-' * len(hdr))
res = {}
for label, a, b in PAIRS:
    for band in ('GROUND', 'UPPER', 'WHOLE'):
        r = cmp_pair(a, b, band)
        if r is None:
            print(f'{label:22s} {band:6s} {"(n/a)":>10s}')
            continue
        res[(label, band)] = r
        print(f'{label:22s} {band:6s} {r[0]:10.5f} {r[1]:10.5f} {r[2]:9d}')
    print()

floor = res.get(('pomOFF2 - pomOFF', 'GROUND'))
print('=== READING (GROUND, hardened; the floor got the identical treatment) ===')
if floor:
    print(f'  DRIFT FLOOR      mean|dL| = {floor[0]:.5f}   p95 = {floor[1]:.5f}')
for label in ('pomLEGACY - pomOFF', 'pomNEW - pomOFF', 'pomNEW - pomLEGACY',
              'tessNEW - tessLEGACY', 'xtra_ambrel - pomOFF2'):
    r, ru = res.get((label, 'GROUND')), res.get((label, 'UPPER'))
    if not r:
        continue
    ratio = (r[0] / floor[0]) if floor and floor[0] > 0 else float('nan')
    gu = (r[0] / ru[0]) if ru and ru[0] > 0 else float('nan')
    print(f'  {label:22s} mean|dL| = {r[0]:.5f} = {ratio:6.2f}x floor;  GROUND/UPPER = {gu:.2f}x')
