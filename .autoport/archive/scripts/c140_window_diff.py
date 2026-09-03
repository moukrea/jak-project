#!/usr/bin/env python3
"""c140_window_diff.py — OU la course B differe de la course A, fenetre par fenetre.

POURQUOI CE N'EST PAS LA MEME CHOSE QUE `c140_trace_compare.py`. Celui-la repond « les deux
courses sont-elles identiques ? ». Celui-ci repond a la question qui decide si un operateur est
un SCALPEL : **agit-il exactement la ou la mesure a dit qu'il agirait, et nulle part ailleurs ?**
Un operateur qui change des fenetres que sa propre condition de declenchement ne designe pas est
hors de controle, quelle que soit la taille de son effet.

Les enregistrements `PHYS*` portent presque tous `c=<chaine> a=<animation> d=<pilotage>` : c'est
la cle de fenetre. Les lignes qui n'en portent pas sont comptees a part et NON ignorees en
silence — une difference qui vit hors de toute fenetre serait le plus interessant des resultats.

Usage : python3 .autoport/c140_window_diff.py <A.log> <B.log> [a:d,a:d,...]
        Le 3e argument est la liste des fenetres ATTENDUES comme differentes.
"""
import re
import sys
import collections

KEY = re.compile(r'^(PHYS[A-Z0-9-]*) c=(\d+) a=(\d+) d=(\d+)')


def load(path):
    keyed = collections.defaultdict(list)
    loose = []
    with open(path, 'rb') as fh:
        for raw in fh:
            ln = raw.decode('utf-8', 'replace').rstrip('\n')
            i = ln.find('PHYS')
            if i < 0:
                continue
            ln = ln[i:]
            m = KEY.match(ln)
            if m:
                keyed[(int(m.group(3)), int(m.group(4)))].append(ln)
            else:
                loose.append(ln)
    return keyed, loose


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    ka, la = load(sys.argv[1])
    kb, lb = load(sys.argv[2])
    expected = set()
    if len(sys.argv) > 3 and sys.argv[3].strip():
        for tok in sys.argv[3].split(','):
            a, d = tok.split(':')
            expected.add((int(a), int(d)))

    allk = sorted(set(ka) | set(kb))
    diff = [k for k in allk if ka.get(k) != kb.get(k)]
    print('FENETRES  A=%d  B=%d  union=%d' % (len(ka), len(kb), len(allk)))
    print('FENETRES DIFFERENTES : %d' % len(diff))
    for k in diff[:40]:
        na, nb = len(ka.get(k, [])), len(kb.get(k, []))
        nd = sum(1 for x, y in zip(ka.get(k, []), kb.get(k, [])) if x != y)
        print('   a=%-3d d=%d   lignes A=%d B=%d  differentes=%d%s'
              % (k[0], k[1], na, nb, nd, '   <-- ATTENDUE' if k in expected else '   <-- INATTENDUE'))
    if expected:
        got = set(diff)
        extra = sorted(got - expected)
        missing = sorted(expected - got)
        print('INATTENDUES : %d %s' % (len(extra), extra[:20]))
        print('ATTENDUES ET IDENTIQUES : %d %s' % (len(missing), missing[:20]))
        print('VERDICT PORTEE : %s'
              % ('L\'OPERATEUR N\'AGIT QUE LA OU SA CONDITION LE DESIGNE'
                 if not extra else
                 'HORS DE CONTROLE : il change des fenetres que sa condition ne designe pas'))
    print('LIGNES HORS FENETRE  A=%d  B=%d  differentes=%d'
          % (len(la), len(lb), sum(1 for x, y in zip(la, lb) if x != y) + abs(len(la) - len(lb))))
    return 0


if __name__ == '__main__':
    sys.exit(main())
