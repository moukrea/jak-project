"""Characterise the torn edges of the mid-hair strands.

Decides between the two candidate fixes for PRIORITE 1 `hair-skinning`:
  (a) the low-side vertices are COINCIDENT duplicates of high-side ones (UV seam split) ->
      the fix is the weld invariant: coincident vertices carry identical weights;
  (b) they are genuinely distinct mesh positions with a weight discontinuity ->
      the fix is a weight transfer (reskin), and it must spare the root (SPEC 2 anchoring).
"""
import os
import sys
import json

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..'))
import numpy as np
sys.path.insert(0, os.path.abspath('.autoport'))
from physics_c6_volumes import load_geometry as lg

g = lg('keira-hd')
V, jn, W, F = g['V'], g['names'], g['W'], g['F']
J = g['J']
ji = {n: i for i, n in enumerate(jn)}
Wd = np.zeros((len(V), len(jn)), dtype=np.float32)
for k in range(W.shape[1]):
    np.add.at(Wd, (np.arange(len(V)), J[:, k]), W[:, k])

par = {}
k2e = json.load(open('recharged_assets/hd_anim/keira-hd-k2e.json', errors='ignore'))
rows = k2e['rows'] if isinstance(k2e, dict) and 'rows' in k2e else k2e
if isinstance(rows, dict):
    rows = list(rows.values())
byk = {r['k']: r for r in rows if isinstance(r, dict) and 'k' in r}
for r in rows:
    if isinstance(r, dict) and 'hd_name' in r:
        p = byk.get(r.get('hd_parent'))
        par[r['hd_name']] = p['hd_name'] if p else None

cj, cur = {}, None
for ln in open('recharged_assets/physics_chains.txt', errors='ignore'):
    if ln.startswith('chain '):
        cur = ln.split()[1]
        cj[cur] = []
    elif ln.startswith('j ') and cur:
        cj[cur].append(ln.split()[1])

edges = set()
for t in F:
    a, b, c = int(t[0]), int(t[1]), int(t[2])
    for u, v in ((a, b), (b, c), (a, c)):
        edges.add((u, v) if u < v else (v, u))

# coincident-position groups
pos = {}
for i in range(len(V)):
    pos.setdefault((round(float(V[i][0]), 3), round(float(V[i][1]), 3),
                    round(float(V[i][2]), 3)), []).append(i)
coincident = {i: grp for grp in pos.values() if len(grp) > 1 for i in grp}

for cn in ('rmidhair', 'lmidhair', 'lbang', 'rbang'):
    sim = [j for j in cj[cn] if j in ji]
    drv = set(sim)
    chg = True
    while chg:
        chg = False
        for j, p in par.items():
            if p in drv and j not in drv and j in ji:
                drv.add(j)
                chg = True
    cols = [ji[j] for j in drv if j in ji]
    ws = Wd[:, cols].sum(1)
    own = set(int(x) for x in np.where(ws > 0.0)[0])
    torn = [(u, v) for (u, v) in edges
            if (u in own or v in own) and abs(ws[u] - ws[v]) > 0.5]

    root = V[[ji[j] for j in sim][0]] if False else None
    # strand axis: use bind positions of the chain joints
    P = g['P']
    jpos = np.array([P[ji[j]] for j in sim])
    anchor = jpos[0]
    axis = jpos[-1] - jpos[0]
    L = float(np.linalg.norm(axis)) or 1.0
    axis = axis / L

    dup_low = 0
    dup_pair_same_pos = 0
    dists = []
    lowsiders = set()
    for (u, v) in torn:
        lo = u if ws[u] < ws[v] else v
        hi = v if lo == u else u
        lowsiders.add(lo)
        if lo in coincident:
            dup_low += 1
            grp = [i for i in coincident[lo] if i != lo]
            if any(abs(float(ws[i] - ws[hi])) < 1e-6 for i in grp):
                dup_pair_same_pos += 1
        t = float(np.dot(V[lo] - anchor, axis))
        dists.append(t)
    dists = np.array(dists) if dists else np.zeros(0)
    # which joints hold the lost weight on the low side
    lost = {}
    for lo in lowsiders:
        for c in np.where(Wd[lo] > 0)[0]:
            if c not in cols:
                lost[jn[c]] = lost.get(jn[c], 0.0) + float(Wd[lo][c])
    top = sorted(lost.items(), key=lambda x: -x[1])[:3]
    tot = max(sum(lost.values()), 1e-9)

    print("%-9s torn=%-4d  strand_len=%.0fu  low-side verts=%d" % (cn, len(torn), L, len(lowsiders)))
    print("           low-side vertex is a COINCIDENT duplicate : %d/%d" % (dup_low, len(torn)))
    print("           ... and its twin already carries the high-side weight : %d" % dup_pair_same_pos)
    if len(dists):
        print("           position along strand (0=root): min=%.0fu med=%.0fu max=%.0fu  (%.0f%% of len at median)"
              % (dists.min(), float(np.median(dists)), dists.max(), 100.0 * float(np.median(dists)) / L))
    print("           lost weight -> %s" % ' · '.join('%s %.0f%%' % (k, 100.0 * v / tot) for k, v in top))
