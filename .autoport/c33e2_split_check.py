#!/usr/bin/env python3
"""Lecteur INDEPENDANT de la decomposition de `dr0` (cycle 33 etape 2).

Il ne partage AUCUN code avec physics_room_table.py : il apparie `PHYSRADL` et `PHYSRADLD` par
ORDRE D'APPARITION dans la trace (les deux blocs sont emis dans la meme vidange de fenetre), et il
verifie l'identite `mlb + cdev = rrr` au signe pres.

NATURE  deux longueurs signees / B0, relevees a la frame de l'argmax de `rrr` dans SA fenetre.
REPERE  l'axe de l'os du maillon (m^), le meme que `rrr`.
ABSENT  une fenetre sans `PHYSRADLD` appariee est comptee et declaree, jamais completee.
"""
import re, sys, collections

LOG = sys.argv[1] if len(sys.argv) > 1 else \
    '.autoport/reports/Grecharged-secondary-motion/keira-room-x86.log'
DRIVES = ['updown', 'leftright', 'accel', 'jerk', 'tilt']
CHAINS = {0: 'chestL', 1: 'chestR'}

rl = re.compile(r'^PHYSRADL c=(\d+) d=(\d+) l=(\d+) rrm=([-\d.e+]+) rrr=([-\d.e+]+) sat=([-\d.e+]+)')
rd = re.compile(r'^PHYSRADLD c=(\d+) d=(\d+) l=(\d+) mlb=([-\d.e+]+) cdev=([-\d.e+]+)')

pend, best, unpaired, nwin = {}, {}, 0, collections.Counter()
for line in open(LOG, errors='replace'):
    m = rl.match(line)
    if m:
        k = (int(m.group(1)), int(m.group(2)), int(m.group(3)))
        pend[k] = (float(m.group(4)), float(m.group(5)), float(m.group(6)))
        nwin[k] += 1
        continue
    m = rd.match(line)
    if m:
        k = (int(m.group(1)), int(m.group(2)), int(m.group(3)))
        if k not in pend:
            unpaired += 1
            continue
        rrm, rrr, sat = pend.pop(k)
        cur = best.get(k)
        if cur is None or rrr > cur[1]:
            best[k] = (rrm, rrr, sat, float(m.group(4)), float(m.group(5)))

if not best:
    print('ABSENT : aucune paire PHYSRADL/PHYSRADLD dans %s' % LOG); sys.exit(1)

print('LECTEUR INDEPENDANT — decomposition de dr0, fenetre de l\'argmax de rrr')
print('  trace : %s' % LOG)
print('  paires appariees %d · lignes PHYSRADLD orphelines %d · fenetres vues %d'
      % (len(best), unpaired, sum(nwin.values())))
print()
print('%-8s %-10s %s %9s %9s %9s %9s   %s'
      % ('chaine', 'pilotage', 'l', 'rrr', 'mlb(OS)', 'cdev(CHAIR)', 'somme', 'part de l\'OS'))
bad = 0
for k in sorted(best):
    c, d, l = k
    rrm, rrr, sat, mlb, cdev = best[k]
    s = mlb + cdev
    err = abs(abs(s) - rrr)
    tot = abs(mlb) + abs(cdev)
    part = (100.0 * abs(mlb) / tot) if tot > 1e-9 else float('nan')
    flag = ''
    if err > 0.002:
        bad += 1; flag = '  ** I0 CASSEE (ecart %.5f) **' % err
    print('%-8s %-10s %d %9.4f %9.4f %11.4f %9.4f   %5.1f %%%s'
          % (CHAINS.get(c, 'c%d' % c), DRIVES[d] if d < len(DRIVES) else 'd%d' % d,
             l, rrr, mlb, cdev, s, part, flag))
print()
print('I0 : %d canal(aux) hors tolerance 0.002 B0 sur %d' % (bad, len(best)))
