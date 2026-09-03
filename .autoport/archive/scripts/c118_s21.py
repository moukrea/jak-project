#!/usr/bin/env python3
"""Cycle 118 — |s| = D_linear + D_angular et |e| = apex, AVANT et APRES la borne de SPEC 21.
NATURE : des normes de VECTEURS en unites de B0 (602 u), sans dimension.
REPERE : le monde, contre la pose d'AUTEUR de la MEME frame — le repere de `apex`.
Les quatre termes sont latches au MEME argmax (jak-hd-physics.gc, meme bloc `when`).
LECTURE HORS DEFAUT : 0.0000 partout a la pose d'auteur.
Ce script NE JUGE RIEN : il lit deux traces et publie la meme statistique sur les deux."""
import re, sys, math

def load(p):
    L = open(p, errors='ignore').read()
    def grab(tag, keys):
        d = {}
        pat = r'^%s c=(\d+) a=(\d+) d=(\d+) ' % tag + ' '.join(k + r'=(\S+)' for k in keys)
        for m in re.finditer(pat, L, re.M):
            g = m.groups()
            d[(int(g[0]), int(g[1]), int(g[2]))] = tuple(float(x) for x in g[3:])
        return d
    A = grab('PHYSAPEX', ['apex', 'ax', 'ay']); A2 = grab('PHYSAPEX2', ['az', 'cydn', 'cyup'])
    T = grab('PHYSAPEXT', ['tx', 'ty', 'tz']); D = grab('PHYSAPEXD', ['dx', 'dy', 'dz'])
    out = {}
    for k in A:
        if k in A2 and k in T and k in D:
            out.setdefault(k[0], []).append((k, (A[k][1], A[k][2], A2[k][0]), T[k], D[k], A[k][0]))
    return out

def n3(v): return math.sqrt(sum(x * x for x in v))

def stats(vals):
    v = sorted(vals); n = len(v)
    return v[n // 2], v[min(n - 1, int(0.9 * n))], v[-1]

for c in (0, 1):
    name = ['chestL', 'chestR'][c]
    print("  ---- %s" % name)
    for lbl, p in (('AVANT (c117)', sys.argv[1]), ('APRES (c118)', sys.argv[2])):
        cells = load(p).get(c, [])
        if not cells:
            print("    %-13s : aucune cellule" % lbl); continue
        S = []; E = []; TP = []; RP = []; DP = []; ID = 0.0
        for k, e, tp, dp, apex in cells:
            rp = tuple(e[i] - tp[i] - dp[i] for i in range(3))
            s = tuple(e[i] - dp[i] for i in range(3))
            S.append(n3(s)); E.append(n3(e)); TP.append(n3(tp)); RP.append(n3(rp)); DP.append(n3(dp))
            ID = max(ID, abs(n3(e) - apex))
        n = len(S)
        print("    %-13s n=%d  identite |e|-apex = %.6f B0" % (lbl, n, ID))
        for nm, arr in (('|s| §21 ', S), ('|e| apex', E), ('|tp|    ', TP), ('|rp|    ', RP), ('|dp|    ', DP)):
            m50, m90, mx = stats(arr)
            print("      %s p50 %.4f  p90 %.4f  max %.4f   >0.42 %3d/%d  >0.50 %3d/%d"
                  % (nm, m50, m90, mx,
                     sum(1 for x in arr if x > 0.42), n, sum(1 for x in arr if x > 0.50), n))
