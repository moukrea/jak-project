#!/usr/bin/env python3
"""Dump a rigged GLB: joints, hierarchy, per-joint vertex ownership, rest positions.

REPERE / NATURE (regle des 3 questions, SPEC-keira-physique.md §7) :
  - NATURE  : positions de REPOS (deplacement soutenu), et COMPTES de sommets (population).
  - REPERE  : MODELE (bind space). La position de repos d'un joint est la translation de la
              matrice de bind M_j = inverse(IBM_j), calculee par une VRAIE INVERSE 4x4
              (np.linalg.inv), jamais par -R^T.t : cette derniere est fausse des qu'il y a
              une echelle, et a deja produit une annonce fausse le 2026-08-28.
  - BASE    : chaque compte est publie AVANT et APRES, sur le meme fichier.
"""
import argparse, os, sys, json
import numpy as np
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'scripts', 'shell'))
from retarget_hd_models import read_glb, consolidate_buffers, read_accessor, skin_info


def load(path):
    js, bufs = read_glb(path)
    bins = consolidate_buffers(js, bufs)
    return js, bins


def joint_chain(names, parent, j):
    out, seen = [], set()
    while j != -1 and j not in seen:
        seen.add(j); out.append(names[j]); j = parent[j]
    return out


def rest_positions(ibms):
    """Position de repos de chaque joint dans le repere MODELE, via inverse 4x4 COMPLETE."""
    pos = np.zeros((len(ibms), 3))
    sv = np.zeros((len(ibms), 3))
    for i, ibm in enumerate(ibms):
        M = np.linalg.inv(ibm)          # <-- VRAIE INVERSE 4x4
        pos[i] = M[0:3, 3]
        sv[i] = np.linalg.svd(ibm[0:3, 0:3], compute_uv=False)
    return pos, sv


def gather(js, bins):
    names, ibms, parent = skin_info(js, bins)
    nj = len(names)
    owned = np.zeros(nj, dtype=np.int64)      # w > 0
    dominant = np.zeros(nj, dtype=np.int64)   # w > 0.5
    wsum = np.zeros(nj)
    wmax = np.zeros(nj)
    nverts = 0
    prim_rows = []
    for mi, mesh in enumerate(js.get('meshes', [])):
        for pi, p in enumerate(mesh['primitives']):
            at = p['attributes']
            if 'JOINTS_0' not in at:
                continue
            J = read_accessor(js, bins, at['JOINTS_0']).astype(np.int64)
            W = read_accessor(js, bins, at['WEIGHTS_0']).astype(np.float64)
            if W.dtype != np.float64:
                W = W.astype(np.float64)
            # normalized weights may be ubyte/ushort
            acc = js['accessors'][at['WEIGHTS_0']]
            if acc['componentType'] == 5121:
                W = W / 255.0
            elif acc['componentType'] == 5123:
                W = W / 65535.0
            n = J.shape[0]
            nverts += n
            pj = {}
            for k in range(J.shape[1]):
                jj = J[:, k]; ww = W[:, k]
                m = ww > 0
                np.add.at(owned, jj[m], 1)
                np.add.at(wsum, jj[m], ww[m])
                md = ww > 0.5
                np.add.at(dominant, jj[md], 1)
                for a, b in zip(jj[m], ww[m]):
                    if b > wmax[a]:
                        wmax[a] = b
                for a in np.unique(jj[m]):
                    pj[int(a)] = pj.get(int(a), 0) + int((jj[m] == a).sum())
            mat = p.get('material')
            mname = js.get('materials', [{}])[mat].get('name', f'mat{mat}') if mat is not None else '-'
            prim_rows.append((mi, pi, n, mname, pj))
    return names, ibms, parent, owned, dominant, wsum, wmax, nverts, prim_rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--in', dest='inp', required=True)
    ap.add_argument('--grep', default=None, help='substring filter (case-insensitive) on joint name')
    ap.add_argument('--prims', action='store_true')
    ap.add_argument('--json', default=None)
    a = ap.parse_args()
    js, bins = load(a.inp)
    names, ibms, parent, owned, dominant, wsum, wmax, nverts, prim_rows = gather(js, bins)
    pos, sv = rest_positions(ibms)
    print(f"FILE {a.inp}")
    print(f"JOINTS {len(names)}  VERTS {nverts}  PRIMS {len(prim_rows)}")
    print(f"{'idx':>4} {'joint':<22} {'parent':<22} {'own':>5} {'dom':>5} {'wsum':>9} {'wmax':>6}  restpos(model, inv4x4)      svd(IBM3x3)")
    for i, n in enumerate(names):
        if a.grep and a.grep.lower() not in n.lower():
            continue
        p = names[parent[i]] if parent[i] != -1 else '-'
        print(f"{i:>4} {n:<22} {p:<22} {owned[i]:>5} {dominant[i]:>5} {wsum[i]:>9.3f} {wmax[i]:>6.3f}  "
              f"({pos[i][0]:8.4f},{pos[i][1]:8.4f},{pos[i][2]:8.4f})  "
              f"[{sv[i][0]:.4f},{sv[i][1]:.4f},{sv[i][2]:.4f}]")
    if a.prims:
        print("\nPRIMS (mesh,prim,verts,material) -> top joints by owned verts")
        for mi, pi, n, mname, pj in prim_rows:
            top = sorted(pj.items(), key=lambda kv: -kv[1])[:8]
            print(f"  m{mi}p{pi:<3} n={n:<6} {mname:<34} " +
                  ' '.join(f"{names[j]}={c}" for j, c in top))
    if a.json:
        json.dump({'names': names, 'parent': parent, 'owned': owned.tolist(),
                   'dominant': dominant.tolist(), 'wsum': wsum.tolist(),
                   'pos': pos.tolist(), 'nverts': nverts}, open(a.json, 'w'), indent=1)


if __name__ == '__main__':
    main()
