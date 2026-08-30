#!/usr/bin/env python3
"""Per-joint DOMINANT-vertex census: material, bbox, count.

REPERE / NATURE :
  - NATURE : une POPULATION de sommets (compte) + une ETENDUE (bbox), pas un scalaire d'amplitude.
  - REPERE : MODELE (pose de bind, POSITION brute du glb).
  - BASE   : un joint qui ne possede aucun sommet rend 0 partout — c'est la lecture quand
             le defaut est absent.
"""
import argparse, os, sys, collections
import numpy as np
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'scripts', 'shell'))
from retarget_hd_models import read_glb, consolidate_buffers, read_accessor, skin_info

def wnorm(js, bins, idx):
    W = read_accessor(js, bins, idx).astype(np.float64)
    ct = js['accessors'][idx]['componentType']
    if ct == 5121: W /= 255.0
    elif ct == 5123: W /= 65535.0
    return W

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--in', dest='inp', required=True)
    ap.add_argument('--joints', nargs='*', default=None)
    ap.add_argument('--thresh', type=float, default=0.5)
    ap.add_argument('--any', action='store_true', help='count w>0 instead of w>thresh')
    a = ap.parse_args()
    js, bufs = read_glb(a.inp); bins = consolidate_buffers(js, bufs)
    names, ibms, parent = skin_info(js, bins)
    want = None
    if a.joints:
        want = {i for i, n in enumerate(names) if any(s.lower() in n.lower() for s in a.joints)}
    # accumulate
    per = collections.defaultdict(lambda: collections.defaultdict(lambda: [0, None, None]))
    for mi, mesh in enumerate(js.get('meshes', [])):
        for pi, p in enumerate(mesh['primitives']):
            at = p['attributes']
            if 'JOINTS_0' not in at: continue
            J = read_accessor(js, bins, at['JOINTS_0']).astype(np.int64)
            W = wnorm(js, bins, at['WEIGHTS_0'])
            P = read_accessor(js, bins, at['POSITION']).astype(np.float64)
            mat = p.get('material')
            mname = js.get('materials', [{}])[mat].get('name', f'mat{mat}') if mat is not None else '-'
            for k in range(J.shape[1]):
                sel = W[:, k] > (0.0 if a.any else a.thresh)
                if not sel.any(): continue
                jj = J[sel, k]; pp = P[sel]
                for j in np.unique(jj):
                    if want is not None and int(j) not in want: continue
                    m = jj == j
                    e = per[int(j)][mname]
                    e[0] += int(m.sum())
                    lo = pp[m].min(axis=0); hi = pp[m].max(axis=0)
                    e[1] = lo if e[1] is None else np.minimum(e[1], lo)
                    e[2] = hi if e[2] is None else np.maximum(e[2], hi)
    mode = 'w>0' if a.any else f'w>{a.thresh}'
    print(f"FILE {a.inp}   mode={mode}")
    for j in sorted(per):
        tot = sum(v[0] for v in per[j].values())
        print(f"\nJOINT {j:>3} {names[j]:<22} parent={names[parent[j]] if parent[j]!=-1 else '-':<20} total={tot}")
        for mname, (c, lo, hi) in sorted(per[j].items(), key=lambda kv: -kv[1][0]):
            print(f"    {c:>6}  {mname:<40} x[{lo[0]:7.4f},{hi[0]:7.4f}] y[{lo[1]:7.4f},{hi[1]:7.4f}] z[{lo[2]:7.4f},{hi[2]:7.4f}]")

if __name__ == '__main__':
    main()
