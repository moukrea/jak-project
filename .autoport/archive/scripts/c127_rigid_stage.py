#!/usr/bin/env python3
"""c127_rigid_stage.py — QUE VAUT LA SAILLIE AVANT DE §10 QUAND ON RETIRE TOUT L'ETIREMENT ?

POURQUOI CE FICHIER EXISTE. Le cycle 126 a refute la route « commander au tenseur le residu
cible/rigide » par deux arguments : (a) la composition s'ecarte de 16,87 % sur §10 — argument
METROLOGIQUE, propre a §10 ; (b) « 7 cellules sur 8 exigent une commande hors de la bande de leur
propre section » — argument de PRINCIPE, applique aux deux sections. L'argument (b) suppose que la
cle du preset et la grandeur observable sont le MEME objet ; depuis le cycle 125 elles ne le sont
plus (la grandeur du verdict est mesuree sur la peau RE-SKINNEE, independante de ce qu'on injecte).
Mais (b) porte une vraie alerte, PROPRE A §10 : commander une EXPANSION pour livrer un
APLATISSEMENT signalerait que l'etage RIGIDE aplatit deja au-dela de la bande.

CE QUI EST MESURE ICI, ET QUI NE L'A JAMAIS ETE. Le cycle 126 a publie le nuage `RIGID` pour la
LONGUEUR de §11 et JAMAIS pour la SAILLIE de §10. Les deux se lisent pourtant sur le MEME `res`
deja calcule : saillie = Lpp x cos(ang). Aucun calcul neuf de skinning : on relit la structure que
`c126_rotation_vs_stretch.run()` produit, exactement comme `c126c_named_quantities.py` le fait pour
le nuage FULL.

NATURE / REPERE / LIGNE DE BASE (les trois questions obligatoires du contrat) :
  NATURE  : deux RAPPORTS DE FORME sans dimension, rapportes a la cellule debout i=0. Ce ne sont
            pas des variances de mouvement : un equilibre tenu ne bouge plus, ces grandeurs
            decrivent une FORME.
            §11 = une LONGUEUR (invariante par rotation). §10 = une SAILLIE SIGNEE le long de
            `fwd` (elle N'EST PAS invariante par rotation, et c'est voulu : la clause nomme une
            projection).
  REPERE  : §11 aucun (invariant euclidien). §10 le triedre de §7 mesure sur le rig, transporte
            dans la base de l'ANCRE `chest` a CHAQUE cellule.
  LIGNE DE BASE : la cellule i=0 (pose debout d'auteur, §9 y exige la forme exacte du modele), et
            la LECTURE HORS DEFAUT est la 2e cellule DEBOUT, que rien ne relie a i=0 dans le
            balayage — elle est identifiee par la GRAVITE MESUREE, jamais par son indice.
"""
import json
import math
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
import c124_delivered_shape as c124
import c126_rotation_vs_stretch as c126

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOG = sys.argv[1] if len(sys.argv) > 1 else \
    '.autoport/reports/Grecharged-secondary-motion/keira-room-x86.log'
txt = open(os.path.join(REPO, LOG) if not os.path.isabs(LOG) else LOG,
           'r', errors='replace').read()

isup, ipro, G = c124._roles(txt)
o2 = c124._ori2(txt)
res, cells = c126.run(txt, inject_fwd=1.50)
P = print


def proj(d, i):
    """saillie = |d| . cos(angle(d, fwd)) — MEME formule que c126c_named_quantities.py:71.
    Deux implementations d'une meme mesure finissent par diverger : celle-ci est copiee, et P5
    verifie qu'elle rend le meme chiffre que le script deja publie."""
    return d['Lpp'][i] * math.cos(math.radians(d['ang'][i]))


# ---- LES CELLULES DEBOUT, DESIGNEES PAR LA GRAVITE MESUREE ------------------------------------
g0 = np.mean([G[(c, 0)] for c in (0, 1) if (c, 0) in G], axis=0)
standing = []
for i in cells:
    if i == 0:
        continue
    gi = np.mean([G[(c, i)] for c in (0, 1) if (c, i) in G], axis=0)
    if float(np.linalg.norm(gi - g0)) < 0.02:
        standing.append(i)

P('C127: cellules designees par la GRAVITE MESUREE : SUPINE i=%s · PRONE i=%s' % (isup, ipro))
P('C127: cellules DEBOUT (|g - g(i=0)| < 0,02), hors i=0 : %s' % (standing,))
P('C127: ' + '=' * 108)

MODES = ('FULL', 'RIGID', 'STRETCH')
LBLS = ('w>0.00', 'w>=0.25')
fail = []

# ---- P4/P5 : LES DEUX CONTROLES, AVANT TOUT VERDICT -------------------------------------------
P('C127: P4 — CONTROLE NEGATIF, LECTURE HORS DEFAUT sur les cellules DEBOUT (seuil declare 1 %)')
worst4 = 0.0
for i9 in standing:
    for cn in c126.CHAINS:
        for lbl in LBLS:
            for mode in MODES:
                d = res[(cn, lbl, mode)]
                if i9 not in d['Lpp']:
                    continue
                rl = d['Lpp'][i9] / d['Lpp'][0]
                rp = proj(d, i9) / proj(d, 0)
                worst4 = max(worst4, abs(rl - 1.0), abs(rp - 1.0))
                P('C127:   i=%-3d %-7s %-8s %-8s  longueur §11 %.4f   saillie §10 %.4f'
                  % (i9, cn, lbl, mode, rl, rp))
P('C127:   ECART MAX A 1,000 sur les deux grandeurs et les trois nuages : %.4f  (seuil 0,0100) -> %s'
  % (worst4, 'TIRE' if worst4 <= 0.01 else 'REFUTE'))
if worst4 > 0.01:
    fail.append('P4')

P('C127: ' + '-' * 108)
P('C127: P5 — CONTROLE DE NON-VACUITE : la saillie FULL doit reproduire le chiffre deja publie par')
P('C127:      c126c_named_quantities.py (0,4619 / 0,4635 / 0,5367 / 0,4757), tolerance 0,5 %.')
PUB = {('chestL', 'w>0.00'): 0.4619, ('chestL', 'w>=0.25'): 0.4635,
       ('chestR', 'w>0.00'): 0.5367, ('chestR', 'w>=0.25'): 0.4757}
worst5 = 0.0
for cn in c126.CHAINS:
    for lbl in LBLS:
        v = proj(res[(cn, lbl, 'FULL')], isup) / proj(res[(cn, lbl, 'FULL')], 0)
        ref = PUB.get((cn, lbl))
        rel = abs(v / ref - 1.0) if ref else float('nan')
        worst5 = max(worst5, rel)
        P('C127:   %-7s %-8s  saillie FULL %.4f   publie c126c %.4f   ecart %.2f %%'
          % (cn, lbl, v, ref, 100.0 * rel))
P('C127:   ECART MAX : %.2f %%  (seuil 0,50 %%) -> %s'
  % (100.0 * worst5, 'TIRE' if worst5 <= 0.005 else 'REFUTE'))
if worst5 > 0.005:
    fail.append('P5')

if fail:
    P('C127: ' + '=' * 108)
    P('C127: CONTROLE(S) %s REFUTE(S) — RIEN N\'EST PUBLIE. Regle du contrat : un instrument qui ne'
      % ','.join(fail))
    P('C127: passe pas son propre controle ne rend pas de verdict.')
    sys.exit(1)

# ---- P1 / P2 / P3 : LE VERDICT ----------------------------------------------------------------
P('C127: ' + '=' * 108)
P('C127: LES TROIS ETAGES, SEPARES. `RIGID` = la chaine se reconfigure (rotation + positions de')
P('C127: joint solvees), ZERO etirement de tissu. `FULL` = ce que la peau recoit reellement.')
P('C127: ' + '-' * 108)
P('C127: %-5s %-7s %-8s | %-9s | %-8s %-8s %-8s | %-9s | %s'
  % ('sec', 'chaine', 'frontiere', 'COMMANDE', 'RIGID', 'STRETCH', 'FULL', 'bande', 'verdict RIGID'))

rows = []
for sec, cell, lo, hi, nom in (('11', ipro, 1.18, 1.26, 'LONGUEUR racine->apex'),
                               ('10', isup, 0.65, 0.75, 'SAILLIE avant')):
    for ci, cn in enumerate(c126.CHAINS):
        for lbl in LBLS:
            vals = {}
            for mode in MODES:
                d = res[(cn, lbl, mode)]
                vals[mode] = ((d['Lpp'][cell] / d['Lpp'][0]) if sec == '11'
                              else (proj(d, cell) / proj(d, 0)))
            cmd = o2.get((ci, cell))
            cmds = ('%.4f' % cmd[2]) if (cmd and sec == '10') else \
                   ('%.4f' % cmd[2]) if cmd else 'ABSENT'
            vr = vals['RIGID']
            verdict = 'DANS' if lo <= vr <= hi else ('SOUS' if vr < lo else 'AU-DESSUS')
            P('C127: §%-4s %-7s %-8s | %-9s | %-8.4f %-8.4f %-8.4f | %.2f-%.2f | %s'
              % (sec, cn, lbl, cmds, vals['RIGID'], vals['STRETCH'], vals['FULL'], lo, hi, verdict))
            rows.append((sec, cn, lbl, vals, lo, hi, verdict))

P('C127: ' + '-' * 108)
n_sous = sum(1 for r in rows if r[0] == '10' and r[6] == 'SOUS')
P('C127: P1 — §10 : le nuage RIGID est SOUS le plancher 0,65 sur %d cellules sur 4.' % n_sous)
P('C127:      Falsificateur declare : >= 2 cellules a 0,65 ou plus. -> %s'
  % ('P1 TENUE — la reconfiguration de la chaine aplatit A ELLE SEULE plus que la spec n\'autorise'
     ' au TOTAL' if n_sous >= 3 else 'P1 REFUTEE — l\'exces vient du tenseur, pas de l\'etage rigide'))

r11 = [r[3]['RIGID'] for r in rows if r[0] == '11']
P('C127: P2 — §11 : RIGID rend %.4f a %.4f  (cycle 126 : 1,0977 a 1,1415)'
  % (min(r11), max(r11)))
d126 = max(abs(min(r11) - 1.0977), abs(max(r11) - 1.1415))
P('C127:      ecart au chiffre du cycle 126 : %.4f (seuil 1 %% = 0,0110) -> %s'
  % (d126, 'TIRE' if d126 <= 0.011 else 'REFUTE — portage faux, rien n\'est publie'))

P('C127: ' + '-' * 108)
P('C127: P3 — LA COMMANDE RESIDUELLE DE §11 : ce que le tenseur devrait porter pour que le TOTAL')
P('C127:      tombe dans la bande, si la composition est multiplicative (verifiee a 2,9-4,7 %% sur')
P('C127:      §11 par c126d_double_count.py).')
lo11, hi11 = 1.18, 1.26
resid = []
for r in rows:
    if r[0] != '11':
        continue
    vr = r[3]['RIGID']
    resid.append((r[1], r[2], vr, lo11 / vr, hi11 / vr))
    P('C127:      %-7s %-8s  rigide %.4f  ->  commande admissible %.4f a %.4f'
      % (r[1], r[2], vr, lo11 / vr, hi11 / vr))
lo_i = max(x[3] for x in resid)
hi_i = min(x[4] for x in resid)
P('C127:      INTERSECTION des 4 cellules : %.4f a %.4f  -> %s'
  % (lo_i, hi_i, 'NON VIDE' if lo_i <= hi_i else 'VIDE'))
P('C127:      balayage independant du cycle 126 (valeur singuliere de S) : 1,1060 a 1,1384')
ov_lo, ov_hi = max(lo_i, 1.1060), min(hi_i, 1.1384)
P('C127:      RECOUVREMENT des deux derivations : %s'
  % ('%.4f a %.4f — les deux chemins se recouvrent' % (ov_lo, ov_hi) if ov_lo <= ov_hi
     else 'VIDE — les deux derivations se contredisent, RIEN n\'est engage'))

P('C127: ' + '=' * 108)
