#!/usr/bin/env python3
"""AUDIT PAR VALEUR : sommets COINCIDENTS portant des liaisons de peau DIFFERENTES.

Deux sommets a la MEME position de bind qui ne portent pas la MEME liaison se separent
des que leurs os divergent : c'est une DECHIRURE garantie, lisible sans aucune course.
Un split UV legitime duplique la position AVEC la meme liaison — il ne ressort pas ici.

REPERE / NATURE / BASE :
  - NATURE : une POPULATION de couples (paires de sommets), pas une amplitude.
  - REPERE : MODELE, pose de bind ; la coincidence est testee sur la position brute.
  - BASE   : un modele dont chaque position a une liaison unique rend 0 couple. C'est la
             lecture quand le defaut est absent, et elle est atteignable.
Balayage EXHAUSTIF du pool : aucune liste de sites ecrite a la main.
"""
import argparse, os, sys, collections, hashlib
import numpy as np
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'scripts', 'shell'))
from retarget_hd_models import read_glb, consolidate_buffers, read_accessor, skin_info

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--in', dest='inp', required=True)
    ap.add_argument('--tol', type=float, default=1e-4, help='ecart de poids tolere')
    ap.add_argument('--drawn-only', action='store_true', default=True)
    a = ap.parse_args()
    js, bufs = read_glb(a.inp); bins = consolidate_buffers(js, bufs)
    names, ibms, parent = skin_info(js, bins)
    mesh = js['meshes'][0]
    P = read_accessor(js, bins, mesh['primitives'][0]['attributes']['POSITION']).astype(np.float64)
    J = read_accessor(js, bins, mesh['primitives'][0]['attributes']['JOINTS_0']).astype(np.int64)
    acc = mesh['primitives'][0]['attributes']['WEIGHTS_0']
    W = read_accessor(js, bins, acc).astype(np.float64)
    ct = js['accessors'][acc]['componentType']
    if ct == 5121: W /= 255.0
    elif ct == 5123: W /= 65535.0
    drawn = set()
    vtex = collections.defaultdict(set)
    for pi, p in enumerate(mesh['primitives']):
        mat = p.get('material')
        t = js['materials'][mat].get('pbrMetallicRoughness', {}).get('baseColorTexture', {}).get('index') if mat is not None else None
        tn = js['images'][js['textures'][t]['source']].get('name', '?') if t is not None else '-'
        for v in np.unique(read_accessor(js, bins, p['indices']).astype(np.int64).ravel()):
            drawn.add(int(v)); vtex[int(v)].add(tn)
    def bind(v):
        return tuple(sorted((int(J[v, k]), round(float(W[v, k]), 4))
                            for k in range(J.shape[1]) if W[v, k] > 0))
    groups = collections.defaultdict(list)
    for v in sorted(drawn):
        groups[(round(P[v][0], 6), round(P[v][1], 6), round(P[v][2], 6))].append(v)
    bad = []
    for pos, vs in groups.items():
        binds = {bind(v) for v in vs}
        if len(binds) > 1:
            bad.append((pos, vs))
    # PROVENANCE PAR CONTENU, PAS PAR CHEMIN. Le 2026-08-30 un `seam_audit.APRES.txt` archive a
    # 04:57 — donc pris AVANT la version finale de l'outil (05:11) et du modele (05:15) — a
    # publie 92 divergences la ou le modele LIVRE en porte 89. Le chiffre du rapport etait juste,
    # c'est sa piece justificative qui etait perimee, et rien dans l'en-tete ne permettait de le
    # voir : un CHEMIN ne dit pas QUEL contenu a ete lu. On signe donc la sortie par le md5 du
    # fichier lu, pour qu'une comparaison contre le glb livre suffise a trancher, sans jugement.
    # (mtime ecarte deliberement : un fichier reecrit a l'identique en change, cf. 2026-08-19.)
    with open(a.inp, 'rb') as fh:
        _md5 = hashlib.md5(fh.read()).hexdigest()
    print(f"FILE {a.inp}")
    print(f"MD5-DU-FICHIER-LU {_md5}")
    print(f"sommets DESSINES {len(drawn)} -> {len(groups)} positions ; "
          f"positions a liaisons DIVERGENTES : {len(bad)}")
    for pos, vs in sorted(bad, key=lambda kv: kv[0][2]):
        print(f"\n  pos=({pos[0]:8.4f},{pos[1]:8.4f},{pos[2]:8.4f})")
        for v in vs:
            infl = ' '.join(f"{names[J[v,k]]}:{W[v,k]:.4f}" for k in range(J.shape[1]) if W[v, k] > 0)
            print(f"     v{v:<6} tex={','.join(sorted(vtex[v])):<40} {infl}")

if __name__ == '__main__':
    main()
