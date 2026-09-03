# La refonte des menus

## Defaut cite
- 2026-08-04 : « l'idée c'était de réorganiser pour que ce soit sensé, logique, intuitif, agréable à parcourir, avec des hints qui expliquent ce que ça change et, pour la partie graphique, l'impact potentiel sur les performances »

## Cause connue
La refonte a deja ete livree une fois puis SORTIE des builds par menu-flag-off (owner 2026-08-04 : parametres inventes, displacement disparu). Elle ne redemarre qu'apres le recensement du menu et la fermeture du navigateur de mesh (memes fichiers).

## Livrable
Le defaut ci-dessus corrige dans le moteur, livre dans un build, et une garde de non-regression qui echoue si le symptome revient.

## Preuve exigee
Aucun critere machine n'est encore ecrit pour cet item. Ecris-le d'abord (une seule ligne `CLE=VALEUR` emise par le moteur), pose-le dans `backlog.yaml`, puis prouve-le.
Le proof se produit par `lib/proof_run.sh recharged-menu-overhaul device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : les menus, du titre aux options.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
