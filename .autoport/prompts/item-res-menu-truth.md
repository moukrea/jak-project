# La resolution affichee est celle qui est rendue, et choisir plus petit coute moins cher

## Defaut cite
- 2026-09-10 : « par defaut on se met sur l'aspect ratio adapte a l'ecran, c'est top, mais le switch de resolution, je pense qu'il est un peu pete... On est jamais surs d'etre a la bonne resolution, l'entree menu resolution devrait afficher la valeur courante meme si on est pas dans le sous menu pour choisir la resolution, et preselectionner la valeur courante quand on y est. Deuxieme bug lie au meme truc... Quand… »

## Cause connue
Aucun cycle n'a etabli de cause. Deux symptomes distincts rapportes le 10/09 sur le dernier build. (a) la ligne « Resolution » n'affiche pas la valeur courante hors du sous-menu, et le sous-menu ne preselectionne pas la valeur en cours : on ne sait jamais ou l'on est. (b) en aspect force 4:3, 640x480 rend PLUS de detail que 800x600 et coute beaucoup plus cher en cadence — un rendu plus fin sous un nom plus petit, donc une resolution effective qui ne suit pas le libelle. Voir aussi l'item res-picker (livre le 30/06, jamais confirme).

## Livrable
`res_menu_defects` = 0. (1) LIBELLE VRAI : la ligne « Resolution » affiche la resolution EFFECTIVE courante hors du sous-menu, et le sous-menu ouvre sur elle, presélectionnée. Publier le libelle affiche ET la resolution effective du framebuffer : ils doivent correspondre a chaque entree du menu, dans chaque aspect. (2) MONOTONIE : pour un aspect donne, le nombre de pixels effectivement rendus CROIT avec la resolution choisie. Publier la table (aspect x entree de menu -> pixels rendus, cadence) : 640x480 rendant plus de pixels que 800x600 est un DEFAUT. (3) L'aspect force ne change que la liste proposee, jamais le lien entre un libelle et ce qui est rendu. (4) La valeur choisie survit a un redemarrage et se relit dans le menu.

## Preuve exigee
`res_menu_defects == 0` dans `reports/res-menu-truth/proof.txt`.
Le proof se produit par `lib/proof_run.sh res-menu-truth device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Options > Graphismes : la ligne Resolution doit montrer ta resolution actuelle sans entrer dedans. Force le 4:3, puis compare 640x480 et 800x600 : le plus petit doit etre le moins detaille et le plus fluide..

## Hors perimetre
Aucune refonte de menu : l'owner a archive ce sujet le 10/09. On corrige la verite du libelle et la resolution effective, rien d'autre.
