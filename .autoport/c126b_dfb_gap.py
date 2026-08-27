#!/usr/bin/env python3
"""c126b_dfb_gap.py — `PHYSORI2` NE PUBLIE QUE LA MOITIE DU TENSEUR QUE LE SOLVEUR APPLIQUE.

POURQUOI CE FICHIER EXISTE. Le cycle 126 a extrait, par decomposition polaire, l'etirement S de la
matrice d'os REELLEMENT ECRITE au squelette, et l'a compare a la commande publiee par `PHYSORI2`.
A la cellule PRONE (i=6) les deux coincident a 6e-05 ; a la cellule SUPINE (i=8) elles different de
4,6e-02, soit ~770 fois plus. Un ecart qui apparait sur UNE cellule n'est pas un fait : c'est un
argmax (registre : `argmax-anchor-is-not-a-population`). Ce fichier le balaye sur TOUTES les
cellules et LES DEUX chaines, et publie la population entiere.

CE QUE LE CODE DIT, ET QU'IL FAUT VERIFIER PAR LA MESURE. `jak-hd-physics.gc:3796` construit le
tenseur applique comme `A = dfa . dfb`, avec le commentaire « forme d'equilibre PUIS etirement
dynamique » : `dfa` est bati sur `*phys-dfs*` — EXACTEMENT ce que `PHYSORI2` publie — et `dfb` est
l'etirement DYNAMIQUE accumule. `PHYSDFMA` lit `*phys-dfa*`, c'est-a-dire le PRODUIT.
Donc `PHYSORI2` publie `dfa` seul et `PHYSDFMA` publie `dfa . dfb` : leur ecart EST `dfb`, et il
vaut l'identite exactement quand la chaine est etablie.

NATURE / REPERE / LIGNE DE BASE (les trois questions obligatoires du contrat) :
  NATURE  : un ECART entre deux triplets de valeurs singulieres, sans dimension, a UN INSTANT (les
            deux enregistrements sont emis dans le MEME bloc de cellule, phys-room.gc:4386 et
            :4297) — pas une variance, pas un maximum de fenetre.
  REPERE  : aucun. Les valeurs singulieres d'une 3x3 sont invariantes par rotation des deux cotes ;
            c'est precisement ce qui rend la comparaison recevable sans supposer un triedre.
  LIGNE DE BASE : la cellule i=0 (pose debout d'auteur) et la cellule i=9 (2e cellule debout), ou
            la chaine est immobile : `dfb` doit y valoir l'identite, donc ecart ~0. C'est la
            LECTURE HORS DEFAUT, mesuree et non supposee.
"""
import math
import re
import sys

import numpy as np

LOG = sys.argv[1] if len(sys.argv) > 1 else \
    '.autoport/reports/Grecharged-secondary-motion/keira-room-x86.log'
txt = open(LOG, 'r', errors='replace').read()

cmd = {}
for m in re.finditer(r'^PHYSORI2 c=(\d+) i=(\d+) sx=([-\d.e+]+) sy=([-\d.e+]+) sz=([-\d.e+]+)',
                     txt, re.M):
    cmd[(int(m.group(1)), int(m.group(2)))] = (float(m.group(3)), float(m.group(4)),
                                               float(m.group(5)))
rows = {}
for m in re.finditer(r'^PHYSDFMA c=(\d+) i=(\d+) r=(\d+)'
                     r' m0=([-\d.e+]+) m1=([-\d.e+]+) m2=([-\d.e+]+)', txt, re.M):
    rows.setdefault((int(m.group(1)), int(m.group(2))), {})[int(m.group(3))] = (
        float(m.group(4)), float(m.group(5)), float(m.group(6)))
dfm = {k: np.array([v[r] for r in range(3)]) for k, v in rows.items() if len(v) == 3}

grav = {}
for m in re.finditer(r'^PHYSORI c=(\d+) i=(\d+) gx=([-\d.e+]+) gy=([-\d.e+]+) gz=([-\d.e+]+)',
                     txt, re.M):
    grav[(int(m.group(1)), int(m.group(2)))] = (float(m.group(3)), float(m.group(4)),
                                                float(m.group(5)))
# canal INDEPENDANT d'etablissement : le pic radial sur les 60 frames d'etablissement de la
# cellule (phys-room.gc:4233). Il ne partage NI la matrice de deformation NI son accesseur.
tr = {}
for m in re.finditer(r'^PHYSORITR c=(\d+) i=(\d+) rrt=([-\d.e+]+)', txt, re.M):
    tr[(int(m.group(1)), int(m.group(2)))] = float(m.group(3))
com = {}
for m in re.finditer(r'^PHYSORICOM2 c=(\d+) i=(\d+) rr=([-\d.e+]+) rrm=([-\d.e+]+)', txt, re.M):
    com[(int(m.group(1)), int(m.group(2)))] = (float(m.group(3)), float(m.group(4)))

if not dfm or not cmd:
    raise SystemExit('c126b: SUSPENDU — enregistrement absent de cette trace.')

print('C126B: `PHYSORI2` publie `dfa` (forme D\'EQUILIBRE seule) · `PHYSDFMA` publie `dfa . dfb`')
print('C126B: (equilibre x etirement DYNAMIQUE, jak-hd-physics.gc:3795-3797). Leur ECART EST `dfb`.')
print('C126B: Les deux sont emis dans le MEME bloc de cellule, donc au MEME instant.')
print('C126B: ' + '-' * 112)
print('C126B: %-4s %-3s | %-26s | %-26s | %-8s | %-7s | %-8s | %s'
      % ('c', 'i', 'COMMANDE (PHYSORI2) triee', 'APPLIQUE (PHYSDFMA) triee',
         'ecart', 'rot deg', 'det', 'pose (gz)'))
pop = []
for c in sorted({c for (c, _i) in dfm}):
    for i in sorted({i for (cc, i) in dfm if cc == c}):
        M = dfm[(c, i)]
        if (c, i) not in cmd:
            continue
        sv = sorted(np.linalg.svd(M, compute_uv=False), reverse=True)
        cv = sorted(cmd[(c, i)], reverse=True)
        gap = max(abs(a - b) for a, b in zip(sv, cv))
        A = (M - M.T) / 2
        rot = math.degrees(np.linalg.norm([A[2, 1], A[0, 2], A[1, 0]]) * 2)
        gz = grav.get((c, i), (0, 0, 0))[2]
        pose = ('DEBOUT' if abs(gz) < 0.2 else ('SUPINE' if gz > 0 else 'PRONE'))
        pop.append((c, i, gap, rot, pose))
        print('C126B: %-4d %-3d | %-26s | %-26s | %-8.2e | %-7.3f | %-8.5f | %+.4f %s'
              % (c, i, ' '.join('%.4f' % x for x in cv), ' '.join('%.4f' % x for x in sv),
                 gap, rot, np.linalg.det(M), gz, pose))
print('C126B: ' + '-' * 112)
gaps = sorted(p[2] for p in pop)
med = gaps[len(gaps) // 2]
print('C126B: POPULATION — %d cellules · mediane de l\'ecart %.2e · min %.2e · max %.2e (x%.0f la mediane)'
      % (len(pop), med, gaps[0], gaps[-1], gaps[-1] / max(med, 1e-12)))
hi = [p for p in pop if p[2] > 10 * med]
print('C126B: CELLULES A PLUS DE 10x LA MEDIANE : %s'
      % (', '.join('c=%d i=%d (%s, %.1e)' % (p[0], p[1], p[4], p[2]) for p in hi) or 'aucune'))
# LECTURE HORS DEFAUT, mesuree : les cellules DEBOUT, ou la chaine est immobile.
st = [p[2] for p in pop if p[4] == 'DEBOUT']
print('C126B: LECTURE HORS DEFAUT (cellules DEBOUT, chaine immobile) : max %.2e sur %d cellules'
      % (max(st), len(st)) if st else 'C126B: aucune cellule DEBOUT')
print('C126B: ' + '-' * 112)
print('C126B: CANAL INDEPENDANT D\'ETABLISSEMENT — `PHYSORITR` (pic radial sur les 60 frames')
print('C126B: d\'etablissement) ne partage NI la matrice de deformation NI son accesseur.')
xs = [p[2] for p in pop if (p[0], p[1]) in tr]
ys = [tr[(p[0], p[1])] for p in pop if (p[0], p[1]) in tr]
for p in pop:
    k = (p[0], p[1])
    if k in tr:
        print('C126B:   c=%d i=%-3d %-6s  ecart(dfb) %.2e   pic d\'etablissement rrt %.5f'
              % (p[0], p[1], p[4], p[2], tr[k]))
if len(xs) > 2:
    r = float(np.corrcoef(xs, ys)[0, 1])
    print('C126B: correlation(ecart dfb, pic d\'etablissement) = %+.4f sur %d cellules' % (r, len(xs)))
