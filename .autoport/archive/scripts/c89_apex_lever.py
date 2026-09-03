#!/usr/bin/env python3
"""c89_apex_lever.py — LE PREALABLE QUE LE CYCLE 88 S'ETAIT POSE, ET IL RETOURNE SA CONCLUSION.

DIRECTIVES v3fee554599.  ZERO course neuve, ZERO ligne de moteur : trace ARCHIVEE + donnee LIVREE.

CE QUE LE CYCLE 88 A ECRIT, ET QUI EST L'OBJET DE CETTE SONDE.
  « L'excursion du point de chair est presque entierement RADIALE le long de son propre levier
    [...] Une rotation autour du joint le deplace sur la sphere de rayon |bm.o|, donc
    PERPENDICULAIREMENT au levier : elle ne peut agir que sur 9 a 15 % de l'excursion, le reste
    lui est inaccessible PAR CONSTRUCTION. »
  Et, dans le meme commit, le prealable qu'il posait au geste suivant :
  « publier |bm.o| a cote de `rad` — une contraction du levier ne peut retirer que le second
    terme, et si celui-ci est minoritaire le geste se dimensionne autrement. »

1. LA PHRASE EST FAUSSE EN GEOMETRIE, ET C'EST EXACT.
   Une rotation d'angle theta d'un levier de longueur L deplace le point sur un CHORDE, pas sur
   une tangente.  La corde est perpendiculaire a la BISSECTRICE, jamais au levier COURANT — et
   c'est le levier COURANT que l'instrument du cycle 88 emploie (`jak-hd-physics.gc:3922` :
   `rl` est |r| pris sur `bm`, la matrice LIVREE).  Donc, pour |r| = |r_a| = L :

       rad = r^ . (r - r_a) = L - L.cos(theta) = L (1 - cos theta)      > 0 des que theta != 0
       |e| = 2 L sin(theta/2)     ->     rad / |e| = sin(theta/2)

   La part RADIALE d'une rotation PURE n'est donc pas nulle : elle vaut sin(theta/2), soit 0,50 a
   60 deg et 0,71 a 90 deg.  Le « 9 a 15 % » du cycle 88 est le residu TANGENTIEL, qui borne la
   part tangentielle de la rotation — pas sa part totale.

2. ET LA CONCLUSION TOMBE AUSSI, PAR LA MESURE, PAS PAR L'ARGUMENT.
   Decomposition exacte de la grandeur que le cycle 88 publie :

       rad = r^.t  +  (|r| - |r_a|)  +  (|r_a| - r^.r_a)
             ^^^^^     ^^^^^^^^^^^^      ^^^^^^^^^^^^^^^
             transl.   ELONGATION        ROTATION du levier ( = |r_a|(1 - cos theta) )

   Les deux premiers termes sont BORNES par de la donnee deja publiee :
     - `r^.t <= |t|`, et |t| est publie par fenetre (`PHYSAPEXT`, LATCHE AU MEME ARGMAX que
       `rad` — c'est le controle du cycle 86, |(ax,ay,az)| - apex <= 1.1e-4 B0) ;
     - l'elongation est plafonnee par le determinant : `PHYSSHAPE2 det` vaut 1.0000 et les trois
       echelles de `PHYSSHAPE` tiennent dans +/- 0,8 %, donc | |r| - |r_a| | <= 0.008 |r|.
   Ce qui reste est la ROTATION.  La sonde publie `rad - |t|` PAR FENETRE : partout ou il est
   positif, la translation NE PEUT PAS produire `rad` a elle seule, et la rotation est le seul
   canal qui reste.

   POURQUOI LA BORNE EST **EXACTE** SUR chestR ET SEULEMENT MAJORANTE SUR chestL.
   `rad` et `tp` sont des sommes ponderees par `aw` SUR LES MAILLONS.  `SOMME aw (r^_l . t_l)`
   n'est majoree par `|SOMME aw t_l|` que si les `t_l` sont colineaires.  Or
   `recharged_assets/physics_mesh.txt:23` livre **`ax chestR 1 0.0000 0.0 0.0 0.0`** : le maillon
   DISTAL de chestR porte un poids d'apex EXACTEMENT NUL, la somme n'a donc qu'UN terme et
   l'inegalite est une identite.  Sur chestL le second poids vaut 0,0818 : le jeu est borne par
   2 x 0,0818 x |t_1|, soit au plus ~16 % de la contribution du maillon distal.

3. |bm.o|, LE PREALABLE DU CYCLE 88, EST DANS LE DEPOT ET N'AVAIT PAS BESOIN D'UNE COURSE.
   `.autoport/reports/Grecharged-secondary-motion/mesh_extents_c14.txt:34` et `:53` publient le
   point d'apex en espace de bind de son os : |p| = 739,5 u (chestL) et 743,2 u (chestR), soit
   **1,228 et 1,235 B0**.  C'est la longueur du levier au bind ; le tenseur ne peut la changer
   que de +/- 0,8 % (point 2).

LES TROIS QUESTIONS (SPEC 7) :
  NATURE  une LONGUEUR SIGNEE en B0 par fenetre, et un ANGLE MINIMAL en degres qui s'en deduit.
          Pas un rapport, pas une amplitude agregee.
  REPERE  le MONDE, contre la pose d'auteur de la meme frame — celui de `rad` et de `tp`.
  ABSENT  `rad - |t| <= 0` = la translation suffit a expliquer `rad`, aucune rotation n'est
          requise ; c'est la lecture hors defaut, et elle sort sur 29 % / 22 % des fenetres.
"""
import math
import os
import re
import statistics as st
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOG = os.path.join(REPO, '.autoport/reports/Grecharged-secondary-motion/keira-room-x86.log')
B0 = 602.0
# |p_bind| du point d'apex, par chaine — mesh_extents_c14.txt:34 (chestL) et :53 (chestR)
LEVER = {0: 739.5 / B0, 1: 743.2 / B0}
# poids d'apex du maillon DISTAL — physics_mesh.txt:19 et :23. Zero sur chestR : la borne y est
# une IDENTITE, pas une majoration.
AWD = {0: 0.0818, 1: 0.0000}
NAMES = {0: 'chestL', 1: 'chestR'}
SCALE_TOL = 0.008          # PHYSSHAPE sx/sy/sz dans [0.992, 1.008], det = 1.0000


def main():
    log = sys.argv[1] if len(sys.argv) > 1 else LOG
    txt = open(log, errors='replace').read()

    def grab(pat, k):
        out = {}
        for m in re.finditer(pat, txt, re.M):
            c, a, d = int(m.group(1)), int(m.group(2)), int(m.group(3))
            out[(c, a, d)] = tuple(float(m.group(4 + i)) for i in range(k))
        return out

    rad = grab(r'^PHYSAPEXR c=(\d+) a=(\d+) d=(\d+) rad=([-\d.e+]+)', 1)
    tpv = grab(r'^PHYSAPEXT c=(\d+) a=(\d+) d=(\d+) tx=([-\d.e+]+) ty=([-\d.e+]+)'
               r' tz=([-\d.e+]+)', 3)
    apx = grab(r'^PHYSAPEX c=(\d+) a=(\d+) d=(\d+) apex=([-\d.e+]+)', 1)
    print('DIRECTIVES v3fee554599')
    print('')
    print('LE TERME DE LEVIER DE `rad`, BORNE PAR EN DESSOUS — ET L\'ANGLE QU\'IL IMPOSE')
    print('=' * 100)
    print('log : %s' % os.path.relpath(log, REPO))
    print('lignes lues : PHYSAPEXR %d · PHYSAPEXT %d · PHYSAPEX %d' % (len(rad), len(tpv),
                                                                       len(apx)))
    if not rad or not tpv:
        print('ABSENT — cette course precede `PHYSAPEXR` (cycle 88) : rien n\'est calcule.')
        return 1
    print('')
    for c in (0, 1):
        ks = [k for k in rad if k[0] == c]
        if not ks:
            continue
        r = [rad[k][0] for k in ks]
        t = [math.dist((0.0, 0.0, 0.0), tpv[k]) for k in ks]
        lev = [ri - ti for ri, ti in zip(r, t)]
        n = len(ks)
        q = lambda v, p: sorted(v)[min(n - 1, int(p * n))]
        th = []
        for b in lev:
            x = b / LEVER[c]
            th.append(math.degrees(math.acos(max(-1.0, min(1.0, 1.0 - x)))) if x > 0 else 0.0)
        pos = sum(1 for v in lev if v > 0)
        print('   === %s ===   n=%d fenetres   levier |p_bind| = %.4f B0'
              '   poids d\'apex du maillon distal = %.4f%s'
              % (NAMES[c], n, LEVER[c], AWD[c],
                 '  -> LA BORNE EST UNE IDENTITE' if AWD[c] == 0.0 else
                 '  -> jeu <= 2 x %.4f x |t_1|' % AWD[c]))
        print('   %-26s %9s %9s %9s' % ('', 'mediane', 'p90', 'max'))
        for lab, v in (('rad', r), ('|tp| (borne de r^.t)', t),
                       ('rad - |tp|  (levier)', lev)):
            print('   %-26s %+9.4f %+9.4f %+9.4f B0' % (lab, st.median(v), q(v, 0.9), max(v)))
        print('   %-26s %9.1f %9.1f %9.1f deg' % ('theta MINIMAL du levier', st.median(th),
                                                  q(th, 0.9), max(th)))
        print('   fenetres ou rad > |tp| : %d/%d (%.1f %%) — la TRANSLATION ne peut pas, a elle'
              ' seule, produire `rad`' % (pos, n, 100.0 * pos / n))
        el = SCALE_TOL * LEVER[c]
        print('   plafond de l\'ELONGATION du levier (det=1, echelles a +/- %.1f %%) : %.4f B0,'
              ' soit %.1f %% de `rad` median' % (SCALE_TOL * 100, el,
                                                 100.0 * el / st.median(r)))
        print('   -> il reste la ROTATION, et elle est MINOREE a %.1f deg en mediane.'
              % st.median(th))
        print('')
    print('   CE QUE CA RETIRE : la phrase du cycle 88 « une rotation [...] ne peut agir que sur')
    print('   9 a 15 % de l\'excursion, le reste lui est inaccessible PAR CONSTRUCTION ». Elle est')
    print('   fausse en geometrie (la part radiale d\'une rotation pure vaut sin(theta/2), pas 0)')
    print('   ET refutee par la mesure ci-dessus. La voie « borner par une rotation », fermee au')
    print('   cycle 87 puis justifiee au cycle 88 par cette phrase, l\'a ete sur un motif qui ne')
    print('   tient pas. Elle n\'est PAS rouverte ici — elle est rendue au superviseur avec le')
    print('   chiffre, parce que la rouvrir demande un instrument de `rp` que la borne elle-meme')
    print('   ne contamine pas (NOTES.md, note de `phys-cap-e22!`).')
    return 0


if __name__ == '__main__':
    sys.exit(main())
