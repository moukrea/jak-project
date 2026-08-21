#!/usr/bin/env python3
"""c78 — ABLATION DU MUR DE FORCE DE SPEC 21 : la course ablatee contre la ligne de base c77.

NATURE des deux grandeurs lues, une fois pour toutes :
  `s0`   (ROOM-REGSTG etage 0) : une LONGUEUR / B0 (SPEC 6, 602.0 u), repere MONDE, contre la
         pose d'AUTEUR de la MEME frame. MAXIMUM sur la fenetre. 0.0000 a la pose d'auteur.
  `perr` (ROOM-REGLIM)         : une LONGUEUR / B0, |p - tg| — l'ARGUMENT que le mur lit, releve
         AVANT les sous-pas de la frame. MAXIMUM sur la fenetre. Sans pilotage : 0.023-0.036.
Ce script ne juge que des RAPPORTS ablation/base, fenetre par fenetre, contre les predictions
pre-inscrites de `c78-predictions.txt` (md5 fbc84958a5919de56ac997e7dcf8101d)."""
import re, sys
OUT='.autoport/reports/Grecharged-secondary-motion/'
BASE=OUT+'keira-room-table.c77-baseline.txt'; ABL=OUT+'keira-room-table.c78-fwalloff.txt'
NAME={0:'base',1:'jumpA-push',2:'jumpA-fly',3:'jumpA-land',4:'jumpB-push',5:'jumpB-fly',
      6:'jumpB-land',7:'runA-accel',8:'runA-brake'}
PRED_S0={'chestL':{1:1.34,2:2.14,3:0.91,4:1.97,5:2.76,6:1.01,7:3.04,8:3.97},
         'chestR':{1:1.31,2:2.02,3:0.92,4:1.93,5:2.66,6:1.03,7:3.01,8:5.08}}
PRED_PE={'chestL':{1:1.22,2:1.81,3:0.94,4:1.65,5:2.67,6:0.99,7:2.74,8:2.92},
         'chestR':{1:1.20,2:1.83,3:0.94,4:1.63,5:2.56,6:1.01,7:2.51,8:3.18}}
def rd(p):
    t=open(p,encoding='utf-8',errors='replace').read()
    s0={}; pe={}
    for m in re.finditer(r'^ROOM-REGSTG:\s+(chest[LR])\s+r=\s*(\d+)\s+\S+\s+s0=([-\d.]+)',t,re.M):
        s0[(m.group(1),int(m.group(2)))]=float(m.group(3))
    for m in re.finditer(r'^ROOM-REGLIM:\s+PH-REG\s+(chest[LR])\s+(\d+)\s+\S+\s+[\d.]+\s+([\d.]+)\s+(\S+)',t,re.M):
        pe[(m.group(1),int(m.group(2)))]=(float(m.group(3)),m.group(4))
    stif=re.search(r'stif_n=([\d.]+)',t)
    idle=re.search(r'^ROOM-IDLE.*?([\d.]+)',t,re.M)
    return s0,pe,(float(stif.group(1)) if stif else None),t
b0,bp,bst,bt=rd(BASE); a0,ap,ast,at=rd(ABL)
print(f"P1  ARMEMENT   stif_n  base={bst}  ablation={ast}   -> "
      f"{'TENUE' if ast==0.0 else 'REFUTEE — RIEN D AUTRE N EST LISIBLE'}")
def blk(lab,base,abl,pred,idx):
    print(f"\n--- {lab} : rapport ablation/base, fenetre par fenetre (tolerance +/-35 % sur le rapport)")
    print("  r  regime        | chestL  base   abl    rap  pred  v | chestR  base   abl    rap  pred  v")
    ok=0; tot=0
    for r in range(0,9):
        row=f" {r:2d}  {NAME[r]:12s} |"
        for c in ('chestL','chestR'):
            kb=base.get((c,r)); ka=abl.get((c,r))
            vb=kb[idx] if isinstance(kb,tuple) else kb
            va=ka[idx] if isinstance(ka,tuple) else ka
            if vb is None or va is None or vb==0: row+="        --                    |"; continue
            q=va/vb; p=pred[c].get(r)
            if p is None: row+=f"        {vb:.4f} {va:.4f} {q:5.2f}   --    |"
            else:
                good=abs(q/p-1.0)<=0.35; ok+=good; tot+=1
                row+=f"        {vb:.4f} {va:.4f} {q:5.2f} {p:5.2f}  {'o' if good else 'X'} |"
        print(row)
    print(f"    -> {ok}/{tot} rapports dans la tolerance")
    return ok,tot
o1,t1=blk("P2  ETAGE 0 (`s0`)",b0,a0,PRED_S0,None)
o2,t2=blk("P3  `perr`",bp,ap,PRED_PE,0)
print("\n--- LE CONTRASTE, QUI EST LE VRAI TEST (P2) ---")
for c in ('chestL','chestR'):
    lo=[a0[(c,r)]/b0[(c,r)] for r in (3,6) if (c,r) in b0 and b0[(c,r)]]
    hi=[a0[(c,r)]/b0[(c,r)] for r in (7,8) if (c,r) in b0 and b0[(c,r)]]
    v=(max(lo)<=1.30 and min(hi)>=2.00) if lo and hi else False
    print(f"  {c} : receptions r=3,r=6 -> {['%.2f'%x for x in lo]} (exige <=1.30) ; "
          f"course r=7,r=8 -> {['%.2f'%x for x in hi]} (exige >=2.00)  -> {'TENU' if v else 'REFUTE'}")
print("\n--- P4  TEMOIN NEGATIF (r=0, aucun pilotage) ---")
for c in ('chestL','chestR'):
    if (c,0) in b0 and b0[(c,0)]:
        q=a0[(c,0)]/b0[(c,0)]
        print(f"  {c} s0 {b0[(c,0)]:.4f} -> {a0[(c,0)]:.4f}  x{q:.3f}  "
              f"-> {'TENU (<=10 %)' if abs(q-1)<=0.10 else 'REFUTE : l ablation n est PAS specifique'}")
print("\n--- P3bis  fenetres classees GELE (PH-REG, les deux chaines) ---")
for lab,d in (('base',bp),('ablation',ap)):
    print(f"  {lab:9s} : "+"  ".join(f"{s}={sum(1 for k in d if d[k][1]==s)}"
          for s in ('LINEAIRE','GENOU','GELE')))
print("\n--- P5  gardes de course ---")
for pat in (r'^ROOM-IDLE.*', r'^ROOM-ANIMS.*', r'^ROOM-ACTORS.*'):
    for lab,t in (('base',bt),('abl ',at)):
        m=re.search(pat,t,re.M)
        if m: print(f"  {lab} {m.group(0)[:96]}")

# ---------------------------------------------------------------------------------------------
# CE QUE L'ABLATION COUTE AILLEURS. Desarmer le mur amont ne dit rien tant qu'on n'a pas regarde
# si la borne de §22 tient TOUJOURS en aval (`phys-cap-e22!`, cycle 76) et si rien n'a saute.
print("\n--- P6bis  §22 TIENT-ELLE ENCORE, ET QU'EST-CE QUI A BOUGE AILLEURS ? ---")
def s6(t):
    d={}
    for m in re.finditer(r'^ROOM-REGSTG:\s+(chest[LR])\s+r=\s*(\d+)\s+\S+.*?s6=([-\d.]+)',t,re.M):
        d[(m.group(1),int(m.group(2)))]=float(m.group(3))
    return d
b6,a6=s6(bt),s6(at)
print("  etage 6 = LA VALEUR LIVREE (apres peau et apres `phys-cap-e22!`) ; plafond dur §22 = 0.50 B0")
print("  r  regime        | chestL  base   abl   | chestR  base   abl")
for r in range(0,9):
    row=f" {r:2d}  {NAME[r]:12s} |"
    for c in ('chestL','chestR'):
        vb,va=b6.get((c,r)),a6.get((c,r))
        row+= f"        {vb:.4f} {va:.4f}"+("  !!>0.50" if va and va>0.5001 else "        ")+" |" if vb is not None else "     --   |"
    print(row)
for lab,pat in (('ROOM-IDLE',r'^ROOM-IDLE:.*'),
                ('worst chestL',r'^worst chain=chestL.*'),('worst chestR',r'^worst chain=chestR.*'),
                ('drive=jerk',r'^drive=jerk.*'),('drive=accel',r'^drive=accel.*'),
                ('ROOM-APEX',r'^ROOM-APEX.*'),('ROOM-COM',r'^ROOM-COM[^P].*')):
    for who,t in (('base',bt),('abl ',at)):
        m=re.search(pat,t,re.M)
        if m: print(f"  {lab:14s} {who} : {m.group(0).strip()[:140]}")
