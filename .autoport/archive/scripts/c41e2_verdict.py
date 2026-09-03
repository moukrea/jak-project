#!/usr/bin/env python3
"""C41 ETAPE 2 — LE COM DE POPULATION, ET LES VERDICTS SUR LES SIX PREDICTIONS GRAVEES.

Predictions : .autoport/reports/Grecharged-secondary-motion/C41E1-population-com-prediction.txt
              md5 ba25c857876a995cdbb4f89e57931603, commit 55a71d1bfc, AVANT la modification.

NATURE / REPERE / LECTURE-HORS-DEFAUT de chaque grandeur lue ici :
  ee_l  LONGUEUR / B0, maximum de la FENETRE, pour LE MAILLON l seul. Repere : le monde, contre la
        pose d'auteur de la MEME frame. Hors defaut : 0.0000.
  jt_l  LONGUEUR / B0, relevee A LA FRAME QUI MAXIMISE ee_l — le deplacement du JOINT seul, donc la
        part de l'excursion INDEPENDANTE de `lc`. Hors defaut : 0.0000.
  comex LONGUEUR / B0, maximum de la fenetre sur LES DEUX maillons (l'ancien instrument).

LA BORNE EST UNE BORNE : |somme ponderee de VECTEURS| <= somme ponderee des NORMES. On publie donc
COMpop_MAJ (borne superieure) et COMpop_MIN (borne inferieure, |difference|), jamais un point.
"""
import re, sys, statistics as st

REF = sys.argv[1] if len(sys.argv) > 1 else '.autoport/reports/Grecharged-secondary-motion/keira-room-x86.C40E5-CAPFIX.log'
NEW = sys.argv[2] if len(sys.argv) > 2 else '.autoport/reports/Grecharged-secondary-motion/keira-room-x86.log'

# Poids MESURES sur le mesh LIVRE out/jak1/fr3/skin/keira-hd-lod0.glb (md5 5cb8a493c43211acf3a04c5b6433df81),
# nuage = sommets portant un poids non nul sur au moins un os de chaine. Poids normalises a 4.5e-08.
# L'ancre (`chest`, `?shoulder`) contribue 0 par construction : non simulee, matrice ecrite == matrice d'auteur.
W = {0: {'name': 'chestL', 'tot': 94.0, 'l': {0: 17.7785, 1: 33.1247}, 'anc': 42.8317 + 0.2651},
     1: {'name': 'chestR', 'tot': 90.0, 'l': {0: 19.8010, 1: 28.7457}, 'anc': 40.7956 + 0.6576}}
CAP, NORM = 0.400, 0.350
DN = {0: 'updown', 1: 'leftright', 2: 'accel', 3: 'jerk', 4: 'tilt', 5: 'BASE(aucun)'}
OUT = []
def A(s=''):
    OUT.append(s); print(s)

def load(path):
    t = open(path, errors='replace').read()
    cw, wl, gr = {}, {}, {}
    for m in re.finditer(r'^PHYSCOMW c=(\d+) a=(\d+) d=(\d+) comex=([-\d.e+]+)', t, re.M):
        cw[(int(m.group(1)), int(m.group(2)), int(m.group(3)))] = float(m.group(4))
    for m in re.finditer(r'^PHYSCOMWL c=(\d+) a=(\d+) d=(\d+) l=(\d+) ee=([-\d.e+]+) jt=([-\d.e+]+)', t, re.M):
        wl[(int(m.group(1)), int(m.group(2)), int(m.group(3)), int(m.group(4)))] = (float(m.group(5)), float(m.group(6)))
    for m in re.finditer(r'^PHYSGRAD c=(\d+) a=(\d+) d=(\d+) l=(\d+) amp=([-\d.e+]+) ang=([-\d.e+]+)', t, re.M):
        gr[(int(m.group(1)), int(m.group(2)), int(m.group(3)), int(m.group(4)))] = (float(m.group(5)), float(m.group(6)))
    return t, cw, wl, gr

TR, cwR, wlR, _ = load(REF)
TN, cwN, wlN, _ = load(NEW)

A('=' * 96)
A('C41 ETAPE 2 — LE COM DE POPULATION. VERDICTS SUR LES SIX PREDICTIONS DE C41E1 (md5')
A('ba25c857876a995cdbb4f89e57931603, commit 55a71d1bfc — gravees AVANT la modification du moteur).')
A('=' * 96)
A('reference : %s' % REF)
A('nouvelle  : %s' % NEW)
A('fenetres : reference %d · nouvelle %d · nouvelles lignes PHYSCOMWL %d' % (len(cwR), len(cwN), len(wlN)))

# ---------------------------------------------------------------- P1 : CONTROLE D'INERTIE
A(''); A('-' * 96)
A('P1 — CONTROLE D\'INERTIE. L\'ajout est un INSTRUMENT : rien dans le solveur ne le relit, donc')
A('     TOUTE ligne deja publiee doit etre identique au caractere pres. Critere : 0 ligne differente.')
A('-' * 96)
TYPES = ('PHYSROW', 'PHYSBASE', 'PHYSCOMW', 'PHYSCOMD', 'PHYSCOMDL', 'PHYSGRAD', 'PHYSGRADS',
         'PHYSRESTW', 'PHYSRESTS', 'PHYSREBASE', 'PHYSACC', 'PHYSBONE', 'PHYSCHAIN')
tot_d = 0
for ty in TYPES:
    a = [l for l in TR.split('\n') if l.startswith(ty + ' ')]
    b = [l for l in TN.split('\n') if l.startswith(ty + ' ')]
    d = 0 if (len(a) == len(b)) else abs(len(a) - len(b))
    if len(a) == len(b):
        d = sum(1 for x, y in zip(a, b) if x != y)
    tot_d += d
    A('   %-11s reference %5d lignes · nouvelle %5d · %s' %
      (ty, len(a), len(b), ('IDENTIQUES' if d == 0 else '**%d DIFFERENTES**' % d)))
A('   VERDICT P1 : %s (%d ligne(s) differente(s))' % ('TENUE' if tot_d == 0 else '**REFUTEE**', tot_d))
if tot_d:
    A('   >>> P1 REFUTEE : tout ce qui suit est SANS VALEUR et je le dis au lieu de le publier.')

# ---------------------------------------------------------------- P2 : IDENTITE
A(''); A('-' * 96)
A('P2 — IDENTITE DE L\'INSTRUMENT : max(ee_0, ee_1) doit RECOMPOSER `comex`. Critere 372/372 a 1e-4.')
A('-' * 96)
ok2 = bad2 = 0; worst2 = 0.0
for k, v in cwN.items():
    c, a_, d = k
    ee = [wlN[(c, a_, d, l)][0] for l in range(4) if (c, a_, d, l) in wlN]
    if not ee:
        continue
    r = abs(max(ee) - v); worst2 = max(worst2, r)
    if r <= 1e-4: ok2 += 1
    else: bad2 += 1
A('   fenetres recomposees %d/%d · residu max |max(ee_l) - comex| = %.6f' % (ok2, ok2 + bad2, worst2))
A('   VERDICT P2 : %s' % ('TENUE' if bad2 == 0 else '**REFUTEE (%d fenetres)**' % bad2))

# ---------------------------------------------------------------- P3 : quel maillon
A(''); A('-' * 96)
A('P3 — QUEL MAILLON PORTE. Predit : ee_0 > ee_1 dans 80-95 %% (chestL) et 88-98 %% (chestR) ;')
A('     rapport median ee_1/ee_0 dans [0.80, 1.00].')
A('-' * 96)
for c in (0, 1):
    ks = sorted(k for k in cwN if k[0] == c)
    d0 = [(wlN[(c, a_, d, 0)][0], wlN[(c, a_, d, 1)][0]) for (_, a_, d) in ks
          if (c, a_, d, 0) in wlN and (c, a_, d, 1) in wlN]
    if not d0: continue
    fr = 100.0 * sum(1 for x, y in d0 if x > y) / len(d0)
    rat = [y / x for x, y in d0 if x > 1e-9]
    A('   %-7s n=%d · ee_0 > ee_1 dans %.1f %% · rapport ee_1/ee_0 median %.3f (min %.3f max %.3f)'
      % (W[c]['name'], len(d0), fr, st.median(rat), min(rat), max(rat)))

# ---------------------------------------------------------------- P4 : LE COM DE POPULATION
A(''); A('-' * 96)
A('P4 — **LE RESULTAT** : LE COM DE POPULATION, BORNE SUPERIEURE RIGOUREUSE.')
A('     COMpop <= ( W0*ee_0 + W1*ee_1 ) / W_total. L\'ancre (%.1f %% / %.1f %% de la masse) contribue'
  % (100 * W[0]['anc'] / W[0]['tot'], 100 * W[1]['anc'] / W[1]['tot']))
A('     exactement 0 : `chest` et `?shoulder` ne sont pas simules, leur matrice ecrite EST leur')
A('     matrice d\'auteur. Plafond dur de sa SPEC 22 : 0.400 B0 · ligne « normal » : 0.350 B0.')
A('-' * 96)
A('   chaine   grandeur              moyenne     pire    fenetres > 0.400   > 0.350')
res = {}
for c in (0, 1):
    tot = W[c]['tot']
    ks = sorted(k for k in cwN if k[0] == c)
    old, up, lo, jtp = [], [], [], []
    for (_, a_, d) in ks:
        if (c, a_, 0) not in [(c, a_, l) for l in (0, 1)]: pass
        if (c, a_, d, 0) not in wlN or (c, a_, d, 1) not in wlN: continue
        e0, j0 = wlN[(c, a_, d, 0)]; e1, j1 = wlN[(c, a_, d, 1)]
        w0, w1 = W[c]['l'][0], W[c]['l'][1]
        old.append(cwN[(c, a_, d)])
        up.append((w0 * e0 + w1 * e1) / tot)
        lo.append(abs(w0 * e0 - w1 * e1) / tot)
        jtp.append((w0 * j0 + w1 * j1) / tot)
    res[c] = dict(old=old, up=up, lo=lo, jt=jtp)
    for nm, v in (('comex (ANCIEN, max)', old), ('COMpop BORNE SUP', up),
                  ('COMpop BORNE INF', lo), ('part sans `lc` (jt)', jtp)):
        A('   %-8s %-20s %8.4f %8.4f %10d (%3.0f %%) %8d (%3.0f %%)'
          % (W[c]['name'], nm, st.mean(v), max(v), sum(1 for x in v if x > CAP),
             100.0 * sum(1 for x in v if x > CAP) / len(v),
             sum(1 for x in v if x > NORM), 100.0 * sum(1 for x in v if x > NORM) / len(v)))
A('')
A('   PAR PILOTAGE (borne superieure du COM de population) — et l\'ecart, seuil du contrat 25 %%')
for c in (0, 1):
    per = {}
    for (cc, a_, d) in sorted(k for k in cwN if k[0] == c):
        if (c, a_, d, 0) not in wlN or (c, a_, d, 1) not in wlN: continue
        e0 = wlN[(c, a_, d, 0)][0]; e1 = wlN[(c, a_, d, 1)][0]
        per.setdefault(d, []).append((W[c]['l'][0] * e0 + W[c]['l'][1] * e1) / W[c]['tot'])
    line = ' · '.join('%s %.4f' % (DN.get(d, d), st.mean(v)) for d, v in sorted(per.items()))
    hi = max(st.mean(v) for v in per.values()); lo2 = min(st.mean(v) for v in per.values())
    A('   %-7s %s' % (W[c]['name'], line))
    A('   %-7s ecart entre pilotages = %.1f %%%s' % ('', 100 * (hi - lo2) / hi,
      '   <- SOUS le seuil de 25 %, mesure NON DISCRIMINANTE' if (hi - lo2) / hi < 0.25 else ''))

# ---------------------------------------------------------------- P5 : la borne est-elle serree
A(''); A('-' * 96)
A('P5 — LA BORNE EST-ELLE SERREE ? Elle l\'est si les deux excursions sont presque colineaires, ce')
A('     que forcerait une part de translation dominante et commune. Critere : median(jt_0/ee_0) >= 0.55.')
A('-' * 96)
for c in (0, 1):
    for l in (0, 1):
        v = [wlN[(c, a_, d, l)][1] / wlN[(c, a_, d, l)][0]
             for (_, a_, d) in sorted(k for k in cwN if k[0] == c)
             if (c, a_, d, l) in wlN and wlN[(c, a_, d, l)][0] > 1e-9]
        if v:
            A('   %-7s maillon %d : jt/ee median %.3f (min %.3f max %.3f, n=%d)'
              % (W[c]['name'], l, st.median(v), min(v), max(v), len(v)))

# ---------------------------------------------------------------- P6 : ce que ca ne ferme pas
A(''); A('-' * 96)
A('P6 — CE QUE LA CORRECTION NE FERME PAS, predit CONTRE moi : la part qui ne depend PAS de `lc`,')
A('     ponderee par la masse, reste >= 0.25 B0. C\'est ce que vaudrait le COM si le centre de chair')
A('     etait pose EXACTEMENT sur les joints.')
A('-' * 96)
for c in (0, 1):
    v = res[c]['jt']
    A('   %-7s ( W0*jt_0 + W1*jt_1 ) / W_total : moyenne %.4f · pire %.4f · %s le critere 0.25'
      % (W[c]['name'], st.mean(v), max(v), 'AU-DESSUS de' if st.mean(v) >= 0.25 else 'SOUS'))

open('.autoport/reports/Grecharged-secondary-motion/C41E2-population-com.txt', 'w').write('\n'.join(OUT) + '\n')
