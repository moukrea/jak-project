#!/usr/bin/env python3
"""probe_breast_rest_overlap.py — SON SEIN EST-IL DEJA DANS SON TORSE, A L'ARRET ?

Ce script ne modifie rien et n'a besoin d'AUCUNE course : il lit la pose de BIND du mesh livre et
les volumes que le fichier de chaines declare, et repond a une question purement geometrique.

POURQUOI (cycle 30). Trois cycles ont cherche un mecanisme de REPONSE pour un defaut qui ne depend
presque pas du stimulus : `comex` (l'excursion du centre de chair, sa §22) vaut 1.04 B0 en moyenne
sur la fenetre ou la salle ne pousse RIEN, pour un plafond dur de 0.40 B0, et la correlation avec
le stimulus recu vaut r = +0.005 sur une plage de 274 x. Une grandeur grande, constante et
independante de ses entrees n'est pas une reponse : c'est un ETAT. Cette sonde teste l'etat au
repos, la ou aucune dynamique n'existe encore.

LES TROIS QUESTIONS (SPEC 7) :
  NATURE  une LONGUEUR de recouvrement : de combien le volume d'un maillon de la chaine entre-t-il
          dans un volume du corps, A LA POSE DE BIND, avant que quoi que ce soit ne bouge.
          Rapportee a B0 pour se comparer aux bandes de sa §22.
  REPERE  la pose de BIND du mesh LIVRE (`out/jak1/fr3/skin/keira-hd-lod0.glb`), en unites de jeu
          (4096 = 1 m). Le centre du volume d'un maillon est le CENTROIDE des sommets qu'il possede
          en majorite — la meme definition que celle qui a produit le `offset=` du fichier livre —
          et son rayon est celui que le moteur resout REELLEMENT (la sphere declaree sur le joint
          l'emporte sur le `radii=` de la chaine ; trace `[HD-PHYS] vol ... -> r=`).
  ABSENT  0.0 u : un organe dont le volume affleure son thorax sans y entrer.

CE QUE CETTE SONDE NE DIT PAS : si le solveur POUSSE effectivement sur ce recouvrement. Elle
mesure l'etat geometrique ; c'est la course (`PHYSCVOL`, corrections par volume et par maillon) et
l'ablation `*phys-col-off*` qui repondent a la causalite. Les trois sont publiees ensemble.

USAGE : python3 .autoport/probe_breast_rest_overlap.py
"""
import os
import re
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(REPO, 'scripts', 'shell'))

import physics_keira_gen2 as G          # noqa: E402
import physics_c6_volumes as c6         # noqa: E402

SHIPPED = os.path.join(REPO, 'out', 'jak1', 'fr3', 'skin', 'keira-hd-lod0.glb')
CHAINS = os.path.join(REPO, 'recharged_assets', 'physics_chains.txt')
B0 = 602.0                    # 6 : la longueur racine->apex de la CHAIR, pas celle de l'os
MAJORITY = 0.5
CH = (('chestL', ('lBoob', 'lBooc')), ('chestR', ('rBoob', 'rBooc')))


def main():
    geo = c6.load_geometry(G.MODEL, glb=SHIPPED)
    if geo is None:
        raise SystemExit('mesh livre introuvable : %s' % SHIPPED)
    names, P, V, J, W = geo['names'], geo['P'], geo['V'], geo['J'], geo['W']
    idx = {n: i for i, n in enumerate(names)}

    caps, sph = [], {}
    for ln in open(CHAINS, errors='ignore'):
        s = ln.split('#', 1)[0].strip()
        m = re.match(r'^capsule (\S+) (\S+) radius=(\d+) radius2=(\d+)', s)
        if m:
            caps.append((m.group(1), m.group(2), float(m.group(3)), float(m.group(4))))
        m = re.match(r'^collider (\S+) radius=(\d+) offset=', s)
        if m:
            sph[m.group(1)] = float(m.group(2))

    def pos(n):
        return np.asarray(P[idx[n]], dtype=float)

    def centroid(n):
        ji = idx[n]
        w = np.zeros(len(W))
        for c in range(J.shape[1]):
            w += np.where(J[:, c] == ji, W[:, c], 0.0)
        m = w > MAJORITY
        if not m.any():
            return None, 0
        return np.asarray(V[m], dtype=float).mean(axis=0), int(m.sum())

    print('LE SEIN EST-IL DEJA DANS LE TORSE A LA POSE DE BIND ?')
    print('NATURE longueur de recouvrement / B0 · REPERE pose de bind du mesh LIVRE, unites de jeu')
    print('ABSENT 0.0 u · B0 = %.0f u (6, la CHAIR)\n' % B0)
    worst = 0.0
    own = set(j for _, js in CH for j in js)
    for cname, joints in CH:
        print('=== %s' % cname)
        for j in joints:
            if j not in idx:
                print('  %-6s ABSENT du mesh' % j)
                continue
            C, nv = centroid(j)
            R = sph.get(j)
            if C is None or R is None:
                print('  %-6s pas de volume resolu' % j)
                continue
            print('  %-6s r=%5.0f u = %.2f B0   centre a %5.0f u de son joint   (%d sommets)'
                  % (j, R, R / B0, np.linalg.norm(C - pos(j)), nv))
            hits = []
            for (j1, j2, r1, r2) in caps:
                if j1 not in idx or j2 not in idx or j1 in own or j2 in own:
                    continue
                A, Bp = pos(j1), pos(j2)
                ab = Bp - A
                t = float(np.dot(C - A, ab) / max(1e-9, float(np.dot(ab, ab))))
                t = max(0.0, min(1.0, t))
                d = float(np.linalg.norm(C - (A + t * ab)))
                rc = r1 * (1.0 - t) + r2 * t          # la capsule est CONIQUE : rayon interpole
                if d < R + rc:
                    hits.append(('%s->%s' % (j1, j2), d, rc, R + rc - d))
            if not hits:
                print('       aucun recouvrement au repos')
            for nm, d, rc, pen in sorted(hits, key=lambda x: -x[3]):
                worst = max(worst, pen / B0)
                print('       RECOUVRE %-20s dist=%7.1f  rayon local=%6.1f  recouvrement=%7.1f u'
                      ' = %.2f B0' % (nm, d, rc, pen, pen / B0))
        print()
    print('PIRE RECOUVREMENT AU REPOS : %.2f B0   contre le plafond DUR de COM de sa 22 : 0.40 B0'
          % worst)
    print('LECTURE : ce que le solveur doit resoudre AVANT que le premier mouvement existe.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
