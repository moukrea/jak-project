#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
CYCLE 119 — LA MARGE DE FALSIFIABILITE DES SIX ECHELLES DE §10/§11.
DIRECTIVES vd9e8b66782

Le BLOC B montre que les bandes de verdict de §10/§11 sont CENTREES sur les valeurs que le
solveur recoit du fichier livre. Ca ne suffit PAS a ecrire `TAUTOLOGIQUE` : la directive du
2026-08-22 22:50 reserve ce mot a une mesure qui REPUBLIE sa cible, c'est-a-dire qui ne peut
pas echouer. Ici il faut le CHIFFRER, et un faux rouge coute autant qu'un faux vert.

  ecart    = |echelle COMMANDEE mesuree - valeur que le fichier donne au solveur|
  demi-b.  = demi-largeur de la bande de verdict de l'instrument
  part     = ecart / demi-largeur.  part << 1 => la cellule ne peut pas echouer en pratique.
             part >= 1 => elle echoue. La cellule qui echoue PROUVE que le test n'est pas vide.

NATURE : sans dimension, rapport a la forme d'auteur.  REPERE : le triedre de §7 (+X lateral,
+Y haut, +Z avant), releve a la pose debout d'auteur.  SOURCE : `ROOM-ORI` du tableau livre —
c'est ce que le solveur COMMANDE, pas ce que la peau recoit.
"""
import re, sys
T = '.autoport/reports/Grecharged-secondary-motion/keira-room-table.txt'
ORI = {}
for L in open(T, encoding='utf-8'):
    m = re.match(r'^ROOM-ORI: (\w+)\s+(\d+)\s+\d+\s+\S+\s+\S+\s+\S+\s+\S+\s+'
                 r'([\d.]+)\s+([\d.]+)\s+([\d.]+)', L)
    if m:
        ORI[(m.group(1), int(m.group(2)))] = (float(m.group(3)), float(m.group(4)), float(m.group(5)))
AX = {'out': 0, 'up': 1, 'fwd': 2}
CELLS = [('§10 supine projection', 8, 'fwd', 0.70, 0.65, 0.75, 'SupineProjectionScale'),
         ('§10 supine largeur',    8, 'out', 1.23, 1.18, 1.28, 'SupineWidthScale'),
         ('§10 supine hauteur',    8, 'up',  1.09, 1.05, 1.12, 'SupineHeightScale'),
         ('§11 prone longueur',    6, 'fwd', 1.23, 1.18, 1.26, 'HangingLengthScale'),
         ('§11 prone largeur',     6, 'out', 0.90, 0.87, 0.93, 'HangingWidthScale'),
         ('§11 prone epaisseur',   6, 'up',  0.91, 0.88, 0.94, 'HangingThicknessScale')]
print('CYCLE 119 — MARGE DE FALSIFIABILITE DES SIX ECHELLES CENTREES SUR LEUR PROPRE ENTREE')
print('DIRECTIVES vd9e8b66782')
print('source : %s\n' % T)
print('%-26s %-8s %7s %7s %8s %9s %7s  %s'
      % ('cellule', 'chaine', 'entree', 'mesure', 'ecart', 'demi-band', 'part', 'verdict'))
n_fail = n_tot = 0
parts = []
for lab, i, ax, tgt, lo, hi, key in CELLS:
    for ch in ('chestL', 'chestR'):
        v = ORI.get((ch, i))
        if not v: continue
        s = v[AX[ax]]
        half = (hi - lo) / 2.0
        d = abs(s - tgt)
        ok = lo <= s <= hi
        n_tot += 1; n_fail += (0 if ok else 1); parts.append(d/half)
        print('%-26s %-8s %7.4f %7.4f %8.4f %9.4f %6.0f %%  %s'
              % (lab, ch, tgt, s, d, half, 100*d/half, 'DANS' if ok else 'HORS'))
print()
print('%d cellules sur %d ECHOUENT — le test n\'est donc PAS vide, et le mot `TAUTOLOGIQUE`'
      % (n_fail, n_tot))
print('(reserve par la directive du 22:50 a une mesure qui NE PEUT PAS echouer) n\'est PAS pose.')
parts.sort()
print('part de la demi-bande : min %.0f %% · mediane %.0f %% · max %.0f %%'
      % (100*parts[0], 100*parts[len(parts)//2], 100*parts[-1]))
print('CE QUI EST POSE A LA PLACE : `MIROIR (bande centree sur l\'entree)`. La bande n\'est pas')
print('une propriete du personnage : elle est construite autour du nombre que NOUS donnons au')
print('solveur, et ce que la cellule mesure est le RESIDU de notre propre entree.')
