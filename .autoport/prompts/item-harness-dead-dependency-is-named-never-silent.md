# Un chantier qui depend d'un chantier archive ou supplante n'attend plus en silence : le lint rougit, le superviseur et l'owner le voient

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
Constate par le superviseur le 23/09 : lighting-bake, lighting-shadows et water-surface-material dependaient de lighting-ao-indirect, ARCHIVE le 17/09 car supplante par ao-indirect-clean (valide). Une dependance vers un item archive n'est jamais satisfaite : l'orchestrateur a saute ces trois items et TOUTE leur descendance (eclairage : regimes, ombres, lumieres locales, interieurs, acteurs, materiaux, presets et 7 items derriere ; eau) pendant 6 jours, sans un mot. Sur 59 chantiers de jeu ouverts, 5 seulement etaient prenables ; l'owner : « on aurait dit que c'était totalement mort ». Redirige a la main (commit 45c8773671). `autoport lint` n'a rien dit, `autoport status` non plus.

## Livrable
1. `autoport lint` rougit sur toute dependance vers un item archive, absent, ou bloque sans issue, et NOMME l'item et la dependance.
2. Quand un item est supplante (archive avec un successeur), ses dependants sont rediriges vers le successeur (champ `superseded_by`), ou le lint l'exige.
3. `autoport status` montre, quand il y en a, le nombre de chantiers de jeu en attente d'une dependance morte.
4. `dead_dependencies` = dependances vers archive/absent ; doit valoir 0. Publier aussi le nombre de chantiers de jeu prenables contre ouverts.
CONTROLE POSITIF (item fabrique dependant d'un archive -> lint rouge, nomme) + CONTROLE NEGATIF.

## Preuve exigee
`dead_dependencies == 0` dans `reports/harness-dead-dependency-is-named-never-silent/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-dead-dependency-is-named-never-silent x86` — jamais a la main, jamais recopie dans le rapport.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
