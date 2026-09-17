# Le navigateur de mesh de debug

## Defaut cite
- 2026-07-30 : « on vise un objet clairement visible et pouf on a en fait sélectionné autre chose à proximité »
- 2026-07-31 : « En réouvrant ce mode, les marques précédentes devraient subsister pour pouvoir reprendre et continuer »
- 2026-07-31 : « Ils sont affichés comme s'il n'y avait pas de texture ou de mesh devant... on sait pas vraiment s'ils sont du bon côté ou du mauvais »
- 2026-07-31 : « Je sais pas pourquoi je peux pas aller au-delà de 256 polygones marqués... C'est pas bon ! »
- 2026-07-31 : « On devrait voir ce qui est marqué d'une façon différente que ce qui ne l'est pas »
- 2026-07-31 : « Quand on a sélectionné un mesh, on devrait avoir la possibilité de cacher les autres — plus pratique pour marquer tous les polygones sans jouer avec la caméra au travers des autres mesh »
- 2026-07-31 : « le device est avec l'owner / indisponible »
- 2026-07-31 : « triangle sous le réticule »
- 2026-09-11 : « TERMINÉ, MAIS IL FAUT SUPPRIMER CETTE FEATURE ELLE SERT A RIEN, Y COMPRIS SES ENTRÉES MENU ET BOUTON SUR OVERLAY TACTILE, ET RACCOURCI MANETTE IL ME SEMBLE »

## Cause connue
Aucun cycle n'a encore etabli de cause sur cet item.

## Livrable
Le defaut ci-dessus corrige dans le moteur, livre dans un build, et une garde de non-regression qui echoue si le symptome revient.

## Preuve exigee
Aucun critere machine n'est encore ecrit pour cet item. Ecris-le d'abord (une seule ligne `CLE=VALEUR` emise par le moteur), pose-le dans `backlog.yaml`, puis prouve-le.
Le proof se produit par `lib/proof_run.sh recharged-mesh-browser x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : le navigateur de mesh de debug.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
