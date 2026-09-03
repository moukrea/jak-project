#!/usr/bin/env python3
"""C80b — LES 7,85 g DE L'ANIMATION : UN A-COUP D'ECHANTILLONNAGE, OU UN VRAI GESTE ?

C'est la question n°1 du chantier du cycle 80, et elle se tranche sur la FORME du pic, pas sur
sa hauteur. Deux hypotheses opposees, discriminables sur la MEME donnee :
  (a) GESTE REEL     -> l'acceleration monte et redescend sur plusieurs frames ; les voisins
                        immediats du maximum en valent une fraction NOTABLE.
  (b) A-COUP DE POSE -> le maximum est isole sur UNE frame (la pose d'auteur saute) ; ses
                        voisins sont petits devant lui.

NATURE : une acceleration, u/frame^2 (11.162 = 1 g), obtenue par DIFFERENCE SECONDE de la
  position monde du joint : a(t) = p(t+1) - 2 p(t) + p(t-1). REPERE : le MONDE, celui de
  `PHYSJTW row=3`. POPULATION : les frames de la sous-fenetre de LIGNE DE BASE (aucun pilotage),
  par animation et par joint. LECTURE QUAND LE DEFAUT EST ABSENT : sur une trajectoire lisse,
  le rapport voisin/maximum tend vers 1 ; sur un saut d'une frame, vers 0.

RESERVE DECLAREE : ces positions sont ECRITES par la physique, pas la pose d'auteur nue. Mais un
integrateur ressort ne PEUT PAS produire un pic isole d'une seule frame — sa sortie est lissee
par construction. Un pic isole ne peut donc venir que de l'ENTREE. C'est ce qui rend le test
valide malgre la reserve : il est concluant dans un sens (isole => a-coup), prudent dans l'autre.
"""
import re, sys
import numpy as np

LOG = '.autoport/reports/Grecharged-secondary-motion/keira-room-x86.log'
txt = open(LOG, errors='ignore').read()
JN = {0: 'lBoob', 1: 'lBooc', 2: 'rBoob', 3: 'rBooc'}

pos, key = {}, {}
for m in re.finditer(r'^PHYSJTW k=(\d+) j=(\d+) row=3 x=([-\d.e+]+) y=([-\d.e+]+) z=([-\d.e+]+)', txt, re.M):
    pos[(int(m.group(1)), int(m.group(2)))] = np.array([float(m.group(i)) for i in (3, 4, 5)])
for m in re.finditer(r'^PHYSJTWK k=(\d+) a=(\d+) d=(\d+) f=([-\d.e+]+)', txt, re.M):
    key[int(m.group(1))] = (int(m.group(2)), int(m.group(3)), float(m.group(4)))

print('DIRECTIVES v3fee554599')
print('== 0. LA FENETRE DE LIGNE DE BASE CONTIENT-ELLE UN BOUCLAGE D\'ANIMATION ? ==')
byanim = {}
for k, (a, d, f) in key.items():
    byanim.setdefault(a, []).append((k, f))
nwrap = 0
for a in sorted(byanim):
    s = sorted(byanim[a])
    fs = [f for _k, f in s]
    d = np.diff(fs)
    back = int((d < -0.5).sum())
    if back:
        nwrap += 1
print('   %d animations ; %d contiennent un RETOUR EN ARRIERE de `f` (bouclage) dans la fenetre'
      % (len(byanim), nwrap))
print('   -> un bouclage serait une discontinuite de pose ; il faut savoir s\'il y en a AVANT')
print('      d\'attribuer quoi que ce soit au geste.')

print()
print('== 1. LA FORME DU PIC D\'ACCELERATION, PAR ANIMATION ET PAR JOINT ==')
print('   rapport = |a| au voisin immediat du maximum / |a| au maximum. Median sur la population.')
rows = []
for a in sorted(byanim):
    ks = [k for k, _f in sorted(byanim[a])]
    for ji in sorted(JN):
        P = [pos.get((k, ji)) for k in ks]
        if any(p is None for p in P) or len(P) < 5:
            continue
        P = np.array(P)
        acc = P[2:] - 2 * P[1:-1] + P[:-2]
        n = np.linalg.norm(acc, axis=1)
        if n.max() <= 1e-9:
            continue
        i = int(n.argmax())
        nb = []
        if i - 1 >= 0: nb.append(n[i - 1])
        if i + 1 < len(n): nb.append(n[i + 1])
        rows.append((a, ji, float(n.max()), float(max(nb) / n.max()) if nb else float('nan'),
                     float(np.median(n))))
r = np.array([[x[2], x[3], x[4]] for x in rows])
print('   n = %d couples (animation, joint)' % len(rows))
print('   |a| MAXIMUM        p50 %8.2f u/f2 (%.2f g)   p95 %8.2f (%.2f g)   max %8.2f (%.2f g)'
      % (np.percentile(r[:, 0], 50), np.percentile(r[:, 0], 50) / 11.162,
         np.percentile(r[:, 0], 95), np.percentile(r[:, 0], 95) / 11.162,
         r[:, 0].max(), r[:, 0].max() / 11.162))
print('   |a| MEDIAN de fenetre  p50 %8.2f u/f2 (%.2f g)'
      % (np.percentile(r[:, 2], 50), np.percentile(r[:, 2], 50) / 11.162))
print('   rapport pic/median     p50 %8.1f x' % np.percentile(r[:, 0] / np.maximum(r[:, 2], 1e-9), 50))
print()
print('   VOISIN / MAXIMUM   p05 %.3f   p25 %.3f   **p50 %.3f**   p75 %.3f   p95 %.3f'
      % tuple(np.percentile(r[:, 1], q) for q in (5, 25, 50, 75, 95)))
med = float(np.percentile(r[:, 1], 50))
print()
print('== VERDICT ==')
if med < 0.25:
    print('   Le voisin immediat du maximum vaut %.1f %% du maximum en median.' % (100 * med))
    print('   **LE PIC EST ISOLE SUR UNE FRAME -> HYPOTHESE (b), A-COUP DE POSE.**')
elif med > 0.5:
    print('   Le voisin immediat du maximum vaut %.1f %% du maximum en median.' % (100 * med))
    print('   **LE PIC EST SOUTENU -> HYPOTHESE (a), GESTE REEL.** La bande de §22 est alors')
    print('   inatteignable tant que ces animations sont jouees : c\'est un appel de l\'owner.')
else:
    print('   Le voisin vaut %.1f %% du maximum en median : NI ISOLE NI SOUTENU.' % (100 * med))
    print('   **NON CONCLUANT sur cette grandeur.** Ne pas trancher ; dire ce qui manque.')
print()
print('== 2. LES DIX PIRES COUPLES, NOMMES ==')
rows.sort(key=lambda x: -x[2])
print('   %-4s %-8s %12s %10s %10s' % ('anim', 'joint', '|a| max u/f2', 'en g', 'voisin/max'))
for a, ji, mx, rt, md in rows[:10]:
    print('   a=%-2d %-8s %12.2f %10.2f %10.3f' % (a, JN[ji], mx, mx / 11.162, rt))
