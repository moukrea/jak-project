#!/usr/bin/env python3
"""c127b_engine_proxy.py — LE MOTEUR PEUT-IL CALCULER LUI-MEME SON ETAGE RIGIDE ?

POURQUOI. `c127_rigid_stage.py` etablit que l'etage RIGIDE (reconfiguration de la chaine, ZERO
etirement de tissu) porte deja 1,0977-1,1415 des 1,18-1,26 que §11 demande. Le tenseur recoit
pourtant la cible TOTALE (1,2125-1,2195 mesures a `PHYSORI2`) : c'est un double compte. La
correction est de ne commander que le RESIDU. Mais l'instrument qui isole l'etage rigide re-skinne
le mesh hors ligne, ce que le solveur ne peut pas faire par frame. **La question qui decide si la
route est cablable est donc : une grandeur que le solveur a DEJA SOUS LA MAIN predit-elle l'etage
rigide que l'instrument mesure ?** Regle `un-proxy-deux-clauses-biais-OPPOSES` : un proxy se VALIDE
contre la grandeur nommee AVANT d'etre cable, jamais apres.

LE PROXY CANDIDAT, ET IL N'UTILISE RIEN DE NEUF. A l'etape (b) (`jak-hd-physics.gc:3548`) la chaine
est deja resolue — l'ordre du pas est 0 (longueurs d'os, :2715) -> 1 (integration, :2726) ->
2 (contraintes, :3105) -> 3/4 (:3232) -> (b) (:3548) -> (f) (:3706) -> 6 ecriture (:3824). Les
positions `*phys-px/py/pz*` sont donc FINALES quand (b) tourne, et elles sont SANS TENSEUR par
construction (l.3899 met la translation a zero avant de multiplier, l.3908-3911 la restaure depuis
`*phys-px/py/pz*`). Le proxy est le vecteur entre les deux joints de la chaine :
    proxy(i) = |p_distal(i) - p_proximal(i)| / |p_distal(0) - p_proximal(0)|
C'est une LONGUEUR : invariante par rotation et par translation, donc lisible sans repere.

CE QUI EST COMPARE : proxy(i) contre `RIGID` de l'instrument (longueur racine->apex sur le nuage
re-skinne rotation-seule). Les deux ont la MEME ligne de base (cellule i=0, pose d'auteur).

NATURE / REPERE / LIGNE DE BASE :
  NATURE  : un rapport de LONGUEUR, sans dimension. Ce n'est pas une variance de mouvement.
  REPERE  : aucun — une longueur entre deux positions est un invariant euclidien.
  LIGNE DE BASE : cellule i=0 (pose debout d'auteur, §9 y exige la forme du modele). La lecture
            HORS DEFAUT est la cellule DEBOUT i=9, que rien ne relie a i=0 dans le balayage.
"""
import math
import os
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
jn, mats, nmiss = c124._read_matrices(txt)
if not mats:
    raise SystemExit('c127b: SUSPENDU — aucune ligne PHYSORIM.')
if nmiss:
    raise SystemExit('c127b: SUSPENDU — %d PHYSORIMMISS.' % nmiss)
slot = {v: k for k, v in jn.items()}
res, cells = c126.run(txt, inject_fwd=1.50)
P = print

P('C127B: cellules : SUPINE i=%s · PRONE i=%s · DEBOUT hors i=0 : 9' % (isup, ipro))
P('C127B: le proxy n\'utilise QUE les positions de joint solvees (ligne 3 des matrices livrees).')
P('C127B: ' + '=' * 104)
P('C127B: %-7s %-6s | %-9s | %-9s %-9s | %-9s | %s'
  % ('chaine', 'cell', 'proxy J-J', 'RIGID w>0', 'RIGID w>=.25', 'ecart pts', 'verdict P6'))

worst = 0.0
rows = []
for cn, joints in c126.CHAINS.items():
    jp, jd = joints[0], joints[1]
    def chord(i):
        a = mats[(i, slot[jp])][3, :3]
        b = mats[(i, slot[jd])][3, :3]
        return float(np.linalg.norm(b - a))
    c0 = chord(0)
    for cell, tag in ((ipro, 'PRONE'), (isup, 'SUPINE'), (9, 'DEBOUT')):
        pv = chord(cell) / c0
        r00 = res[(cn, 'w>0.00', 'RIGID')]
        r25 = res[(cn, 'w>=0.25', 'RIGID')]
        v00 = r00['Lpp'][cell] / r00['Lpp'][0]
        v25 = r25['Lpp'][cell] / r25['Lpp'][0]
        ec = max(abs(pv - v00), abs(pv - v25)) * 100.0
        if tag == 'PRONE':
            worst = max(worst, ec)
        P('C127B: %-7s %-6s | %-9.4f | %-9.4f %-12.4f | %8.2f  | %s'
          % (cn, tag, pv, v00, v25, ec, 'reference' if tag != 'PRONE' else
             ('DANS 5 pts' if ec <= 5.0 else 'AU-DELA de 5 pts')))
        rows.append((cn, tag, pv, v00, v25))

P('C127B: ' + '-' * 104)
P('C127B: P6 — ecart max du proxy au RIGID mesure, sur la cellule PRONE : %.2f points de pourcentage'
  % worst)
P('C127B:      Falsificateur declare : > 5 points. -> %s'
  % ('P6 TENUE — le proxy est admissible, le moteur peut calculer son etage rigide'
     if worst <= 5.0 else
     'P6 REFUTEE — le proxy N\'EST PAS admissible ; la route residuelle exige une grandeur que le'
     ' moteur n\'a pas, et ca se publie au lieu de cabler un proxy faux'))

# ---- CONTROLE : la cellule DEBOUT doit rendre 1,000 sur le proxy ET sur l'instrument -----------
d9 = [abs(r[2] - 1.0) for r in rows if r[1] == 'DEBOUT']
P('C127B:      CONTROLE hors defaut (cellule DEBOUT i=9) : ecart max du proxy a 1,000 = %.4f'
  ' (seuil 0,0100) -> %s' % (max(d9), 'TIRE' if max(d9) <= 0.01 else 'REFUTE'))
P('C127B: ' + '=' * 104)
