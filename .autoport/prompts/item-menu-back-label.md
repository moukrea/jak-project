# Le « Retour » des sous-menus affiche le bon texte, pas une chaine au hasard

## Defaut cite
- 2026-09-11 : « dans les sous-menus, la string 'Retour' n'est pas la ca prend une string random dans les sous menus des reglages realtime lighting, p'tetre dans les autres aussi »
- 2026-09-13 : « Labels retour propres dans les menus, validé »

## Cause connue
Owner 11/09 : « dans les sous-menus, la string « Retour » n'est pas la, ca prend une string random dans les sous menus des reglages realtime lighting, p'tetre dans les autres aussi ». Une chaine prise au hasard sent l'identifiant hors bornes ou l'index decale dans le banc de texte — la page « Recharged Lighting » est construite a l'execution, ses lignes ne sont pas numerotees a la main.

## Livrable
`menu_label_wrong` = 0 : CHAQUE ligne de CHAQUE sous-menu affiche le texte qui lui correspond. Publier, pour toutes les pages, le couple (identifiant demande, texte effectivement affiche) et le compte de ceux qui ne concordent pas. Verifier dans CHAQUE langue installee : un identifiant hors bornes ne se voit pas dans la langue ou la table est la plus longue. Nommer la cause plutot que corriger la seule ligne « Retour ».

## Preuve exigee
`menu_label_wrong == 0` dans `reports/menu-back-label/proof.txt`.
Le proof se produit par `lib/proof_run.sh menu-back-label device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Options > Recharged > Recharged Lighting, puis les autres sous-menus : la ligne de retour dit « Retour », et aucune ligne ne porte un texte qui n'a rien a y faire.

## Hors perimetre
Ne pas retraduire le jeu ni toucher aux polices. On corrige la correspondance identifiant/texte.
