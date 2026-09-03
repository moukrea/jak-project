#!/usr/bin/env python3
"""c40e4_capsweep.py — CE QUE CHAQUE VALEUR DE LA BORNE RENDRAIT, FENETRE PAR FENETRE.

NATURE  : une SIMULATION EXACTE de la fonction de publication `phys-softmin(dr0, cap)` appliquee
          aux `dr0` REELLEMENT LIVRES. Ce n'est PAS une prediction du comportement du moteur :
          changer la borne change ce que le tenseur consomme, donc la dynamique, donc `dr0`.
          C'est l'effet AU PREMIER ORDRE, et il est dit comme tel.
REPERE  : par maillon, par pilotage ; `dr0` lu comme `mlb + cdev` (identite verifiee a 1e-4).
ABSENT  : une borne qui ne mord pas rend `drr == dr0` et un ecart identique a celui de l'entree.

CE QU'IL TRANCHE : le cycle 33 a refute le passage 0.40 -> 0.25 au motif que « serrer AGGRAVE »
la platitude. Ce script mesure la platitude que 0.25 produirait, sur la vraie plage de stimulus.
"""
import re, statistics, sys
LOG = sys.argv[1] if len(sys.argv) > 1 else \
    '.autoport/reports/Grecharged-secondary-motion/keira-room-x86.C38E4-FINAL.log'
DRIVES = ('updown','leftright','accel','jerk','tilt','AUCUN'); CHAIN=('chestL','chestR')
BL = {(0,0):1040.5006,(0,1):140.4225,(1,0):1039.0379,(1,1):144.2315}
B0 = 602.0

def softmin(v, cap):
    kn = 0.84*cap
    if cap <= 0.0 or v <= kn: return v
    cp = cap-kn; x = (v-kn)/cp
    return kn + cp*(x/(1.0+x))

re_d = re.compile(r'^PHYSRADLD c=(\d+) d=(\d+) l=(\d+) mlb=([-\d.]+) cdev=([-\d.]+)')
win = []   # (c,d,l,dr0_in_B0)
for ln in open(LOG, errors='replace'):
    m = re_d.match(ln)
    if m:
        c,d,l = int(m.group(1)),int(m.group(2)),int(m.group(3))
        win.append((c,d,l,float(m.group(4))+float(m.group(5))))

print('BALAYAGE DE LA BORNE DU CANAL RADIAL, SUR LES `dr0` REELLEMENT LIVRES')
print('NATURE simulation exacte de la fonction de publication, effet AU PREMIER ORDRE seulement')
print('REPERE par maillon et par pilotage · ABSENT borne qui ne mord pas -> ecart = celui de l\'entree')
print('seuil de non-discrimination du contrat : 25 %')
print()
CAPS = [('0.40 B0 (ACTUEL, ligne COM de la 22)', lambda c,l: 0.40),
        ('0.25 B0 (ligne AbsoluteStretchClamp de la 22/38)', lambda c,l: 0.25),
        ('0.25 * bl / B0 (deformation LOCALE du segment)', lambda c,l: 0.25*BL[(c,l)]/B0),
        ('pas de borne', lambda c,l: 1e9)]
for lbl, capf in CAPS:
    print('=== BORNE : %s' % lbl)
    print('   chaine  maillon  cap(B0)  ' + ''.join('%9s' % d for d in DRIVES) + '   ecart   moyenne  = deform. locale')
    for c in (0,1):
        for l in (0,1):
            cap = capf(c,l)
            means = []
            for d in range(6):
                vv = [abs(softmin(abs(v), cap)) for (cc,dd,ll,v) in win if cc==c and dd==d and ll==l]
                means.append(statistics.mean(vv) if vv else float('nan'))
            mx, mn = max(means), min(means)
            sp = (mx-mn)/mx if mx>0 else 0.0
            allm = statistics.mean([abs(softmin(abs(v), cap)) for (cc,dd,ll,v) in win if cc==c and ll==l])
            loc = 100.0*allm*B0/BL[(c,l)]
            print('   %-7s l=%d   %7.3f  ' % (CHAIN[c], l, min(cap,9.999))
                  + ''.join('%9.4f' % v for v in means)
                  + '  %5.1f %%  %7.4f   %7.1f %%' % (100*sp, allm, loc))
    print()
print('RAPPEL DES ROLES, MESURES ET NON SUPPOSES :')
print('  l=0 = LEVIER chest->lBoob (1040 u), AUCUNE chair — sa `dr0` n\'est pas une deformation')
print('  l=1 = SEUL segment de chair simule lBoob->lBooc (140 u), r de 0.480 a 0.674 sur 0..1')
print('  la clef de sa SPEC 22 pour la deformation locale : 25 %')
