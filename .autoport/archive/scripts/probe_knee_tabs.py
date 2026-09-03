#!/usr/bin/env python3
"""probe_knee_tabs.py — QUEL OS PORTE LES LANGUETTES DES GENOUX ?

Defaut ouvert `knee-tabs`, owner : « les LANGUETTES au niveau des genoux ne bougent pas (les
sangles, elles, bougent) ». Deux reponses possibles, et une seule est vraie :

  A. les languettes sont peintes sur `lKneeFlap`/`rKneeFlap` — les memes os que les sangles, qui
     ONT une chaine et bougent (tipvar 0.168 / 0.124). Il n'y a alors rien a chainer de plus et
     le defaut est une question d'AMPLITUDE, pas d'absence.
  B. elles sont peintes sur un os RIGIDE (le genou, la cuisse, la cheville). Elles ne peuvent alors
     PAS bouger, quel que soit le reglage, et c'est une reprise d'ASSET.

Le 2026-08-12 la reponse ecrite dans `owner-defects.txt` etait « les os LfootFlaps/RfootFlaps
n'existent pas dans le rig HD ». C'est vrai, mais ca ne repond pas a la question : il faut savoir
QUEL os porte la geometrie, pas seulement lequel n'existe pas.

Ce script ne decide rien et n'ecrit rien : il mesure et il imprime.
"""
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(REPO, 'scripts', 'shell'))

import physics_keira_gen2 as G  # noqa: E402


def main():
    names, parent, _ = G.load_rig(os.path.join(REPO, G.RIG_REL))
    geo = G.load_mesh(G.MODEL)
    idx_of = {n: i for i, n in enumerate(names)}
    P = geo['P']
    V = geo['V']

    # --- 1. la boite du genou : toute geometrie qui vit autour de lKneeFlap ---------------------
    for side, flap, knee, ankle, thigh in (('GAUCHE', 'lKneeFlap', 'Lknee', 'Lankle', 'Lthigh'),
                                           ('DROIT',  'rKneeFlap', 'Rknee', 'Rankle', 'Rthigh')):
        jf = idx_of.get(flap)
        jk = idx_of.get(knee)
        if jf is None or jk is None:
            print(f"{side}: {flap} ou {knee} absent du rig")
            continue
        print(f"== COTE {side} — la geometrie autour de {flap} (joint a {P[jf]}) ==")
        # rayon d'interet : la longueur genou->cheville, ca couvre largement la bande et ses
        # languettes sans avaler le pied.
        ja = idx_of[ankle]
        R = float(np.linalg.norm(P[ja] - P[jk]))
        d = np.linalg.norm(V - P[jf], axis=1)
        near = np.where(d <= R)[0]
        print(f"   rayon d'interet = |{knee}-{ankle}| = {R:.0f} u ; {len(near)} sommets dedans")
        # qui DOMINE chacun de ces sommets ? J/W sont (nv, 4) : 4 influences par sommet.
        J, W = np.asarray(geo['J']), np.asarray(geo['W'])
        slot = W[near].argmax(axis=1)
        dom = J[near, slot]
        counts = {}
        for j in dom:
            counts[int(j)] = counts.get(int(j), 0) + 1
        print(f"   {'os dominant':<16}{'nv':>5} {'|c-os|':>8} {'etendue p100':>13}"
              f" {'chaine ?':>10}")
        for j, nv in sorted(counts.items(), key=lambda kv: -kv[1]):
            sel = near[dom == j]
            pts = V[sel]
            c = pts.mean(axis=0)
            spread = float(np.linalg.norm(pts - c, axis=1).max())
            dcj = float(np.linalg.norm(c - P[j]))
            print(f"   {names[j]:<16}{nv:>5} {dcj:>8.0f} {spread:>13.0f} {'':>10}")
        # --- 2. l'etendue propre du flap : une bande seule est compacte, une bande + languettes
        # --- a une queue. On le lit sur la distribution des distances au centroide.
        for thr in (0.5, 0.25, 0.05):
            _n, _w, sel = G.influence(geo, jf, thr)
            if len(sel) < 4:
                continue
            pts = V[sel]
            c = pts.mean(axis=0)
            dd = np.linalg.norm(pts - c, axis=1)
            print(f"   {flap} @w>{thr}: nv={len(sel):>4} centroide a {np.linalg.norm(c-P[jf]):.0f} u"
                  f" du joint ; distances au centroide p50={np.percentile(dd,50):.0f}"
                  f" p90={np.percentile(dd,90):.0f} max={dd.max():.0f}")
        # --- 3. l'os RIGIDE qui porte le plus de geometrie autour du genou : s'il en porte plus
        # --- que le flap, ce qui pend la est peint sur la jambe et ne peut pas bouger.
        rigid = [idx_of[n] for n in (knee, ankle, thigh) if n in idx_of]
        nflap = counts.get(jf, 0)
        nrig = sum(counts.get(j, 0) for j in rigid)
        print(f"   VERDICT BRUT : {nflap} sommets domines par {flap} (SIMULE, il a une chaine)"
              f" contre {nrig} par {knee}/{ankle}/{thigh} (RIGIDES, aucune chaine).")
        print()


if __name__ == '__main__':
    main()
