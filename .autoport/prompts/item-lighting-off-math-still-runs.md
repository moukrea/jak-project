# Eclairage eteint, le processeur calcule encore l'eclairage entier a chaque image

## Defaut cite
- 2026-09-10 : « bah c'est debile, c'est des choses a traiter ! OK pas par lui, mais s'il fait que les mentionner et on en fait jamais rien, ca va rester la, et on va potentiellement se trainer cette merde pendant des mois pour rien, pour qu'un jour quelqu'un retrouve l'erreur par hasard et la corrige... DEBILE !!! Si ce que remonte le worker n'est jamais traite par qui que ce soit, ca sert a rien, quel gaspillage ! Donc si, a traiter ! Et c'est exactement le genre de choses que tu devrais me remonter pour que je te dise si c'est pertinent ou pas, a faire ou pas ! Donc si, ces choses sont a traiter, je dirais juste apres meme ! »

## Cause connue
MESURE par gl-uniforms-off-cost (essai 2, proof.txt du 10/09) : ce correctif a coupe les POUSSEES, pas les CALCULS. Eclairage eteint et poussees toutes sautees (`uniform_off_pushes=0`, `uniform_off_skipped_per_setup=52`), `first_tfrag_draw_setup` coute ENCORE `uniform_setup_ns_per_frame_off=341068` ns par image sur x86, soit 0,34 ms — sur 16 appels par image. Les ~1000 lignes qui calculent position du soleil, harmoniques spheriques, lissage temporel et couleurs de mood tournent toujours. Elles portent des effets de bord consommes AILLEURS (`pbr_cover_publish_gates`, `Gfx::g_global_settings.mb_cur_relief_x100`, les trois `lighting_census::gate_*`, les statiques de lissage de background_common.cpp:2835-2838) : les sauter demande de savoir ce que chaque effet de bord alimente. C'est le chantier, pas un detail.

## Livrable
`lighting_off_math_blocks` = 0 : eclairage eteint, aucun bloc de calcul d'eclairage ne s'execute. Recenser les blocs et leurs effets de bord AVANT : chaque effet de bord consomme ailleurs est soit re-heberge, soit documente comme raison de garder son bloc. Publier le compte AVANT (non nul) et le cout CPU par image des deux cotes, avec la meme grandeur `uniform_setup_ns_per_frame_off` que gl-uniforms-off-cost, pour que les deux mesures se comparent.

## Preuve exigee
`lighting_off_math_blocks == 0` dans `reports/lighting-off-math-still-runs/proof.txt`.
Le proof se produit par `lib/proof_run.sh lighting-off-math-still-runs x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : rien a voir : la cadence eclairage eteint ; owner_test=false.

## Hors perimetre
Ne pas toucher au rendu allume ni aux poussees (gl-uniforms-off-cost les a deja coupees). On vise le CALCUL, pas l'envoi.
