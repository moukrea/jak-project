# Les animations saccadees quand le jeu descend vers 20 images/s

## Defaut cite
- 2026-09-01 : « interpolation de rendu »
- 2026-09-03 : « je trouve les animations très jittery [...] c'est très jittery quelque soit le framerate, 60 FPS comme 15 fps comme 45... etc »
- 2026-09-05 : « Les animations jitter toujours sur des framerates inattendus par le jeu (genre 45 FPS) à 30 ça roule nickel, à 60 pareil (les deux framerates attendus par l'App, car sur PS2 ça oscillait entre ces deux là et le jeu était prévu pour) mais sur des framerates autres qu'aux alentours de 30 et 60 ça jitter! Par contre le pas de temps on valide, juste les animations qu'on valide pas... Enfin j'ai l'impr… »

## Cause connue
Owner 2026-09-05 : propre a 30 et 60, jitter a 45. Ce sont exactement les cadences ou les 60 ticks/s de la logique tombent en compte ENTIER par image (2 ticks a 30, 1 a 60). A 45 il en faudrait 1,333 : la suite reelle est 1,2,1,1,2... et le reste doit etre absorbe par l'alpha d'interpolation. `*fixed-tick-alpha*` n'a que DEUX consommateurs (cam-update.gc:246 et drawable.gc:1107) ; si le retimage d'animation ne le consomme pas, la pose saute d'un tick entier certaines images et pas d'autres — invisible aux ratios entiers, visible a 45.

## Livrable
Le moteur emet `anim_step_jitter_worst_us` = le PIRE ecart type du pas de pose vu par le rendu, image apres image, mesure a CHAQUE cadence de la serie 30, 45, 50, 60, 75, 90 — pas la moyenne, qui reste verte sur une alternance 1-2-1-1-2 ticks. Zero a 500 us pres partout. A 30 et a 60 le comportement reste identique au bit (`anim_step_bitexact_30`, `anim_step_bitexact_60` = 1). Preuve sur le Redmi.

## Preuve exigee
`anim_step_jitter_worst_us <= 500` dans `reports/anim-interp-low-fps/proof.txt`.
Le proof se produit par `lib/proof_run.sh anim-interp-low-fps device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : joue a 45 images/s (et 50, 75) : les animations doivent etre aussi lisses qu'a 30 et a 60.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
