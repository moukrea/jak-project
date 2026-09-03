#!/usr/bin/env python3
"""c55_verdict.py — adjuge les cinq predictions de C55E1 sur la trace de la salle.
NATURE / REPERE : identiques a ROOM-SIGN (apex = maximum de fenetre en % B0, monde contre pose
d'auteur ; directions d'os = unitaires, monde). Aucun nombre en dur : tout est relu de la trace."""
import re, math, sys
NEW = '.autoport/reports/Grecharged-secondary-motion/keira-room-x86.log'
REF = '.autoport/reports/Grecharged-secondary-motion/keira-room-x86.C54-REF.log'
L = open(NEW, encoding='utf-8', errors='ignore').read()

ax = {}
for m in re.finditer(r'^PHYSAXW ax=(\d+) ux=([-\d.e+]+) uy=([-\d.e+]+) uz=([-\d.e+]+)', L, re.M):
    ax[int(m[1])] = (float(m[2]), float(m[3]), float(m[4]))
bone = {}
for m in re.finditer(r'^PHYSSGNB c=(\d+) l=(\d+) ux=([-\d.e+]+) uy=([-\d.e+]+) uz=([-\d.e+]+)', L, re.M):
    bone[(int(m[1]), int(m[2]))] = (float(m[3]), float(m[4]), float(m[5]))
A, V = {}, {}
for m in re.finditer(r'^PHYSSGN c=(\d+) i=(\d+) k=(\d+) a=(\d+) s=(-?\d+) apex=([-\d.e+]+)', L, re.M):
    A[int(m[2])] = (int(m[3]), int(m[4]), int(m[5])); V[(int(m[1]), int(m[2]))] = float(m[6])

def dot(a, b): return sum(x * y for x, y in zip(a, b))
def nrm(a): return math.sqrt(dot(a, a))
def mir(u, n):
    d = dot(u, n); return tuple(u[i] - 2 * d * n[i] for i in range(3))
def ang(a, b): return math.degrees(math.acos(max(-1.0, min(1.0, dot(a, b) / (nrm(a) * nrm(b))))))

print("=" * 92)
print("C55 — ADJUDICATION DES CINQ PREDICTIONS")
print("=" * 92)
pose = re.search(r'^PHYSSGNPOSE ai=(-?\d+) src=(\S+)', L, re.M)
print("epingle : %s" % (pose.group(0) if pose else "AUCUNE LIGNE PHYSSGNPOSE — l'epingle n'a pas tourne"))

# ---- P1 : la pose tenue est-elle symetrique ? ----
if 2 not in ax or (0, 0) not in bone:
    print("P1 : DONNEES MANQUANTES"); sys.exit(1)
lat = ax[2]
a0 = ang(mir(bone[(0, 0)], lat), bone[(1, 0)])
a1 = ang(mir(bone[(0, 1)], lat), bone[(1, 1)]) if (0, 1) in bone else float('nan')
print("\nP1  ecart au miroir parfait de la pose TENUE : racine %.1f deg   distal %.1f deg" % (a0, a1))
print("    (pose asymetrique des cycles 52-54 : 43.4 deg)   -> %s"
      % ("TENUE — l'epingle a pris" if a0 < 10 else "REFUTEE — l'epingle n'a pas donne une pose symetrique ; RIEN d'autre n'est lisible"))

# ---- P4 : les angles os/pilotage dans la NOUVELLE pose ----
print("\n    angles os / axe pousse dans la pose epinglee :")
cos = {}
for c, nm in ((0, 'chestL'), (1, 'chestR')):
    u = bone[(c, 0)]
    row = []
    for a in (0, 1, 2):
        cs = min(1.0, abs(dot(u, ax[a]) / nrm(u))); cos[(c, a)] = cs
        row.append("%-9s %5.1f deg 1/sin=%s" % (('vert', 'ap', 'lat')[a], math.degrees(math.acos(cs)),
                   ("%.2f" % (1 / math.sin(math.acos(cs)))) if math.sin(math.acos(cs)) > 1e-6 else "inf"))
    print("      %-7s  %s" % (nm, "  ".join(row)))

cells = {}
for i, (k, a, s) in A.items(): cells.setdefault((k, a, s), []).append(i)
def mean(c, k, a, s):
    ii = cells.get((k, a, s), [])
    v = [V[(c, i)] for i in ii if (c, i) in V]
    return sum(v) / len(v) if v else None

# ---- P3 : l'ecart gauche/droite vertical ----
print("\nP3  ECART GAUCHE/DROITE SUR L'AXE VERTICAL, k=0 (il valait x3.41 en pose asymetrique)")
worst = 0.0
for s in (1, -1):
    l, r = mean(0, 0, 0, s), mean(1, 0, 0, s)
    if l and r:
        f = max(l, r) / min(l, r); worst = max(worst, f)
        print("      s=%+d : chestL %.4f   chestR %.4f   -> x%.2f" % (s, l, r, f))
print("      pire des deux sens : x%.2f" % worst)
print("      -> %s" % ("P3 TENUE : l'ecart tombe sous x1.5. LA POSE PORTAIT L'ECART." if worst < 1.5
      else ("P3 REFUTEE : l'ecart reste au-dessus de x2.5. LA POSE N'ETAIT PAS LA CAUSE, et je "
            "retire l'explication des cycles 53-54." if worst > 2.5
            else "P3 INDECISE : entre x1.5 et x2.5, ni tenue ni refutee.")))

# ---- P5 : l'ecart de CONFISCATION ----
print("\nP5  ECART DE CONFISCATION (k=1/k=0) ENTRE LES DEUX CHAINES, axe vertical")
conf = {}
for c, nm in ((0, 'chestL'), (1, 'chestR')):
    for s in (1, -1):
        v0, v1 = mean(c, 0, 0, s), mean(c, 1, 0, s)
        if v0 and v1:
            conf[(c, s)] = v1 / v0
            print("      %-7s s=%+d : %.4f -> %.4f   x%.2f   (predit par 1/sin : x%.2f)"
                  % (nm, s, v0, v1, v1 / v0,
                     1 / math.sin(math.acos(cos[(c, 0)])) if math.sin(math.acos(cos[(c, 0)])) > 1e-6 else float('inf')))
for s in (1, -1):
    if (0, s) in conf and (1, s) in conf:
        xl, xr = conf[(0, s)], conf[(1, s)]
        d = abs(xl - xr) / max(xl, xr)
        print("      s=%+d : |x_L - x_R| / max = %.3f  (critere P5 : <= 0.30) -> %s"
              % (s, d, "TENUE" if d <= 0.30 else "REFUTEE"))

# ---- temoins negatifs ----
print("\n    TEMOINS NEGATIFS (meme ablation k=1 sur les axes non alignes) :")
for c, nm in ((0, 'chestL'), (1, 'chestR')):
    for a in (1, 2):
        for s in (1, -1):
            v0, v1 = mean(c, 0, a, s), mean(c, 1, a, s)
            if v0 and v1:
                print("      %-7s %-4s s=%+d : x%.2f  (predit x%.2f)"
                      % (nm, ('vert', 'ap', 'lat')[a], s, v1 / v0,
                         1 / math.sin(math.acos(cos[(c, a)])) if math.sin(math.acos(cos[(c, a)])) > 1e-6 else float('inf')))
