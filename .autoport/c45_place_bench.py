#!/usr/bin/env python3
"""c45_place_bench.py — LA CHAINE A N NOEUDS, PREDITE SANS CUISSON.

Phase Grecharged-secondary-motion, branche physics-keira-clean, KEIRA / POITRINE SEULE.
DIRECTIVES v3fee554599

POURQUOI (cycle 41 -> 45). L'owner a tranche le 2026-08-19 20:00 : sa spec ne bouge pas, c'est la
GEOMETRIE qui suit. « la chaine passe de 2 articulations a ~5-6, chacune repesee (regle du serial 7 :
une injection n'existe que si >= 30 % des sommets ont le nouvel os pour joint MAJORITAIRE) ».
Le banc du cycle 41 ne savait glisser que DEUX noeuds. Celui-ci est generique en N, et il repond a
la seule question qui decide de la cuisson : **jusqu'ou la chair simulee peut-elle s'etendre, et
combien de noeuds la barre des 30 % autorise-t-elle reellement sur ce nuage ?**

LES TROIS QUESTIONS (SPEC 7), repondues avant d'ecrire :
  NATURE  : une REPARTITION (combien de sommets chaque os possede en MAJORITE, w > 0.5) et une
            COUVERTURE (quelle part de `r` la chaine sous-tend). Ni une amplitude, ni une somme.
  REPERE  : `r` au sens de sa SPEC 31 (`axis=flesh`) — projection sur l'axe de la chaine,
            normalisee par les EXTREMES du nuage. C'est le repere ou `anchor30` travaille.
  ABSENT  : un placement qui ne pilote rien lit 0 sommet majoritaire pour l'os concerne.

CE QUE LE BANC PROUVE PAR CONSTRUCTION (identique au c41, et l'argument ne depend pas de N) :
  `anchor30` pose l'ancrage a `root*(1-s)^p` ou `s` ne depend QUE de la direction de l'axe et des
  extremes du nuage. Glisser/ajouter des noeuds LE LONG de cet axe ne change ni la direction ni le
  nuage, donc `s`, `p`, l'ancrage, les cinq bandes et `StrongRootFraction` sont INVARIANTS. Seule
  bouge `tk`. `physics_c7_reskin._anchor30` construit sa partition sur une liste `tk` de longueur
  quelconque : la fonction `partition()` recopiee ici est deja generique en N.

CE QU'IL NE DIT PAS : ni la SPEC 24, ni la penetration, ni `comex`. Celles-la se re-mesurent a la
salle APRES la cuisson, jamais avant.

USAGE : python3 .autoport/c45_place_bench.py [--in /tmp/c24/b-derived/prepped.glb] [--nmax 6]
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
# demande AVANT borne (`rrr` moyen, maillon de chair), course C40E5-CAPFIX, en unites de jeu :
DEMAND_U = {'chestL': 0.3424 * 602.0, 'chestR': 0.3455 * 602.0}
# organe racine->apex mesure sur le mesh LIVRE (probe_breast_chain_span.py), unites de jeu :
ORGAN_U = {'chestL': 734.21, 'chestR': 766.60}
U_PER_M = 4096.0                     # 4096 u = 1 m. Toute longueur porte sa conversion (owner 08-19).


def rule_for(target):
    for r in RS.load_cfg().get('keira-hd', []):
        if r.get('kind') == 'anchor30' and r.get('target') == target:
            return r
    return None


def partition(s, tk, grad):
    """LA PARTITION DE LA 31, RECOPIEE DE `physics_c7_reskin._anchor30` (:468-483).
    Generique en N : `tk` peut porter 2 noeuds comme 6."""
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


def majority(s, anc, tk, grad):
    """Nombre de sommets que CHAQUE noeud possede en MAJORITE (poids de chaine > 0.5)."""
    A = partition(s, tk, grad)
    Aw = (1.0 - anc)[:, None] * A
    return [int((Aw[:, k] > 0.5).sum()) for k in range(len(tk))]


def interior_by_quantile(s, grad, r0, rl, n_inner):
    """Noeuds interieurs poses aux QUANTILES DE MASSE du nuage entre r0 et rl.

    C'est le placement qui maximise le plus petit compte de sommets par maillon : repartir en
    parts EGALES DE NUAGE, pas en parts egales de longueur. Un espacement uniforme en `r` donne a
    la racine (dense, mais ancree) et a l'apex (clairsemé) des parts tres inegales."""
    inside = s[(s >= r0) & (s <= rl)]
    if len(inside) < n_inner + 1:
        return None
    qs = np.quantile(inside, [(k + 1) / (n_inner + 1) for k in range(n_inner)])
    tk = np.concatenate(([r0], qs, [rl]))
    if np.any(np.diff(tk) <= 1e-3):
        return None
    return tk


def interior_uniform(r0, rl, n_inner):
    return np.linspace(r0, rl, n_inner + 2)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--in', dest='inp', default='/tmp/c24/b-derived/prepped.glb')
    ap.add_argument('--nmax', type=int, default=6)
    a = ap.parse_args()
    if not os.path.exists(a.inp):
        raise SystemExit("entree absente : %s (c'est la sortie de prep, AVANT reskin)" % a.inp)

    geo = c6.load_geometry(G.MODEL, glb=a.inp)
    if geo is None:
        raise SystemExit('mesh illisible : %s' % a.inp)
    names, P, V, J, W = geo['names'], geo['P'], geo['V'], geo['J'], geo['W']
    idx = {n: i for i, n in enumerate(names)}

    print('BANC DE PLACEMENT A N NOEUDS — LA BARRE DE LA 30 PREDITE SANS CUISSON')
    print('NATURE repartition (w>0.5) + couverture de `r` · REPERE `axis=flesh` de la 31')
    print('ABSENT un placement qui ne pilote rien lit 0 sommet majoritaire')
    print('entree (sortie de prep, AVANT reskin) : %s' % a.inp)
    print('ordre owner 2026-08-19 20:00 : couvrir la course racine->apex, ~5-6 articulations,')
    print('barre du serial 7 (2026-08-18 08:55) : CHAQUE os injecte majoritaire sur >= 30 % du nuage')
    print()

    verdicts = {}
    for tag, joints in CHAINS.items():
        r = rule_for(tag)
        if r is None:
            print('%s : aucune regle anchor30' % tag)
            continue
        grp = [idx[j] for j in joints]
        ws = np.zeros(len(W))
        for c in range(J.shape[1]):
            ws += np.where(np.isin(J[:, c], grp), W[:, c], 0.0)
        vi = np.nonzero(ws > r['gate'])[0]
        pts = np.asarray([P[g] for g in grp], dtype=float)
        ax = pts[-1] - pts[0]
        ax = ax / float(np.linalg.norm(ax))
        q = (np.asarray(V[vi], dtype=float) - pts[0]) @ ax
        qlo, qhi = float(q.min()), float(q.max())
        s = (q - qlo) / (qhi - qlo)
        span = qhi - qlo
        tk0 = np.clip((((pts - pts[0]) @ ax) - qlo) / (qhi - qlo), 0.0, 1.0)

        plo, phi = RS._spec30_p_range(r['root'])
        cand = np.linspace(plo, phi, 2001)
        fr = np.array([float((r['root'] * np.power(1.0 - s, pc) >= r['strong']).mean())
                       for pc in cand])
        p = float(cand[int(np.argmin(np.abs(fr - r['frac'])))])
        anc = r['root'] * np.power(np.clip(1.0 - s, 0.0, 1.0), p)

        # --- LE PLAFOND DUR DU NUAGE, avant tout placement -------------------------------------
        # Un sommet ne peut appartenir a la CHAINE en majorite que si (1-anc) > 0.5, c'est-a-dire
        # anc < 0.5. Ce compte ne depend d'AUCUN placement : c'est ce que la 30 laisse disponible.
        free = int((anc < 0.5).sum())
        nfree = len(vi)
        s_wall = None
        ss = np.sort(s)
        for v in ss:
            if r['root'] * (1.0 - v) ** p < 0.5:
                s_wall = float(v)
                break
        bar = int(np.ceil(r['frac'] * nfree))
        nmax_bar = free // bar if bar else 0

        print('=' * 108)
        print('=== %s   nuage=%d sommets   chair sur l\'axe=%.1f u (%.1f cm)   grad=%.2f  root=%.2f'
              '  p=%.3f' % (tag, nfree, span, 100.0 * span / U_PER_M, r['grad'], r['root'], p))
        print('  LIVRE : noeud 0 a r=%.3f · noeud 1 a r=%.3f · segment simule = %.1f u (%.1f cm)'
              ' = **%.1f %% de la chair**'
              % (tk0[0], tk0[1], (tk0[1] - tk0[0]) * span,
                 100.0 * (tk0[1] - tk0[0]) * span / U_PER_M, 100.0 * (tk0[1] - tk0[0])))
        line = '  ANCRAGE (INVARIANT sous un glissement le long de l\'axe) : '
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
        print('  PLAFOND DUR DU NUAGE — il ne depend d\'AUCUN placement, seulement de la 30 :')
        print('    sommets ou la chaine PEUT etre majoritaire (anc < 0.5) : %d / %d = %.1f %%'
              % (free, nfree, 100.0 * free / nfree))
        print('    mur d\'ancrage : le premier sommet ou anc < 0.5 est a s = %.3f'
              % (s_wall if s_wall is not None else float('nan')))
        print('    barre du serial 7 : >= 30 %% du nuage = %d sommets par os injecte' % bar)
        print('    => AU PLUS %d os peuvent tenir la barre EN MEME TEMPS (%d disponibles / %d requis)'
              % (nmax_bar, free, bar))
        print()

        # --- BALAYAGE PAR NOMBRE DE NOEUDS -----------------------------------------------------
        print('  BALAYAGE PAR NOMBRE DE NOEUDS. Pour chaque N, on cherche le placement de plus')
        print('  GRANDE COUVERTURE admissible. Deux criteres, publies cote a cote :')
        print('    [A] barre du serial 7 telle qu\'ecrite : CHAQUE os injecte (noeuds 1..N-1)')
        print('        majoritaire sur >= 30 %% du nuage, et aucun maillon inerte.')
        print('    [B] critere de production du cycle 41 : aucun maillon inerte (>= 1 sommet')
        print('        majoritaire chacun) et le noeud DISTAL >= 30 %%.')
        print('    N   critere  r0     rN-1   couverture  segment      majorites par noeud'
              '        elong.organe')
        rows = []
        for N in range(2, a.nmax + 1):
            for crit in ('A', 'B'):
                best = None
                for r0 in [round(0.30 + 0.01 * k, 3) for k in range(41)]:
                    for rl in [round(0.60 + 0.01 * k, 3) for k in range(41)]:
                        if rl <= r0 + 0.02:
                            continue
                        for mk in (interior_by_quantile(s, r['grad'], r0, rl, N - 2),
                                   interior_uniform(r0, rl, N - 2)):
                            if mk is None:
                                continue
                            mj = majority(s, anc, mk, r['grad'])
                            if min(mj) < 1:
                                continue
                            if crit == 'A':
                                if any(m < bar for m in mj[1:]):
                                    continue
                            else:
                                if mj[-1] < bar:
                                    continue
                            cov = rl - r0
                            if best is None or cov > best[0] + 1e-9:
                                best = (cov, r0, rl, tuple(mk), tuple(mj))
                if best is None:
                    print('    %d   [%s]      AUCUN PLACEMENT ADMISSIBLE' % (N, crit))
                    rows.append((N, crit, None))
                    continue
                cov, r0, rl, mk, mj = best
                seg_u = cov * span
                deliv = min(DEMAND_U[tag], 0.25 * seg_u)
                org = 100.0 * deliv / ORGAN_U[tag]
                print('    %d   [%s]     %.3f  %.3f   %6.1f %%   %6.1f u    %-26s   %5.1f %%'
                      % (N, crit, r0, rl, 100.0 * cov, seg_u,
                         '/'.join(str(x) for x in mj), org))
                rows.append((N, crit, (cov, r0, rl, mk, mj, seg_u, org)))
        verdicts[tag] = dict(rows=rows, span=span, bar=bar, free=free, nfree=nfree,
                             tk0=tk0, organ=ORGAN_U[tag], s_wall=s_wall)
        print()

    # --- VERDICT ------------------------------------------------------------------------------
    print('=' * 108)
    print('VERDICT — CE QUE LA GEOMETRIE PEUT RENDRE, ET CE QU\'ELLE NE PEUT PAS')
    for tag, v in verdicts.items():
        bestA = [r for r in v['rows'] if r[1] == 'A' and r[2]]
        bestB = [r for r in v['rows'] if r[1] == 'B' and r[2]]
        nA = max((r[0] for r in bestA), default=0)
        nB = max((r[0] for r in bestB), default=0)
        covA = max((r[2][0] for r in bestA), default=0.0)
        covB = max((r[2][0] for r in bestB), default=0.0)
        orgA = max((r[2][6] for r in bestA), default=0.0)
        orgB = max((r[2][6] for r in bestB), default=0.0)
        cov0 = float(v['tk0'][1] - v['tk0'][0])
        print('  %s : LIVRE %.1f %% de couverture. Critere [A] (barre telle qu\'ecrite) : au plus'
              ' %d noeuds,' % (tag, 100.0 * cov0, nA))
        print('        couverture max %.1f %%, elongation d\'organe %.1f %%. Critere [B] : au plus'
              ' %d noeuds,' % (100.0 * covA, orgA, nB))
        print('        couverture max %.1f %%, elongation d\'organe %.1f %%.'
              % (100.0 * covB, orgB))
        print('        Cible de sa SPEC 22 : 21-25 %% d\'elongation d\'organe. Facteur restant :'
              ' x%.1f [A] / x%.1f [B].'
              % (21.0 / orgA if orgA else float('inf'), 21.0 / orgB if orgB else float('inf')))


if __name__ == '__main__':
    main()
