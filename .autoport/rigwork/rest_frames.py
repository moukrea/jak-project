#!/usr/bin/env python3
"""Positions de REPOS, par INVERSE 4x4 COMPLETE, et demonstration que -R^T.t est faux ici.

REPERE / NATURE / BASE :
  - NATURE : des POSITIONS (deplacement soutenu), pas une variance.
  - REPERE : deux reperes publies cote a cote —
        (a) MODELE : position de repos du joint = translation de M_j = inv(IBM_j) ;
        (b) LOCAL AU JOINT PILOTE : offset du sommet dans le repere de son os, IBM_j . p.
      C'est (b) qui dit ce que change une reliaison : le sommet ne bouge pas au repos, il
      change de REPERE PORTEUR.
  - BASE : au repos, skinning = somme_j w_j . M_j . IBM_j . p = p pour toute liaison qui somme
      a 1. Une reliaison est donc NEUTRE a la pose de bind — verifie ici numeriquement, ce qui
      est la lecture attendue quand l'operation est correcte.

POURQUOI L'INVERSE COMPLETE : l'IBM de ce rig porte une echelle uniforme 0.7143 (valeurs
singulieres publiees). La formule abregee -R^T.t n'est valable que pour une isometrie ; hors
de son domaine elle se trompe du carre de l'echelle. Elle a deja fait annoncer a l'owner, le
2026-08-28, un defaut inexistant a 62 fois la taille du modele. Les deux valeurs sont donc
publiees COTE A COTE, avec leur ecart.
"""
import argparse, os, sys
import numpy as np
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'scripts', 'shell'))
from retarget_hd_models import read_glb, consolidate_buffers, read_accessor, skin_info

def wnorm(js, bins, idx):
    W = read_accessor(js, bins, idx).astype(np.float64)
    ct = js['accessors'][idx]['componentType']
    if ct == 5121: W = W / 255.0
    elif ct == 5123: W = W / 65535.0
    return W

def chain(names, parent, j):
    out, seen = [], set()
    while j != -1 and j not in seen:
        seen.add(j); out.append(names[j]); j = parent[j]
    return out

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--in', dest='inp', required=True)
    ap.add_argument('--joints', nargs='+', required=True)
    ap.add_argument('--verts', nargs='*', type=int, default=[])
    a = ap.parse_args()
    js, bufs = read_glb(a.inp); bins = consolidate_buffers(js, bufs)
    names, ibms, parent = skin_info(js, bins)
    mesh = js['meshes'][0]
    P = read_accessor(js, bins, mesh['primitives'][0]['attributes']['POSITION']).astype(np.float64)
    J = read_accessor(js, bins, mesh['primitives'][0]['attributes']['JOINTS_0']).astype(np.int64)
    W = wnorm(js, bins, mesh['primitives'][0]['attributes']['WEIGHTS_0'])
    print(f"FILE {a.inp}")
    print("\n-- POSITION DE REPOS DU JOINT, repere MODELE --")
    print(f"{'joint':<16} {'inverse 4x4 COMPLETE (juste)':<34} {'-R^T.t (abregee, FAUSSE ici)':<34} "
          f"{'ecart':<9} valeurs singulieres IBM")
    idx = {}
    for jn in a.joints:
        m = [i for i, n in enumerate(names) if n == jn]
        if not m:
            print(f"{jn:<16} ABSENT DU RIG"); continue
        j = m[0]; idx[jn] = j
        ibm = ibms[j]
        M = np.linalg.inv(ibm)                 # <-- vraie inverse 4x4
        good = M[0:3, 3]
        bad = -(ibm[0:3, 0:3].T @ ibm[0:3, 3])  # <-- formule abregee, hors domaine
        sv = np.linalg.svd(ibm[0:3, 0:3], compute_uv=False)
        print(f"{jn:<16} ({good[0]:9.4f},{good[1]:9.4f},{good[2]:9.4f})   "
              f"({bad[0]:9.4f},{bad[1]:9.4f},{bad[2]:9.4f})   "
              f"{np.linalg.norm(good-bad):8.4f}  [{sv[0]:.4f},{sv[1]:.4f},{sv[2]:.4f}]")
        print(f"{'':<16} chaine de parents : " + " <- ".join(chain(names, parent, j)))
    if a.verts:
        print("\n-- SOMMETS : position MODELE, os pilote, offset dans le repere de CET os --")
        print("   (offset = IBM_os . p ; controle inv4x4 : inv(IBM_os) . offset doit rendre p)")
        for v in a.verts:
            drv = int(J[v, np.argmax(W[v])])
            ibm = ibms[drv]
            p4 = np.array([P[v][0], P[v][1], P[v][2], 1.0])
            loc = (ibm @ p4)[0:3]
            back = (np.linalg.inv(ibm) @ np.append(loc, 1.0))[0:3]
            bind = ' '.join(f"{names[J[v,k]]}:{W[v,k]:.4f}" for k in range(J.shape[1]) if W[v, k] > 0)
            print(f"  v{v:<6} modele=({P[v][0]:8.4f},{P[v][1]:8.4f},{P[v][2]:8.4f}) "
                  f"os={names[drv]:<14} offset=({loc[0]:8.4f},{loc[1]:8.4f},{loc[2]:8.4f}) "
                  f"|retour-p|={np.linalg.norm(back-P[v]):.3e}  [{bind}]")
        print("\n-- NEUTRALITE A LA POSE DE BIND (somme_j w_j . M_j . IBM_j . p) --")
        worst = 0.0
        for v in a.verts:
            p4 = np.array([P[v][0], P[v][1], P[v][2], 1.0]); acc = np.zeros(3)
            for k in range(J.shape[1]):
                if W[v, k] > 0:
                    acc += W[v, k] * (np.linalg.inv(ibms[J[v, k]]) @ (ibms[J[v, k]] @ p4))[0:3]
            worst = max(worst, float(np.linalg.norm(acc - P[v])))
        print(f"  ecart maximal a la pose d'auteur sur les {len(a.verts)} sommets : {worst:.3e}")

if __name__ == '__main__':
    main()
