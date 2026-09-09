# Marcher, tomber, nager : la surface repond

## Defaut cite
- 2026-09-09 : « bah je valide, beau boulot ! »

## Cause connue
LIS D'ABORD prompts/SPEC-refonte-eau.md : c'est le contrat, il porte le detail que ce prompt ne repete pas. Tout existe pour les EVENEMENTS (water-control, splash-spawn, 2 groupes sparticle) mais la SURFACE ne bouge pas (SPEC 2.3). Le fil GOAL du Redmi est le goulot : rien de nouveau par image sur ce fil (regle 4).

## Livrable
La RT de rides W1 en espace monde centree sur Jak (equation d'onde ping-pong, re-projection par texel entier, canal ecume), la file d'impulsions sur le fil de rendu, le sillage derive de la position de Jak, UN appel FFI pc-water-impulse! pose au site existant de splash-spawn (water.gc:776) — un appel par evenement, zero par image —, le maillage d'eclaboussure, lecture en vertex (clipmap et merc) et en fragment. Les PNJ a water-control passent par le meme site. Palier Tres bas : RT statique. SPEC 5.4. Publie ripple_energy avant/apres un pas force (causal), ripple_reproject_slips=0, splash_mesh_spawned. GOAL neuf (pc/water-pc.gc) liste dans game.gd et engine.gd. PREUVE : `FEATURE water-interaction armed=1 hits=<impulsions injectees dans la RT de rides>` + la ligne `ripple_impulses_dropped=` seule sur sa ligne ; `--off` doit rendre `armed=0 hits=0` dans la MEME scene. Le publicateur EXISTE : game/system/autoport_proof.{h,cpp} — appelle armed_for("water-interaction"), jamais armed(), et n'en ecris pas un second.

## Preuve exigee
`ripple_impulses_dropped == 0` dans `reports/water-interaction/proof.txt`.
Le proof se produit par `lib/proof_run.sh water-interaction device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : patauger dans les rizieres de Sandover et tomber dans la mer : un sillage derriere Jak, une gerbe et des anneaux qui s'eloignent.

## Hors perimetre
Tout ce qui n'est pas cet item. DEUX origines restent bit-identiques — master OFF, et recharged_water OFF — et tout sous-reglage d'eau se garde sur recharged_water, jamais sur le master seul (SPEC 1.2 regle 1, 7). La hauteur de JEU (ocean-get-height, ripple-find-height) ne change pas d'un millimetre (regle 2). Aucune physique : l'interaction est simulee pour de faux (SPEC 1.4). Ne touche a aucune feature validee. Pas de mesure visuelle. Aucune force en retour, aucune flottabilite, aucun courant qui pousse : la surface reagit, elle n'agit sur rien.
