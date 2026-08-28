#!/usr/bin/env python3
"""c149_compare.py — CONTROLE DE PURETE L1 : la course de la jambe 1 doit etre IDENTIQUE AU
CHIFFRE a la course livree du cycle 148 sur toute grandeur SOLVEUR. Les seules lignes autorisees
a differer sont l'empreinte de la course et le bloc neuf `PHYSSATD` / `ROOM-SATD`.
Usage : c149_compare.py <table_avant> <table_apres>"""
import re, sys

a, b = sys.argv[1], sys.argv[2]
LA = open(a, encoding='utf-8', errors='replace').read().splitlines()
LB = open(b, encoding='utf-8', errors='replace').read().splitlines()

# lignes NEUVES autorisees a apparaitre
NEW = ('ROOM-SATD', 'PHYSSATD')
# lignes dont on sait qu'elles portent une empreinte de course
STAMP = ('md5', 'MD5', 'horodat', 'empreinte')

sa = [l for l in LA if not any(k in l for k in NEW)]
sb = [l for l in LB if not any(k in l for k in NEW)]

import difflib
diff = [l for l in difflib.unified_diff(sa, sb, lineterm='', n=0)
        if l[:1] in '+-' and l[:3] not in ('+++', '---')]
stampish = [l for l in diff if any(k in l for k in STAMP)]
real = [l for l in diff if l not in stampish]

print("lignes AVANT (hors bloc neuf) : %d" % len(sa))
print("lignes APRES (hors bloc neuf) : %d" % len(sb))
print("lignes du bloc NEUF dans APRES : %d" % (len(LB) - len(sb)))
print("--- differences hors bloc neuf : %d (dont %d d'empreinte) ---" % (len(diff), len(stampish)))
for l in real[:80]:
    print(l[:220])
print()
print("VERDICT L1 : %s" % ("PURE — l'instrument ne deplace pas ce qu'il compte"
                           if not real else
                           "IMPURE — %d ligne(s) solveur ont bouge, LE LOT EST RETIRE" % len(real)))
sys.exit(0 if not real else 1)
