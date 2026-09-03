#!/usr/bin/env python3
"""probe_c57_anchor_axis.py — SUR QUEL AXE LE REPESAGE INSTALLE-T-IL LE PROFIL DE LA SPEC 30 ?

Phase Grecharged-secondary-motion, branche physics-keira-clean, KEIRA / POITRINE SEULE.
DIRECTIVES v3fee554599

POURQUOI CET INSTRUMENT (cycle 57). Le registre porte depuis le cycle 51 un plafond d'apex de
x1.76 / x1.68 « hors d'atteinte de toute physique », qui BORNE les verdicts de six sections
(14, 16, 17, 18, 22, 30). Ce plafond vaut `1 - ancrage(apex)`. Deux instruments a moi rendaient
sur ce point des chiffres qui different d'un facteur ~10 :
    probe_breast_anchor30.py, bloc « ABSCISSE DE LA 31 » : ancrage(apex) = 0.040 / 0.029  -> 5/5 DANS
    probe_c48_com_identity.py, decile C (axe anatomique) : ancrage(apex) = 0.4451 / 0.4064 -> AU-DESSUS
Un des deux se trompe de REPERE, et le verdict de six sections en depend.

LES TROIS QUESTIONS DE LA SPEC 7, repondues AVANT le chiffre :
  NATURE  — un PROFIL (l'ancrage en fonction de la profondeur) ET l'ACCORD DE DEUX ABSCISSES
            (angle, correlation). Pas une amplitude : la question n'est pas « le profil
            descend-il » mais « descend-il le long de la BONNE direction ».
  REPERE  — pose de bind, monde, et LES MEMES sommets pour les deux abscisses :
            (a) `s_op`  = ce que l'operateur `anchor30 axis=flesh` calcule REELLEMENT,
                          physics_c7_reskin.py:436-444 : projection sur `pts[-1]-pts[0]`,
                          c'est-a-dire l'axe d'OS de la chaine.
            (b) `r_ana` = l'axe que la 31 DEFINIT, mot pour mot : « r = 0 at chest attachment
                          and r = 1 at distal/apex region » — joint racine -> centroide pondere
                          de l'organe. C'est `axa` de probe_c48_com_identity.py:342-344.
  ABSENT  — si les deux abscisses etaient le meme repere : angle 0 deg, correlation +1.000, et
            les deux colonnes de bandes identiques. C'est la lecture qui REFUTE l'hypothese.

CE QUE L'INSTRUMENT NE FAIT PAS : il ne cuit rien et n'ecrit rien. Lecture pure.

USAGE : python3 .autoport/probe_c57_anchor_axis.py [chemin.glb]
"""
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(REPO, 'scripts', 'shell'))

import physics_keira_gen2 as G          # noqa: E402
import physics_c6_volumes as c6         # noqa: E402
from probe_skin_profile import parse_chain_joints, CHAINS, SHIPPED   # noqa: E402

GATE = G.INFL_GATE
# LES CINQ BANDES DE LA 30, recopiees du texte (SPEC-breast-softbody.md l.378-382), pas choisies.
BANDS = ((0.000, 0.125, 0.90, 1.00, 'Deep root'),
         (0.125, 0.375, 0.55, 0.85, 'Rear/intermed'),
         (0.375, 0.625, 0.25, 0.55, 'Mid-volume'),
         (0.625, 0.875, 0.05, 0.30, 'Distal'),
         (0.875, 1.001, 0.00, 0.10, 'Apex (minimal)'))
ROOT_ANCHOR, STRONG, STRONG_FRAC = 0.95, 0.55, 0.30


def bands_of(absc, anc):
    out = []
    for lo, hi, blo, bhi, lbl in BANDS:
        m = (absc >= lo) & (absc < hi)
        if not m.any():
            out.append((lbl, 0, float('nan'), 'n=0'))
            continue
        a = float(anc[m].mean())
        v = 'DANS' if blo <= a <= bhi else ('AU-DESSUS' if a > bhi else 'SOUS')
        out.append((lbl, int(m.sum()), a, v))
    return out


def main():
    rel = sys.argv[1] if len(sys.argv) > 1 else SHIPPED
    geo = c6.load_geometry(G.MODEL, glb=rel)
    if geo is None:
        raise SystemExit('mesh introuvable : %s' % rel)
    names, P, V, J, W = geo['names'], geo['P'], geo['V'], geo['J'], geo['W']
    idx_of = {n: i for i, n in enumerate(names)}
    chains = parse_chain_joints(CHAINS)

    print('PROFIL D\'ANCRAGE — DEUX ABSCISSES SUR LES MEMES SOMMETS   mesh : %s' % rel)
    print('NATURE profil ancrage(r) + accord de deux abscisses · REPERE bind, monde')
    print('ABSENT angle 0 deg, correlation +1.000, colonnes identiques\n')

    for cname in ('chestL', 'chestR'):
        joints = [j for j in chains[cname]['joints'] if j in idx_of]
        grp = [idx_of[j] for j in joints]
        ws = np.zeros(len(W))
        for c in range(J.shape[1]):
            ws += np.where(np.isin(J[:, c], grp), W[:, c], 0.0)
        for lbl_pop, vi in (('REGLE  (ws > %.2f)' % GATE, np.flatnonzero(ws > GATE)),
                            ('ORGANE (ws > 0)   ', np.flatnonzero(ws > 0.0))):
            Vv = np.asarray(V[vi], dtype=float)
            pts = np.asarray([P[g] for g in grp], dtype=float)
            axb = pts[-1] - pts[0]
            axb = axb / np.linalg.norm(axb)
            q = (Vv - pts[0]) @ axb
            s_op = (q - q.min()) / (q.max() - q.min())
            wch = ws[vi]
            corg = (wch[:, None] * Vv).sum(axis=0) / wch.sum()
            axa = corg - pts[0]
            axa = axa / np.linalg.norm(axa)
            p2 = (Vv - pts[0]) @ axa
            r_ana = (p2 - p2.min()) / (p2.max() - p2.min())
            anc = 1.0 - wch
            ang = float(np.degrees(np.arccos(np.clip(float(axb @ axa), -1, 1))))
            rho = float(np.corrcoef(s_op, r_ana)[0, 1])
            print('=== %s   population %s   n=%d' % (cname, lbl_pop, len(vi)))
            print('    angle(axe d\'OS de l\'operateur , axe ANATOMIQUE de la 31) = %.2f deg'
                  '   cos = %.3f' % (ang, float(axb @ axa)))
            print('    correlation Pearson(s_op , r_ana) = %+.3f' % rho)
            for nm, absc in (('s_op  (ce que l\'operateur INSTALLE)', s_op),
                             ('r_ana (ce que la 31 DEMANDE)      ', r_ana)):
                cols = ' | '.join('%s=%.3f %s' % (l[:4], a, v) for l, n, a, v in bands_of(absc, anc))
                nin = sum(1 for l, n, a, v in bands_of(absc, anc) if v == 'DANS')
                print('    %s : %s   -> %d/5 DANS' % (nm, cols, nin))
            srf = float((anc >= STRONG).mean())
            print('    StrongRootFraction (ancrage >= %.2f) = %.3f   bande 0.28-0.35   %s'
                  % (STRONG, srf, 'DANS' if 0.28 <= srf <= 0.35 else 'HORS'))
            print('    PLAFOND D\'APEX = poids de chaine moyen sur la bande apex de r_ana :')
            m = r_ana >= 0.875
            if m.any():
                cap = float(wch[m].mean())
                print('        %.4f  (l\'apex ne peut rendre que cette fraction de ce que les'
                      ' maillons produisent -> x%.2f manquant)' % (cap, 1.0 / max(cap, 1e-9)))
            print()


if __name__ == '__main__':
    main()
