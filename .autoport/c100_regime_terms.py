#!/usr/bin/env python3
"""DIRECTIVES v3fee554599 — cycle 100.
QUEL TERME PORTE L'EXCES DES CELLULES ANGULAIRES ? (§18, §19, §20)
Lit PHYSREG4/4T/4D/4R (fenetres de REGIME, PH-REG). NATURE: longueurs / B0 (602 u).
REPERE: monde, contre la pose d'auteur de la MEME frame. ARGMAX: le meme pour les 4 records.
ABSENT: 0.0000 partout a la pose d'auteur. `rp` est DERIVE: rp = a - tp - dp."""
import sys, re, math
L = sys.argv[1] if len(sys.argv) > 1 else '.autoport/reports/Grecharged-secondary-motion/keira-room-x86.log'
A,T,D,Rr,V = {},{},{},{},set()
for line in open(L, errors='replace'):
    if   line.startswith('PHYSREG4 '):  m=dict(re.findall(r'(\w+)=(-?[\d.]+)',line)); A[(m['c'],int(m['r']))]=(float(m['apex']),(float(m['ax']),float(m['ay']),float(m['az'])))
    elif line.startswith('PHYSREG4T '): m=dict(re.findall(r'(\w+)=(-?[\d.]+)',line)); T[(m['c'],int(m['r']))]=(float(m['tx']),float(m['ty']),float(m['tz']))
    elif line.startswith('PHYSREG4D '): m=dict(re.findall(r'(\w+)=(-?[\d.]+)',line)); D[(m['c'],int(m['r']))]=(float(m['dx']),float(m['dy']),float(m['dz']))
    elif line.startswith('PHYSREG4R '): m=dict(re.findall(r'(\w+)=(-?[\d.]+)',line)); Rr[(m['c'],int(m['r']))]=float(m['rad'])
    elif line.startswith('PHYSREG4V '): m=dict(re.findall(r'(\w+)=(-?[\d.]+)',line)); V.add((m['c'],int(m['r'])))
# canal : alp==0 -> LINEAIRE, alp!=0 -> ANGULAIRE (ROOM-REGIME-STIM / phys-room)
LIN={1,2,3,4,5,6,7,8}; ANG={9,10,11,12,13,14}
BAND={1:('§14',.20,.30),3:('§16',.30,.42),4:('§14',.30,.38),6:('§16',.42,.50),8:('§17',.25,.35),
      10:('§18',.20,.30),11:('§19',.30,.40),12:('§19',.30,.40),13:('§20',.20,.30),14:('§20',.20,.30)}
NAME={0:'base',1:'jumpA-push',2:'jumpA-fly',3:'jumpA-land',4:'jumpB-push',5:'jumpB-fly',6:'jumpB-land',
      7:'runA-accel',8:'runA-brake',9:'yawA',10:'yawB',11:'pitchA-bend',12:'pitchA-return',13:'rollA',14:'rollB'}
def nrm(v): return math.sqrt(sum(x*x for x in v))
def proj(v,u):  # part SIGNEE de v sur la direction unitaire u : les trois parts somment a 100 %
    n=nrm(u); return sum(v[i]*u[i] for i in range(3))/n if n>1e-9 else 0.0
print("DIRECTIVES v3fee554599 — cycle 100 : LES TROIS TERMES SUR LES FENETRES DE REGIME")
print("part SIGNEE = projection sur e^ (les trois somment a 100 %), PAS un rapport de normes.\n")
print(f"{'ch':6} {'r':>2} {'regime':14} {'canal':4} {'sec':4} {'bande':11} {'apex':>7} {'verdict':16} {'tp%':>7} {'rp%':>7} {'dp%':>7}")
rows=[]
for c,nm in (('0','chestL'),('1','chestR')):
    for r in sorted(BAND):
        if (c,r) in V: print(f"{nm:6} {r:2} {NAME[r]:14} VACUITE — apex=0, termes perimes, cellule ECARTEE"); continue
        ap,a = A[(c,r)]; t=T[(c,r)]; d=D[(c,r)]
        rp=tuple(a[i]-t[i]-d[i] for i in range(3))
        pt,pr,pd = 100*proj(t,a)/ap, 100*proj(rp,a)/ap, 100*proj(d,a)/ap
        sec,lo,hi = BAND[r]
        vd = "DANS" if lo<=ap<=hi else (f"AU-DESSUS x{ap/hi:.2f}" if ap>hi else f"SOUS x{ap/lo:.2f}")
        ch = 'LIN' if r in LIN else 'ANG'
        print(f"{nm:6} {r:2} {NAME[r]:14} {ch:4} {sec:4} [{lo:.2f}-{hi:.2f}] {ap:7.4f} {vd:16} {pt:+7.1f} {pr:+7.1f} {pd:+7.1f}")
        rows.append((nm,r,ch,sec,lo,hi,ap,vd,pt,pr,pd))
print("\n--- MOYENNE DES PARTS, PAR CANAL ET PAR VERDICT (n = nombre de cellules) ---")
for ch in ('LIN','ANG'):
    for tag,f in (("toutes",lambda v:True),("AU-DESSUS",lambda v:v.startswith("AU-DESSUS")),
                  ("DANS",lambda v:v=="DANS"),("SOUS",lambda v:v.startswith("SOUS"))):
        s=[x for x in rows if x[2]==ch and f(x[7])]
        if not s: continue
        print(f"  {ch} {tag:10} n={len(s):2}  apex moy={sum(x[6] for x in s)/len(s):.4f}  "
              f"tp={sum(x[8] for x in s)/len(s):+6.1f} %  rp={sum(x[9] for x in s)/len(s):+6.1f} %  dp={sum(x[10] for x in s)/len(s):+6.1f} %")
print("\n--- CE QU'IL FAUDRAIT RETIRER POUR RENTRER DANS LA BANDE (cellules AU-DESSUS) ---")
for x in rows:
    if x[7].startswith("AU-DESSUS"):
        exc=x[6]-x[5]
        print(f"  {x[0]:6} r={x[1]:2} {x[3]} exces={exc:.4f} B0 ; a lui seul, tp={x[8]/100*x[6]:.4f}  rp={x[9]/100*x[6]:.4f}  dp={x[10]/100*x[6]:.4f} B0"
              f"   -> {'rp SEUL SUFFIT' if x[9]/100*x[6]>=exc else ('dp SEUL SUFFIT' if x[10]/100*x[6]>=exc else 'AUCUN terme seul ne suffit')}")
