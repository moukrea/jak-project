# GOAL construit l'image suivante pendant que le GPU rend la precedente

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
Sur Android g_perf_overlap (android_gfx.cpp:145) est ecrase a faux au premier sondage (:621-636) depuis le 2026-07-04 : GOAL attend sync-path (rendu fini) puis syncv (swap) avant de construire ; sur PC gl_vsync/gl_sync_path (opengl.cpp:1089-1111) ont le meme predicat. Periode = T_goal + T_gl au lieu de max. La regression de juillet : le rendu lisait hors chaine des donnees (merc-mod, texture-anim, eye, pointeurs GOAL) que GOAL reecrivait pour l'image suivante. Gperf-particles mesurait goal idle 142 -> 0,1 ms/60 img avec l'overlap.

## Livrable
Recouvrement ON par defaut sur Android ET PC, avec la course corrigee a la source : tout ce que le rendu lit hors chaine DMA est double-bufferise et estampille par image (blerc, texanim, eye, merc-mod, et tout scalaire pousse par pc-set-*! ecrit dans un slot indexe par image ; aucun pointeur GOAL lu par le fil de rendu). Le moteur publie overlap_defects = (empreinte de la chaine rendue != empreinte de la chaine construite) + (lectures hors chaine non estampillees) + (draws merc dont le tampon a change pendant le rendu). refset_replay_maxdiff == 0 sur ORIGINE. La regle « scalaires par slot, jamais de pointeur » est ecrite dans SPEC lumiere 6.1 dans le meme commit.

## Preuve exigee
`overlap_defects == 0` dans `reports/perf-goal-gl-overlap/proof.txt`.
Le proof se produit par `lib/proof_run.sh perf-goal-gl-overlap device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : la cadence en jeu ; et AUCUNE geometrie qui pope (c'est la regression de juillet).

## Hors perimetre
Pas de tolerance de la course (pas de « pop rare accepte »). Si la porte ne tient pas en 3 essais, l'item se bloque et la refonte lumiere continue. Ne touche a aucune feature validee.
