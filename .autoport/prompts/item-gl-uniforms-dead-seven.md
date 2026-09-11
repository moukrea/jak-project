# Sept parametres d'eclairage partent a chaque image et aucun shader ne les lit

## Defaut cite
- 2026-09-10 : « bah c'est debile, c'est des choses a traiter ! OK pas par lui, mais s'il fait que les mentionner et on en fait jamais rien, ca va rester la, et on va potentiellement se trainer cette merde pendant des mois pour rien, pour qu'un jour quelqu'un retrouve l'erreur par hasard et la corrige... DEBILE !!! Si ce que remonte le worker n'est jamais traite par qui que ce soit, ca sert a rien, quel gaspillage ! Donc si, a traiter ! Et c'est exactement le genre de choses que tu devrais me remonter pour que je te dise si c'est pertinent ou pas, a faire ou pas ! Donc si, ces choses sont a traiter, je dirais juste apres meme ! »

## Cause connue
Recense par le worker de gl-uniforms-off-cost (essai 2, notes/recensement-70-uniformes.csv) et LAISSE EN L'ETAT : sept uniformes de la famille eclairage sont pousses par `first_tfrag_draw_setup` a chaque appel — donc ~16 fois par image, ALLUME COMME ETEINT — et n'ont AUCUN site de lecture dans aucun shader de l'arbre. `u_pbr_sun_dir` (declare pbr_uniforms.glsl:14), `u_pbr_sun_color` (pbr_uniforms.glsl:15), `u_rt_ambient_key` (shade.glsl:76), `u_rt_ambient_contrast` (shade.glsl:77), `u_rt_shadow_mul` (shade.glsl:170), `u_rt_tint_shadow` (shade.glsl:172), et `u_pbr_uv_tile` qui n'est meme DECLARE nulle part — `glu::loc` rend -1 en permanence pour lui. Jamais mesure, jamais corrige.

## Livrable
`dead_uniform_pushes` = 0 : plus aucune poussee vers un uniforme sans lecteur. Recenser les sept par un temoin machine (le nom, sa declaration, ses sites de lecture = 0) AVANT de retirer quoi que ce soit — un recensement a zero avant correction rendrait la porte verte par inaction. Publier aussi le compte AVANT, non nul, dans le meme proof. Si l'un des sept doit VIVRE parce qu'un shader le lira bientot, le dire et le garder.

## Preuve exigee
`dead_uniform_pushes == 0` dans `reports/gl-uniforms-dead-seven/proof.txt`.
Le proof se produit par `lib/proof_run.sh gl-uniforms-dead-seven x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : rien a voir : recensement ; owner_test=false.

## Hors perimetre
Ne pas toucher au rendu ni aux uniformes qui ont un lecteur. Seuls les sept sont vises.
