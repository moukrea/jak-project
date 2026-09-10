# Le nom des jeux et de la collection Recharged

## Defaut cite
- 2026-09-11 : « JE SAIS PAS DE QUOI IL S'AGIT VRAIMENT... « Jak and Daxter: The Precursor Legacy » doit etre nomme « Jak and Daxter: Recharged » (sans mention d'OpenGOAL) »

## Cause connue
L'owner ne reconnait pas l'item ; il pose l'exigence en clair le 11/09 : « Jak and Daxter: The Precursor Legacy » doit s'appeler « Jak and Daxter: Recharged », sans aucune mention d'OpenGOAL.

## Livrable
`naming_wrong_sites` = 0 : recenser CHAQUE endroit ou le jeu se nomme — nom de l'application au lanceur, titre de la fenetre, ecran-titre, menus, ecrans de credits, description du paquet, notification. Aucun n'affiche « The Precursor Legacy » ni « OpenGOAL » ; tous affichent « Jak and Daxter: Recharged ». Publier la liste des sites avec la chaine effectivement affichee, dans CHAQUE langue installee — une chaine traduite oubliee compte comme un site faux.

## Preuve exigee
Aucun critere machine n'est encore ecrit pour cet item. Ecris-le d'abord (une seule ligne `CLE=VALEUR` emise par le moteur), pose-le dans `backlog.yaml`, puis prouve-le.
Le proof se produit par `lib/proof_run.sh recharged-naming x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : le nom du jeu partout ou il apparait : icone du lanceur, ecran-titre, menus. « Jak and Daxter: Recharged », jamais « The Precursor Legacy » ni « OpenGOAL »..

## Hors perimetre
Ne pas renommer le paquet Android ni casser les sauvegardes existantes.
