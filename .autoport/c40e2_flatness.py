#!/usr/bin/env python3
"""c40e2_flatness.py — LE « 14 % » DU CYCLE 39, REFAIT SUR SA PROPRE TRANCHE, PUIS PAR MAILLON.

NATURE  : un ECART RELATIF entre stimuli (discrimination), sans unite.
REPERE  : identique a celui du cycle 39 — la valeur AGREGEE PAR CHAINE (`PHYSRAD`, un max sur les
          maillons) puis, en regard, la MEME grandeur par MAILLON (`PHYSRADL`).
ABSENT  : un canal qui ne repond pas au stimulus lit 0 %.
Le contrat rejette une mesure sous 25 % d'ecart entre le plus fort et le plus faible stimulus.
"""
import collections, re, statistics, sys
LOG = sys.argv[1] if len(sys.argv) > 1 else \
    '.autoport/reports/Grecharged-secondary-motion/keira-room-x86.C38E4-FINAL.log'
DRIVES = ('updown','leftright','accel','jerk','tilt','AUCUN')
CHAIN = ('chestL','chestR')
re_rad  = re.compile(r'^PHYSRAD c=(\d+) a=(\d+) d=(\d+) rr=([-\d.]+) rrm=([-\d.]+) rrr=([-\d.]+)')
re_radl = re.compile(r'^PHYSRADL c=(\d+) d=(\d+) l=(\d+) rrm=([-\d.]+) rrr=([-\d.]+) sat=([-\d.]+)')
rad, radl = [], []
for ln in open(LOG, errors='replace'):
    if not ln.startswith('PHYSRAD'): continue
    m = re_rad.match(ln)
    if m: rad.append((int(m.group(1)),int(m.group(2)),int(m.group(3)),float(m.group(4)),float(m.group(5)),float(m.group(6)))); continue
    m = re_radl.match(ln)
    if m: radl.append((int(m.group(1)),int(m.group(2)),int(m.group(3)),float(m.group(4)),float(m.group(5)),float(m.group(6))))
KNEE = 0.84*0.40   # genou du softmin, en B0
print('LE CHIFFRE DU CYCLE 39 REFAIT, PUIS LA MEME GRANDEUR PAR MAILLON')
print('NATURE ecart relatif entre stimuli · REPERE agrege par CHAINE puis par MAILLON · ABSENT 0 %')
print('seuil de non-discrimination du contrat : 25 %')
print()
print("A. LA TRANCHE DU CYCLE 39 : AGREGE PAR CHAINE, FENETRES AU-DESSUS DU GENOU (rrr > %.4f)" % KNEE)
print('   chaine    n     entree rrr  min -> max      sortie rrm  min -> max     ecart entree  ecart sortie')
for c in (0,1):
    sel=[r for r in rad if r[0]==c and r[5]>KNEE]
    if not sel: continue
    ri=[r[5] for r in sel]; ro=[r[4] for r in sel]
    ei=(max(ri)-min(ri))/max(ri); eo=(max(ro)-min(ro))/max(ro)
    print('   %-7s %4d   %.4f -> %.4f            %.4f -> %.4f          %6.1f %%      %6.1f %%'
          % (CHAIN[c],len(sel),min(ri),max(ri),min(ro),max(ro),100*ei,100*eo))
print()
print('B. LA MEME TRANCHE, MAIS PAR MAILLON (fenetres du maillon au-dessus du genou)')
print('   chaine  maillon    n     ecart entree rrr   ecart sortie rrm')
for c in (0,1):
    for l in (0,1):
        sel=[r for r in radl if r[0]==c and r[2]==l and r[4]>KNEE]
        if not sel:
            print('   %-7s l=%d      %3d     (aucune fenetre au-dessus du genou)'%(CHAIN[c],l,0)); continue
        ri=[r[4] for r in sel]; ro=[r[3] for r in sel]
        ei=(max(ri)-min(ri))/max(ri); eo=(max(ro)-min(ro))/max(ro)
        print('   %-7s l=%d      %3d           %6.1f %%           %6.1f %%'%(CHAIN[c],l,len(sel),100*ei,100*eo))
print()
print('C. TOUTES FENETRES, PAR PILOTAGE (moyenne des 31 fenetres), AGREGE PAR CHAINE')
print('   chaine  grandeur     '+''.join('%10s'%d for d in DRIVES)+'    ecart')
for c in (0,1):
    for lbl,idx in (('rrr DEMANDE',5),('rrm LIVRE  ',4)):
        mm=[]
        for d in range(6):
            vv=[r[idx] for r in rad if r[0]==c and r[2]==d]
            mm.append(statistics.mean(vv) if vv else float('nan'))
        sp=(max(mm)-min(mm))/max(mm)
        print('   %-7s %s'%(CHAIN[c],lbl)+''.join('%10.4f'%v for v in mm)+'   %6.1f %%'%(100*sp))
print()
print("D. LA PART DU PLAFOND DE SA SPEC 22 PRISE PAR CE CANAL, ET CE QU'IL LIVRE EN DEFORMATION")
BL={(0,0):1040.5006,(0,1):140.4225,(1,0):1039.0379,(1,1):144.2315}; B0=602.0
print('   chaine  maillon   rrm moyen (B0)   = u        / bl        = deformation LIVREE')
for c in (0,1):
    for l in (0,1):
        vv=[r[3] for r in radl if r[0]==c and r[2]==l]
        m=statistics.mean(vv); u=m*B0
        print('   %-7s l=%d      %8.4f    %8.1f u   /%8.1f    **%7.1f %%**'
              %(CHAIN[c],l,m,u,BL[(c,l)],100*u/BL[(c,l)]))
print('   rappel : AbsoluteStretchClamp de sa SPEC 22 = 25.0 %')
