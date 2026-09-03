#!/usr/bin/env python3
"""c102 — L'EFFET DU REBASE RIGIDE, PAR FENETRE, SUR LES GRANDEURS QUE LES SECTIONS LISENT.

Paire appariee : meme source hormis le bloc du rebase, meme salle, meme ordre de fenetres
(verifie). NATURE : des rapports apres/avant, par fenetre. REPERE : celui de chaque emetteur,
inchange. LECTURE QUAND LE DEFAUT EST ABSENT : 1.000 partout.
Le solveur est CONTINU d'une fenetre a l'autre : une seule intervention deplace la trajectoire de
tout ce qui suit. Ce script ne cherche donc PAS une fenetre isolee, il cherche un SIGNE SYSTEMATIQUE.
"""
import sys, re, statistics as st
from collections import defaultdict

FIELDS = [('PHYSAPEX','apex'), ('PHYSCOMW','comex'), ('PHYSSTR','str'),
          ('PHYSRAD','rad'), ('PHYSREBASE','fired'), ('PHYSREBASE','amax'), ('PHYSACC','acc')]

def load(p, tag, field):
    out = {}
    for ln in open(p, errors='ignore'):
        if not ln.startswith(tag + ' '): continue
        kv = dict(x.split('=') for x in ln.split()[1:] if '=' in x)
        if field not in kv: continue
        try: k = (int(kv['c']), int(kv['a']), int(kv['d']))
        except KeyError: continue
        try: out[k] = float(kv[field])
        except ValueError: pass
    return out

a, b = sys.argv[1], sys.argv[2]
print("%-18s %6s   %-28s %-28s  %s" % ("grandeur", "n", "AVANT p50 / moyenne", "APRES p50 / moyenne", "signe"))
for tag, f in FIELDS:
    A, B = load(a, tag, f), load(b, tag, f)
    ks = sorted(set(A) & set(B))
    if not ks: continue
    va = [A[k] for k in ks]; vb = [B[k] for k in ks]
    up = sum(1 for k in ks if B[k] > A[k]); dn = sum(1 for k in ks if B[k] < A[k])
    print("%-18s %6d   %12.4f %12.4f   %12.4f %12.4f   %d hausse / %d baisse / %d egal"
          % (tag + '.' + f, len(ks), st.median(va), st.mean(va), st.median(vb), st.mean(vb),
             up, dn, len(ks) - up - dn))
