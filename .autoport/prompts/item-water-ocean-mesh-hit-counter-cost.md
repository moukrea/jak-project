# Quatorze millions d'incrementations par seconde depuis un seul instrument de recensement

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
MESURE DU 12/09 (reports/census-audit-blind-spots/proof.txt, table `proof_feature_hits_table`), rendue lisible par le comptage par feature livre le matin meme.
`water-ocean-mesh` porte 4 536 325 248 prises sur les 4 546 910 549 du compteur global, soit 99,8 %, en 318 secondes de course. C'est environ QUATORZE MILLIONS d'incrementations atomiques par seconde depuis un seul site, celui d'un item encore ouvert.
Pour comparaison, `lighting-census` en porte 6,9 millions et `lighting-unify` 3,6 millions : trois ordres de grandeur en dessous. L'ecart suggere un compteur place PAR SOMMET ou par iteration de boucle interne plutot que par evenement.
Le cout processeur de cet instrument n'est mesure par personne, et il tourne en regime de production sur un appareil qui plafonne a ~44 img/s.

## Livrable
`hit_counter_cost_defects` = 0, somme de termes publies SEPAREMENT.
1. LE COUT D'ABORD : publier le temps processeur par image imputable a cet instrument, mesure sur l'appareil, instrument arme puis desarme, meme lieu et meme binaire. Un gain non chiffre n'est pas un gain.
2. Le site est NOMME et sa granularite dite : par sommet, par iteration, par evenement. Publier le compte de prises et le compte d'EVENEMENTS reels que l'instrument voulait compter. L'ecart entre les deux est le defaut.
3. Apres correction, le compte de prises est du meme ordre que le compte d'evenements : publier les deux. Un instrument qui compte trois ordres de grandeur au-dessus de ce qu'il observe ne mesure plus, il chauffe.
4. Ce que l'instrument prouvait continue d'etre prouve : reprendre les cles de `water-ocean-mesh` et montrer qu'elles gardent leur sens.

## Preuve exigee
`hit_counter_cost_defects == 0` dans `reports/water-ocean-mesh-hit-counter-cost/proof.txt`.
Le proof se produit par `lib/proof_run.sh water-ocean-mesh-hit-counter-cost device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Invisible a l'oeil. Le gain se voit sur la cadence dans les niveaux qui portent de l'eau..

## Hors perimetre
Ne change pas le rendu de l'eau. Ne retire pas l'instrument, on corrige sa granularite.
