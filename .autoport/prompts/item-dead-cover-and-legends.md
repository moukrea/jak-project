# Plus de conditions mortes ni de legendes perimees dans les sorties vivantes

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
Signalements du worker lighting-legacy-purge (11/09) : `background_common.cpp:1145` teste `disp == 2` (tessellation) alors que la variable recoit la constante 1, et `(bis & 128)` alors qu'elle recoit 0 — deux conditions structurellement mortes, et le seau `disp_tess` est publie avec une legende qui nomme un programme qui n'existe plus. `refset.cpp:2355` nomme encore la subdivision retiree. `MeshSubdivide.h:106` cite un champ supprime de gfx.h.

## Livrable
`dead_legend_sites` = 0 : recenser toute condition dont l'issue est fixee par construction et toute legende nommant un programme, un champ ou un reglage retire. Les supprimer. Publier le recensement avant/apres. Aucun changement de comportement attendu : ce sont des chemins morts.

## Preuve exigee
`dead_legend_sites == 0` dans `reports/dead-cover-and-legends/proof.txt`.
Le proof se produit par `lib/proof_run.sh dead-cover-and-legends x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : rien a voir : nettoyage ; owner_test=false.

## Hors perimetre
Ne rien supprimer qui soit encore lu. Un doute se signale, ne se tranche pas ici.
