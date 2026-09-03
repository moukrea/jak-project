#!/usr/bin/env python3
"""c76_arbitrage.py — JUGER LE CYCLE 76 CONTRE SES PREDICTIONS PRE-INSCRITES, SANS EN CHOISIR UNE.

Lit trois courses : celle du cycle 75 (reference), la jambe DESARMEE (controle de bit-identite) et
la jambe ARMEE (l'etat livre). Il ne decide rien : il imprime, pour chaque question pre-inscrite
dans c76-predictions.txt (md5 3236f6ceae86fdcd49727ba8b60fcb3f), ce que la mesure rend et si la
prediction TIENT ou ECHOUE. Une prediction ratee s'imprime comme ratee.
"""
import re, sys, statistics as S
from collections import defaultdict

D   = ".autoport/reports/Grecharged-secondary-motion/"
REF = D + "keira-room-x86.c75.log"
DIS = D + "keira-room-x86.c76-disarmed.log"
ARM = D + "keira-room-x86.c76-armed.log"
B0_U, U_M = 602.0, 4096.0                     # 1 B0 = 602.0 u ; 4096 u = 1 m

def physlines(p):
    try:  return [l for l in open(p, errors='ignore') if l.startswith('PHYS')]
    except FileNotFoundError: return None

def stages(p):
    """PHYSSTG -> {(c,a,d): {st: jt}} ; le septuplet LATCHE d'une meme frame."""
    rx = re.compile(r'^PHYSSTG c=(\d+) a=(\d+) d=(\d+) st=(\d+) jt=([-\d.]+)')
    W = defaultdict(dict)
    for l in open(p, errors='ignore'):
        m = rx.match(l)
        if m:
            W[(int(m[1]), int(m[2]), int(m[3]))][int(m[4])] = float(m[5])
    return {k: v for k, v in W.items() if len(v) == 7}

def tagline(p, key):
    out = {}
    for l in open(p, errors='ignore'):
        if l.startswith(key + ' '):
            f = dict(kv.split('=', 1) for kv in l.split()[1:] if '=' in kv)
            out[f.get('tag', '?')] = f
    return out

def table(p):
    return open(p, errors='ignore').read()

def verdict(ok):  return "TIENT " if ok else "ECHOUE"

# ------------------------------------------------------------------------------------------------
print("CYCLE 76 — ARBITRAGE CONTRE LES PREDICTIONS PRE-INSCRITES (md5 3236f6ceae86fdcd49727ba8b60fcb3f)")
print("=" * 98)

# ---- Q1 : le controle de bit-identite ----------------------------------------------------------
r, d = physlines(REF), physlines(DIS)
print("\nQ1  CONTROLE — la jambe DESARMEE doit etre IDENTIQUE AU BIT a la course du cycle 75")
if d is None:
    print("    course desarmee absente :", DIS)
else:
    diff = sum(1 for a, b in zip(r, d) if a != b) + abs(len(r) - len(d))
    print(f"    lignes PHYS  ref={len(r)}  desarmee={len(d)}  DIFFERENTES={diff}")
    print(f"    -> {verdict(diff == 0)}   (si != 0, rien d'autre de ce cycle n'est attribuable)")

# ---- Q2 : la borne tient sur la valeur livree ---------------------------------------------------
print("\nQ2  LA BORNE TIENT SUR LA VALEUR LIVREE — `PHYSSTG` etage 6, plafond dur 0.50 B0")
WR, WA = stages(REF), stages(ARM)
q2 = True
for c, nom in ((0, 'chestL'), (1, 'chestR')):
    a6 = [v[6] for k, v in WA.items() if k[0] == c]
    r6 = [v[6] for k, v in WR.items() if k[0] == c]
    r5 = [v[5] for k, v in WR.items() if k[0] == c]
    a5 = [v[5] for k, v in WA.items() if k[0] == c]
    if not a6: print(f"    {nom}: course armee absente"); q2 = False; continue
    over_r, over_a = sum(1 for x in r6 if x > 0.50), sum(1 for x in a6 if x > 0.50)
    ok = max(a6) <= 0.5010
    q2 &= ok
    print(f"    {nom}  etage5 med {S.median(r5):.4f} -> {S.median(a5):.4f}"
          f"   etage6 med {S.median(r6):.4f} -> {S.median(a6):.4f}"
          f"   max {max(r6):.4f} -> {max(a6):.4f}")
    print(f"            fenetres > 0.50 : {over_r}/{len(r6)} -> {over_a}/{len(a6)}    max<=0.5010 : {verdict(ok)}")
print(f"    -> Q2 {verdict(q2)}")

# ---- Q3 : le compteur tire ---------------------------------------------------------------------
print("\nQ3  LE COMPTEUR TIRE armee, et rend EXACTEMENT 0 desarmee (`PHYSE22`)")
ea, ed = tagline(ARM, 'PHYSE22'), (tagline(DIS, 'PHYSE22') if d is not None else {})
for t in ('run', 'rest', 'skin-armed'):
    fa, fd = ea.get(t, {}), ed.get(t, {})
    print(f"    tag={t:<12} armee n={fa.get('n','-'):>14} cut_b0={fa.get('cut_b0','-'):>14}"
          f"   |  desarmee n={fd.get('n','-'):>10} cut_b0={fd.get('cut_b0','-'):>10}")
fire = float(ea.get('run', {}).get('n', 0) or 0) > 0
zero = all(float(v.get('n', 0) or 0) == 0 for v in ed.values()) if ed else False
print(f"    -> arme tire : {verdict(fire)}   desarme muet : {verdict(zero)}")

# ---- Q4 : le prix paye a SPEC 33/34 -------------------------------------------------------------
print("\nQ4  LE PRIX PAYE A SPEC 33/34 — `ROOM-SKINPEN-DETAIL`, predit A LA HAUSSE des deux cotes")
TA, TR = D + "keira-room-table.txt", D + "keira-room-table.c75.txt"
rxp = re.compile(r'ROOM-SKINPEN-DETAIL: chain=(\S+)\s+skinpen=([\d.]+)')
def pen(p):
    try: return dict((m[1], float(m[2])) for m in rxp.finditer(table(p)))
    except FileNotFoundError: return {}
pr, pa = pen(TR), pen(TA)
band = {'chestL': (0.0721, 0.0951), 'chestR': (0.0918, 0.1168)}
for ch in ('chestL', 'chestR'):
    if ch in pr and ch in pa:
        lo, hi = band[ch]
        print(f"    {ch}  skinpen {pr[ch]:.4f} -> {pa[ch]:.4f} m   ({pa[ch]-pr[ch]:+.4f})"
              f"   monte : {verdict(pa[ch] > pr[ch])}   dans [{lo};{hi}] : {verdict(lo <= pa[ch] <= hi)}")

# ---- Q5 : pas de muselage ----------------------------------------------------------------------
print("\nQ5  PAS DE MUSELAGE — `tipvar_max` par pilotage, plancher = 60 % de la mesure du cycle 75")
rxt = re.compile(r'drive=(\S+)\s+windows=\d+\s+tipvar_max=([\d.]+)')
def tv(p):
    try: return dict((m[1], float(m[2])) for m in rxt.finditer(table(p)))
    except FileNotFoundError: return {}
tr, ta = tv(TR), tv(TA)
q5 = True
for k in tr:
    if k in ta:
        fl = 0.6 * tr[k]; ok = ta[k] >= fl; q5 &= ok
        print(f"    {k:<11} {tr[k]:.4f} -> {ta[k]:.4f}  ({100*(ta[k]-tr[k])/tr[k]:+6.1f} %)"
              f"   plancher {fl:.4f} : {verdict(ok)}")
print(f"    -> Q5 {verdict(q5)}")

# ---- Q6 / Q7 -----------------------------------------------------------------------------------
print("\nQ6  INERTE AU REPOS — `ROOM-IDLE maxdev`")
for nom, p in (("c75", TR), ("c76", TA)):
    m = re.search(r'ROOM-IDLE: maxdev=([\d.]+)', table(p) if p else '')
    print(f"    {nom} : maxdev={m.group(1) if m else '-'}")

print("\nQ7  CE CYCLE NE FERME PAS §22 — `ROOM-APEX`, et je l'ai ecrit d'avance")
rxa = re.compile(r'ROOM-APEX: chain=(\S+)\s+pic_typique=([\d.]+)\s+max=([\d.]+)')
def apx(p):
    try: return dict((m[1], (float(m[2]), float(m[3]))) for m in rxa.finditer(table(p)))
    except FileNotFoundError: return {}
ar, aa = apx(TR), apx(TA)
for ch in ('chestL', 'chestR'):
    if ch in ar and ch in aa:
        print(f"    {ch}  pic {ar[ch][0]:.4f} -> {aa[ch][0]:.4f}   max {ar[ch][1]:.4f} -> {aa[ch][1]:.4f}"
              f"   reste > 0.50 : {verdict(aa[ch][1] > 0.50)}")
