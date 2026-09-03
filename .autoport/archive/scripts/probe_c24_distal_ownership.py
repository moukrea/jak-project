#!/usr/bin/env python3
"""probe_c24_distal_ownership.py — CE QUE LE REPESAGE PEUT ATTEINDRE POUR L'OS INJECTE.

Phase Grecharged-secondary-motion, branche physics-keira-clean, KEIRA / POITRINE SEULE.
DIRECTIVES vb249967379

POURQUOI CET INSTRUMENT (2026-08-18, cycle 24). La directive du 08:55 pose une barre :
« au moins 30 % des sommets de la chaine ont le NOUVEL os pour joint majoritaire (w > 0.5) ».
Le cycle 23 a livre 21/77 = 27.3 % (chestL) et 17/75 = 22.7 % (chestR) — SOUS la barre des deux
cotes. Avant de depenser une cuisson, on mesure CE QUE LA REGLE PEUT PRODUIRE sur toute la boite
que la spec autorise, et on ecrit la prediction.

LES TROIS QUESTIONS DE LA SPEC 7, repondues avant d'ecrire la mesure :
  NATURE  — une REPARTITION (combien de sommets chaque os POSSEDE), pas une amplitude et pas une
            somme de poids : la directive du 08:55 dit mot pour mot « la preuve est la REPARTITION,
            jamais la presence », parce qu'un os peut porter 20 unites de poids et n'etre
            majoritaire nulle part (c'est exactement ce qui s'est produit trois fois).
  REPERE  — le mesh LIVRE, apres la regle, restreint aux sommets de la chaine (`ws > gate`), et le
            joint MAJORITAIRE d'un sommet est celui dont le poids somme depasse 0.5. Meme domaine
            et meme seuil que `probe_breast_anchor30.py`, pour que les deux instruments parlent des
            memes sommets.
  ABSENT  — un os injecte que la geometrie ignore lit 0 sommet majoritaire (mesure du 2026-08-13
            sur `backHair4`, et de la directive du 08:55 sur `lBooc`/`rBooc` : 0 des deux cotes).

FIDELITE : la sortie de ce banc est BIT-EXACTE avec la cuisson. L'entree `--in` est le glb que la
cuisson passe reellement a `physics_c7_reskin.py` (inject -> stamp -> prep), et le banc appelle
`apply_model` du MEME module avec les MEMES regles, seuls `root=`/`grad=` variant. Verifie :
md5 de la sortie a (root=0.95, grad=2.00) == md5 de `out/jak1/fr3/skin/keira-hd-lod0.glb`.

USAGE : python3 .autoport/probe_c24_distal_ownership.py --in /tmp/c24/reskin-input.glb
"""
import argparse
import copy
import os
import sys

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'scripts', 'shell'))

import physics_c7_reskin as RS                                          # noqa: E402
from retarget_hd_models import read_glb, consolidate_buffers  # noqa: E402
import physics_c6_volumes as c6                                        # noqa: E402
import physics_keira_gen2 as G                                         # noqa: E402
from probe_skin_profile import arc_param                               # noqa: E402

UNITS = RS.UNITS
# LES CINQ BANDES DE LA 30, RECOPIEES DE LA SPEC (« Root Attachment »), pas choisies.
BANDS = ((0.000, 0.125, 0.90, 1.00, 'root'), (0.125, 0.375, 0.55, 0.85, 'rear'),
         (0.375, 0.625, 0.25, 0.55, 'mid'), (0.625, 0.875, 0.05, 0.30, 'dist'),
         (0.875, 1.001, 0.00, 0.10, 'apex'))
# `StrongRootFraction = 0.30`, bande « approximately 28-35% » de la 30.
SRF_LO, SRF_HI = 0.28, 0.35


def measure(path, chains, axis='chain'):
    """Repartition par os sur le mesh PRODUIT — relue sur J/W, jamais sur la cible de la regle.

    LE DOMAINE EST CELUI DE `probe_breast_anchor30.py`, PAS UN AUTRE. On passe par
    `physics_c6_volumes.load_geometry`, le meme lecteur que la sonde d'ancrage : il COMPACTE les
    sommets du modele (les 28 primitives de Keira partagent un seul jeu d'attributs, donc les
    compter primitive par primitive multiplie le domaine par 28) et se restreint aux primitives du
    personnage. Deux instruments qui repondent a la meme question doivent lire les memes sommets —
    sinon leurs deux « 30 % » ne portent pas sur le meme denominateur, ce qui est exactement le
    piege que ce cycle corrige.
    """
    geo = c6.load_geometry(G.MODEL, glb=path)
    if geo is None:
        raise SystemExit('mesh illisible : %s' % path)
    names, P, V, J, W = geo['names'], geo['P'], geo['V'], geo['J'], geo['W']
    idx = {n: i for i, n in enumerate(names)}
    out = {}
    for tag, joints in chains.items():
        grp = [idx[j] for j in joints]
        per = []
        for g in grp:
            w = np.zeros(len(W))
            for c in range(J.shape[1]):
                w += np.where(J[:, c] == g, W[:, c], 0.0)
            per.append(w)
        ws = np.sum(per, axis=0)
        vi = np.flatnonzero(ws > 0.05)
        pts = np.asarray([P[g] for g in grp], dtype=float)
        if axis == 'flesh':
            # LE VERDICT SE LIT DANS LE REPERE OU LA REGLE TRAVAILLE. La 31 definit `r` par la
            # CHAIR (r=0 attache thoracique, r=1 apex) : lire les bandes de la 30 sur la polyligne
            # des JOINTS pendant que la regle les pose sur la chair compare deux abscisses
            # differentes — c'est le meme piege de repere que le gradient monde/parent du 08-11.
            ax = pts[-1] - pts[0]
            ax = ax / np.linalg.norm(ax)
            q = (np.asarray(V[vi], dtype=float) - pts[0]) @ ax
            s = (q - q.min()) / (q.max() - q.min())
        else:
            s, _beyond = arc_param(pts, np.asarray(V[vi], dtype=float))
        anc = np.zeros(len(W))
        for c in range(J.shape[1]):
            anc += np.where(np.isin(J[:, c], grp), 0.0, W[:, c])
        anc = anc[vi]
        bands = []
        for lo, hi, blo, bhi, lbl in BANDS:
            m = (s >= lo) & (s < hi)
            v = float(anc[m].mean()) if m.any() else float('nan')
            bands.append((lbl, v, (blo <= v <= bhi) if m.any() else None))
        out[tag] = dict(n=len(vi),
                        maj={joints[k]: int((per[k][vi] > 0.5).sum()) for k in range(len(grp))},
                        tot={joints[k]: float(per[k].sum()) for k in range(len(grp))},
                        bands=bands,
                        srf=float((anc >= 0.55).mean()) if len(anc) else float('nan'))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--in', dest='inp', required=True)
    ap.add_argument('--roots', default='0.90,0.925,0.95,0.975,1.00')
    ap.add_argument('--grads', default='1.60,1.70,1.80,1.90,2.00')
    ap.add_argument('--tmp', default='/tmp/c24/sweep.glb')
    ap.add_argument('--axis', default='chain', choices=('chain', 'flesh'),
                    help="repere de `r` : `chain` (historique) ou `flesh` (la 31 a la lettre)")
    a = ap.parse_args()

    chains = {'chestL': ['lBoob', 'lBooc'], 'chestR': ['rBoob', 'rBooc']}
    base = RS.load_cfg().get('keira-hd', [])
    if not base:
        print('FAIL: aucune regle keira-hd'); return 2

    print('BANC DE DERIVATION — REPARTITION ATTEIGNABLE POUR L\'OS INJECTE (cycle 24)')
    print('NATURE repartition (sommets MAJORITAIRES w>0.5) · REPERE mesh LIVRE, sommets de la')
    print('chaine (ws>0.05) · ABSENT un os que la geometrie ignore lit 0')
    print('barre du contrat 2026-08-18 08:55 : part du NOUVEL os >= 30 % des sommets de la chaine')
    print('boite autorisee par la spec : RootAnchor 0.90-1.00 (30) · RootDeformationExponent'
          ' 1.6-2.0 (31)')
    print(f'repere de r : axis={a.axis}')
    print()
    hdr = (f"{'root':>6} {'grad':>5} | {'chestL n':>8} {'lBoob':>6} {'lBooc':>6} {'part':>7}"
           f" {'SRF':>6} {'bandes':>7} | {'chestR n':>8} {'rBoob':>6} {'rBooc':>6} {'part':>7}"
           f" {'SRF':>6} {'bandes':>7}")
    print(hdr); print('-' * len(hdr))
    rows = []
    for root in [float(x) for x in a.roots.split(',')]:
        for grad in [float(x) for x in a.grads.split(',')]:
            rules = copy.deepcopy(base)
            for r in rules:
                if r['kind'] == 'anchor30':
                    r['root'], r['grad'], r['axis'] = root, grad, a.axis
            js, bufs = read_glb(a.inp)
            binc = consolidate_buffers(js, bufs)
            RS.apply_model(js, binc, rules, verbose=False)
            binc = RS.gc_glb(js, binc)
            RS.write_glb(a.tmp, js, binc)
            m = measure(a.tmp, chains, axis=a.axis)
            cells = []
            for tag, new in (('chestL', 'lBooc'), ('chestR', 'rBooc')):
                d = m[tag]
                part = d['maj'][new] / d['n'] if d['n'] else 0.0
                nb = sum(1 for _l, _v, ok in d['bands'] if ok)
                old = 'lBoob' if tag == 'chestL' else 'rBoob'
                cells.append((d['n'], d['maj'][old], d['maj'][new], part, d['srf'], nb))
            rows.append((root, grad, cells, m))
            L, R = cells
            print(f"{root:6.3f} {grad:5.2f} | {L[0]:8d} {L[1]:6d} {L[2]:6d} {100*L[3]:6.1f}%"
                  f" {L[4]:6.3f} {L[5]:5d}/5 | {R[0]:8d} {R[1]:6d} {R[2]:6d} {100*R[3]:6.1f}%"
                  f" {R[4]:6.3f} {R[5]:5d}/5")

    print()
    print('CRITERES, TOUS DE LA SPEC OU DU CONTRAT — un candidat doit les tenir ENSEMBLE :')
    print('  (1) part du NOUVEL os >= 30.0 % des sommets de la chaine   [contrat 08:55]')
    print('  (2) l\'os PROXIMAL garde des sommets majoritaires (> 0)     [meme regle, autre bout]')
    print('  (3) StrongRootFraction dans 0.28-0.35                      [30]')
    print('  (4) les 5 bandes d\'ancrage DANS                            [30]')
    ok = []
    for root, grad, cells, _m in rows:
        good = all(c[3] >= 0.30 and c[1] > 0 and SRF_LO <= c[4] <= SRF_HI and c[5] == 5
                   for c in cells)
        if good:
            ok.append((root, grad))
    print()
    if ok:
        print(f'CANDIDATS QUI TIENNENT LES QUATRE : {ok}')
    else:
        best = max(rows, key=lambda r: min(c[3] for c in r[2]))
        print('AUCUN CANDIDAT NE TIENT LES QUATRE DANS LA BOITE DE LA SPEC.')
        print(f'  meilleure part minimale : root={best[0]:.3f} grad={best[1]:.2f} ->'
              f' {100*best[2][0][3]:.1f}% / {100*best[2][1][3]:.1f}%')
        mx = max(rows, key=lambda r: max(c[3] for c in r[2]))
        print(f'  part maximale observee  : root={mx[0]:.3f} grad={mx[1]:.2f} ->'
              f' {100*mx[2][0][3]:.1f}% / {100*mx[2][1][3]:.1f}%')
    return 0


if __name__ == '__main__':
    sys.exit(main())
