#!/usr/bin/env python3
"""c132_trace_compare.py — compare DEUX traces de la salle, corps `PHYS*` seulement.

Pourquoi pas un md5 du log : le fichier porte les HORODATAGES du prefixe de runtime sur ~21 000
lignes, donc deux courses IDENTIQUES au bit rendent deux md5 differents (etabli cycle 106).
L'empreinte d'une course est le corps `PHYS*`, rien d'autre.

Pourquoi une PRECONDITION avant la comparaison : la salle n'est deterministe qu'a CONDITIONS
INITIALES PARTAGEES (cycle 125). Si `PHYSROOM-START ... :state` ou la distance a l'origine du
sujet different, 79 % des enregistrements divergent quel que soit le lot teste, et la comparaison
ne parle plus de ce qu'on croit tester. Le script REFUSE la paire dans ce cas au lieu de publier
un chiffre qui ne veut rien dire.

Usage :  python3 .autoport/c132_trace_compare.py <A.log> <B.log>
Sortie :  code 0 si les corps sont identiques, 1 sinon (ou si la precondition echoue).
"""
import re
import sys


def body(path):
    out = []
    with open(path, 'rb') as fh:
        for raw in fh:
            ln = raw.decode('utf-8', 'replace').rstrip('\n')
            i = ln.find('PHYS')
            if i < 0:
                continue
            # on repart de `PHYS...` pour jeter le prefixe de runtime, qui porte l'horodatage
            out.append(ln[i:])
    return out


def initial_conditions(path):
    st, dist = None, None
    with open(path, 'rb') as fh:
        for raw in fh:
            ln = raw.decode('utf-8', 'replace')
            if st is None and 'PHYSROOM-START' in ln:
                m = re.search(r':state\s+(\S+)', ln)
                st = m.group(1) if m else '(aucun :state sur la ligne)'
            if dist is None and 'PHYSPOSED' in ln:
                m = re.search(r'dist-from-origin[= ]([0-9.]+)', ln)
                if m:
                    dist = m.group(1)
            if st is not None and dist is not None:
                break
    return st, dist


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        return 2
    a, b = sys.argv[1], sys.argv[2]

    ca, cb = initial_conditions(a), initial_conditions(b)
    print('CONDITIONS INITIALES')
    print('  A  state=%s  dist=%s  (%s)' % (ca[0], ca[1], a))
    print('  B  state=%s  dist=%s  (%s)' % (cb[0], cb[1], b))
    if ca != cb:
        print('REFUS: conditions initiales DIFFERENTES. La paire ne peut rien prouver sur le lot')
        print('       teste — 79 %% des enregistrements divergent alors (cycle 125). Relancer.')
        return 1

    ba, bb = body(a), body(b)
    print('ENREGISTREMENTS  A=%d  B=%d  communs=%d' % (len(ba), len(bb), min(len(ba), len(bb))))
    n = min(len(ba), len(bb))
    diff = [i for i in range(n) if ba[i] != bb[i]]
    print('DIFFERENTS sur la longueur commune : %d' % len(diff))
    for i in diff[:8]:
        print('  ligne %d\n    A: %s\n    B: %s' % (i + 1, ba[i][:160], bb[i][:160]))
    if len(ba) != len(bb):
        print('NOTE: longueurs differentes (%d vs %d) — une course a ete tronquee, ce qui n\'est'
              ' PAS une difference de comportement mais un defaut de course.' % (len(ba), len(bb)))
    ok = (not diff) and len(ba) == len(bb)
    print('VERDICT: %s' % ('IDENTIQUE AU BIT' if ok else 'DIFFERENT'))
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main())
