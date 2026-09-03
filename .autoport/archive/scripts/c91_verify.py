#!/usr/bin/env python3
"""c91_verify.py — LE CONTROLE DU CYCLE 91 : CE QUI A LE DROIT DE BOUGER, ET RIEN D'AUTRE.

DIRECTIVES v3fee554599.

LA PREDICTION EST PUBLIEE AVANT LA COURSE, ET ELLE PORTE SUR L'ETAT (piege
`bit-identity-prediction-must-cover-state`). Le filtre du cycle 91 ne touche QUE `dfb`, qui
n'entre QUE dans `*phys-dfm*`, qui n'entre QUE dans la partie 3x3 de la matrice d'os ecrite
(`jak-hd-physics.gc:3898-3906`) — la translation est reposee juste apres depuis `*phys-px/py/pz*`.
Aucune position simulee, aucune vitesse, aucune contrainte ne lit le tenseur.

DONC :
  * TOUT enregistrement construit sur les POSITIONS DE JOINTS doit etre IDENTIQUE AU BIT ;
  * seuls les enregistrements construits sur le TENSEUR, ou sur `bm` APRES son application, ont le
    droit de bouger — et ils DOIVENT bouger, sinon le correctif n'est pas actif (un zero des deux
    cotes serait un faux vert : `wired-but-disarmed`).

Une ligne qui bouge alors qu'elle est predite identique INVALIDE le cycle : cela voudrait dire que
le tenseur reboucle sur la simulation, ce que la lecture du source dit impossible.

Usage :  python3 .autoport/c91_verify.py <log-avant> <log-apres>
"""
import os
import re
import sys
from collections import OrderedDict

# predits IDENTIQUES : positions de joints, deviations squelettiques, geometrie, stimulus
IDENT = ['PHYSJTW', 'PHYSJTWK', 'PHYSJTWN', 'PHYSORICOML', 'PHYSORICOM', 'PHYSORICOM2',
         'PHYSORI', 'PHYSORI2', 'PHYSORI3', 'PHYSORI4', 'PHYSORITR', 'PHYSTRI',
         'PHYSRING', 'PHYSRINGA', 'PHYSRINGS', 'PHYSRINGAT', 'PHYSGRAD', 'PHYSGRADS',
         'PHYSRAD', 'PHYSRADL', 'PHYSRADLD', 'PHYSRADLE', 'PHYSSTG', 'PHYSSTGW',
         'PHYSREST', 'PHYSREST2', 'PHYSRESTW', 'PHYSRESTS', 'PHYSSTR', 'PHYSCOMWL',
         'PHYSCOMW', 'PHYSCOMD', 'PHYSCOMDL', 'PHYSBONE', 'PHYSCHAIN', 'PHYSJOINT',
         'PHYSANIM', 'PHYSAXIS', 'PHYSACC', 'PHYSPOSEFB', 'PHYSPOSEF']
# predits DIFFERENTS : le tenseur, et tout ce qui se lit sur `bm` APRES lui
MOVE = ['PHYSDFMA', 'PHYSCTLDF', 'PHYSAPEX', 'PHYSAPEX2', 'PHYSAPEXD', 'PHYSAPEXR',
        'PHYSAPEXT', 'PHYSSHAPE', 'PHYSSHAPE2', 'PHYSSHAPE3', 'PHYSSHAPE4', 'PHYSSHAPE5',
        'PHYSSHAPE6', 'PHYSSHAPE7', 'PHYSSHAPE8', 'PHYSSHAPE9']


def bucket(path):
    out = OrderedDict()
    with open(path, errors='replace') as f:
        for line in f:
            if not line.startswith('PHYS'):
                continue
            tag = re.match(r'^(PHYS[A-Z0-9]*)', line)
            if tag:
                out.setdefault(tag.group(1), []).append(line.rstrip('\n'))
    return out


def main():
    a, b = sys.argv[1], sys.argv[2]
    A, B = bucket(a), bucket(b)
    print('DIRECTIVES v3fee554599')
    print('')
    print('C91 — CONTROLE DE BIT-IDENTITE, PREDICTION PUBLIEE AVANT LA COURSE')
    print('=' * 100)
    print('avant : %s' % a)
    print('apres : %s' % b)
    print('')
    tags = sorted(set(A) | set(B))
    bad_ident, ok_move, mute_move, other = [], [], [], []
    print('%-16s %8s %8s %9s   %s' % ('tag', 'n avant', 'n apres', 'lignes !=', 'verdict'))
    for t in tags:
        la, lb = A.get(t, []), B.get(t, [])
        if len(la) != len(lb):
            diff = max(len(la), len(lb))
        else:
            diff = sum(1 for x, y in zip(la, lb) if x != y)
        pred = 'IDENTIQUE' if t in IDENT else ('BOUGE' if t in MOVE else '-')
        if t in IDENT:
            v = 'OK' if diff == 0 else '**ECHEC : predit identique, %d lignes changent**' % diff
            (bad_ident if diff else other).append(t)
        elif t in MOVE:
            v = ('OK' if diff else '**MUET : predit different, aucune ligne ne change**')
            (ok_move if diff else mute_move).append(t)
        else:
            v = 'non predit'
            other.append(t)
        print('%-16s %8d %8d %9d   %-9s %s' % (t, len(la), len(lb), diff, pred, v))
    print('')
    print('PREDICTION « IDENTIQUE » : %d tag(s) en echec %s'
          % (len(bad_ident), ('-> ' + ', '.join(bad_ident)) if bad_ident else '(aucun)'))
    print('PREDICTION « BOUGE »     : %d tag(s) muets %s'
          % (len(mute_move), ('-> ' + ', '.join(mute_move)) if mute_move else '(aucun)'))
    return 1 if (bad_ident or mute_move) else 0


if __name__ == '__main__':
    sys.exit(main())
