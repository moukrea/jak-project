#!/usr/bin/env python3
# gci_toggle_analyze.py — segmented OFF-vs-ON camera-smoothness from a SINGLE within-run
# caminterp-toggle capture. Because OFF and ON segments are interleaved a few seconds
# apart in ONE run, they share the same thermal/fps state => a clean, drift-free A/B
# (unlike two separate runs that can land at different framerates).
#
# The capture logs "GCAM-CI=0" / "GCAM-CI=1" markers each time debug.opengoal.caminterp
# is toggled; PACE-EE lines carry per-render-frame *math-camera* yaw + wall dt + integer
# time-ratio k. We assign each PACE-EE frame to the current CI state, DROP a guard window
# after each toggle (the prop is polled every ~64 frames, so the flip lands with a lag),
# then pool all OFF frames vs all ON frames and score per-render-frame camera-step
# continuity. A valid A/B requires both pools to sit at the SAME k regime (same fps).
#
# usage: gci_toggle_analyze.py <log> [guard_frames=90] [move_deg=0.05] [cut_deg=15.0]
import sys, re, statistics as st
from collections import Counter

log = sys.argv[1]
GUARD = int(sys.argv[2]) if len(sys.argv) > 2 else 90   # frames dropped after each toggle
MOVE  = float(sys.argv[3]) if len(sys.argv) > 3 else 0.05
CUT   = float(sys.argv[4]) if len(sys.argv) > 4 else 15.0

pace = re.compile(
    r'PACE-EE dt_ms=([-0-9.]+) k=([0-9]+) afc=([0-9-]+) bfc=([0-9-]+) '
    r'cam=([-0-9.]+),([-0-9.]+),([-0-9.]+) yaw=([-0-9.]+) valid=([01])')
mark = re.compile(r'GCAM-CI=([01])')

rows = []            # ordered stream: ('mark', ci) or ('pace', dict)
for line in open(log, errors='replace'):
    mm = mark.search(line)
    if mm:
        rows.append(('mark', int(mm.group(1))))
        continue
    m = pace.search(line)
    if m and m.group(9) == '1':
        rows.append(('pace', dict(dt=float(m.group(1)), k=int(m.group(2)),
                                  afc=int(m.group(3)), bfc=int(m.group(4)),
                                  yaw=float(m.group(8)))))

# assign CI state; count frames since last toggle to apply the guard drop
def unwrap(d):
    while d > 180.0: d -= 360.0
    while d < -180.0: d += 360.0
    return d

ci = None; since = 10**9; prev = None
pools = {0: [], 1: []}   # ci -> list of step dicts (guarded, consecutive)
for kind, val in rows:
    if kind == 'mark':
        ci = val; since = 0; prev = None
        continue
    r = val
    if ci is None:
        continue
    since += 1
    if prev is not None:
        dafc = r['afc'] - prev['afc']
        if 1 <= dafc <= 3 and since > GUARD:
            d = abs(unwrap(r['yaw'] - prev['yaw']))
            pools[ci].append(dict(d=d, dt=r['dt'], k=r['k']))
    prev = r

def cov(xs):
    xs = [x for x in xs if x is not None]
    if len(xs) < 2: return None
    m = st.mean(xs)
    return (st.pstdev(xs) / m) if m > 1e-9 else None

def score(pool, name):
    pan = [s for s in pool if MOVE < s['d'] < CUT]
    d = [s['d'] for s in pan]
    vel = [s['d']/s['dt'] for s in pan if s['dt'] > 0]
    ratios = [b['d']/a['d'] for a, b in zip(pan, pan[1:]) if a['d'] > MOVE]
    jump15 = (sum(1 for r in ratios if r > 1.5)/len(ratios)) if ratios else None
    kc = Counter(s['k'] for s in pan)
    kdith = (1.0 - max(kc.values())/sum(kc.values())) if kc else 0.0
    mdt = st.mean([s['dt'] for s in pan]) if pan else 0.0
    print(f"-- {name}: pan frames={len(pan)}  mean|dyaw|={st.mean(d):.4f} deg" if d else f"-- {name}: (no pan frames)")
    if not d: return None
    print(f"     step CoV={cov(d):.4f}  vel CoV={cov(vel):.4f}  "
          f"jump>1.5x={jump15:.3f}  step-ratio med={st.median(ratios):.3f}")
    print(f"     k={dict(sorted(kc.items()))} dither={kdith:.3f}  "
          f"mean dt={mdt:.2f}ms (~{1000.0/mdt:.0f} fps)")
    return dict(stepcov=cov(d), velcov=cov(vel), jump=jump15, kdith=kdith, fps=1000.0/mdt if mdt else 0)

print(f"=== gci_toggle_analyze {log} (guard={GUARD} frames) ===")
print(f"  OFF frames pooled={len(pools[0])}  ON frames pooled={len(pools[1])}")
off = score(pools[0], "caminterp OFF")
on  = score(pools[1], "caminterp ON ")
if off and on:
    print("\n  === before(OFF) -> after(ON) ===")
    print(f"  step CoV      {off['stepcov']:.4f} -> {on['stepcov']:.4f}   "
          f"({100*(off['stepcov']-on['stepcov'])/off['stepcov']:+.0f}%)")
    print(f"  vel  CoV      {off['velcov']:.4f} -> {on['velcov']:.4f}   "
          f"({100*(off['velcov']-on['velcov'])/off['velcov']:+.0f}%)")
    print(f"  jump>1.5x     {off['jump']:.3f} -> {on['jump']:.3f}   "
          f"({100*(off['jump']-on['jump'])/off['jump']:+.0f}%)")
    same = abs(off['fps']-on['fps'])/max(off['fps'],1) < 0.15 and abs(off['kdith']-on['kdith']) < 0.12
    print(f"  A/B VALIDITY: OFF ~{off['fps']:.0f}fps (dither {off['kdith']:.2f}) vs "
          f"ON ~{on['fps']:.0f}fps (dither {on['kdith']:.2f}) -> "
          f"{'SAME regime (clean A/B)' if same else 'DIFFERENT regime (confounded — interpret with care)'}")
