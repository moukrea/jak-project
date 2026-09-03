#!/usr/bin/env python3
"""c113_estimator_identity.py — LES DEUX INSTRUMENTS DE §24 NE SE CONTREDISENT PAS.
ILS MESURENT DEUX GRANDEURS DIFFERENTES, EXACTEMENT RELIEES.

Le cycle 99 a laisse cette reserve ouverte dans SPEC-COVERAGE.md :
  « d'ou `chestL lat = 2,393 SOUS` au cycle 97 contre `2,550 DANS` au tableau, A LA MEME COURSE.
    A reconcilier AVANT de prononcer TENUE. »
et l'a attribuee aux deux FAMILLES DE FENETRES (AX contaminee contre PH-AXC propre).

CE CYCLE MESURE QUE L'ATTRIBUTION EST FAUSSE. Sur le meme estimateur, les deux familles
s'accordent a +0,41 % au pire (`ROOM-SPEC24-RECONCILE`). L'ecart de 6 % est entre les deux
ESTIMATEURS, et il est SYSTEMATIQUE — six cellules sur six, toujours dans le meme sens.

CE QUI LE PRODUIT, ET C'EST UNE IDENTITE, PAS UN DESACCORD :
  * `physics_room_table.py::_fitseries` ajuste  e^{-z.w.t} [cos(w_d.t), sin(w_d.t)]  avec
    w = 2.pi.f  et  w_d = w.sqrt(1-z^2).  Son `f` est donc la frequence propre NON AMORTIE f_n.
  * `c96_axc_pair.py::fit_damped` ajuste       A.e^{-sigma.t}.cos(2.pi.f.t + phi).
    Son `f` est la frequence AMORTIE f_d, celle qu'on voit passer par zero.
  * f_d = f_n . sqrt(1 - zeta^2).  A zeta = 0,335-0,339 ca vaut -6,0 a -6,3 %.

ET C'EST LA PREMIERE GRANDEUR QUE §24 NOMME : sa section s'intitule « Primary NATURAL
Frequencies », et sa §28 pose `k = m(2.pi.f)^2`, qui EST la definition de la pulsation propre
non amortie. La bande de §24 porte donc sur f_n. Comparer f_d a cette bande, c'est comparer une
grandeur a la bande d'une autre — la faute que le registre appelle
`strain-denominator-is-the-local-rest-length` et `b0-denominator-axis-not-in-spec`.

NATURE : des frequences en Hz. REPERE : triedre de l'ancre (SPEC 7). LIGNE DE BASE : sans objet.
CE QUI DISCRIMINE : le residu de l'identite. S'il est de l'ordre du pourcent, les deux
instruments mesurent la meme chose a la conversion pres ; s'il ne l'est pas, ils se contredisent
vraiment et §24 ne se prononce pas.
"""
import math

# --- `_fitseries` sur les fenetres PROPRES (ROOM-AXC-FIT diagonale et ROOM-AXC-RAD) : f_n ------
FN = {('chestL', 'v'): 2.320, ('chestL', 'ap'): 2.450, ('chestL', 'lat'): 2.550,
      ('chestR', 'v'): 2.415, ('chestR', 'ap'): 2.555, ('chestR', 'lat'): 2.655}
# --- `fit_damped` du cycle 96 sur LES MEMES fenetres (jeu AXC, maillon 0) : f_d et son zeta ----
#     v      -> canal RADIAL   (bloc « pic »)      ap/lat -> canal TRANSLATION (bloc « tau s »)
FD = {('chestL', 'v'): (2.209, 0.327), ('chestL', 'ap'): (2.309, 0.339),
      ('chestL', 'lat'): (2.393, 0.339),
      ('chestR', 'v'): (2.282, 0.338), ('chestR', 'ap'): (2.409, 0.335),
      ('chestR', 'lat'): (2.502, 0.335)}
B24 = {'v': (2.1, 2.5), 'ap': (2.3, 2.7), 'lat': (2.4, 2.9)}

print('DIRECTIVES vd9e8b66782')
print('=' * 100)
# LES DEUX SOURCES DE `zeta` SONT PUBLIEES COTE A COTE, POUR QU'ON NE PUISSE PAS ME SOUPCONNER
# D'AVOIR CHOISI LA PLUS FLATTEUSE. `_fitseries` balaie zeta sur une grille de pas 0.01 et rend
# 0.35 sur les quatre cellules diagonales ; `fit_damped` raffine et rend 0.327-0.339. La grille
# est plus grossiere, donc son residu est plus grand — et il reste sous 1.7 %.
ZG = 0.35   # zeta rendu par `_fitseries` (grille de pas 0.01)
print('%-8s %-4s %8s %8s %7s %9s %8s %9s %8s  %s'
      % ('chaine', 'axe', 'f_n', 'f_d', 'z(c96)', 'fd(z c96)', 'residu', 'fd(z=.35)', 'residu',
         'verdict sur f_n (la grandeur de §24)'))
worst = worstg = 0.0
for c in ('chestL', 'chestR'):
    for a in ('v', 'ap', 'lat'):
        fn = FN[(c, a)]
        fd, z = FD[(c, a)]
        pred = fn * math.sqrt(1.0 - z * z)          # identite f_d = f_n.sqrt(1-zeta^2)
        predg = fn * math.sqrt(1.0 - ZG * ZG)       # la meme, avec le zeta de la GRILLE
        res = 100.0 * (pred - fd) / fd
        resg = 100.0 * (predg - fd) / fd
        worst = max(worst, abs(res))
        worstg = max(worstg, abs(resg))
        lo, hi = B24[a]
        print('%-8s %-4s %8.3f %8.3f %7.3f %9.4f %7.2f %% %9.4f %7.2f %%  %s   (f_d contre la meme bande : %s)'
              % (c, a, fn, fd, z, pred, res, predg, resg,
                 'DANS' if lo <= fn <= hi else 'HORS',
                 'DANS' if lo <= fd <= hi else 'HORS'))
print('=' * 100)
print('residu maximal de l identite : %.2f %% avec le zeta raffine de `fit_damped` (0,327-0,339)'
      % worst)
print('                              %.2f %% avec le zeta de grille de `_fitseries` (0,35, pas 0,01)'
      % worstg)
print('Les deux confirment l identite. La grille est plus grossiere, et c est tout ce qui les separe.')
print()
print('CE QUE CA ETABLIT :')
print('  1. les deux instruments NE SE CONTREDISENT PAS — ils sont relies par f_d = f_n.sqrt(1-z^2)')
print('     a %.2f %% pres sur les six cellules, sans un seul parametre ajuste ;' % worst)
print('  2. §24 s intitule « Primary NATURAL Frequencies » et §28 pose k = m(2.pi.f)^2 : sa bande')
print('     porte sur f_n. Le verdict du cycle 97 lisait f_d contre cette bande ;')
print('  3. c est ce decalage de -6 %, et lui seul, qui mettait `chestL lat` SOUS son plancher')
print('     (2,393 contre 2,400). Sur la grandeur que la section nomme, la cellule vaut 2,550.')
