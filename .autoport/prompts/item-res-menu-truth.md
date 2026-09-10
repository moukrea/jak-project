# La resolution affichee est celle qui est rendue, et choisir plus petit coute moins cher

## Defaut cite
- 2026-09-10 : « la partie aspect ratio, resolution, dynamic resolution scaling on/off, bascule entre toutes ces options... C'est finiky, je sais pas comment expliquer mais j'ai l'impression que certaines resolutions marchent pas vraimen… »

## Cause connue
Aucun cycle n'a etabli de cause. Deux symptomes distincts rapportes le 10/09 sur le dernier build. (a) la ligne « Resolution » n'affiche pas la valeur courante hors du sous-menu, et le sous-menu ne preselectionne pas la valeur en cours : on ne sait jamais ou l'on est. (b) en aspect force 4:3, 640x480 rend PLUS de detail que 800x600 et coute beaucoup plus cher en cadence — un rendu plus fin sous un nom plus petit, donc une resolution effective qui ne suit pas le libelle. Voir aussi l'item res-picker (livre le 30/06, jamais confirme).

## Livrable
`res_menu_defects` = 0. (1) LIBELLE VRAI : la ligne « Resolution » affiche la resolution EFFECTIVE hors du sous-menu, qui s'ouvre presélectionné dessus ; publier libelle ET framebuffer effectif, ils correspondent. (2) MONOTONIE : a aspect donne, les pixels rendus CROISSENT avec la resolution choisie. (3) L'aspect force ne change que la liste proposee. (4) Le choix survit au redemarrage. S'AJOUTE (refus 10/09) : (5) TOUTE LA MATRICE : chaque combinaison aspect x resolution x echelle dynamique (marche/arret) ET chaque bascule de l'une a l'autre ; publier pour chacune le libelle et les pixels rendus. (6) Changer d'aspect ajuste la resolution en accord au lieu de laisser une valeur qui n'appartient plus a la liste. (7) Aucune combinaison inerte : une resolution proposee et choisie DOIT changer ce qui est rendu.

## Preuve exigee
`res_menu_defects == 0` dans `reports/res-menu-truth/proof.txt`.
Le proof se produit par `lib/proof_run.sh res-menu-truth device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Options > Graphismes : la ligne Resolution doit montrer ta resolution actuelle sans entrer dedans. Force le 4:3, puis compare 640x480 et 800x600 : le plus petit doit etre le moins detaille et le plus fluide..

## Hors perimetre
Aucune refonte de menu : l'owner a archive ce sujet le 10/09. On corrige la verite du libelle et la resolution effective, rien d'autre.
