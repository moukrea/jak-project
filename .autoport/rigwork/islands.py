#!/usr/bin/env python3
"""Composantes connexes (ILOTS) d'une piece dessinee, et le joint qui pilote chacune.

REPERE / NATURE / BASE :
  - NATURE : une PARTITION topologique (ilots de triangles) + par ilot une POPULATION
             (sommets) et une ETENDUE (bbox). Un ilot est une PIECE PHYSIQUE separee.
  - REPERE : MODELE, pose de bind.
  - BASE   : une piece d'un seul tenant rend UN ilot ; c'est la lecture quand il n'y a
             pas d'accessoire separe a trouver.
Les positions sont fusionnees par coordonnee (les splits UV dupliquent un sommet
geometrique en plusieurs indices : sans fusion, une piece soudee parait en morceaux).
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

class DSU:
    def __init__(s, n): s.p = list(range(n))
    def f(s, x):
        while s.p[x] != x: s.p[x] = s.p[s.p[x]]; x = s.p[x]
        return x
    def u(s, a, b):
        a, b = s.f(a), s.f(b)
        if a != b: s.p[a] = b

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--in', dest='inp', required=True)
    ap.add_argument('--piece', type=int, nargs='*', default=None)
    ap.add_argument('--min-verts', type=int, default=1)
    a = ap.parse_args()
    js, bufs = read_glb(a.inp); bins = consolidate_buffers(js, bufs)
    names, ibms, parent = skin_info(js, bins)
    mesh = js['meshes'][0]
    P0 = read_accessor(js, bins, mesh['primitives'][0]['attributes']['POSITION']).astype(np.float64)
    J0 = read_accessor(js, bins, mesh['primitives'][0]['attributes']['JOINTS_0']).astype(np.int64)
    W0 = wnorm(js, bins, mesh['primitives'][0]['attributes']['WEIGHTS_0'])
    # weld by coordinate
    key = {}
    weld = np.zeros(len(P0), dtype=np.int64)
    for i, p in enumerate(P0):
        k = (round(p[0], 6), round(p[1], 6), round(p[2], 6))
        weld[i] = key.setdefault(k, len(key))
    print(f"FILE {a.inp}\nPOOL {len(P0)} indices -> {len(key)} sommets geometriques (fusion par coordonnee)")
    for pi, p in enumerate(mesh['primitives']):
        if a.piece and pi not in a.piece: continue
        idx = read_accessor(js, bins, p['indices']).astype(np.int64).ravel()
        tris = idx.reshape(-1, 3)
        d = DSU(len(key))
        for t in tris:
            w = weld[t]
            d.u(w[0], w[1]); d.u(w[1], w[2])
        comp = collections.defaultdict(list)
        for v in np.unique(idx):
            comp[d.f(weld[v])].append(v)
        tri_of = collections.Counter(d.f(weld[t[0]]) for t in tris)
        print(f"\nPIECE {pi:>2} tex={texname(js,p):<24} tris={len(tris)} ilots={len(comp)}")
        for c, vs in sorted(comp.items(), key=lambda kv: -len(kv[1])):
            if len(vs) < a.min_verts: continue
            vs = np.array(vs)
            lo = P0[vs].min(axis=0); hi = P0[vs].max(axis=0); ctr = P0[vs].mean(axis=0)
            jw = collections.Counter()
            for k in range(J0.shape[1]):
                m = W0[vs, k] > 0
                for j, w in zip(J0[vs, k][m], W0[vs, k][m]): jw[int(j)] += float(w)
            tot = sum(jw.values()) or 1.0
            top = ' '.join(f"{names[j]}={w/tot*100:.1f}%" for j, w in jw.most_common(5))
            print(f"   ilot v={len(vs):>4} t={tri_of[c]:>4} ctr=({ctr[0]:7.4f},{ctr[1]:7.4f},{ctr[2]:7.4f}) "
                  f"bb x[{lo[0]:7.4f},{hi[0]:7.4f}] y[{lo[1]:7.4f},{hi[1]:7.4f}] z[{lo[2]:7.4f},{hi[2]:7.4f}]")
            print(f"        -> {top}")

if __name__ == '__main__':
    main()
