#!/usr/bin/env python3
# gci_stepmetric.py — Gcamera-interp per-RENDER-frame camera-smoothness metric.
#
# The owner's judder = uneven per-frame camera ROTATION during a right-stick pan at
# sub-60fps. With render interpolation OFF the render yaw advances by k*theta per frame
# (k = integer time-ratio, dithers 1<->2<->3 at sub-60fps) => uneven step => judder.
# With interpolation ON the render yaw advances proportional to REAL display time =>
# even step / even angular velocity => smooth. This tool quantifies that from a PACE-EE
# capture (per-render-frame *math-camera* forward-yaw + wall dt + integer k), so we can
# show device before(OFF)->after(ON) and confirm the k-dither step is gone.
#
# Metrics over the PAN window (frames where the camera is actually rotating, cuts
# dropped):
#   step CoV        = sd/mean of |dyaw| per render frame   (LOWER = smoother)
#   vel  CoV        = sd/mean of |dyaw|/dt (deg/ms)         (LOWER = smoother; accounts
#                                                            for real display time)
#   jump>1.5x frac  = fraction of consecutive frames whose |dyaw| jumps >1.5x the prev
#                     (the discrete k-dither signature; ~0 when smooth)
#   step-ratio med  = median |dyaw[i]|/|dyaw[i-1]|          (~1.0 == perfectly even)
# Plus context: k-histogram (confirms sub-60 dither), mean pan rate + total swept
# (confirms the pan happened and speed is preserved), game-clock bfc rate (speed check).
#
# usage: gci_stepmetric.py <pace-ee.log> [move_deg=0.05] [cut_deg=15.0]
import sys, re, statistics as st
from collections import Counter

log = sys.argv[1]
MOVE = float(sys.argv[2]) if len(sys.argv) > 2 else 0.05   # min |dyaw| to count as "panning"
CUT  = float(sys.argv[3]) if len(sys.argv) > 3 else 15.0   # |dyaw| above this = a camera cut, dropped

pat = re.compile(
    r'PACE-EE dt_ms=([-0-9.]+) k=([0-9]+) afc=([0-9-]+) bfc=([0-9-]+) '
    r'cam=([-0-9.]+),([-0-9.]+),([-0-9.]+) yaw=([-0-9.]+) valid=([01])')
rows = []
for line in open(log, errors='replace'):
    m = pat.search(line)
    if not m:
        continue
    rows.append(dict(dt=float(m.group(1)), k=int(m.group(2)), afc=int(m.group(3)),
                     bfc=int(m.group(4)), yaw=float(m.group(8)), valid=int(m.group(9))))

rows = [r for r in rows if r['valid'] == 1]

def unwrap(d):
    while d > 180.0:
        d -= 360.0
    while d < -180.0:
        d += 360.0
    return d

# per-render-frame yaw step over consecutive frames (afc advances 1..3; drop gaps)
steps = []   # dict(d=|dyaw|, dt, k, signed)
for a, b in zip(rows, rows[1:]):
    dafc = b['afc'] - a['afc']
    if dafc < 1 or dafc > 3:
        continue
    d = unwrap(b['yaw'] - a['yaw'])
    steps.append(dict(d=abs(d), signed=d, dt=b['dt'], k=b['k']))

# PAN window = frames where the camera is actually rotating, cuts dropped
pan = [s for s in steps if MOVE < s['d'] < CUT]

def cov(xs):
    xs = [x for x in xs if x is not None]
    if len(xs) < 2:
        return None
    m = st.mean(xs)
    return (st.pstdev(xs) / m) if m > 1e-9 else None

def fmt(x, nd=4):
    return "n/a" if x is None else f"{x:.{nd}f}"

print(f"=== gci_stepmetric {log} ===")
print(f"  PACE-EE valid rows={len(rows)}  consecutive steps={len(steps)}  "
      f"PAN frames (|dyaw| in ({MOVE},{CUT}) deg)={len(pan)}")
if len(pan) < 30:
    print("  !! too few pan frames — the injected pan may not have registered "
          "(check pad_replay ANCHOR + foreground).")

d   = [s['d'] for s in pan]
vel = [s['d'] / s['dt'] for s in pan if s['dt'] > 0]
# consecutive |dyaw| ratio (the k-dither jump signature)
ratios = []
for x, y in zip(pan, pan[1:]):
    if x['d'] > MOVE:
        ratios.append(y['d'] / x['d'])
jump15 = (sum(1 for r in ratios if r > 1.5) / len(ratios)) if ratios else None

if d:
    print(f"  mean |dyaw|/frame = {st.mean(d):.4f} deg   sd = {st.pstdev(d):.4f}")
    print(f"  >> step CoV        = {fmt(cov(d))}    (LOWER=smoother; k-dither=>high)")
    print(f"  >> vel  CoV        = {fmt(cov(vel))}    (|dyaw|/ms; LOWER=smoother)")
    print(f"  >> jump>1.5x frac  = {fmt(jump15,3)}     (k-dither signature; ~0=smooth)")
    print(f"  >> step-ratio med  = {fmt(st.median(ratios) if ratios else None,3)}  (~1.0=even)")

# context: k histogram over the pan (confirm sub-60 dither), speed preservation
kc = Counter(s['k'] for s in pan)
kdither = 1.0 - (max(kc.values()) / sum(kc.values())) if kc else 0.0
print(f"  time-ratio k over pan = {dict(sorted(kc.items()))}  "
      f"(dither frac={kdither:.3f}; >0 => sub-60 regime the fix targets)")
if pan:
    swept = sum(s['signed'] for s in pan)
    dt_tot = sum(s['dt'] for s in pan) / 1000.0
    print(f"  pan: total swept={swept:.1f} deg over {dt_tot:.1f}s  "
          f"mean rate={swept/dt_tot:.1f} deg/s  (speed check: compare OFF vs ON)")
# game-clock rate (render-only fix must NOT change this): bfc advance / wall-sec
gc = [r for r in rows if r['bfc'] > 0]
if len(gc) > 10:
    dbfc = gc[-1]['bfc'] - gc[0]['bfc']
    dwall = sum(r['dt'] for r in rows) / 1000.0
    if dwall > 0:
        print(f"  game-clock: bfc advanced {dbfc} over {dwall:.1f}s wall "
              f"= {dbfc/dwall:.1f} game-frames/s (must match OFF vs ON => speed unchanged)")
