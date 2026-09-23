# Les reglages Recharged sont tout en majuscules et pas tous traduits

## Defaut cite
- 2026-09-04 : « tous les éléments sont en majuscule dans les réglages rechargées, et pas tous sont localisés correctement. »
- 2026-09-05 : « Traduire celles qui restent en anglais dans toutes les langues supportées par le jeu ! »
- 2026-09-06 : « Validé »

## Cause connue
Aucun cycle n'a encore etabli de cause sur cet item.

## Livrable
Le moteur emet `settings_case_l10n_defects=N` = lignes du menu Recharged rendues en TOUT-MAJUSCULES (hors sigles) + lignes non traduites, comptees DANS CHAQUE LANGUE QUE LE JEU SUPPORTE, pas seulement le francais : une ligne dont la chaine affichee est identique a l'anglais alors que les autres menus sont traduits dans cette langue-la compte comme un defaut. Zero, toutes langues confondues. La casse des autres menus est la reference.

## Preuve exigee
`settings_case_l10n_defects == 0` dans `reports/recharged-settings-case-l10n/proof.txt`.
Le proof se produit par `lib/proof_run.sh recharged-settings-case-l10n x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Options > Recharged, dans chaque langue du jeu : casse normale comme le reste du menu, et rien qui reste en anglais.

## Hors perimetre
Ne touche pas au censement des options (menu-census-cleanup), seulement leur rendu et leur traduction.
