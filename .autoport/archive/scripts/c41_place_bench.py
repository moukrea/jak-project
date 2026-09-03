#!/usr/bin/env python3
"""c41_place_bench.py — CE QUE LA SPEC 30 DEVIENT SI ON GLISSE LES NOEUDS. SANS CUISSON.

Phase Grecharged-secondary-motion, branche physics-keira-clean, KEIRA / POITRINE SEULE.
DIRECTIVES vb249967379

POURQUOI (cycle 40 -> 41). Le cycle 40 a PROUVE que le segment de chair simule est x5.2 trop
court : aucune valeur de la borne d'elongation ne tient a la fois la ligne « elongation de tissu
de l'organe 21-25 % » et la ligne « deformation locale <= 25 % » de sa SPEC 22. Le remede est
GEOMETRIQUE — glisser les noeuds pour que le segment couvre `r` de 0 a 1. Mais la barre du
2026-08-18 08:55 (« >= 30 % des sommets de la chaine ont le NOUVEL os pour joint majoritaire »)
a deja coute trois constats faux, et une cuisson ecrase des artefacts irreproductibles. **Ce banc
predit la barre AVANT la cuisson, et il se valide en reproduisant le mesh LIVRE.**

LES TROIS QUESTIONS (SPEC 7), repondues avant d'ecrire :
  NATURE  : une REPARTITION (combien de sommets chaque os possede en MAJORITE, w > 0.5) et une
            COUVERTURE (quelle part de `r` le segment simule sous-tend). Ni une amplitude, ni une
            somme de poids.
  REPERE  : `r` au sens de sa SPEC 31 (`axis=flesh`) — projection sur l'axe de la chaine,
            normalisee par les EXTREMES du nuage. C'est le repere ou la regle `anchor30` travaille.
  ABSENT  : un placement qui ne pilote rien lit 0 sommet majoritaire pour l'os injecte.

CE QUE LE BANC PROUVE PAR CONSTRUCTION, ET C'EST LE RESULTAT QUI DEBLOQUE LE CHANTIER :
  `anchor30` pose l'ancrage a `root*(1-s)^p` ou `s` ne depend QUE de la direction de l'axe et des
  extremes du nuage. Glisser un noeud LE LONG de cet axe ne change ni la direction ni le nuage,
  donc **`s`, `p`, l'ancrage et les CINQ BANDES de la 30 sont INVARIANTS**. Seule bouge `tk`, la
  position des joints sur cet axe — donc seule bouge la REPARTITION entre les deux maillons.
  Le lissage sur aretes ne peut pas casser la barre : `_distal_ok` est sa condition d'ARRET, donc
  la barre tient a la sortie si et seulement si elle tient a l'entree (partition initiale).
  C'est pourquoi ce banc n'a pas besoin de cuire.

USAGE : python3 .autoport/c41_place_bench.py [--in /tmp/c24/b-derived/prepped.glb]
"""
import argparse
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, '..', 'scripts', 'shell'))

import physics_c7_reskin as RS                                          # noqa: E402
import physics_c6_volumes as c6                                         # noqa: E402
import physics_keira_gen2 as G                                          # noqa: E402

BANDS = ((0.000, 0.125, 0.90, 1.00, 'root'), (0.125, 0.375, 0.55, 0.85, 'rear'),
         (0.375, 0.625, 0.25, 0.55, 'mid'), (0.625, 0.875, 0.05, 0.30, 'dist'),
         (0.875, 1.001, 0.00, 0.10, 'apex'))
CHAINS = {'chestL': ['lBoob', 'lBooc'], 'chestR': ['rBoob', 'rBooc']}
# elongation radiale LIVREE, moyenne, mesuree cycle 40 sur la course C38E4-FINAL (en unites de jeu)
DELIV_U = {'chestL': 179.7, 'chestR': 174.8}
# demande AVANT borne (`rrr` moyen, maillon de chair), course C40E5-CAPFIX, en unites de jeu :
DEMAND_U = {'chestL': 0.3424 * 602.0, 'chestR': 0.3455 * 602.0}
# organe racine->apex mesure sur le mesh LIVRE (probe_breast_chain_span.py) :
ORGAN_U = {'chestL': 734.21, 'chestR': 766.60}


def rule_for(target):
    for r in RS.load_cfg().get('keira-hd', []):
        if r.get('kind') == 'anchor30' and r.get('target') == target:
            return r
    return None


def partition(s, tk, grad):
    """LA PARTITION DE LA 31, RECOPIEE DE `physics_c7_reskin._anchor30` (:468-483)."""
    u = np.power(np.clip(s, 0.0, 1.0), grad)
    uk = np.power(np.clip(tk, 0.0, 1.0), grad)
    A = np.zeros((len(s), len(tk)))
    for a in range(len(tk) - 1):
        lo, hi = uk[a], uk[a + 1]
        last = (a == len(tk) - 2)
        m = (u >= lo) & (u <= hi) if last else (u >= lo) & (u < hi)
        if m.any():
            q = (u[m] - lo) / (hi - lo) if (hi - lo) > 1e-12 else np.zeros(int(m.sum()))
            A[m, a] += 1.0 - q
            A[m, a + 1] += q
    A[u < uk[0], 0] = 1.0
    A[u > uk[-1], -1] = 1.0
    rs = A.sum(axis=1)
    return A / np.where(rs < 1e-12, 1.0, rs)[:, None]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--in', dest='inp', default='/tmp/c24/b-derived/prepped.glb')
    a = ap.parse_args()
    if not os.path.exists(a.inp):
        raise SystemExit('entree absente : %s (c\'est la sortie de prep, avant RESKIN)' % a.inp)

    geo = c6.load_geometry(G.MODEL, glb=a.inp)
    if geo is None:
        raise SystemExit('mesh illisible : %s' % a.inp)
    names, P, V, J, W = geo['names'], geo['P'], geo['V'], geo['J'], geo['W']
    idx = {n: i for i, n in enumerate(names)}

    print('BANC DE PLACEMENT — LA BARRE DE LA 30 PREDITE SANS CUISSON')
    print('NATURE repartition (w>0.5) + couverture de `r` · REPERE `axis=flesh` de la 31')
    print('ABSENT un placement qui ne pilote rien lit 0 sommet majoritaire')
    print('entree (sortie de prep, AVANT reskin) : %s' % a.inp)
    print('barre du contrat 2026-08-18 08:55 : os INJECTE majoritaire sur >= 30 %% du nuage')
    print()

    for tag, joints in CHAINS.items():
        r = rule_for(tag)
        if r is None:
            print('%s : aucune regle anchor30' % tag); continue
        grp = [idx[j] for j in joints]
        ws = np.zeros(len(W))
        for c in range(J.shape[1]):
            ws += np.where(np.isin(J[:, c], grp), W[:, c], 0.0)
        vi = np.nonzero(ws > r['gate'])[0]
        pts = np.asarray([P[g] for g in grp], dtype=float)
        ax = pts[-1] - pts[0]
        axn = float(np.linalg.norm(ax)); ax = ax / axn
        q = (np.asarray(V[vi], dtype=float) - pts[0]) @ ax
        qlo, qhi = float(q.min()), float(q.max())
        s = (q - qlo) / (qhi - qlo)
        span = qhi - qlo                                    # etendue de la CHAIR sur l'axe
        tk0 = np.clip((((pts - pts[0]) @ ax) - qlo) / (qhi - qlo), 0.0, 1.0)

        plo, phi = RS._spec30_p_range(r['root'])
        cand = np.linspace(plo, phi, 2001)
        fr = np.array([float((r['root'] * np.power(1.0 - s, pc) >= r['strong']).mean())
                       for pc in cand])
        p = float(cand[int(np.argmin(np.abs(fr - r['frac'])))])
        anc = r['root'] * np.power(np.clip(1.0 - s, 0.0, 1.0), p)

        print('=' * 100)
        print('=== %s   nuage=%d sommets   axe de la chair=%.1f u   grad=%.2f  root=%.2f  p=%.3f'
              % (tag, len(vi), span, r['grad'], r['root'], p))
        print('  LIVRE : lBoob/rBoob a r=%.3f · lBooc/rBooc a r=%.3f · segment simule = %.1f u'
              ' = **%.1f %% de la chair**'
              % (tk0[0], tk0[1], (tk0[1] - tk0[0]) * span,
                 100.0 * (tk0[1] - tk0[0])))
        # invariance de l'ancrage, DEMONTREE et non affirmee : les bandes ne dependent que de `s`
        print('  ANCRAGE (INVARIANT sous un glissement le long de l\'axe — il ne depend que de `s`) :')
        line = '   '
        for lo, hi, blo, bhi, lbl in BANDS:
            m = (s >= lo) & (s < hi)
            v = float(anc[m].mean()) if m.any() else float('nan')
            ok = 'DANS' if (m.any() and blo <= v <= bhi) else ('n/a' if not m.any() else 'HORS')
            line += ' %s=%.3f[%s]' % (lbl, v, ok)
        print(line)
        srf = float((anc >= r['strong']).mean())
        print('   StrongRootFraction=%.3f (bande 0.28-0.35 de la 30)  %s'
              % (srf, 'DANS' if 0.28 <= srf <= 0.35 else 'HORS'))
        print()
        print('  BALAYAGE DU PLACEMENT — on glisse les DEUX noeuds sur l\'axe (r0 = proximal,')
        print('  r1 = distal). La ligne marquee LIVRE reproduit le mesh du jeu : c\'est la')
        print('  VALIDATION du banc, pas un resultat.')
        print('    r0     r1   segment  couverture  maj prox  maj dist  part distale  '
              'deform.loc  elong.organe (bande 22)   barre 30 %')
        cands = [(tk0[0], tk0[1], 'LIVRE')]
        for r0 in [round(0.40 + 0.02 * k, 3) for k in range(11)]:
            for r1 in [round(0.65 + 0.025 * k, 3) for k in range(15)]:
                cands.append((r0, r1, ''))
        for r0, r1, tagc in cands:
            if r1 <= r0 + 1e-6:
                continue
            tk = np.array([r0, r1])
            A = partition(s, tk, r['grad'])
            Aw = (1.0 - anc)[:, None] * A
            mj = [int((Aw[:, k] > 0.5).sum()) for k in range(2)]
            seg_u = (r1 - r0) * span
            part = mj[1] / len(vi)
            # CE QUE LA BORNE DU CYCLE 40 LIVRERAIT SUR CE SEGMENT : min(demande, 0.25*bl).
            # `demande` = `rrr` moyen mesure a la salle (avant borne), en unites de jeu.
            cap_u = 0.25 * seg_u
            deliv = min(DEMAND_U[tag], cap_u)
            loc = 100.0 * deliv / seg_u if seg_u > 1e-6 else float('inf')
            org = 100.0 * deliv / ORGAN_U[tag]
            adm = (mj[0] > 0) and (mj[1] > 0) and (part >= r['frac'])
            ok = ('ADMISSIBLE' if adm else
                  ('maillon PROXIMAL inerte' if mj[0] == 0 else
                   ('maillon DISTAL inerte' if mj[1] == 0 else 'SOUS LA BARRE')))
            if not adm and tagc != 'LIVRE':
                continue
            band = ('exceptionnelle' if 21.0 <= org <= 25.0 else
                    'large' if 15.0 <= org < 21.0 else
                    'courante' if 5.0 <= org < 15.0 else 'SOUS LE PLANCHER 5 %')
            print('   %5.3f  %5.3f  %6.1f u   %6.1f %%    %4d     %4d      %6.1f %%   '
                  '  %5.1f %%     %5.1f %% (%s)   %s %s'
                  % (r0, r1, seg_u, 100.0 * (r1 - r0), mj[0], mj[1], 100.0 * part,
                     loc, org, band, ok, tagc))
        print()
    print('RAPPEL DE CE QUE CE BANC NE DIT PAS : il predit la REPARTITION et la COUVERTURE.')
    print('Il ne predit ni la SPEC 24, ni la penetration, ni `comex` — celles-la se re-mesurent')
    print('a la salle APRES la cuisson, jamais avant.')


if __name__ == '__main__':
    main()
