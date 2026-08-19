#!/usr/bin/env python3
"""c40e6_verdict.py — LES SIX CRITERES DU CYCLE 40, LUS SUR DEUX COURSES.

NATURE  : une COMPARAISON AVANT/APRES, grandeur par grandeur ; chaque grandeur garde la nature
          qu'elle avait (deformation sans unite, excursion en B0, amplitude en metres, Hz).
REPERE  : la course LIVREE du cycle 38 (avant) contre la course de ce cycle (apres), memes
          fenetres, memes pilotages, meme salle.
ABSENT  : une intervention sans effet rend des colonnes identiques.
USAGE   : python3 .autoport/c40e6_verdict.py <log_avant> <log_apres>
"""
import re, statistics, sys
BEF, AFT = sys.argv[1], sys.argv[2]
DRIVES=('updown','leftright','accel','jerk','tilt','AUCUN'); CHAIN=('chestL','chestR')
BLK='PHYSBONE'
def load(p):
    d={'bl':{}, 'radl':[], 'radld':[], 'comd':[], 'rows':[], 'freq':[]}
    re_b=re.compile(r'^PHYSBONE c=(\d+) l=(\d+) len=([-\d.]+)')
    re_l=re.compile(r'^PHYSRADL c=(\d+) d=(\d+) l=(\d+) rrm=([-\d.]+) rrr=([-\d.]+) sat=([-\d.]+)')
    re_d=re.compile(r'^PHYSRADLD c=(\d+) d=(\d+) l=(\d+) mlb=([-\d.]+) cdev=([-\d.]+)')
    re_c=re.compile(r'^PHYSCOMW c=(\d+) a=(\d+) d=(\d+) comex=([-\d.]+)')
    for ln in open(p, errors='replace'):
        if not ln.startswith('PHYS'): continue
        m=re_b.match(ln)
        if m: d['bl'].setdefault((int(m.group(1)),int(m.group(2))), float(m.group(3))); continue
        m=re_l.match(ln)
        if m: d['radl'].append((int(m.group(1)),int(m.group(2)),int(m.group(3)),float(m.group(4)),float(m.group(5)),float(m.group(6)))); continue
        m=re_d.match(ln)
        if m: d['radld'].append((int(m.group(1)),int(m.group(2)),int(m.group(3)),float(m.group(4))+float(m.group(5)))); continue
        m=re_c.match(ln)
        if m: d['comd'].append((int(m.group(1)),int(m.group(3)),float(m.group(4)))); continue
    return d
A, B = load(BEF), load(AFT)
B0=602.0
print('LES SIX CRITERES DU CYCLE 40 (graves, md5 0ea470d980c4cee54f45c9bd137fc2a5)')
print('AVANT : %s' % BEF); print('APRES : %s' % AFT); print()

def perdrive(d, c, l, idx):
    out=[]
    for dr in range(6):
        vv=[r[idx] for r in d['radl'] if r[0]==c and r[1]==dr and r[2]==l]
        out.append(statistics.mean(vv) if vv else float('nan'))
    return out
def spread(v):
    mx,mn=max(v),min(v); return (mx-mn)/mx if mx>0 else 0.0

print('='*100)
print('Q1 + Q3 — DEFORMATION LOCALE LIVREE, ET LE LEVIER DOIT ETRE INTACT')
print('='*100)
print('  chaine maillon   role        bl(u)     rrm moyen AVANT->APRES     deform. locale AVANT->APRES')
for c in (0,1):
    for l in (0,1):
        bl=B['bl'].get((c,l), A['bl'].get((c,l)))
        va=[r[3] for r in A['radl'] if r[0]==c and r[2]==l]; vb=[r[3] for r in B['radl'] if r[0]==c and r[2]==l]
        ma,mb=statistics.mean(va),statistics.mean(vb)
        role='LEVIER (0 chair)' if l==0 else 'CHAIR'
        print('  %-6s l=%d  %-17s %7.1f   %.4f -> %.4f  (%+6.1f %%)   %6.1f %% -> %6.1f %%'
              % (CHAIN[c],l,role,bl,ma,mb,100*(mb-ma)/ma if ma else 0,
                 100*ma*B0/bl, 100*mb*B0/bl))
print('  clef de sa SPEC 22 : deformation locale <= 25 %  ·  bande exceptionnelle 21-25 %')
print()
print('='*100)
print('Q2 — DISCRIMINATION PAR PILOTAGE SUR LE MAILLON DE CHAIR (seuil du contrat 25 %)')
print('='*100)
print('  chaine  course   '+''.join('%10s'%d for d in DRIVES)+'    ecart')
for c in (0,1):
    for nm,d in (('AVANT',A),('APRES',B)):
        v=perdrive(d,c,1,3)
        print('  %-7s %-7s'%(CHAIN[c],nm)+''.join('%10.4f'%x for x in v)+'   %6.1f %%'%(100*spread(v)))
print()
print('='*100)
print('Q4 — SPEC 22 : `comex`, L\'EXCURSION DU CENTRE DE CHAIR (plafond dur 0.400 B0)')
print('='*100)
print('  chaine  course    moyenne     max     %% de fenetres hors plafond')
for c in (0,1):
    for nm,d in (('AVANT',A),('APRES',B)):
        vv=[x[2] for x in d['comd'] if x[0]==c]
        if not vv: print('  %-7s %-7s  (aucune ligne PHYSCOMD)'%(CHAIN[c],nm)); continue
        out=sum(1 for v in vv if v>0.400)/len(vv)
        print('  %-7s %-7s  %7.4f  %7.4f       %5.1f %%   (n=%d)'%(CHAIN[c],nm,statistics.mean(vv),max(vv),100*out,len(vv)))
print()
print('='*100)
print('Q5 — LE PRIX : la valeur DEMANDEE (`rrr`, avant borne) doit etre inchangee si la borne')
print('     ne retro-agit pas ; tout ecart mesure la retro-action sur la dynamique.')
print('='*100)
print('  chaine maillon   rrr moyen AVANT -> APRES     ecart')
for c in (0,1):
    for l in (0,1):
        va=[r[4] for r in A['radl'] if r[0]==c and r[2]==l]; vb=[r[4] for r in B['radl'] if r[0]==c and r[2]==l]
        ma,mb=statistics.mean(va),statistics.mean(vb)
        print('  %-6s l=%d      %.4f -> %.4f          %+6.1f %%'%(CHAIN[c],l,ma,mb,100*(mb-ma)/ma if ma else 0))
