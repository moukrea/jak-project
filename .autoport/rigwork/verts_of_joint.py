#!/usr/bin/env python3
"""Table SOMMET PAR SOMMET des influences d'un joint, avec la piece dessinee d'origine.

REPERE / NATURE / BASE :
  - NATURE : la LISTE EXHAUSTIVE des enregistrements (index, 4 couples joint/poids,
             position). Pas un agregat : le defaut porte sur des sommets NOMMES.
  - REPERE : MODELE, pose de bind.
  - BASE   : un joint sans sommet rend une table VIDE — lecture quand le defaut est absent.
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

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--in', dest='inp', required=True)
    ap.add_argument('--joint', required=True)
    a = ap.parse_args()
    js, bufs = read_glb(a.inp); bins = consolidate_buffers(js, bufs)
    names, ibms, parent = skin_info(js, bins)
    tgt = [i for i, n in enumerate(names) if n.lower() == a.joint.lower()]
    if not tgt:
        tgt = [i for i, n in enumerate(names) if a.joint.lower() in n.lower()]
    mesh = js['meshes'][0]
    P = read_accessor(js, bins, mesh['primitives'][0]['attributes']['POSITION']).astype(np.float64)
    J = read_accessor(js, bins, mesh['primitives'][0]['attributes']['JOINTS_0']).astype(np.int64)
    W = wnorm(js, bins, mesh['primitives'][0]['attributes']['WEIGHTS_0'])
    vpiece = collections.defaultdict(set)
    for pi, p in enumerate(mesh['primitives']):
        for v in np.unique(read_accessor(js, bins, p['indices']).astype(np.int64).ravel()):
            vpiece[int(v)].add(texname(js, p))
    for t in tgt:
        sel = np.where((J == t) & (W > 0))[0]
        sel = np.unique(sel)
        print(f"\n=== JOINT {t} {names[t]}  parent-chain: " +
              " <- ".join(_chain(names, parent, t)) + f"   sommets(w>0)={len(sel)}")
        for v in sel:
            infl = ' '.join(f"{names[J[v,k]]}:{W[v,k]:.4f}" for k in range(J.shape[1]) if W[v, k] > 0)
            print(f"  v{v:<6} pos=({P[v][0]:8.4f},{P[v][1]:8.4f},{P[v][2]:8.4f})  "
                  f"pieces={','.join(sorted(vpiece[int(v)])):<40} {infl}")

def _chain(names, parent, j):
    out, seen = [], set()
    while j != -1 and j not in seen:
        seen.add(j); out.append(names[j]); j = parent[j]
    return out

if __name__ == '__main__':
    main()
