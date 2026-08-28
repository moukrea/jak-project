#!/usr/bin/env python3
"""c148_compare.py — AVANT/APRES du lot « mur de force de §21 » (cycle 148).

Ne juge rien tout seul : il rapproche deux tableaux deja produits par
.autoport/physics_room_table.py et publie, prediction par prediction, ce que la
course rend. Les deux fichiers sont passes en argument (avant, apres).
"""
import re, sys, math
from collections import Counter

def load(p):
    return open(p, encoding='utf-8', errors='replace').read().splitlines()

RE_REGLIM = re.compile(r'^ROOM-REGLIM: +(\S+) +(\S+) +(\d+) +(\S+) +([\d.]+) +([\d.]+) +(LINEAIRE|GENOU|GELE)')
RE_APEX   = re.compile(r'^ROOM-APEX-REGIME: (\S+) +r= ?(\d+) (\S+) +apex=([\d.]+) B0(.*)$')

def reglim(lines):
    out = {}
    for l in lines:
        m = RE_REGLIM.match(l)
        if m:
            key = (m.group(1), m.group(2), int(m.group(3)))
            out.setdefault(key, []).append((float(m.group(6)), m.group(7)))
    return out

def apex(lines):
    out = {}
    for l in lines:
        m = RE_APEX.match(l)
        if m:
            tail = m.group(5)
            v = ('AU-DESSUS' if 'AU-DESSUS' in tail else
                 'SOUS' if 'SOUS' in tail else
                 'DANS' if '-> DANS' in tail else 'SANS-BANDE')
            out[(m.group(1), int(m.group(2)))] = (float(m.group(4)), v, m.group(3))
    return out

def block(lines, prefixes):
    return [l for l in lines if any(l.startswith(p) for p in prefixes)]

def fisher2x2(a, b, c, d):
    """p bilateral exact sur [[a,b],[c,d]]."""
    def C(n, k):
        return math.comb(n, k) if 0 <= k <= n else 0
    n = a + b + c + d
    r1, c1 = a + b, a + c
    tot = C(n, c1)
    def P(x):
        return C(r1, x) * C(n - r1, c1 - x) / tot
    p0 = P(a)
    lo, hi = max(0, c1 - (n - r1)), min(r1, c1)
    return sum(P(x) for x in range(lo, hi + 1) if P(x) <= p0 * (1 + 1e-9))

A, B = load(sys.argv[1]), load(sys.argv[2])

print('=' * 92)
print('CYCLE 148 — AVANT/APRES DU MUR DE FORCE DE §21')
print('  avant : %s\n  apres : %s' % (sys.argv[1], sys.argv[2]))
print('=' * 92)

# --- P2 : la classe gelee -----------------------------------------------------------------
for tag, L in (('AVANT', A), ('APRES', B)):
    c = Counter(cls for v in reglim(L).values() for _, cls in v)
    tot = sum(c.values())
    print('P2 %s  REGLIM %3d cellules : %3d LINEAIRE · %3d GENOU · %3d GELE  (%.1f %% gelees)'
          % (tag, tot, c['LINEAIRE'], c['GENOU'], c['GELE'], 100.0 * c['GELE'] / max(1, tot)))

# --- P3 : le pire perr --------------------------------------------------------------------
for tag, L in (('AVANT', A), ('APRES', B)):
    rows = [(perr, k) for k, v in reglim(L).items() for perr, _ in v]
    if rows:
        perr, k = max(rows)
        print('P3 %s  pire perr = %.4f B0  sur %s' % (tag, perr, k))

# --- P1/P4 : les cellules d'apex, une par une ---------------------------------------------
ra, rb = reglim(A), reglim(B)
aa, ab = apex(A), apex(B)
cls_before = {}
for (ph, ch, r), v in ra.items():
    if ph == 'PH-REG':
        cls_before[(ch, r)] = v[0][1]
print('\nP1/P4  LES CELLULES DE PH-REG, PAR REGIME (classe = celle d\'AVANT)')
print('  %-8s %2s %-14s %-9s %8s %8s %9s   %s' % ('chaine', 'r', 'regime', 'classe', 'apexA', 'apexB', 'delta', 'verdict A -> B'))
chg = same = 0
for k in sorted(aa, key=lambda x: (x[1], x[0])):
    if k not in ab:
        continue
    va, vb = aa[k], ab[k]
    cls = cls_before.get(k, '?')
    d = (vb[0] - va[0]) / va[0] * 100.0 if va[0] else 0.0
    ident = abs(vb[0] - va[0]) < 5e-5
    if ident:
        same += 1
    else:
        chg += 1
    print('  %-8s %2d %-14s %-9s %8.4f %8.4f %+8.2f%%   %-9s -> %-9s%s'
          % (k[0], k[1], va[2], cls, va[0], vb[0], d, va[1], vb[1],
             '   IDENTIQUE' if ident else ''))
print('  -> %d cellule(s) identique(s) a 5e-5, %d changee(s)' % (same, chg))

# --- le croisement gele x verdict, avant et apres ------------------------------------------
for tag, ap in (('AVANT', aa), ('APRES', ab)):
    t = {}
    for k, v in ap.items():
        if v[1] == 'SANS-BANDE':
            continue
        cls = cls_before.get(k, '?')
        t[('GELE' if cls == 'GELE' else 'NON-GELE', v[1])] = t.get(('GELE' if cls == 'GELE' else 'NON-GELE', v[1]), 0) + 1
    g_up = t.get(('GELE', 'AU-DESSUS'), 0); g_no = t.get(('GELE', 'DANS'), 0) + t.get(('GELE', 'SOUS'), 0)
    n_up = t.get(('NON-GELE', 'AU-DESSUS'), 0); n_no = t.get(('NON-GELE', 'DANS'), 0) + t.get(('NON-GELE', 'SOUS'), 0)
    p = fisher2x2(g_up, g_no, n_up, n_no) if (g_up + g_no) and (n_up + n_no) else float('nan')
    print('\n  CROISEMENT %s (classe du mur mesuree AVANT le lot) :' % tag)
    print('    GELE     : %2d AU-DESSUS · %2d autre' % (g_up, g_no))
    print('    NON GELE : %2d AU-DESSUS · %2d autre     Fisher exact bilateral p = %.4f' % (n_up, n_no, p))

# --- ROOM-REGA-BANDE : la pose dont le miroir EST valide (0,50 deg) -------------------------
RE_REGA = re.compile(r'^ROOM-REGA-BANDE: (\S+) r=(\d+) +sgn=(\S+) +§(\d+) +apex=([\d.]+) B0 +\[([^\]]*)\](.*)$')
def rega(lines):
    out = {}
    for l in lines:
        m = RE_REGA.match(l)
        if m:
            tail = m.group(7)
            v = ('AU-DESSUS' if 'AU-DESSUS' in tail else 'SOUS' if 'SOUS' in tail else
                 'DANS' if 'DANS' in tail else 'SANS-BANDE')
            cls = ('GELE' if '| GELE' in tail else 'GENOU' if '| GENOU' in tail else
                   'LINEAIRE' if '| LINEAIRE' in tail else '?')
            out[(m.group(1), int(m.group(2)), m.group(3))] = (float(m.group(5)), v, m.group(4), cls, m.group(6))
    return out

ga, gb = rega(A), rega(B)
print('\nREGA  LA POSE DONT LE MIROIR EST VALIDE — LES CELLULES QUI PORTENT §18/§19/§20')
print('  %-8s %2s %-5s %-4s %-11s %-9s %8s %8s %9s   %s'
      % ('chaine', 'r', 'sgn', 'sec', 'bande', 'classe A', 'apexA', 'apexB', 'delta', 'verdict A -> B'))
for k in sorted(ga, key=lambda x: (int(ga[x][2]), x[1], x[0], x[2])):
    if k not in gb or ga[k][1] == 'SANS-BANDE':
        continue
    va, vb = ga[k], gb[k]
    d = (vb[0] - va[0]) / va[0] * 100.0 if va[0] else 0.0
    ident = abs(vb[0] - va[0]) < 5e-5
    print('  %-8s %2d %-5s §%-3s %-11s %-9s %8.4f %8.4f %+8.2f%%   %-9s -> %-9s%s'
          % (k[0], k[1], k[2], va[2], va[4], va[3], va[0], vb[0], d, va[1], vb[1],
             '   IDENTIQUE' if ident else ''))
for tag, g in (('AVANT', ga), ('APRES', gb)):
    t = Counter()
    for k, v in g.items():
        if v[1] == 'SANS-BANDE':
            continue
        t[(ga[k][3], v[1])] += 1          # classe TOUJOURS celle d'AVANT
    gu = t[('GELE', 'AU-DESSUS')] + t[('GENOU', 'AU-DESSUS')]
    go = sum(v for (c, w), v in t.items() if c in ('GELE', 'GENOU') and w != 'AU-DESSUS')
    lu = t[('LINEAIRE', 'AU-DESSUS')]
    lo = sum(v for (c, w), v in t.items() if c == 'LINEAIRE' and w != 'AU-DESSUS')
    p = fisher2x2(gu, go, lu, lo) if (gu + go) and (lu + lo) else float('nan')
    print('  REGA %s : au-dessus du genou %2d AU-DESSUS / %2d autre · sous le genou %2d / %2d'
          '   Fisher p = %.4f' % (tag, gu, go, lu, lo, p))
for tag, g in (('AVANT', ga), ('APRES', gb)):
    for sec in ('18', '19', '20'):
        cs = [v for v in g.values() if v[2] == sec and v[1] != 'SANS-BANDE']
        if cs:
            print('  §%s %s : %d cellule(s) — %d DANS · %d AU-DESSUS · %d SOUS'
                  % (sec, tag, len(cs), sum(1 for c in cs if c[1] == 'DANS'),
                     sum(1 for c in cs if c[1] == 'AU-DESSUS'), sum(1 for c in cs if c[1] == 'SOUS')))
for l in B:
    if l.startswith('ROOM-REGA-FACTEUR'):
        print('  APRES  ' + l.strip())

# --- P6 : les familles que le c147 a trouvees identiques au bit ----------------------------
print('\nP6  LES FAMILLES QUE LE CYCLE 147 A TROUVEES IDENTIQUES AU BIT')
for name, pref in (('ROOM-AXFIT', ('ROOM-AXFIT',)), ('ROOM-RINGFIT', ('ROOM-RINGFIT',)),
                   ('ROOM-RINGDOWN', ('ROOM-RINGDOWN',)), ('ROOM-SETTLE', ('ROOM-SETTLE',)),
                   ('ROOM-ORICOM-MASS', ('ROOM-ORICOM-MASS',)), ('ROOM-IDLE', ('ROOM-IDLE',)),
                   ('ROOM-SKINPEN', ('ROOM-SKINPEN',))):
    x, y = block(A, pref), block(B, pref)
    n = sum(1 for u, v in zip(x, y) if u != v)
    print('  %-18s %3d lignes A / %3d lignes B  ->  %s'
          % (name, len(x), len(y),
             'IDENTIQUE AU BIT' if (x == y) else '%d ligne(s) differente(s)' % (n + abs(len(x) - len(y)))))

# --- les compteurs -------------------------------------------------------------------------
print('\nP0  COMPTEURS')
for tag, L in (('AVANT', A), ('APRES', B)):
    for l in L:
        if l.startswith('ROOM-LIM-RESSORT: stif_n') or l.startswith('ROOM-LIM-FWSAT'):
            print('  %s  %s' % (tag, l.strip()))
