#!/usr/bin/env python3
"""Prepend un bloc de cycle dans la 4e colonne d'une ligne de section de SPEC-COVERAGE.md.

Le registre est un ETAT, pas un historique : chaque cycle PREPEND son bloc en tete de la colonne
« Preuve / ce qui manque », les blocs anciens restent derriere. Ce script fait UNIQUEMENT cette
insertion, sans toucher au statut ; changer un statut est une decision, elle se fait a la main.

Usage : python3 .autoport/c131_prepend_coverage.py <numero-de-section> <fichier-contenant-le-bloc>
"""
import sys

PATH = '.autoport/SPEC-COVERAGE.md'

def main():
    if len(sys.argv) != 3:
        print(__doc__)
        return 2
    sec, blockfile = sys.argv[1], sys.argv[2]
    block = open(blockfile, encoding='utf-8').read().strip()
    lines = open(PATH, encoding='utf-8').read().split('\n')
    hits = [i for i, l in enumerate(lines)
            if l.startswith('| ') and l.split('|')[1].strip() == sec]
    if len(hits) != 1:
        print('ECHEC : %d ligne(s) pour la section %s (il en faut exactement 1)' % (len(hits), sec))
        return 1
    i = hits[0]
    cols = lines[i].split('|')
    if len(cols) < 5:
        print('ECHEC : la ligne %d n a pas 4 colonnes' % (i + 1))
        return 1
    before = len(cols[4])
    cols[4] = ' ' + block + ' ' + cols[4].strip()
    lines[i] = '|'.join(cols)
    open(PATH, 'w', encoding='utf-8').write('\n'.join(lines))
    print('section %s : ligne %d, colonne de preuve %d -> %d caracteres (+%d)'
          % (sec, i + 1, before, len(cols[4]), len(cols[4]) - before))
    return 0

if __name__ == '__main__':
    sys.exit(main())
