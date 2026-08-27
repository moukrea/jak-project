#!/usr/bin/env python3
"""c140_trace_compare.py — comme c132_trace_compare.py, mais SANS les tags NEUFS du cycle 140.

POURQUOI CE FICHIER EXISTE, ET POURQUOI CE N'EST PAS UNE COMPLAISANCE. La comparaison de c132 est
POSITIONNELLE : elle apparie la n-ieme ligne `PHYS*` de A avec la n-ieme de B. Un lot qui AJOUTE
un emetteur decale donc tout ce qui suit sa premiere emission, et la comparaison rendrait « 99 %%
de lignes differentes » sur un solveur strictement inchange — un faux rouge, et le pire genre :
celui qui a l'air d'une preuve d'effet.

Ce que ce script retire, il le retire des DEUX cotes et il le NOMME : les deux tags que le cycle
140 vient de creer et qui, par construction, ne peuvent pas exister dans une trace anterieure.
Rien d'autre n'est filtre — surtout pas une ligne qui EXISTAIT avant et qui aurait change.

Usage :  python3 .autoport/c140_trace_compare.py <A.log> <B.log>
"""
import sys

sys.path.insert(0, '.autoport')
from c132_trace_compare import body, initial_conditions  # noqa: E402

NEW_TAGS = ('PHYSANROT ', 'PHYSANROTK ')


def strip_new(lines):
    return [ln for ln in lines if not ln.startswith(NEW_TAGS)]


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
        print('REFUS: conditions initiales DIFFERENTES (cycle 125). La paire ne prouve rien.')
        return 1
    ra, rb = body(a), body(b)
    ba, bb = strip_new(ra), strip_new(rb)
    print('TAGS NEUFS RETIRES  A=%d  B=%d  (PHYSANROT / PHYSANROTK, cycle 140)'
          % (len(ra) - len(ba), len(rb) - len(bb)))
    print('ENREGISTREMENTS COMPARES  A=%d  B=%d' % (len(ba), len(bb)))
    n = min(len(ba), len(bb))
    diff = [i for i in range(n) if ba[i] != bb[i]]
    print('DIFFERENTS sur la longueur commune : %d' % len(diff))
    for i in diff[:10]:
        print('  ligne %d\n    A: %s\n    B: %s' % (i + 1, ba[i][:170], bb[i][:170]))
    if len(ba) != len(bb):
        print('NOTE: longueurs differentes (%d vs %d) — une course tronquee, PAS un effet.'
              % (len(ba), len(bb)))
    ok = (not diff) and len(ba) == len(bb)
    print('VERDICT: %s' % ('IDENTIQUE AU BIT (hors tags neufs)' if ok else 'DIFFERENT'))
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main())
