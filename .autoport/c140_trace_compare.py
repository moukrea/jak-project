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

NEW_TAGS = ('PHYSANROT ', 'PHYSANROTK ', 'PHYSANROTF ')


def strip_new(lines):
    return [ln for ln in lines if not ln.startswith(NEW_TAGS)]


def audit_new(lines_before):
    """Compte chaque tag retire DANS LA TRACE ANTERIEURE. La promesse du docstring (« rien
    d'autre n'est filtre, surtout pas une ligne qui EXISTAIT avant ») etait ecrite, pas verifiee :
    il suffisait d'ajouter un tag deja present pour effacer en silence une ligne qui a change.
    Elle est desormais MESUREE — un tag non nul ici n'est pas neuf, et le filtre le cacherait."""
    return [(t, sum(1 for ln in lines_before if ln.startswith(t))) for t in NEW_TAGS]


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
    # LE FILTRE SE JUSTIFIE AVANT DE S'APPLIQUER : chaque tag retire doit etre ABSENT de la trace
    # anterieure (A). Un tag present des deux cotes ne serait pas « neuf » et le retirer
    # masquerait une ligne qui a change — exactement ce que ce script est cense ne pas faire.
    presents = [(t, n) for t, n in audit_new(ra) if n]
    print('AUDIT DU FILTRE (occurrences dans A, la trace ANTERIEURE) : %s'
          % ', '.join('%s=%d' % (t.strip(), n) for t, n in audit_new(ra)))
    if presents:
        print('REFUS: %s existe(nt) DEJA dans A — ce ne sont pas des tags neufs, et les retirer'
              % ', '.join(t.strip() for t, _ in presents))
        print('       masquerait une difference reelle.')
        return 1
    ba, bb = strip_new(ra), strip_new(rb)
    print('TAGS NEUFS RETIRES  A=%d  B=%d  (PHYSANROT / PHYSANROTK / PHYSANROTF, cycle 140)'
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
