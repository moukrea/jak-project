#!/usr/bin/env python3
"""c131_length_readings.py — LES TROIS LECTURES DE LA CLAUSE PORTEUSE DE §11, COTE A COTE.

NATURE      : un RAPPORT sans dimension (longueur racine->apex a la cellule prone divisee par
              la meme a la pose debout d'auteur). Pas une longueur : un rapport de longueurs.
REPERE      : aucun pour le rapport lui-meme ; les deux longueurs sont mesurees en MONDE, donc
              la grandeur est invariante par rotation — c'est exactement ce que §11 nomme
              (« Root-to-apex length »), et c'est ce qui distingue la lecture ARBITREE des deux
              autres, qui sont des etendues le long d'un AXE FIXE.
HORS DEFAUT : 1.0000 (cellule i=0 divisee par elle-meme). La bande de §11 est 1.18-1.26.

D'OU VIENNENT LES CHIFFRES — aucun n'est calcule ici, tous sont RECOPIES d'une source publiee :
  * colonne « MOTEUR LIVRE »  : `ROOM-SPEC1011-LIVREE` du tableau livre pour les deux premieres
    lectures ; `c128-report.md` section 7 pour la troisieme (elle n'est publiee nulle part
    ailleurs, et c'est precisement le defaut que ce cycle corrige) ;
  * colonne « LOT c128 »      : `keira-room-table.c128-experiment.txt` et la meme section 7.
Ce fichier ne mesure rien : il MET EN REGARD. Il existe pour que le fait tienne en une commande.
"""
LO, HI = 1.18, 1.26
CELLS = ['chestL w>0.00', 'chestL w>=0.25', 'chestR w>0.00', 'chestR w>=0.25']
LECT = [
    ('ecart-type pondere le long de `fwd`  [REFUTE au c126 — ET IL PORTE LE VERDICT AUJOURD HUI]',
     [1.4455, 1.4514, 1.4370, 1.4588], [1.3293, 1.3279, 1.3097, 1.3169]),
    ('etendue max-min le long de `fwd`     [publiee a cote, sensibilite]',
     [1.3939, 1.4275, 1.3384, 1.4234], [1.2998, 1.3148, 1.2483, 1.2967]),
    ('distance racine->apex entre centroides de DECILE  [ARBITREE au c126 — la grandeur NOMMEE]',
     [1.3363, 1.2734, 1.3183, 1.3116], [1.2512, 1.1986, 1.2350, 1.2246]),
]
def vd(v):
    return 'SOUS' if v < LO else ('DANS' if v <= HI else 'AU-DESSUS')
def marge(v):
    return (v - HI) / v * 100 if v > HI else ((LO - v) / v * 100 if v < LO else 0.0)

print('C131: §11 clause PORTEUSE « Root-to-apex length: +18 to +26% » (SPEC l.179), bande 1.18-1.26')
print('C131: ' + '-' * 100)
for nom, av, ap in LECT:
    print('C131: %s' % nom)
    print('C131:   %-16s %-32s %s' % ('cellule', 'MOTEUR LIVRE', 'LOT c128 (trace archivee)'))
    for i, c in enumerate(CELLS):
        print('C131:   %-16s %.4f %-9s marge %5.2f %%    %.4f %-9s marge %5.2f %%'
              % (c, av[i], vd(av[i]), marge(av[i]), ap[i], vd(ap[i]), marge(ap[i])))
    print('C131:   -> DANS : %d/4 sur le moteur livre   ·   %d/4 sous le lot c128'
          % (sum(vd(x) == 'DANS' for x in av), sum(vd(x) == 'DANS' for x in ap)))
    print('C131: ' + '-' * 100)
print('C131: CE QUE LE TABLEAU DIT, ET C EST LE POINT DU CYCLE :')
print('C131:   (1) sur le MOTEUR LIVRE les trois lectures s accordent — AU-DESSUS, 0/4 DANS.')
print('C131:       Rebrancher le verdict ne change donc AUCUN statut de section aujourd hui ;')
print('C131:   (2) mais la TAILLE du depassement passe de 12,3-13,6 % a 1,1-5,7 % ;')
print('C131:   (3) et surtout, le verdict du LOT c128 s inverse completement : 0/4 DANS sur le')
print('C131:       proxy refute, 4/4 DANS sur la grandeur nommee. C EST L INSTRUMENT QUI DECIDE')
print('C131:       SI LE CORRECTIF MARCHE — d ou l obligation de le rebrancher AVANT de chiffrer')
print('C131:       un chantier sur lui.')
