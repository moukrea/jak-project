#!/usr/bin/env python3
"""Recensement PAR PIECE DESSINEE (prim = un effect merc = une texture).

REPERE / NATURE / BASE (regle des 3 questions) :
  - NATURE : une POPULATION (compte de sommets REELLEMENT INDEXES par la piece) et une
             ETENDUE (bbox). Pas une amplitude, pas une variance.
  - REPERE : MODELE, pose de bind (POSITION brute du glb ; scale IBM uniforme 0.7143).
  - BASE   : une piece dont aucun sommet ne porte le joint interroge rend 0. C'est la
             lecture quand le defaut est ABSENT — donc le zero est signifiant.

ATTENTION : les 24 prims PARTAGENT UN SEUL accessor POSITION/JOINTS/WEIGHTS. Compter par
prim sans passer par ses INDICES compte le pool 24 fois (c'est ce que fait un recensement
naif, et il rend 82 la ou la piece en a 82/24). On indexe donc explicitement.
"""
import argparse, os, sys, collections
import numpy as np
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'scripts', 'shell'))
from retarget_hd_models import read_glb, consolidate_buffers, read_accessor, skin_info

def wnorm(js, bins, idx):
    W = read_accessor(js, bins, idx).astype(np.float64)
    ct = js['accessors'][idx]['componentType']
    if ct == 5121: W = W / 255.0
    elif ct == 5123: W = W / 65535.0
    return W

def texname(js, p):
    mat = p.get('material')
    if mat is None: return '-'
    t = js['materials'][mat].get('pbrMetallicRoughness', {}).get('baseColorTexture', {}).get('index')
    if t is None: return js['materials'][mat].get('name', f'mat{mat}')
    return js['images'][js['textures'][t]['source']].get('name', '?')

def load(path):
    js, bufs = read_glb(path); bins = consolidate_buffers(js, bufs)
    names, ibms, parent = skin_info(js, bins)
    return js, bins, names, ibms, parent

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--in', dest='inp', required=True)
    ap.add_argument('--top', type=int, default=10)
    ap.add_argument('--joint', default=None, help='ne lister que les pieces touchant ce joint')
    a = ap.parse_args()
    js, bins, names, ibms, parent = load(a.inp)
    mesh = js['meshes'][0]
    print(f"FILE {a.inp}")
    print(f"POOL {js['accessors'][mesh['primitives'][0]['attributes']['POSITION']]['count']} verts partages, "
          f"{len(mesh['primitives'])} pieces, {len(names)} joints")
    jfilter = None
    if a.joint:
        jfilter = {i for i, n in enumerate(names) if a.joint.lower() in n.lower()}
    for pi, p in enumerate(mesh['primitives']):
        idx = read_accessor(js, bins, p['indices']).astype(np.int64).ravel()
        vs = np.unique(idx)
        J = read_accessor(js, bins, p['attributes']['JOINTS_0']).astype(np.int64)[vs]
        W = wnorm(js, bins, p['attributes']['WEIGHTS_0'])[vs]
        P = read_accessor(js, bins, p['attributes']['POSITION']).astype(np.float64)[vs]
        own = collections.Counter(); dom = collections.Counter(); wsum = collections.Counter()
        for k in range(J.shape[1]):
            m = W[:, k] > 0
            for j, w in zip(J[m, k], W[m, k]):
                own[int(j)] += 1; wsum[int(j)] += float(w)
            md = W[:, k] > 0.5
            for j in J[md, k]: dom[int(j)] += 1
        if jfilter is not None and not (set(own) & jfilter):
            continue
        tn = texname(js, p)
        print(f"\nPIECE {pi:>2}  tex={tn:<24} tris={len(idx)//3:>5} verts={len(vs):>5}")
        for j, c in own.most_common(a.top):
            sel = np.zeros(len(vs), bool)
            for k in range(J.shape[1]):
                sel |= (J[:, k] == j) & (W[:, k] > 0)
            lo = P[sel].min(axis=0); hi = P[sel].max(axis=0)
            mark = '  <<<' if (jfilter and j in jfilter) else ''
            print(f"      {names[j]:<20} own={c:>5} dom={dom[j]:>5} wsum={wsum[j]:>8.2f}  "
                  f"x[{lo[0]:7.4f},{hi[0]:7.4f}] y[{lo[1]:7.4f},{hi[1]:7.4f}] z[{lo[2]:7.4f},{hi[2]:7.4f}]{mark}")

if __name__ == '__main__':
    main()
