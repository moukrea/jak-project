#!/usr/bin/env python3
# c145_verdict.py — les NEUF predictions du cycle 145, relevees sur la course NEUVE contre la
# course du cycle 144. Ce script ne juge que ce que `.autoport/c145-predictions.txt` a ecrit
# AVANT la course : il ne choisit ni une bande ni un seuil.
import re, sys, os, hashlib

D = '.autoport/reports/Grecharged-secondary-motion'
NEW_LOG, NEW_TAB = f'{D}/keira-room-x86.log', f'{D}/keira-room-table.txt'
OLD_LOG = f'{D}/keira-room-x86.20260828-053004.log'
OLD_TAB = f'{D}/keira-room-table.20260828-053641.txt'

def md5(p):
    h = hashlib.md5()
    with open(p,'rb') as f:
        for b in iter(lambda: f.read(1<<20), b''): h.update(b)
    return h.hexdigest()

def rd(p): return open(p, encoding='utf-8', errors='replace').read().splitlines()

for p in (NEW_LOG, NEW_TAB, OLD_LOG, OLD_TAB):
    if not os.path.exists(p): sys.exit(f'ABSENT: {p}')
if md5(OLD_LOG) != 'a91ea459b6710dd8f7eecf2559442871':
    sys.exit('la trace de reference du c144 n\'est plus celle que les predictions citent')
new, old = rd(NEW_LOG), rd(OLD_LOG)
ntab, otab = rd(NEW_TAB), rd(OLD_TAB)
print(f'trace NEUVE  md5 {md5(NEW_LOG)}  ({os.path.getsize(NEW_LOG)} octets)')
print(f'trace c144   md5 {md5(OLD_LOG)}  ({os.path.getsize(OLD_LOG)} octets)')
print(f'PHYSEND neuf : {sum(1 for l in new if "PHYSEND" in l)}   (0 = course non aboutie, tout ce qui suit est nul)')
print()

# ---- P0 : le canal est PROUVE LU -------------------------------------------------------------
print('== P0  gmx PUBLIE PAR LE PARSEUR ==')
gmx = {}
for l in new:
    m = re.search(r'PHYSGRADSET c=(\d+) p=([\d.]+) w0=([\d.]+) w1=([\d.]+) cws=([\d.]+)(?: gmx=([\d.]+))?', l)
    if m:
        gmx[int(m.group(1))] = float(m.group(6)) if m.group(6) else None
        print('  ' + l.split('] ',1)[-1])
ok0 = all(v is not None and v > 1.0001 for v in gmx.values()) and len(gmx) == 2
print(f'  -> P0 {"TENUE" if ok0 else "REFUTEE"}  (attendu gmx=1.1035 / 1.1128 ; 1.0000 = falsificateur)\n')

# ---- P1/P2 : PHYSORI5 --------------------------------------------------------------------------
def ori5(lines):
    d = {}
    for l in lines:
        m = re.search(r'PHYSORI5 c=(\d+) i=(\d+) sxm=([\d.-]+) sym=([\d.-]+) szm=([\d.-]+)', l)
        if m: d[(int(m.group(1)), int(m.group(2)))] = tuple(float(m.group(i)) for i in (3,4,5))
    return d
N5, O5 = ori5(new), ori5(old)
ASC = {0: 0.25/1.1035, 1: 0.25/1.1128}
print('== P1  LE PLAFOND MORD, ET A LA VALEUR DE L\'ELONGATION *RECUE* ==')
ok1 = True
for c in (0,1):
    om = max(v[0] for k,v in O5.items() if k[0]==c) if O5 else 0
    nm = max(v[0] for k,v in N5.items() if k[0]==c) if N5 else 0
    cap = 1.0 + ASC[c]
    good = nm <= cap + 0.0005
    ok1 &= good
    etat = ('plafond ABSENT' if nm > 1.30 else
            'plafond sur la cle BRUTE (gmx inoperant)' if nm > cap + 0.0005 else
            'plafond sur l\'elongation RECUE')
    print(f'  c={c}  sxm max  {om:.4f} -> {nm:.4f}   plafond effectif {cap:.4f}   [{etat}]')
print(f'  -> P1 {"TENUE" if ok1 else "REFUTEE"}\n')

print('== P2  LES DEUX AUTRES AXES : IDENTITE AU BIT SAUF i=10 ==')
bad = []
for k in sorted(set(N5) & set(O5)):
    for ax, nm in ((1,'sym'), (2,'szm')):
        d = N5[k][ax] - O5[k][ax]
        expected_move = (ax == 2 and k[1] == 10)
        if abs(d) > 0.0002 and not expected_move: bad.append((k, nm, O5[k][ax], N5[k][ax], d))
        if expected_move: print(f'  c={k[0]} i={k[1]}  szm {O5[k][ax]:.5f} -> {N5[k][ax]:.5f}  ({d:+.5f})  [PREDIT]')
for b in bad: print(f'  HORS PREDICTION  c={b[0][0]} i={b[0][1]} {b[1]} {b[2]:.5f} -> {b[3]:.5f} ({b[4]:+.5f})')
print(f'  cellules hors prediction : {len(bad)}  ->  P2 {"TENUE" if not bad else "REFUTEE"}\n')

# ---- P3/P4 : les huit cellules de largeur ------------------------------------------------------
def livree(lines):
    d = {}
    for l in lines:
        m = re.match(r'ROOM-SPEC1011-LIVREE: (chest[LR])\s+(\S+)\s+§(10|11)\s+out\s+\|\s+([\d.]+)\s+([\d.]+)\s+([\d.]+)\s+\|\s+([\d.]+)', l)
        if m:
            d[(m.group(1), m.group(2), m.group(3))] = (float(m.group(4)), float(m.group(7)),
                                                       'DANS' if ' DANS ' in l else
                                                       'SOUS' if ' SOUS ' in l else
                                                       'AU-DESSUS' if 'AU-DESSUS' in l else 'SANS VERDICT')
    return d
NL, OL = livree(ntab), livree(otab)
for sec, pred in (('10', 'SOUS, 1.10-1.15'), ('11', 'inchangee a 0.002 pres')):
    print(f'== P{"3" if sec=="10" else "4"}  §{sec} LARGEUR  ({pred}) ==')
    for k in sorted(set(NL) & set(OL)):
        if k[2] != sec: continue
        o, n = OL[k], NL[k]
        print(f'  {k[0]:7s} {k[1]:8s}  livree {o[0]:.4f} -> {n[0]:.4f} ({n[0]-o[0]:+.4f})   '
              f'commande {o[1]:.4f} -> {n[1]:.4f}   verdict {o[2]} -> {n[2]}')
    print()

# ---- P5..P8 : les lignes de verdict deja existantes --------------------------------------------
def show(title, pat, tabs=(otab, ntab), cut=200):
    print(f'== {title} ==')
    for nom, t in (('c144', tabs[0]), ('c145', tabs[1])):
        for l in t:
            if re.search(pat, l): print(f'  [{nom}] ' + l[:cut])
    print()
show('P5  §10 MIGRATION SORTANTE, ORGANE LIVRE', r'^ROOM-SPEC10: chest[LR]\s+sortant\s+ORGANE LIVRE')
show('P6  COLLISION', r'^ROOM-SKINPEN-DETAIL:')
show('P7  REPOS',     r'^ROOM-IDLE:')
show('P8  §24',       r'^ROOM-SPEC24-VERDICT:')
