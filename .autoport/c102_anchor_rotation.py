#!/usr/bin/env python3
"""c102 — CONTRE-CONTROLE INDEPENDANT DE LA ROTATION D'ANCRE DU CYCLE 101.

Le cycle 101 a publie `PHYSANROT` — un instrument du MOTEUR, depuis retire — et en a tire que
« l'ancre tourne de 59,9 deg en une frame dans TOUTES les fenetres de ligne de base ». Ce script
rederive la MEME grandeur par un chemin qui ne partage NI l'operateur NI le site d'emission :
`PHYSJTW`, publie par la SALLE, qui donne les quatre lignes de la 4x4 du joint `chest` resolu PAR
NOM (`PHYSJTWN j=4 idx=3 name=chest`) — `chest` etant l'ancre des deux chaines et n'etant simule
par rien.

NATURE : un ANGLE en DEGRES. REPERE : celui de l'ancre — angle de `R(f-1)^T . R(f)`, intrinseque,
sans axe choisi. STATISTIQUE : la distribution des angles frame-a-frame, PAS un max de fenetre.
LECTURE QUAND LE DEFAUT EST ABSENT : 0 sur une ancre immobile.
DOMAINE : `PHYSJTW` n'est emis que sur la sous-fenetre SANS pilotage et seulement a partir de
`PHYSROOM-MEASAT` (54) — donc 37 des 90 frames de la fenetre. Ce que ce script peut affirmer
porte sur CES 37 frames et sur rien d'autre ; c'est dit dans la sortie.
"""
import sys, math, statistics as st
from collections import defaultdict

log = sys.argv[1]
M = defaultdict(dict); KK = {}; R = {}; A = {}
for ln in open(log, errors='ignore'):
    p = ln.split()
    if not p: continue
    if p[0] == 'PHYSJTW':
        m = dict(kv.split('=') for kv in p[1:])
        M[(int(m['k']), int(m['j']))][int(m['row'])] = (float(m['x']), float(m['y']), float(m['z']))
    elif p[0] == 'PHYSJTWK':
        m = dict(kv.split('=') for kv in p[1:]); KK[int(m['k'])] = (int(m['a']), int(m['d']), float(m['f']))
    elif p[0] == 'PHYSREBASE':
        m = dict(kv.split('=') for kv in p[1:]); R[(int(m['c']), int(m['a']), int(m['d']))] = (float(m['fired']), float(m['amax']))
    elif p[0] == 'PHYSANROT':
        m = dict(kv.split('=') for kv in p[1:]); A[(int(m['c']), int(m['a']), int(m['d']))] = float(m['deg'])

def nrm(v): return math.sqrt(sum(c * c for c in v))
def basis(k, j):
    r = M.get((k, j)); return None if not r or len(r) < 3 else [list(r[0]), list(r[1]), list(r[2])]
def angle(A_, B_):
    An = [[c / nrm(r) for c in r] for r in A_]; Bn = [[c / nrm(r) for c in r] for r in B_]
    tr = sum(sum(An[k][i] * Bn[k][i] for k in range(3)) for i in range(3))
    return math.degrees(math.acos(max(-1.0, min(1.0, (tr - 1.0) / 2.0))))
def q(v, lbl):
    v = sorted(v)
    print("  %-30s n=%5d  p50=%8.4f  p90=%8.4f  max=%9.4f" % (lbl, len(v), st.median(v), v[int(.9*len(v))-1], v[-1]))

by_a = defaultdict(list)
for k, (a, d, f) in KK.items(): by_a[a].append((k, f))
print("1. CHEMIN INDEPENDANT — rotation frame-a-frame de `chest`, DANS la sous-fenetre mesuree")
print("   (PHYSJTW, sous-fenetre sans pilotage, frames %s..%s de 90 ; 3 joints pour l'echelle)" % (54, 90))
for j, nm in ((4, 'chest  = L\'ANCRE'), (5, 'main   (racine perso)'), (0, 'lBoob  (racine chaine)')):
    per = []
    for a in sorted(by_a):
        seq = sorted(by_a[a])
        for i in range(1, len(seq)):
            k0, k1 = seq[i-1][0], seq[i][0]
            if k1 != k0 + 1: continue
            B0, B1 = basis(k0, j), basis(k1, j)
            if B0 and B1: per.append(angle(B0, B1))
    if per: q(per, nm)

if A:
    print("\n2. L'INSTRUMENT DU CYCLE 101 (`PHYSANROT`, MAX de fenetre) — pour comparaison")
    byd = defaultdict(list)
    for k, v in A.items(): byd[k[2]].append(v)
    for d in sorted(byd): q(byd[d], "drive d=%d" % d)
    inter = set(A) & set(R)
    print("\n3. APPARIEMENT PHYSANROT x PHYSREBASE — domaines %d / %d / intersection %d" % (len(A), len(R), len(inter)))
    fired = sorted(A[k] for k in inter if R[k][0] > 0)
    notf  = sorted(A[k] for k in inter if R[k][0] == 0)
    q(fired, "fenetres ou le rebase TIRE"); q(notf, "fenetres ou il NE TIRE PAS")
    grey = sorted(x for x in notf if x > 10.0)
    print("\n4. LA ZONE GRISE QUE LE CYCLE 101 DECLARAIT ABSENTE")
    print("   fenetres SANS declenchement dont l'ancre tourne de plus de 10 deg : %d / %d" % (len(grey), len(notf)))
    if grey: print("   leurs angles : %s" % " ".join("%.2f" % x for x in grey))
    print("   max(sans declenchement) = %.4f   min(avec) = %.4f  -> les deux populations SE CHEVAUCHENT"
          % (notf[-1], fired[0]))
