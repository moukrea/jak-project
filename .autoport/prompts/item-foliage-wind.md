# La brise dans les arbres et les buissons

## Defaut cite
- 2026-09-07 : « demerdes toi pour HDR/Blanc brûlés, c'est la top priorité, la brise et la cadence c'est sensé être tout en bas de la pile, je t'ai jamais dit de reprendre ça ! La top priorité c'est la refonte du lighting, commençant par reprendre le HDR/blancs brûlés ! »
- 2026-09-10 : « je suis alle dans forbidden jungle... les plateformes sur des troncs oscillent au vent c'est debile, c'est pas des troncs fins et febriles qui sont senses bouger au vent, ce sont des arbres epais ! et les arbres du niveau pareil, tout leur tronc bouge, a la limite les petites branches OK, mais les t… »

## Cause connue
Deux refus complets de l'owner. Le 03/09 : « on dirait une ondulation bizarre [...] sous l'eau ». Le 06/09 : « les feuilles de palmiers meriteraient de bouger plus a leur extremites qu'a leur bases [...] ca doit varier en amplitude, distorsion, direction ». Les deux extremes sont refuses : ni sinusoide pure, ni basculement sec. Le critere tronc/cime ne jugeait que DEUX points d'un arbre entier, d'ou les verdicts 8 et 9.

## Livrable
`wind_owner_defects_open` = 0, preuve sur appareil. NEUF verdicts deja tenus le 2026-09-07 (natif conforme au stock, pivot des buissons a leur base, zero instance immobile, zero paire identique divergente, pic spectral, rapport tronc/cime, etc.) : voir l'historique de l'item et son rapport d'essai 11, ils restent exiges. S'AJOUTE (refus 10/09, Forbidden Jungle) : le TRONC d'un arbre epais NE BOUGE PAS. Publier, par instance, le deplacement du tronc et celui du feuillage : le tronc reste sous un plafond declare et proche de zero pour les troncs epais ; seuls feuillage, petites branches et lianes bougent. Une plateforme posee sur un tronc suit le tronc, donc n'oscille pas. Les lianes qui grimpent ne traversent pas le tronc.

## Preuve exigee
`wind_owner_defects_open == 0` dans `reports/foliage-wind/proof.txt`.
Le proof se produit par `lib/proof_run.sh foliage-wind device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Forbidden Jungle : les troncs epais et les plateformes posees dessus ne bougent pas ; feuilles, petites branches et lianes oui. Puis les palmiers de Sandover, brise eteinte PUIS allumee..

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
