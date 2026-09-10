# Eteindre une option eteint VRAIMENT ce qui en depend, et l'eclairage a son sous-menu

## Defaut cite
- 2026-09-10 : « j'ai l'impression que passer a off une option dans les reglages recharges qui desactive d'autres options qui en dependent... Ne desactive pas les options qui en dependent reellement, elles restent actives dans l'etat ou elles etaient quand elles ont ete grisees. On devrait avoir tout un sous menu «… »

## Cause connue
Owner 10/09 sur le Redmi : « passer a off une option dans les reglages recharges qui desactive d'autres options qui en dependent... Ne desactive pas les options qui en dependent reellement, elles restent actives dans l'etat ou elles etaient quand elles ont ete grisees ». Il soupconne aussi des reglages actifs sous le master Recharged, et relie explicitement les mauvaises perfs du Redmi a ce defaut. Un grisage qui n'eteint rien rend FAUSSE toute preuve ON/OFF du harnais : OFF doit egaler l'ABSENCE.

## Livrable
`gating_defects` = 0. (1) RECENSEMENT : chaque option Recharged publie ses sites d'execution ; `gating_ungated_sites` = 0, aucun site n'agit sans lire sa porte. (2) EFFET : parent OFF, le compteur d'execution de CHAQUE dependante = 0 sur une course reelle — grisee ne suffit pas, il faut que le code ne tourne plus. (3) MASTER : master Recharged OFF, aucun chemin Recharged execute, tous compteurs a 0. (4) MEMOIRE : une option grisee affiche la valeur qu'elle avait a l'instant du OFF et la retrouve telle quelle au re-ON (`gating_value_restored` = 1). (5) MENU : un sous-menu « Recharged Lighting » avec interrupteur global, contenant Realtime Lighting, HDR Output, Ambient Occlusion et ses sous-reglages, ouvert a la suite de la refonte ; `gating_menu_parent` publie le parent de chaque ligne. (6) COUT : la cadence master OFF ne depend pas de l'etat des options grisees (`gating_off_cost_delta_pct` <= 2).

## Preuve exigee
`gating_defects == 0` dans `reports/recharged-gating-real/proof.txt`.
Le proof se produit par `lib/proof_run.sh recharged-gating-real device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Options > Recharged : eteins une option dont d'autres dependent — les lignes grisees doivent vraiment cesser d'agir, garder la valeur qu'elles avaient, et l'eclairage doit avoir son sous-menu Recharged Lighting..

## Hors perimetre
Aucune optimisation, aucun changement de rendu. On ne touche pas au contenu des features, seulement a leur porte et a leur place dans le menu.
