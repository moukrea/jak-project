# Une pression sur la croix deplace d'UN cran, jamais deux

## Defaut cite
- 2026-09-11 : « parcourir les menus au d-pad tactile est un peu pete, pas teste a la manette mais quand on appuie un cran vers le bas par example, parfois ca saute deux ou plus items au lieu d'un seul, pareil dans les sous menus et compagnie »
- 2026-09-13 : « Navigation au D-Pad, validé »

## Cause connue
Owner 11/09 : « parcourir les menus au d-pad tactile est un peu pete [...] quand on appuie un cran vers le bas par exemple, parfois ca saute deux items ou plus au lieu d'un seul, pareil dans les sous menus ». Non teste a la manette : le recensement doit dire si le defaut est propre au TACTILE ou commun aux deux entrees.

## Livrable
`menu_step_overshoots` = 0 : une pression franche deplace la selection d'UN cran. Publier, par entree (tactile ET manette) et par page (menu principal ET sous-menus), le nombre de pressions et le nombre de crans parcourus : le rapport vaut 1. Nommer la cause — repetition automatique declenchee trop tot, evenement compte deux fois, ou pas de temporisation entre deux lectures. La repetition en maintien reste possible, mais elle commence apres un delai declare et avance a cadence declaree.

## Preuve exigee
`menu_step_overshoots == 0` dans `reports/menu-dpad-steps/proof.txt`.
Le proof se produit par `lib/proof_run.sh menu-dpad-steps device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Options, puis n'importe quel sous-menu : une pression = une ligne, au doigt comme a la manette.

## Hors perimetre
Ne pas retoucher la mise en page des menus ni l'ordre des lignes.
