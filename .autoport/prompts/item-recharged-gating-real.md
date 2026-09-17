> LIS D'ABORD `prompts/item-recharged-gating-real-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# Eteindre une option eteint VRAIMENT ce qui en depend, et l'eclairage a son sous-menu

## Defaut cite
- 2026-09-11 : « Validé »

## Cause connue
Owner 10/09 sur le Redmi : « passer a off une option dans les reglages recharges qui desactive d'autres options qui en dependent... Ne desactive pas les options qui en dependent reellement, elles restent actives dans l'etat ou elles etaient quand elles ont ete grisees ». Il soupconne aussi des reglages actifs sous le master Recharged, et relie explicitement les mauvaises perfs du Redmi a ce defaut. Un grisage qui n'eteint rien rend FAUSSE toute preuve ON/OFF du harnais : OFF doit egaler l'ABSENCE.

## Livrable
`gating_defects` = 0. (1) Aucun site n'agit sans lire sa porte (`gating_ungated_sites`=0). (2) Parent OFF : le compteur d'execution de CHAQUE dependante = 0 sur une course reelle. (3) Master OFF : aucun chemin Recharged execute. (4) Une option masquee garde sa valeur et la retrouve au re-ON (`gating_value_restored`=1). (5) Sous-menu « Recharged Lighting », `gating_menu_parent` publie le parent de chaque ligne. (6) La cadence master OFF ne depend pas de l'etat des options desarmees. S'AJOUTE (refus 10/09) : (7) MASQUER, PAS GRISER : une option dont le parent est eteint DISPARAIT de la page — regle generale, pas seulement l'AO. (8) LIBELLE PORTEUR : chaque ligne affiche sa valeur courante (« Occlusion ambiante : HBAO », « Qualite : Moyen », « Force AO : Defaut ») et ouvrir la ligne PRESELECTIONNE la valeur en cours. (9) VRAI SOUS-MENU : les sous-reglages vivent dans une page a eux, pas en petits choix sous la ligne parente.

## Preuve exigee
`gating_defects == 0` dans `reports/recharged-gating-real/proof.txt`.
Le proof se produit par `lib/proof_run.sh recharged-gating-real device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Options > Recharged : eteins une option dont d'autres dependent — les lignes grisees doivent vraiment cesser d'agir, garder la valeur qu'elles avaient, et l'eclairage doit avoir son sous-menu Recharged Lighting..

## Hors perimetre
Aucune optimisation, aucun changement de rendu. On ne touche pas au contenu des features, seulement a leur porte et a leur place dans le menu.
