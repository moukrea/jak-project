#!/usr/bin/env python3
"""c40e1_strain.py — LE CANAL RADIAL DE SA SPEC 23, RELU EN DEFORMATION.

LES TROIS QUESTIONS (SPEC 7), repondues avant d'ecrire le moindre chiffre :
  NATURE  : une DEFORMATION (sans unite) = allongement / longueur de repos DU MAILLON.
            Sa SPEC 22 donne les deplacements en B0 et l'elongation de tissu en POURCENT :
            un pourcent est un rapport, son denominateur est la longueur LOCALE.
            Tout le corpus des 39 cycles a divise par B0 (l'organe entier). C'est le sujet.
  REPERE  : le long de l'axe COURANT du maillon (`m^ = (p - a)/|p - a|`), par maillon,
            par fenetre, par pilotage. `dr0 = dot(cp - a, m^) - bl` = (ml-bl) + dot(cp-p, m^),
            identite verifiee ici meme (colonne `id`).
  ABSENT  : un maillon dont la chair ne bouge pas lit dr0 = 0, donc deformation 0 %.

CE QU'IL LIT, ET RIEN D'AUTRE : la course LIVREE du cycle 38 (aucune course lancee).
"""
import collections
import os
import re
import statistics
import sys

LOG = sys.argv[1] if len(sys.argv) > 1 else \
    '.autoport/reports/Grecharged-secondary-motion/keira-room-x86.C38E4-FINAL.log'

DRIVES = ('updown', 'leftright', 'accel', 'jerk', 'tilt', 'AUCUN')
CHAIN = ('chestL', 'chestR')

# --- 1. les longueurs de repos, lues dans la course (jamais supposees) ----------------------
bl = {}
b0 = {}
re_bone = re.compile(r'^PHYSBONE c=(\d+) l=(\d+) len=([-\d.]+)')
re_b0 = re.compile(r'^PHYSB0 c=(\d+).*flesh=([-\d.]+)')
# PHYSRADL c=0 d=0 l=0 rrm=.. rrr=.. sat=..
re_radl = re.compile(r'^PHYSRADL c=(\d+) d=(\d+) l=(\d+) rrm=([-\d.]+) rrr=([-\d.]+) sat=([-\d.]+)')
re_radld = re.compile(r'^PHYSRADLD c=(\d+) d=(\d+) l=(\d+) mlb=([-\d.]+) cdev=([-\d.]+)')
re_radle = re.compile(r'^PHYSRADLE c=(\d+) d=(\d+) l=(\d+) ctg=([-\d.]+) cdd=([-\d.]+)')

radl, radld, radle = [], [], []
with open(LOG, 'r', errors='replace') as fh:
    for ln in fh:
        if not ln.startswith('PHYS'):
            continue
        m = re_bone.match(ln)
        if m:
            bl.setdefault((int(m.group(1)), int(m.group(2))), float(m.group(3)))
            continue
        m = re_b0.match(ln)
        if m:
            b0.setdefault(int(m.group(1)), float(m.group(2)))
            continue
        m = re_radl.match(ln)
        if m:
            radl.append(tuple(int(x) for x in m.groups()[:3]) + tuple(float(x) for x in m.groups()[3:]))
            continue
        m = re_radld.match(ln)
        if m:
            radld.append(tuple(int(x) for x in m.groups()[:3]) + tuple(float(x) for x in m.groups()[3:]))
            continue
        m = re_radle.match(ln)
        if m:
            radle.append(tuple(int(x) for x in m.groups()[:3]) + tuple(float(x) for x in m.groups()[3:]))

if not b0:
    for ln in open(LOG, 'r', errors='replace'):
        if 'flesh=' in ln:
            mm = re.search(r'c=(\d+).*flesh=([-\d.]+)', ln)
            if mm:
                b0.setdefault(int(mm.group(1)), float(mm.group(2)))
B0 = {c: (b0.get(c) or 602.0) for c in (0, 1)}

print('CANAL RADIAL DE SA SPEC 23 — RELU EN DEFORMATION (denominateur = longueur DU MAILLON)')
print('trace : %s' % LOG)
print('NATURE deformation sans unite · REPERE axe COURANT du maillon · ABSENT = 0 %%')
print()
print('LES LONGUEURS DE REPOS LIVREES, ET CE QUE LE PLAFOND ACTUEL VAUT EN DEFORMATION')
print('  chaine  maillon   bl (u)      B0 (u)   plafond 0.40*B0 (u)   = deformation reelle')
for c in (0, 1):
    for l in (0, 1):
        L = bl.get((c, l))
        if L is None:
            continue
        cap = 0.40 * B0[c]
        print('  %-7s l=%d    %9.2f  %8.2f   %10.2f            **%7.1f %%**'
              % (CHAIN[c], l, L, B0[c], cap, 100.0 * cap / L))
print('  cle de sa SPEC 22 pour cette grandeur : AbsoluteStretchClamp = 25.0 %%')
print()

# --- 2. table jointe par (c, d, l) ----------------------------------------------------------
# chaque source a 31 fenetres par (c,d,l) ; elles sont dans le MEME ordre (meme boucle d'emission)
key = lambda t: (t[0], t[1], t[2])
gl, gd, ge = collections.defaultdict(list), collections.defaultdict(list), collections.defaultdict(list)
for t in radl:
    gl[key(t)].append(t[3:])
for t in radld:
    gd[key(t)].append(t[3:])
for t in radle:
    ge[key(t)].append(t[3:])

rows = []   # (c, d, l, rrm, rrr, sat, mlb, cdev, ctg, cdd)
for k in sorted(gl):
    n = min(len(gl[k]), len(gd[k]), len(ge[k]))
    for i in range(n):
        rows.append(k + gl[k][i] + gd[k][i] + ge[k][i])

print('lignes appariees : %d  (PHYSRADL %d · PHYSRADLD %d · PHYSRADLE %d)'
      % (len(rows), len(radl), len(radld), len(radle)))

# --- 3. identite de controle : rrr == |mlb + cdev| ------------------------------------------
worst_id = 0.0
for (c, d, l, rrm, rrr, sat, mlb, cdev, ctg, cdd) in rows:
    worst_id = max(worst_id, abs(abs(mlb + cdev) - rrr))
print('CONTROLE INTERNE — identite  rrr == |mlb + cdev|  : ecart max **%.6f** (attendu ~1e-4)'
      % worst_id)
print()

def pct(x):
    return 100.0 * x

# --- P1 : la deformation par maillon --------------------------------------------------------
print('=' * 96)
print('P1 — LA DEFORMATION REELLE PAR MAILLON, CONTRE LES BANDES DE SA SPEC 22')
print('     bandes : courante 5-15 %% · large 15-21 %% · exceptionnelle 21-25 %% · clamp 25 %%')
print('=' * 96)
print('  chaine  maillon    n   deformation |dr0|/bl : mediane   moyenne     max   %%>25%%   facteur median/25%%')
verdict_p1 = {}
for c in (0, 1):
    for l in (0, 1):
        vals = [abs(mlb + cdev) * B0[c] / bl[(c, l)]
                for (cc, d, ll, rrm, rrr, sat, mlb, cdev, ctg, cdd) in rows if cc == c and ll == l]
        if not vals:
            continue
        med, mean, mx = statistics.median(vals), statistics.mean(vals), max(vals)
        over = sum(1 for v in vals if v > 0.25) / len(vals)
        verdict_p1[(c, l)] = (med, over)
        print('  %-7s l=%d    %3d           %8.1f %% %8.1f %% %7.1f %%  %5.1f %%        x%.2f'
              % (CHAIN[c], l, len(vals), pct(med), pct(mean), pct(mx), pct(over), med / 0.25))
print()

# --- P2 : le signe --------------------------------------------------------------------------
print('=' * 96)
print('P2 — LE SIGNE DE `dr0` PAR MAILLON (extension positive, compression negative)')
print('=' * 96)
print('  chaine  maillon    %% positif   %% negatif   mediane signee (deformation)')
verdict_p2 = {}
for c in (0, 1):
    for l in (0, 1):
        sv = [(mlb + cdev) * B0[c] / bl[(c, l)]
              for (cc, d, ll, rrm, rrr, sat, mlb, cdev, ctg, cdd) in rows if cc == c and ll == l]
        if not sv:
            continue
        pos = sum(1 for v in sv if v > 0) / len(sv)
        verdict_p2[(c, l)] = pos
        print('  %-7s l=%d      %6.1f %%    %6.1f %%          %+8.1f %%'
              % (CHAIN[c], l, pct(pos), pct(1 - pos), pct(statistics.median(sv))))
print()

# --- P3 : l'artefact de rotation ------------------------------------------------------------
print('=' * 96)
print('P3 — MA PROPRE PREMIERE HYPOTHESE, TESTEE : L\'ARTEFACT DE ROTATION `bl*(cos(th)-1)`')
print('     artefact = dr0/B0 - ctg   (ctg = dot(cp-tg, m^)/B0, le vrai ecart du point libre)')
print('=' * 96)
print('  chaine  maillon   |artefact| / |dr0| : mediane   max      part >25%% des fenetres')
verdict_p3 = {}
for c in (0, 1):
    for l in (0, 1):
        fr = []
        for (cc, d, ll, rrm, rrr, sat, mlb, cdev, ctg, cdd) in rows:
            if cc != c or ll != l:
                continue
            dr = mlb + cdev
            if abs(dr) < 1e-6:
                continue
            fr.append(abs(dr - ctg) / abs(dr))
        if not fr:
            continue
        med = statistics.median(fr)
        verdict_p3[(c, l)] = med
        print('  %-7s l=%d           %8.1f %%  %8.1f %%      %6.1f %%'
              % (CHAIN[c], l, pct(med), pct(max(fr)),
                 pct(sum(1 for v in fr if v > 0.25) / len(fr))))
print()

# --- P4 : la borne d'etat -------------------------------------------------------------------
cdds = [cdd for (c, d, l, rrm, rrr, sat, mlb, cdev, ctg, cdd) in rows]
over4 = sum(1 for v in cdds if v > 0.4005)
print('=' * 96)
print('P4 — LA BORNE D\'ETAT `|cp - tg| <= 0.40 B0` : max **%.4f**, hors borne **%d / %d**'
      % (max(cdds), over4, len(cdds)))
print('=' * 96)
print()

# --- P5 : la discrimination par pilotage ----------------------------------------------------
print('=' * 96)
print('P5 — DISCRIMINATION PAR PILOTAGE. Seuil de non-discrimination du contrat : 25 %%')
print('     spread = (max - min) / max sur les SIX pilotages, moyenne des 31 fenetres de chacun')
print('=' * 96)
hdr = '  chaine  maillon  grandeur   ' + ''.join('%10s' % d for d in DRIVES) + '    spread'
print(hdr)
verdict_p5 = {}
for c in (0, 1):
    for l in (0, 1):
        for lbl, idx in (('rrr DEMANDE', 4), ('rrm LIVRE  ', 3)):
            means = []
            for d in range(6):
                vv = [r[idx] for r in rows if r[0] == c and r[1] == d and r[2] == l]
                means.append(statistics.mean(vv) if vv else float('nan'))
            mx, mn = max(means), min(means)
            spread = (mx - mn) / mx if mx > 0 else 0.0
            verdict_p5[(c, l, idx)] = spread
            print('  %-7s l=%d  %s' % (CHAIN[c], l, lbl)
                  + ''.join('%10.4f' % v for v in means) + '   %6.1f %%' % pct(spread))
print()

# --- verdicts ------------------------------------------------------------------------------
print('=' * 96)
print('VERDICTS SUR LES PREDICTIONS GRAVEES (md5 7b06309f89cb9ec9bf375227c3e39fd8)')
print('=' * 96)
ok = lambda b: 'TENUE  ' if b else 'REFUTEE'
p1 = all(verdict_p1[(c, 0)][1] <= 0.50 for c in (0, 1)) \
     and all(verdict_p1[(c, 1)][1] >= 0.90 for c in (0, 1)) \
     and all(verdict_p1[(c, 1)][0] / 0.25 >= 4.0 for c in (0, 1))
print('P1 racine dans la bande / distal >=90 %% hors bande, facteur >=4 : %s' % ok(p1))
for c in (0, 1):
    print('     %-7s racine hors bande %5.1f %% (predit <=50) · distal hors bande %5.1f %% '
          '(predit >=90) · facteur distal x%.2f (predit >=4)'
          % (CHAIN[c], pct(verdict_p1[(c, 0)][1]), pct(verdict_p1[(c, 1)][1]),
             verdict_p1[(c, 1)][0] / 0.25))
p2 = all(verdict_p2[(c, 0)] >= 0.90 for c in (0, 1)) and all(verdict_p2[(c, 1)] <= 0.10 for c in (0, 1))
print('P2 racine >=90 %% positive et distal >=90 %% negative                : %s' % ok(p2))
p3 = all(v < 0.25 for v in verdict_p3.values())
print('P3 artefact de rotation <25 %% de |dr0| (auto-refutation)          : %s' % ok(p3))
p4 = (over4 == 0)
print('P4 borne d\'etat tenue sur 100 %% des lignes                        : %s' % ok(p4))
p5 = all(verdict_p5[(c, 1, 3)] < 0.15 for c in (0, 1)) and all(verdict_p5[(c, 1, 4)] > 0.40 for c in (0, 1))
print('P5 distal : livre plat (<15 %%) et demande discriminant (>40 %%)     : %s' % ok(p5))
