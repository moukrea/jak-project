#!/usr/bin/env python3
"""c127c_bone_aggregate.py — DE COMBIEN D'OS LE MOTEUR A-T-IL BESOIN POUR PORTER L'ETAGE RIGIDE ?

POURQUOI. `c127b` refute le proxy POSITIONNEL (13,0 / 14,2 points) : la corde d'os est invariante a
1e-4 dans toutes les poses, donc l'etage rigide est ENTIEREMENT ANGULAIRE — il faut porter les
OFFSETS DE TISSU et les faire tourner avec leurs os.

FONDEMENT ALGEBRIQUE. Le skinning lineaire est LINEAIRE en les matrices d'os, donc un centroide
pondere est EXACTEMENT une somme par OS :
    c = Sum_v w_v Sum_b W_vb (q_vb . R_b + t_b) / Sum w = Sum_b ( s_b . R_b + m_b t_b )
avec  s_b = Sum_v w_v W_vb q_vb / Sum w   et   m_b = Sum_v w_v W_vb / Sum w.
`s_b` et `m_b` sont des CONSTANTES CUITES DU MESH — meme classe que `*phys-lcx/lcy/lcz*` et
`*phys-apx/apy/apz*`, deja lus par le moteur depuis le fichier livre. Aucun ajustement sur un
verdict n'entre ici.

NATURE / REPERE / LIGNE DE BASE :
  NATURE  : un rapport de LONGUEUR sans dimension (racine->apex), et l'ECART en points de
            pourcentage entre une reconstruction et la mesure de reference.
  REPERE  : aucun — une longueur entre deux centroides est un invariant euclidien.
  LIGNE DE BASE : cellule i=0 (pose debout d'auteur). Lecture HORS DEFAUT : cellule DEBOUT i=9.
  REFERENCE : le nuage `RIGID` de `c126_rotation_vs_stretch.run()`, sommet par sommet.
"""
import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
import physics_c6_volumes as c6
from physics_c6_volumes import consolidate_buffers, read_glb, skin_info
import c124_delivered_shape as c124
import c126_rotation_vs_stretch as c126

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOG = sys.argv[1] if len(sys.argv) > 1 else \
    '.autoport/reports/Grecharged-secondary-motion/keira-room-x86.log'
txt = open(os.path.join(REPO, LOG) if not os.path.isabs(LOG) else LOG,
           'r', errors='replace').read()

isup, ipro, _G = c124._roles(txt)
jn, mats, nmiss = c124._read_matrices(txt)
if not mats or nmiss:
    raise SystemExit('c127c: SUSPENDU — trace incomplete.')
slot = {v: k for k, v in jn.items()}

g = c6.load_geometry('keira-hd', glb=c126.SHIPPED)
names, V, J, W, Pb = list(g['names']), g['V'], g['J'], g['W'], g['P']
js, bufs = read_glb(os.path.join(REPO, c126.SHIPPED))
_nn, ibms, _pp = skin_info(js, consolidate_buffers(js, bufs))
ai = names.index(c126.ANCHOR)


def bindR(j):
    Rj = np.linalg.inv(np.array(ibms[j], dtype=float))[:3, :3].copy()
    for k in range(3):
        Rj[:, k] /= np.linalg.norm(Rj[:, k])
    return Rj


Ranc = bindR(ai)
RB = {n: bindR(names.index(n)) for n in slot}
mass = json.load(open(os.path.join(REPO, c126.MASSJSON)))

# ---- LES MATRICES `RIGID` : rotation pure sur les joints de chaine, livrees ailleurs -----------
MM = {}
for (i, sl), M in mats.items():
    nm = jn.get(sl)
    if nm not in c126.CHAINJOINTS:
        MM[(i, sl)] = M
        continue
    S, Rr = c126.polar_SR(M[:3, :3])
    M2 = M.copy()
    M2[:3, :3] = Rr
    MM[(i, sl)] = M2

res, cells = c126.run(txt, inject_fwd=1.50)
CELLS = [(0, 'DEBOUT(base)'), (ipro, 'PRONE'), (isup, 'SUPINE'), (9, 'DEBOUT(2e)')]
P = print
P('C127C: SUPINE i=%d · PRONE i=%d · reference = nuage RIGID sommet par sommet' % (isup, ipro))
P('C127C: ' + '=' * 106)

worst = {'ALL': 0.0, 'B3': 0.0, 'B2': 0.0}
worst_pro = {'ALL': 0.0, 'B3': 0.0, 'B2': 0.0}
for cname, joints in c126.CHAINS.items():
    jp, jd = joints
    idx = [names.index(j) for j in joints]
    wsum = np.zeros(len(V))
    for ji in idx:
        wsum += (W * (J == ji)).sum(axis=1)
    AX = {a: np.asarray(mass['chains'][cname]['axes'][a], dtype=float)
          for a in ('out', 'up', 'fwd')}
    for cut, lbl in ((0.0, 'w>0.00'), (0.25, 'w>=0.25')):
        sel = wsum > cut if cut == 0.0 else wsum >= cut
        wv = wsum[sel]
        xb = (V[sel] - Pb[ai]) @ Ranc @ AX['fwd']
        qlo, qhi = np.quantile(xb, 0.10), np.quantile(xb, 0.90)
        pops = {'prox': xb <= qlo, 'dist': xb >= qhi}
        Js, Ws, Vs = J[sel], W[sel], V[sel]

        # ---- AGGREGATION PAR OS : s_b (vecteur) et m_b (scalaire), par population -------------
        agg = {}
        for pn, pm in pops.items():
            wsub, tot = wv[pm], float(wv[pm].sum())
            d = {}
            for nmj in slot:
                bi = names.index(nmj)
                s = np.zeros(3)
                m = 0.0
                for k in range(Ws.shape[1]):
                    mk = (Js[pm][:, k] == bi) & (Ws[pm][:, k] > 0)
                    if not mk.any():
                        continue
                    ww = wsub[mk] * Ws[pm][mk, k]
                    q = (Vs[pm][mk] - Pb[bi]) @ RB[nmj]
                    s += (ww[:, None] * q).sum(0)
                    m += float(ww.sum())
                if m > 0.0 or np.any(s):
                    d[nmj] = (s / tot, m / tot)
            agg[pn] = d

        SETS = {'ALL': set(slot), 'B3': {c126.ANCHOR, jp, jd}, 'B2': {jp, jd}}

        def centro(pn, i, keep):
            s3, tot = np.zeros(3), 0.0
            for nmj, (s, m) in agg[pn].items():
                if nmj not in keep:
                    continue
                M = MM[(i, slot[nmj])]
                s3 += s @ M[:3, :3] + m * M[3, :3]
                tot += m
            return s3 / tot if tot > 0 else s3   # renormalisation quand on omet des os

        ref = res[(cname, lbl, 'RIGID')]
        for setn, keep in SETS.items():
            L0 = float(np.linalg.norm(centro('dist', 0, keep) - centro('prox', 0, keep)))
            for cell, tag in CELLS:
                Lc = float(np.linalg.norm(centro('dist', cell, keep) - centro('prox', cell, keep)))
                got = Lc / L0
                exp = ref['Lpp'][cell] / ref['Lpp'][0]
                ec = abs(got - exp) * 100.0
                worst[setn] = max(worst[setn], ec)
                if tag == 'PRONE':
                    worst_pro[setn] = max(worst_pro[setn], ec)
                    P('C127C: %-7s %-8s %-4s %-6s  reconstruit %.4f   RIGID mesure %.4f   ecart %6.3f pts'
                      % (cname, lbl, setn, tag, got, exp, ec))

P('C127C: ' + '-' * 106)
P('C127C: P8a CONTROLE DE MA DERIVATION — tous les os, ecart max sur les 4 cellules : %.6f pts'
  % worst['ALL'])
P('C127C:     Falsificateur : > 0,1 pt (1e-3). -> %s'
  % ('TIRE — le centroide pondere EST une somme par os, et ma convention de skinning est la bonne'
     if worst['ALL'] <= 0.1 else 'REFUTE — derivation ou convention fausse, RIEN n\'est publie'))
if worst['ALL'] > 0.1:
    sys.exit(1)
P('C127C: P8b TROIS OS (ancre + 2 maillons) — ecart max sur la cellule PRONE : %.3f pts -> %s'
  % (worst_pro['B3'], 'TENUE' if worst_pro['B3'] < 5.0 else 'REFUTEE'))
P('C127C: P8c DEUX OS (ancre OMISE) — ecart max sur la cellule PRONE : %.3f pts -> %s'
  % (worst_pro['B2'], 'P8c TENUE (l\'ancre est necessaire)' if worst_pro['B2'] >= 5.0
     else 'P8c REFUTEE — l\'ancre ne porte PAS la longueur malgre son poids ; l\'estimateur est deux fois moins cher'))
P('C127C: ' + '=' * 106)
