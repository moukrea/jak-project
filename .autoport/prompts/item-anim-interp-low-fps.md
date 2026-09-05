# Les animations saccadees quand le jeu descend vers 20 images/s

## Defaut cite
- 2026-09-01 : « c'est la que le jitter se voit »
- 2026-09-01 : « interpolation de rendu »
- 2026-09-03 : « je trouve les animations très jittery [...] c'est très jittery quelque soit le framerate, 60 FPS comme 15 fps comme 45... etc »

## Cause connue
Le facteur d'interpolation n'est lu qu'a UN SEUL endroit du moteur. La porte du cycle 1 exigeait une mesure au-dessus de 60 img/s et releguait les mesures basses hors verdict : elle a valide un travail qui ne traitait pas le cas de l'owner, qui joue vers 20 img/s.

## Livrable
Le jitter reduit AUX DEUX BOUTS (a 30 img/s et moins, et au-dessus de 60), le comportement a 60 img/s identique au bit.

## Preuve exigee
`anim_render_step_err_max_us <= 2000` dans `reports/anim-interp-low-fps/proof.txt`.
Le proof se produit par `lib/proof_run.sh anim-interp-low-fps x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : joue autour de 20 images/s : les animations des personnages.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
