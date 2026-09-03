#!/usr/bin/env python3
"""CYCLE 93 — les trois mesures du cycle, reproductibles sur la trace ARCHIVEE.

    python3 .autoport/c93_statistics.py .autoport/reports/Grecharged-secondary-motion/keira-room-x86.log

Aucun build, aucune course : tout est lu dans la trace. Chaque bloc imprime la grandeur ET la
statistique par laquelle il classe — c'est le verrou que ce cycle a pose
(`classify-a-population-by-its-window-maximum`).

  A. §21 — `perr` classe sur sa MOYENNE (pesum/rgn de PHYSRESTS) et sur son MAXIMUM (PHYSRESTW).
     C'est le calcul qui retire le « GELE 95,7 % / 97,8 % » du cycle 85.
  B. §36 — la population d'amplitude (PHYSSHAPE2/3) et la demande BRUTE, obtenue en inversant
     `phys-softmin` exactement.
  C. §2/§9/§27 — la queue de PHYSRINGA est-elle un plancher REEL ou un artefact d'ajustement ?
"""
import collections
import math
import re
import statistics
import sys

CAP36, KNF = 0.07, 0.84 * 0.07       # PHYS-SEC-MAX et le genou de phys-softmin
LIM_KN, LIM_FRZ = 0.42, 0.4992       # genou et gel du mur de force de SPEC 21, en B0
NAMES = {0: 'chestL', 1: 'chestR'}


def softmin_inverse(o):
    """Inverse EXACT de `phys-softmin(v, 0.07)` : out = kn + cp.x/(1+x), x = (v-kn)/cp."""
    a, cp = abs(o), CAP36 - KNF
    if a <= KNF:
        return a
    y = (a - KNF) / cp
    return float('inf') if y >= 1.0 else KNF + cp * (y / (1.0 - y))


def bloc_a(txt):
    print('== A. SPEC 21 — `perr`, LA MOYENNE CONTRE LE MAXIMUM ' + '=' * 40)
    moy, mx = collections.defaultdict(list), collections.defaultdict(list)
    for m in re.finditer(r'^PHYSRESTS c=(\d+) a=\d+ d=(\d+) rgsum=[-\d.e+]+'
                         r' pesum=([-\d.e+]+) rgn=([-\d.e+]+)', txt, re.M):
        n = float(m.group(4))
        if n > 0.0:
            moy[int(m.group(1))].append((int(m.group(2)), float(m.group(3)) / n))
    for m in re.finditer(r'^PHYSRESTW c=(\d+) a=\d+ d=(\d+) rgap=[-\d.e+]+ perr=([-\d.e+]+)',
                         txt, re.M):
        mx[int(m.group(1))].append((int(m.group(2)), float(m.group(3))))
    cls = lambda a: (sum(1 for x in a if x <= LIM_KN),
                     sum(1 for x in a if LIM_KN < x <= LIM_FRZ),
                     sum(1 for x in a if x > LIM_FRZ))
    for c in sorted(moy):
        vm = [v for _d, v in moy[c]]
        vx = [v for _d, v in mx.get(c, [])]
        t5m = [v for d, v in moy[c] if d == 5]
        t5x = [v for d, v in mx.get(c, []) if d == 5]
        print('  %-7s n=%d' % (NAMES.get(c, c), len(vm)))
        # MEME CONVENTION DE MEDIANE QUE LE TABLEAU (`v[n // 2]`, pas la moyenne des deux
        # valeurs centrales) : deux chiffres differents pour la meme grandeur sont exactement le
        # genre d'ecart qui coute un cycle a expliquer.
        print('    MOYENNE  med=%.4f  LIN/GEN/GEL = %d/%d/%d'
              % (sorted(vm)[len(vm) // 2], *cls(vm)))
        print('    MAXIMUM  med=%.4f  LIN/GEN/GEL = %d/%d/%d   <- le classement du cycle 85'
              % (sorted(vx)[len(vx) // 2], *cls(vx)))
        if t5m:
            _a = sorted(t5m)[len(t5m) // 2]
            _b = sorted(t5x)[len(t5x) // 2]
            print('    temoin d=5 (aucun pilotage) : moyenne %.4f  contre maximum %.4f   -> x%.1f'
                  % (_a, _b, _b / _a))


def bloc_b(txt):
    print('== B. SPEC 36 — POPULATION D\'AMPLITUDE ET DEMANDE BRUTE ' + '=' * 36)
    liv, brut = collections.defaultdict(list), collections.defaultdict(list)
    for m in re.finditer(r'^PHYSSHAPE2 c=(\d+) a=\d+ d=\d+ det=[-\d.e+]+ secm=([-\d.e+]+)',
                         txt, re.M):
        liv[int(m.group(1))].append(float(m.group(2)))
    for m in re.finditer(r'^PHYSSHAPE3 c=(\d+) a=\d+ d=\d+ secr=([-\d.e+]+)', txt, re.M):
        brut[int(m.group(1))].append(float(m.group(2)))
    for c in sorted(liv):
        v, r = sorted(liv[c]), sorted(brut.get(c, []))
        n = len(v)
        print('  %-7s n=%d   med=%.2f %%  max=%.2f %%   | <2%%:%d  2-5%%:%d  5-7%%:%d  >7%%:%d'
              % (NAMES.get(c, c), n, 100 * v[n // 2], 100 * v[-1],
                 sum(1 for x in v if x < 0.02), sum(1 for x in v if 0.02 <= x <= 0.05),
                 sum(1 for x in v if 0.05 < x <= 0.07), sum(1 for x in v if x > 0.07)))
        if r:
            print('           AVANT plafond : max=%.2f %%   fenetres > 7 %% : %d/%d (%.1f %%)'
                  % (100 * r[-1], sum(1 for x in r if x > 0.07), len(r),
                     100.0 * sum(1 for x in r if x > 0.07) / len(r)))
    ser = collections.defaultdict(dict)
    for m in re.finditer(r'^PHYSSEC c=(\d+) f=(\d+) s=([-\d.e+]+)', txt, re.M):
        ser[int(m.group(1))][int(m.group(2))] = float(m.group(3))
    for c in sorted(ser):
        vals = [ser[c][f] for f in sorted(ser[c])]
        pic = max(abs(x) for x in vals)
        raw = softmin_inverse(pic)
        print('  %-7s fenetre de secousse : pic LIVRE %.5f (%.2f %% du plafond) ; demande BRUTE'
              ' %.2f %% ; le filet retire %.1f %%'
              % (NAMES.get(c, c), pic, 100 * pic / CAP36, 100 * raw,
                 100.0 * (1.0 - pic / raw)))


def bloc_c(txt):
    print('== C. SPEC 2/9/27 — LE PLANCHER DE DETENTE EST-IL REEL ? ' + '=' * 35)
    ser = collections.defaultdict(list)
    for m in re.finditer(r'^PHYSRINGA c=(\d+) f=(\d+) l=(\d+) v=([-\d.e+]+) ap=([-\d.e+]+)'
                         r' lat=([-\d.e+]+)', txt, re.M):
        ser[(int(m.group(1)), int(m.group(3)))].append(
            (int(m.group(2)), float(m.group(4)), float(m.group(5)), float(m.group(6))))
    for k in ser:
        ser[k].sort()
    print('  Si la queue est PLATE, `s_inf` n\'est pas extrapole : il se lit directement.')
    for (c, l) in sorted(ser):
        for ax, lab in ((1, 'v'), (2, 'ap'), (3, 'lat')):
            q = [r[ax] for r in ser[(c, l)]][-30:]
            print('  %-7s l=%d %-4s  moyenne des 30 dernieres frames = %+.7f   ecart-type = %.7f'
                  % (NAMES.get(c, c), l, lab, statistics.mean(q), statistics.pstdev(q)))
    for m in re.finditer(r'^PHYSGRAV tag=(shaken|idle|tilt) c=(\d+) gn=([-\d.e+]+)', txt, re.M):
        print('  PHYSGRAV %-7s %-7s gn=%s   (gn~0 = ancre debout : aucun terme de gravite'
              ' constant n\'a droit de cite)' % (m.group(1), NAMES.get(int(m.group(2))), m.group(3)))


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else \
        '.autoport/reports/Grecharged-secondary-motion/keira-room-x86.log'
    txt = open(path, encoding='utf-8', errors='replace').read()
    print('trace : %s' % path)
    bloc_a(txt)
    bloc_b(txt)
    bloc_c(txt)


if __name__ == '__main__':
    main()
