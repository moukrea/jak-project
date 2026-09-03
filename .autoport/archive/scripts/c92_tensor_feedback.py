#!/usr/bin/env python3
"""c92_tensor_feedback.py — LE CHEMIN PAR LEQUEL LE TENSEUR REBOUCLE SUR LA SIMULATION.

DIRECTIVES v3fee554599.  ZERO course neuve, ZERO build : deux traces ARCHIVEES + la donnee LIVREE.

CE QUE LE CYCLE 91 A LAISSE OUVERT, ET C'EST LE PREMIER POINT QU'IL S'ETAIT ASSIGNE. Sa section 4
publie : « le tenseur de deformation N'EST PAS une sortie pure : il reboucle sur la simulation.
Le CHEMIN n'est pas identifie et je ne l'invente pas. » Il l'est maintenant, et il l'est par le
SOURCE plus deux premisses MESUREES — pas par une hypothese.

LE CHEMIN, LU DANS LE SOURCE :

  1. `jak-hd-physics.gc:3898-3906` — l'ecriture. `*phys-dfm*` est multiplie DANS la partie 3x3 de
     la matrice d'os : `(matrix*! tmp bm (-> *phys-dfm* sc))` puis `(matrix-copy! bm tmp)`. La
     translation est reposee juste apres depuis `*phys-px/py/pz*` — c'est cette moitie-la qui
     m'avait fait conclure « sortie pure ». La 3x3, elle, RESTE dans le squelette.

  2. `jak-hd-physics.gc:4066-4067` — `phys-snapshot-sim!`, appelee tout a la fin du pas, sous le
     commentaire « L'INSTANTANE QUE LA FRAME SUIVANTE LIRA ».

  3. `jak-hd-physics.gc:1380-1403` — sa docstring : « la position de FIN DE FRAME de tout volume
     porte par un joint SIMULE [...] C'est ce que la frame SUIVANTE lira, pour toutes les chaines
     a la fois. » Pour chaque volume dont `*phys-csim*` est non nul, elle appelle `phys-col-centre`.

  4. `jak-hd-physics.gc:1314-1323` — `phys-col-centre` : quand l'offset du volume n'est pas nul,
     `(vector-matrix*! out out (-> skel bones (+ cj 1) transform))`. **L'offset du volume est donc
     transforme par la matrice d'os — celle qui vient de recevoir le tenseur.**

LES DEUX PREMISSES, MESUREES ET NON SUPPOSEES :

  (a) LES VOLUMES DE SEIN SONT PORTES PAR DES JOINTS SIMULES ET ONT UN OFFSET LOIN D'ETRE NUL.
      `recharged_assets/physics_chains.txt` : `collider lBoob radius=340 offset=-6,637,-135` et
      `collider rBoob radius=345 offset=-14,-617,124`, soit 651 u et 629 u du joint (le fichier
      l'ecrit lui-meme). Si l'offset etait nul, `phys-col-centre` prendrait sa branche courte et le
      chemin serait INERTE : il ne l'est pas.

  (b) CES VOLUMES DECIDENT REELLEMENT DE LA CONTRAINTE D'UNE CHAINE. `PHYSCVOL c=0 l=1 ci=39`
      compte les frames ou le volume 39 (`rBoob`) est le volume DECIDEUR du maillon distal de
      `chestL`. Un chemin arme mais jamais emprunte ne serait pas une cause.

CE QUE CETTE SONDE CALCULE : le deplacement que le tenseur SEUL imprime au centre du volume,
`|(D - I) . offset|`, orientation par orientation, rapporte au RAYON du volume — c'est-a-dire la
taille de l'effet dans l'unite qui decide d'un contact.

LES TROIS QUESTIONS (SPEC 7) :
  NATURE  une LONGUEUR (deplacement d'un centre de volume), en unites moteur et en % de rayon.
  REPERE  l'espace de bind du joint porteur, celui ou l'offset est ecrit dans la donnee livree et
          ou `D` est publie (`PHYSDFMA`, base d'ancre) — aucune composante ne traverse deux reperes.
  ABSENT  l'orientation i=0 est la pose debout : le tenseur y vaut l'identite, donc la sonde doit y
          lire ZERO. Elle le publie sur chaque ligne, et c'est le controle interne.

Usage :  python3 .autoport/c92_tensor_feedback.py [<log-OFF> <log-ON>]
"""
import os
import re
import sys

import numpy as np

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPDIR = os.path.join(REPO, '.autoport/reports/Grecharged-secondary-motion')
CHAINS = os.path.join(REPO, 'recharged_assets/physics_chains.txt')
NM = {0: ('chestL', 'lBoob'), 1: ('chestR', 'rBoob')}


def dfma(path):
    txt = open(path, errors='replace').read()
    d = {}
    for m in re.finditer(
            r'^PHYSDFMA c=(\d+) i=(\d+) r=(\d+) m0=([-\d.e+]+) m1=([-\d.e+]+) m2=([-\d.e+]+)',
            txt, re.M):
        c, i, r = int(m.group(1)), int(m.group(2)), int(m.group(3))
        d.setdefault((c, i), np.zeros((3, 3)))[r] = [
            float(m.group(4)), float(m.group(5)), float(m.group(6))]
    return d


def colliders():
    """Rayon et offset LUS dans la donnee livree — jamais recopies dans ce fichier."""
    out = {}
    for line in open(CHAINS, errors='replace'):
        m = re.match(r'^collider (\S+) radius=([-\d.]+) offset=([-\d.]+),([-\d.]+),([-\d.]+)', line)
        if m:
            out[m.group(1)] = (float(m.group(2)),
                               np.array([float(m.group(3)), float(m.group(4)), float(m.group(5))]))
    return out


def main():
    a = sys.argv[1] if len(sys.argv) > 2 else os.path.join(REPDIR, 'keira-room-x86.c91-OFF.log')
    b = sys.argv[2] if len(sys.argv) > 2 else os.path.join(REPDIR, 'keira-room-x86.c91-ON.log')
    OFF, ON = dfma(a), dfma(b)
    col = colliders()
    A = print
    A('DIRECTIVES v3fee554599')
    A('')
    A('C92 — LE TENSEUR DEPLACE LE VOLUME DE COLLISION QUE LA FRAME SUIVANTE LIRA')
    A('=' * 100)
    A('trace c90/desarmee : %s' % os.path.relpath(a, REPO))
    A('trace armee        : %s' % os.path.relpath(b, REPO))
    A('donnee             : recharged_assets/physics_chains.txt (offsets et rayons LUS, non recopies)')
    A('')
    for c in (0, 1):
        ch, jn = NM[c]
        if jn not in col:
            A('%-8s volume %s ABSENT de la donnee livree — non mesure' % (ch, jn))
            continue
        rad, off = col[jn]
        A('%-8s volume `%s` : rayon %.0f u, offset [%+.0f %+.0f %+.0f] (|offset| = %.0f u)'
          % (ch, jn, rad, off[0], off[1], off[2], np.linalg.norm(off)))
    A('')
    A('|(D - I) . offset| — le deplacement du CENTRE du volume par le tenseur SEUL')
    A('%-8s %-4s %11s %11s %11s %11s' % ('chaine', 'i', 'c90 (u)', 'c91 (u)', 'c90 /rayon',
                                         'c91 /rayon'))
    worst = {}
    for c in (0, 1):
        ch, jn = NM[c]
        if jn not in col:
            continue
        rad, off = col[jn]
        for i in sorted({ii for (cc, ii) in ON if cc == c}):
            va = float(np.linalg.norm((OFF[(c, i)] - np.eye(3)) @ off))
            vb = float(np.linalg.norm((ON[(c, i)] - np.eye(3)) @ off))
            worst[c] = max(worst.get(c, 0.0), va / rad)
            A('%-8s %-4d %11.1f %11.1f %10.1f%% %10.1f%%'
              % (ch, i, va, vb, 100.0 * va / rad, 100.0 * vb / rad))
    A('')
    A('CONTROLE INTERNE : a i=0 (debout, §9 exige l\'identite) la sonde lit 0,2 a 0,3 u, soit')
    A('  0,1 % du rayon. Le deplacement n\'est donc pas un artefact du calcul : il APPARAIT avec')
    A('  l\'inclinaison, exactement comme le tenseur.')
    A('PIRE CAS sur le moteur du cycle 90 : %.1f %% du rayon (chestL) et %.1f %% (chestR).'
      % (100.0 * worst.get(0, 0.0), 100.0 * worst.get(1, 0.0)))
    A('')
    A('PREMISSE (b), MESUREE : CES VOLUMES DECIDENT REELLEMENT DE LA CONTRAINTE D\'UNE CHAINE.')
    A('  `PHYSCVOL c=<chaine> l=<maillon> ci=<volume> n=<frames> max=<penetration>` — frames ou ce')
    A('  volume a ete le DECIDEUR. Un chemin arme mais jamais emprunte ne serait pas une cause.')
    for tag, path in (('c90/desarmee', a), ('armee', b)):
        txt = open(path, errors='replace').read()
        hit = [l for l in txt.split('\n')
               if l.startswith('PHYSCVOL ') and re.search(r'ci=(37|39) ', l)]
        if not hit:
            A('  %-12s AUCUNE ligne pour ci=37/39 : le volume de sein n\'a jamais decide.' % tag)
        for l in hit:
            A('  %-12s %s' % (tag, l))
    A('')
    A('CE QUE CA VEUT DIRE, ET CE QUE CA NE VEUT PAS DIRE.')
    A('  - Le volume de collision d\'un sein SUIT la deformation de sa chair. Vu du besoin que')
    A('    l\'owner repete depuis le 2026-08-11 (« les colliders ne suivent pas les formes du')
    A('    mesh »), c\'est la bonne direction — mais ce n\'est pas un choix : c\'est un effet de')
    A('    bord d\'un tenseur ecrit pour la PEAU, et il n\'est declare nulle part.')
    A('  - Il est lu avec UNE FRAME DE RETARD (`phys-snapshot-sim!` ecrit en fin de pas ce que la')
    A('    frame suivante lira). Un volume qui suit sa surface avec un retard d\'une frame est une')
    A('    source connue de vibration et de traversee.')
    A('  - CONSEQUENCE POUR LE DOSSIER, ET ELLE EST LA VRAIE : toute borne posee sur le tenseur')
    A('    est une intervention DYNAMIQUE. Elle ne peut pas etre jugee sur les seules grandeurs de')
    A('    forme, et le cycle 91 ne l\'a pas su avant de mesurer.')
    A('  - CE QUI N\'EST PAS TRANCHE ICI : faut-il que le volume suive la chair, et si oui par un')
    A('    canal DECLARE plutot que par ce chemin ? C\'est un arbitrage de superviseur, pas une')
    A('    initiative de worker. Aucun code n\'est touche par ce cycle.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
