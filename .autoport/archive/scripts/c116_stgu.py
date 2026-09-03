#!/usr/bin/env python3
"""c116 — LE SEPTUPLET AU POINT DE PARCAGE, A UNE RESOLUTION QUI PEUT LE VOIR.

Ne juge rien qu'il ne lise. Trois sorties :
  1. le controle negatif : PHYSRESTQ / PHYSSTGQ doivent etre BIT-IDENTIQUES a la course archivee ;
  2. la coherence : PHYSSTGU arrondi a 4 decimales doit redonner PHYSSTGQ ;
  3. la mesure : les six deltas par cellule, en B0 ET en unites de jeu (B0 = 602.0 u).
"""
import re, sys, collections

B0 = 602.0
K2 = {0: 0.058019, 1: 0.062661}          # w^2 dt^2, recalcule des parametres livres
GG = 0.00145                             # |gy| . gn . tf mesure au cycle 115, u/frame^2

def load(path):
    stgu = collections.defaultdict(dict)   # (c,ax,f) -> {st: jt}
    stgq = {}                              # (c,ax,st) -> jt(texte)
    restq = {}                             # (c,ax) -> (rgap,perr) textes
    for ln in open(path, errors='replace'):
        m = re.match(r'PHYSSTGU c=(\d+) ax=(\d+) f=(\d+) st=(\d+) jt=([-\d.]+)', ln)
        if m:
            c,ax,f,st,v = int(m[1]),int(m[2]),int(m[3]),int(m[4]),float(m[5])
            stgu[(c,ax,f)][st] = v; continue
        m = re.match(r'PHYSSTGQ c=(\d+) ax=(\d+) st=(\d+) jt=([-\d.]+)', ln)
        if m:
            stgq[(int(m[1]),int(m[2]),int(m[3]))] = m[4]; continue
        m = re.match(r'PHYSRESTQ c=(\d+) ax=(\d+) rgap=([-\d.]+) perr=([-\d.]+)', ln)
        if m:
            restq[(int(m[1]),int(m[2]))] = (m[3], m[4])
    return stgu, stgq, restq

new = sys.argv[1]; old = sys.argv[2] if len(sys.argv) > 2 else None
su, sq, rq = load(new)

print("=" * 96)
print("A1  NON-VACUITE")
print(f"    PHYSSTGU : {sum(len(v) for v in su.values())} lignes, {len(su)} cellules (c,ax,frame)")
print(f"    attendu  : 210 lignes, 30 cellules (5 frames x 3 axes x 2 chaines)")
print(f"    PHYSSTGQ : {len(sq)} lignes (attendu 42)   PHYSRESTQ : {len(rq)} (attendu 6)")

if old:
    su_o, sq_o, rq_o = load(old)
    print("=" * 96)
    print("A2  CONTROLE NEGATIF — L'EMETTEUR EST-IL PUR ? (vs la course archivee)")
    dq = [k for k in sq if sq.get(k) != sq_o.get(k)]
    dr = [k for k in rq if rq.get(k) != rq_o.get(k)]
    print(f"    PHYSSTGQ  : {len(dq)} / {len(sq)} valeurs DIFFERENTES  {'-> PUR' if not dq else '-> LE SOLVEUR A BOUGE : '+str(dq[:6])}")
    print(f"    PHYSRESTQ : {len(dr)} / {len(rq)} valeurs DIFFERENTES  {'-> PUR' if not dr else '-> LE SOLVEUR A BOUGE : '+str(dr)}")

print("=" * 96)
print("A3  COHERENCE DES DEUX CHEMINS D'IMPRESSION (PHYSSTGU arrondi == PHYSSTGQ)")
bad = 0; tot = 0
for (c,ax,f), d in sorted(su.items()):
    for st, v in d.items():
        q = sq.get((c,ax,st))
        if q is None: continue
        tot += 1
        if f"{v:.4f}" != q: bad += 1
print(f"    {tot-bad} / {tot} concordent" + ("" if not bad else f"  — {bad} DIVERGENCES, l'impression ment"))

print("=" * 96)
print("A4  LES SIX DELTAS, PAR CELLULE — en B0 puis en unites de jeu (1 B0 = 602.0 u)")
print("    intervalles : 0->1 mur SPEC21/22 | 1->2 longueur | 2->3 collision | 3->4 7x(long+col)")
print("                  4->5 repli+3x+4x    | 5->6 2x(cap-e22 + peau)")
print()
hdr = f"    {'c':>2} {'ax':>2} {'f':>4} | " + " ".join(f"{f'{i}->{i+1}':>12}" for i in range(6)) + f" | {'st0':>10} {'st6':>10} {'|st6-st0|u':>11}"
print(hdr); print("    " + "-"*(len(hdr)-4))
worst = 0.0; worst_key = None; per_int = [0.0]*6
for (c,ax,f), d in sorted(su.items()):
    if len(d) < 7: continue
    dl = [d[i+1]-d[i] for i in range(6)]
    for i,x in enumerate(dl): per_int[i] = max(per_int[i], abs(x)*B0)
    net = abs(d[6]-d[0])*B0
    if net > worst: worst, worst_key = net, (c,ax,f)
    print(f"    {c:>2} {ax:>2} {f:>4} | " + " ".join(f"{x*B0:>12.6f}" for x in dl)
          + f" | {d[0]:>10.7f} {d[6]:>10.7f} {net:>11.6f}")
print()
print("    MAXIMUM ABSOLU PAR INTERVALLE, en unites de jeu :")
names = ["0->1 mur 21/22","1->2 longueur","2->3 collision","3->4 7x(l+c)","4->5 repli","5->6 e22+peau"]
for i,(nm,v) in enumerate(zip(names, per_int)):
    print(f"      {nm:<16} {v:>12.6f} u")
print()
print("    SEUILS ECRITS AVANT LA COURSE (.autoport/c116-predictions.txt) :")
print(f"      A4  au moins un delta >= 0.021000 u        -> {'ATTEINT' if max(per_int) >= 0.021 else 'NON ATTEINT'} (max {max(per_int):.6f} u)")
print(f"      A5  |st6-st0| dans [0.010 ; 0.100] u       -> max mesure {worst:.6f} u sur {worst_key}")
print(f"      A6  falsificateur : les six deltas a 0     -> {'LE FALSIFICATEUR TIRE' if max(per_int) == 0.0 else 'refute (au moins un delta non nul)'}")
