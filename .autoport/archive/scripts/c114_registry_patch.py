#!/usr/bin/env python3
"""c114_registry_patch.py — amende les cellules du registre touchees par le cycle 114.

PUREMENT ADDITIF : le texte du cycle est insere EN TETE de la colonne de notes, les notes
existantes sont conservees mot pour mot, et AUCUN statut n'est change. Le script verifie les deux
proprietes apres ecriture et refuse d'ecrire s'il en casse une — un patch de registre qui perd une
note ancienne est la faute du cycle 56, et elle ne se detecte pas a l'oeil sur 300 Ko.
"""
import re
import sys

PATH = '.autoport/SPEC-COVERAGE.md'

NOTES = {}   # rempli par --note SEC=texte


def cells(text):
    """Rend {numero: (ligne_index, champs)} pour les lignes de tableau `| N | ... |`."""
    out = {}
    for i, ln in enumerate(text.split('\n')):
        m = re.match(r'^\| *(\d+) +\|', ln)
        if m:
            f = ln.split('|')
            out[int(m.group(1))] = (i, f)
    return out


def main():
    args = sys.argv[1:]
    for a in args:
        sec, _, txt = a.partition('=')
        NOTES[int(sec)] = txt
    text = open(PATH, encoding='utf-8').read()
    lines = text.split('\n')
    C = cells(text)
    before = {n: (C[n][1][3].strip(), len(C[n][1][4])) for n in NOTES if n in C}
    for n, txt in NOTES.items():
        if n not in C:
            print('section %d absente du registre' % n)
            return 2
        i, f = C[n]
        f[4] = ' ' + txt + ' ' + f[4].strip() + ' '
        lines[i] = '|'.join(f)
    out = '\n'.join(lines)
    C2 = cells(out)
    for n in NOTES:
        st, ln0 = before[n]
        st2 = C2[n][1][3].strip()
        ln2 = len(C2[n][1][4])
        if st != st2:
            print('REFUS : le statut de la section %d a change (%s -> %s)' % (n, st, st2))
            return 3
        if ln2 <= ln0:
            print('REFUS : la note de la section %d a RETRECI (%d -> %d)' % (n, ln0, ln2))
            return 3
    open(PATH, 'w', encoding='utf-8').write(out)
    print('registre amende : sections %s, statuts inchanges, notes purement additives'
          % ', '.join(str(n) for n in sorted(NOTES)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
