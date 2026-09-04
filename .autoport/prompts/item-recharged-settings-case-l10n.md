# Les reglages Recharged sont tout en majuscules et pas tous traduits

## Defaut cite
- 2026-09-04 : « tous les éléments sont en majuscule dans les réglages rechargées, et pas tous sont localisés correctement. »

## Cause connue
Aucun cycle n'a encore etabli de cause sur cet item.

## Livrable
Le moteur emet `settings_case_l10n_defects=N` = lignes du menu Recharged rendues en TOUT-MAJUSCULES (hors sigles) + lignes dont la chaine affichee en francais est identique a la chaine anglaise alors qu'une traduction existe pour les autres menus. Zero. La casse des autres menus est la reference : ce menu ne doit pas se distinguer.

## Preuve exigee
`settings_case_l10n_defects == 0` dans `reports/recharged-settings-case-l10n/proof.txt`.
Le proof se produit par `lib/proof_run.sh recharged-settings-case-l10n x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Options > Recharged : chaque ligne en casse normale (comme le reste du menu, police Urbanist), et chaque ligne traduite quand le jeu est en francais.

## Hors perimetre
Ne touche pas au censement des options (menu-census-cleanup), seulement leur rendu et leur traduction.
