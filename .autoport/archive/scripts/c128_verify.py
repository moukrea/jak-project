#!/usr/bin/env python3
"""c128_verify.py — JUGE LE LOT DU CYCLE 128 CONTRE LES PREDICTIONS P10..P16, ECRITES AVANT LA COURSE.

Les predictions sont dans `.autoport/c128-predictions.txt`, seconde serie. Ce script ne fait que
les CONFRONTER : il ne choisit rien, il n'ajuste rien, et il publie chaque grandeur avec son
falsificateur a cote. Deux traces sont comparees :

    AVANT : .autoport/reports/Grecharged-secondary-motion/keira-room-x86.c127.log  (md5 abb090c9...)
    APRES : .autoport/reports/Grecharged-secondary-motion/keira-room-x86.log       (course de ce cycle)

NATURE / REPERE / LIGNE DE BASE :
  NATURE  : des RAPPORTS DE LONGUEUR sans dimension (etage rigide, echelles commandees, longueur
            livree), et une LONGUEUR en unites de jeu (`dauth`, le denominateur).
  REPERE  : `rs` et les longueurs sont des invariants euclidiens ; les echelles commandees vivent
            sur le triedre de SPEC 7, convention `sx/sy/sz = (out, up, fwd)` du cycle 90.
  LIGNE DE BASE : la trace AVANT, cellule par cellule. LECTURE HORS DEFAUT : les cellules DEBOUT,
            ou l'etage rigide vaut 1 et ou la correction ne doit RIEN faire.
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import c124_delivered_shape as c124

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
R = os.path.join(REPO, '.autoport/reports/Grecharged-secondary-motion')
NEW = open(os.path.join(R, 'keira-room-x86.log'), 'r', errors='replace').read()
OLD = open(os.path.join(R, 'keira-room-x86.c127.log'), 'r', errors='replace').read()
P = print

RIG = re.compile(r'^PHYSRIGID c=(\d+) i=(\d+) rs=([-\d.]+) dauth=([-\d.]+)', re.M)
OR2 = re.compile(r'^PHYSORI2 c=(\d+) i=(\d+) sx=([-\d.]+) sy=([-\d.]+) sz=([-\d.]+) det=([-\d.]+)', re.M)
CH = {0: 'chestL', 1: 'chestR'}

isup_n, ipro_n, _ = c124._roles(NEW)
isup_o, ipro_o, _ = c124._roles(OLD)
P('C128V: cellules APRES  supine i=%d  prone i=%d   |   AVANT  supine i=%d  prone i=%d'
  % (isup_n, ipro_n, isup_o, ipro_o))
if (isup_n, ipro_n) != (isup_o, ipro_o):
    P('C128V: !! les roles de cellule ont bouge entre les deux courses — la comparaison cellule a '
      'cellule est SUSPENDUE (feedback_room_run_not_frame_reproducible).')

rig = {}
for m in RIG.finditer(NEW):
    rig[(int(m.group(1)), int(m.group(2)))] = (float(m.group(3)), float(m.group(4)))
o2n, o2o = {}, {}
for m in OR2.finditer(NEW):
    o2n[(int(m.group(1)), int(m.group(2)))] = tuple(float(m.group(i)) for i in (3, 4, 5, 6))
for m in OR2.finditer(OLD):
    o2o[(int(m.group(1)), int(m.group(2)))] = tuple(float(m.group(i)) for i in (3, 4, 5, 6))

P('C128V: ' + '=' * 104)
P('C128V: --- P10 LE CANAL AGIT ET IL EST NON VACUEUX -------------------------------------------')
if not rig:
    P('C128V: P10 ECHEC TOTAL — aucune ligne PHYSRIGID dans la trace. Le canal n\'a pas ete emis.')
    sys.exit(1)
cells = sorted({i for (_, i) in rig})
P('C128V: cellules d\'orientation emises : %s' % cells)
for c in sorted({c for (c, _) in rig}):
    row = [(i, rig[(c, i)][0]) for i in cells if (c, i) in rig]
    P('C128V: %-7s rs par cellule : %s'
      % (CH.get(c, str(c)), ' '.join('i%d=%.4f' % (i, v) for i, v in row)))
p10 = {}
for c in sorted({c for (c, _) in rig}):
    if (c, ipro_n) in rig:
        p10[c] = rig[(c, ipro_n)][0]
pro_ok = all(1.05 <= v <= 1.25 for v in p10.values()) and len(p10) >= 2
P('C128V: P10 etage rigide au PRONE : %s   (bande predite 1,05-1,25) -> %s'
  % (' · '.join('%s %.4f' % (CH.get(c, c), v) for c, v in sorted(p10.items())),
     'TENUE' if pro_ok else 'REFUTEE'))
# LES CELLULES DEBOUT SE LISENT DANS LA TRACE, PAS PAR EXCLUSION. Premier jet de ce script :
# « toute cellule qui n'est ni prone ni supine » — c'etait FAUX, ca englobait les 7 orientations
# INCLINEES ou l'etage rigide vaut legitimement 0,87 a 1,12, et ca faisait echouer deux controles
# qui n'avaient rien a juger. La verite est publiee par `PHYSORI3 deg=` : DEBOUT <=> deg = 0.
ORI3 = re.compile(r'^PHYSORI3 c=(\d+) i=(\d+) ax=(-?\d+) deg=([-\d.]+)', re.M)
STAND = sorted({int(m.group(2)) for m in ORI3.finditer(NEW) if abs(float(m.group(4))) < 0.001})
P('C128V: cellules DEBOUT (PHYSORI3 deg=0) : %s' % STAND)
std = [(c, i, rig[(c, i)][0]) for (c, i) in sorted(rig) if i in STAND]
worst_std = max((abs(v - 1.0) * 100 for _, _, v in std), default=0.0)
P('C128V:     lecture HORS DEFAUT (cellules DEBOUT) : ecart max a 1,000 = %.3f %% '
  '(seuil 1 %%) -> %s' % (worst_std, 'TIRE' if worst_std <= 1.0 else 'ECHEC'))

P('C128V: --- P11 GARDE : LE DENOMINATEUR EST-IL CONSTANT ? --------------------------------------')
for c in sorted({c for (c, _) in rig}):
    ds = [rig[(c, i)][1] for i in cells if (c, i) in rig]
    if not ds:
        continue
    spread = (max(ds) / min(ds) - 1.0) * 100.0 if min(ds) > 0 else float('inf')
    P('C128V: %-7s dauth min %.2f  max %.2f  u   etendue %.3f %%  (falsificateur 2 %%) -> %s'
      % (CH.get(c, c), min(ds), max(ds), spread, 'TENUE' if spread < 2.0 else 'REFUTEE — MESURE SUSPENDUE'))

P('C128V: --- P12 / P16 LA COMMANDE DE §11 (axe fwd = sz) ---------------------------------------')
for c in sorted({c for (c, _) in o2n}):
    a = o2o.get((c, ipro_o)), o2n.get((c, ipro_n))
    if a[0] and a[1]:
        P('C128V: %-7s PRONE  sz AVANT %.4f -> APRES %.4f   (%+.2f %%)   predit [1,05 ; 1,12]'
          % (CH.get(c, c), a[0][2], a[1][2], (a[1][2] / a[0][2] - 1) * 100))
    stdc = [i for i in STAND if (c, i) in o2n and (c, i) in o2o]
    if stdc:
        w = max(abs(o2n[(c, i)][2] / o2o[(c, i)][2] - 1) * 100 for i in stdc)
        P('C128V: %-7s P16 controle negatif de portee — cellules DEBOUT, ecart max sur sz = %.3f %% '
          '(seuil 0,5 %%) -> %s' % (CH.get(c, c), w, 'TENUE' if w <= 0.5 else 'REFUTEE'))

P('C128V: --- P13 / P14 CE QUE LA PEAU RECOIT ---------------------------------------------------')
AXN = {'out': 'largeur', 'up': 'epaisseur', 'fwd': 'LONGUEUR'}
BAND = c124.BANDS['11']
try:
    _l_new, rows_new, _ = c124.measure(NEW)
    _l_old, rows_old, _ = c124.measure(OLD)
except Exception as e:                                            # noqa: BLE001
    P('C128V: c124 a echoue : %s' % e)
    sys.exit(1)
keys = sorted(k for k in rows_new if k[2] == '11')
for k in keys:
    cn, lbl, _sec, ax = k
    if k not in rows_old:
        continue
    nv, ov = rows_new[k], rows_old[k]
    lo, hi = BAND[ax]
    P('C128V: %-7s %-8s %-9s  AVANT %.4f -> APRES %.4f  (%+.2f %%)  bande %.2f-%.2f  %s'
      % (cn, lbl, AXN[ax], ov[0], nv[0], (nv[0] / ov[0] - 1) * 100 if ov[0] else 0.0,
         lo, hi, 'DANS' if lo <= nv[0] <= hi else ('AU-DESSUS' if nv[0] > hi else 'SOUS')))
fwd_new = [rows_new[k][0] for k in keys if k[3] == 'fwd']
if fwd_new:
    P('C128V: P13 longueur livree APRES : %s   predit [1,16 ; 1,23]  falsificateur >1,26 ou <1,12'
      % ' · '.join('%.4f' % v for v in fwd_new))
    P('C128V:     -> %s'
      % ('TENUE' if all(1.16 <= v <= 1.23 for v in fwd_new)
         else ('REFUTEE PAR SON FALSIFICATEUR' if any(v > 1.26 or v < 1.12 for v in fwd_new)
               else 'HORS DE MA BANDE PREDITE mais DANS son falsificateur — publie tel quel')))
    inb = sum(1 for v in fwd_new if BAND['fwd'][0] <= v <= BAND['fwd'][1])
    P('C128V:     cellules DANS la bande de la SPEC (1,18-1,26) : %d / %d' % (inb, len(fwd_new)))
P('C128V: ' + '=' * 104)
