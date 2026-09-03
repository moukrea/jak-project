#!/usr/bin/env python3
"""c102 — CONTROLE DIFFERENTIEL DU REBASE RIGIDE DE §37.

PREDICTION POSEE AVANT LA COURSE (le correctif vit ENTIEREMENT dans le `when` du rebase) :
  (a) toute fenetre ou `PHYSREBASE fired = 0` doit etre INCHANGEE AU CARACTERE ;
  (b) les fenetres ou `fired > 0` doivent changer — sinon la moitie rotation ne fait rien.
Une violation de (a) veut dire que le changement n'est pas celui qu'on croit et le cycle s'arrete.

NATURE : un COMPTE de lignes de trace differentes, par fenetre. REPERE : la trace elle-meme,
aucun repere geometrique n'entre. LECTURE QUAND LE DEFAUT EST ABSENT : 0 ligne differente.
"""
import sys, re
from collections import defaultdict

def load(path):
    """rend  {(c,a,d): [lignes]}  pour tout emetteur porteur des trois cles, + les non-cles."""
    win = defaultdict(list); other = []
    kre = re.compile(r'\bc=(\d+)\b.*?\ba=(\d+)\b.*?\bd=(\d+)\b')
    for ln in open(path, errors='ignore'):
        if not ln.startswith('PHYS') and not ln.startswith('ROOM'):
            continue
        m = kre.search(ln)
        if m:
            win[(int(m.group(1)), int(m.group(2)), int(m.group(3)))].append(ln.rstrip('\n'))
        else:
            other.append(ln.rstrip('\n'))
    return win, other

def fired_map(path):
    f = {}
    for ln in open(path, errors='ignore'):
        if ln.startswith('PHYSREBASE '):
            kv = dict(x.split('=') for x in ln.split()[1:])
            f[(int(kv['c']), int(kv['a']), int(kv['d']))] = float(kv['fired'])
    return f

a, b = sys.argv[1], sys.argv[2]
wa, oa = load(a); wb, ob = load(b)
fa = fired_map(a)
keys = sorted(set(wa) | set(wb))
same_f0 = diff_f0 = same_f1 = diff_f1 = 0
viol = []
for k in keys:
    changed = wa.get(k) != wb.get(k)
    if fa.get(k, 0.0) > 0.0:
        if changed: diff_f1 += 1
        else:       same_f1 += 1
    else:
        if changed:
            diff_f0 += 1
            if len(viol) < 8:
                la, lb = wa.get(k, []), wb.get(k, [])
                d = [(x, y) for x, y in zip(la, lb) if x != y]
                viol.append((k, len(d), d[0] if d else ('<len>', '')))
        else: same_f0 += 1
print("fenetres AVANT=%d APRES=%d  (cles communes %d)" % (len(wa), len(wb), len(set(wa) & set(wb))))
print()
print("  fired > 0 :  %3d changees   %3d identiques    <- (b) doit etre 'changees' majoritaire" % (diff_f1, same_f1))
print("  fired = 0 :  %3d changees   %3d identiques    <- (a) doit etre 0 changees" % (diff_f0, same_f0))
print()
print("lignes hors-cle : avant=%d apres=%d  identiques=%s" % (len(oa), len(ob), oa == ob))
for k, n, ex in viol:
    print("  VIOLATION (a) %s : %d lignes differentes" % (str(k), n))
    print("      avant: %s" % ex[0][:150]); print("      apres: %s" % ex[1][:150])
