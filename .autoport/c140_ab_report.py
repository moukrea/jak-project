#!/usr/bin/env python3
"""c140_ab_report.py — les chiffres du cycle 140, en une passe et sans intermediaire manuel.

Entrees : la course ARMEE (B) et la course du cycle 139 (avant le lot). Sortie : les grandeurs que
le rapport publie, chacune avec son unite et sa portee. Rien n'est arrondi ici pour faire joli :
les nombres sortent tels que la trace les porte.

Usage : python3 .autoport/c140_ab_report.py <B.log> <c139.log> [runA-anrot.txt]
"""
import math
import re
import sys
import collections

B0 = 602.0  # SPEC 6, mesure sur le maillage livre — la meme constante que le fichier de chaines
DRIVES = {0: 'updown', 1: 'leftright', 2: 'accel', 3: 'jerk', 4: 'tilt', 5: 'BASE-0stim'}


def omc2deg(v):
    return math.degrees(math.acos(max(-1.0, min(1.0, 1.0 - v / 1000.0))))


def grab(path, pat):
    out = []
    with open(path, 'rb') as fh:
        for raw in fh:
            ln = raw.decode('utf-8', 'replace')
            m = pat.search(ln)
            if m:
                out.append(m.groups())
    return out


P_ANROT = re.compile(r'^PHYSANROT c=(\d+) a=(\d+) d=(\d+) omcmax=([-\d.e+]+) nrot=([-\d.e+]+)'
                     r' nfr=([-\d.e+]+)', re.M)
P_ANROTF = re.compile(r'^PHYSANROTF c=(\d+) a=(\d+) d=(\d+) rbfix=([-\d.e+]+)', re.M)
P_ANROTK = re.compile(r'^PHYSANROTK c=(\d+) rbt=([-\d.e+]+)', re.M)
P_REB = re.compile(r'^PHYSREBASE c=(\d+) a=(\d+) d=(\d+) fired=([-\d.e+]+) amax=([-\d.e+]+)', re.M)
P_APEX = re.compile(r'^PHYSAPEX c=(\d+) a=(\d+) d=(\d+) apex=([-\d.e+]+)', re.M)


def main():
    b, base = sys.argv[1], sys.argv[2]
    anrot = grab(b, P_ANROT)
    print('== 1. LA POPULATION DE LA ROTATION D\'ANCRE (course ARMEE) ==')
    by = collections.defaultdict(list)
    for c, a, d, om, nr, nf in anrot:
        by[int(d)].append((float(om), float(nr), float(nf)))
    print('%-11s %4s %9s %9s %9s %11s %10s %8s' %
          ('pilotage', 'n', 'p50 deg', 'p90 deg', 'max deg', 'franchies', 'evaluees', 'part%'))
    tf = tn = 0
    for d in sorted(by):
        v = sorted(x[0] for x in by[d])
        n = len(v)
        f = sum(x[1] for x in by[d])
        e = sum(x[2] for x in by[d])
        tf += f
        tn += e
        print('%-11s %4d %9.2f %9.2f %9.2f %11d %10d %8.3f' %
              (DRIVES.get(d, d), n, omc2deg(v[n // 2]), omc2deg(v[int(0.9 * n)]), omc2deg(v[-1]),
               f, e, 100.0 * f / e))
    print('TOTAL franchies=%d evaluees=%d part=%.4f%%' % (tf, tn, 100.0 * tf / tn))
    print('rbt depose par le parseur : %s' % dict((int(c), float(v)) for c, v in grab(b, P_ANROTK)))

    if len(sys.argv) > 3:
        A = {}
        for ln in open(sys.argv[3]):
            p = ln.split()
            A[(p[0], p[1], p[2])] = (p[3], p[4], p[5])
        same = tot = 0
        for c, a, d, om, nr, nf in anrot:
            k = (c, a, d)
            if k in A:
                tot += 1
                if A[k] == (om, nr, nf):
                    same += 1
        print('== 2. B2 — IDENTITE DE LA MESURE ENTRE COURSE DESARMEE ET COURSE ARMEE ==')
        print('   fenetres appariees=%d  identiques (omcmax, nrot, nfr)=%d' % (tot, same))

    print('== 3. LE REBASE : AVANT (c139) / APRES (B), PAR ANIMATION ==')
    def reb(path):
        r = {}
        for c, a, d, f, am in grab(path, P_REB):
            r[(int(c), int(a), int(d))] = (float(f), float(am))
        return r
    rb, ra = reb(b), reb(base)
    fa = sum(v[0] for v in ra.values())
    fb = sum(v[0] for v in rb.values())
    print('   frames rebasees : c139 = %d   ->   B = %d   (delta %+d)' % (fa, fb, fb - fa))
    neuves = sorted(k for k in rb if rb[k][0] > 0 and ra.get(k, (0, 0))[0] == 0)
    perdues = sorted(k for k in ra if ra[k][0] > 0 and rb.get(k, (0, 0))[0] == 0)
    print('   fenetres NEUVES : %s' % [(k[1], k[2]) for k in neuves])
    print('   fenetres PERDUES : %s' % [(k[1], k[2]) for k in perdues])

    print('== 4. `rbfix` — LA TAILLE DE L\'IMPULSION RETIREE, PAR FENETRE ==')
    fx = [(int(c), int(a), int(d), float(v)) for c, a, d, v in grab(b, P_ANROTF)]
    hot = sorted([x for x in fx if x[3] > 0], key=lambda x: (x[1], x[2], x[0]))
    for c, a, d, v in hot:
        tag = 'ROTATION SEULE' if ra.get((c, a, d), (0, 0))[0] == 0 else 'distance deja active'
        print('   c=%d a=%-3d d=%d   rbfix=%12.4f u = %7.4f B0   [%s]' % (c, a, d, v, v / B0, tag))
    rot_only = [x for x in hot if ra.get((x[0], x[1], x[2]), (0, 0))[0] == 0]
    if rot_only:
        vs = sorted(x[3] for x in rot_only)
        print('   ROTATION SEULE : n=%d  min=%.4f B0  median=%.4f B0  max=%.4f B0'
              % (len(vs), vs[0] / B0, vs[len(vs) // 2] / B0, vs[-1] / B0))

    print('== 5. APEX : B contre c139, DANS et HORS les fenetres touchees ==')
    def apex(path):
        r = {}
        for c, a, d, v in grab(path, P_APEX):
            r[(int(c), int(a), int(d))] = float(v)
        return r
    ab, aa = apex(b), apex(base)
    touched = {(c, a, d) for c, a, d, v in fx if v > 0}
    for c in (0, 1):
        ins = [(k, aa[k], ab[k]) for k in sorted(ab) if k[0] == c and k in aa and k in touched]
        out = [(k, aa[k], ab[k]) for k in sorted(ab) if k[0] == c and k in aa and k not in touched]
        chg_in = sum(1 for k, x, y in ins if x != y)
        chg_out = sum(1 for k, x, y in out if x != y)
        print('   chaine c=%d : DANS n=%d changees=%d   HORS n=%d changees=%d'
              % (c, len(ins), chg_in, len(out), chg_out))
        for k, x, y in ins:
            if x != y:
                print('      a=%-3d d=%d  apex %.4f -> %.4f  (%+.4f B0)' % (k[1], k[2], x, y, y - x))
        allb = sorted(v for k, v in ab.items() if k[0] == c)
        alla = sorted(v for k, v in aa.items() if k[0] == c)
        print('      p50 %.4f -> %.4f   max %.4f -> %.4f (B0)'
              % (alla[len(alla) // 2], allb[len(allb) // 2], alla[-1], allb[-1]))
    return 0


if __name__ == '__main__':
    sys.exit(main())
