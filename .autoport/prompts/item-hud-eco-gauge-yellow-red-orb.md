# Dans la jauge d'eco, l'orbe JAUNE et l'orbe ROUGE gardent la meme taille que la bleue (validee) au lieu de s'evanouir par moments

## Defaut cite
- 2026-09-23 : « Alors pour l'eco Bleue c'est parfait, j'ai pas de moyens rapide de tester l'Eco jaune et rouge mais du coup on peut valider en l'état parce que si c'est pas bon pour la jaune et rouge, la modif sera minime ça pourra être traité séparément. »

## Cause connue
Mesure par l'acquis acquis-hud-eco-gauge le 23/09, sur le build VALIDE par l'owner (code_rev 18, publie 22/09 23:10 depuis e4f7e2ba32) : la BLEUE est stable a 755/16 de rayon, la ROUGE tombe au pire a 96/16 et la JAUNE a 24/16 (`hud_gauge_t12_fit=2`, `hud_gauge_defects=4`, reports/acquis-hud-eco-gauge/proof.txt). Site : goal_src/jak1/pc/hud-classes-pc.gc:4657 (rhud-gauge-fit-bad). L'owner n'a teste QUE le bleu et a demande que jaune et rouge soient traites separement s'ils ne vont pas.
NE PAS TOUCHER : forme de la particule et fond noir (valides), taille de la BLEUE (755/16, validee). La cible des deux autres est la bleue. ATTENTION : 377/16 (essai 17) est une taille que l'owner avait REFUSEE le 22/09 19:41 — ne pas y revenir.

## Livrable
1. Rayon par type d'eco mesure sur l'appareil pendant une course qui ramasse les trois : minimum, mediane, maximum par type.
2. Jaune et rouge suivent la bleue (meme cible, meme stabilite) ; la bleue ne bouge pas.
3. `hud_gauge_orb_size_defects` = types dont le rayon s'ecarte de la bleue au-dela de la tolerance, a n'importe quelle image ; doit valoir 0. Publier les trois series et le nombre d'images par type (une population vide = defaut, pas un zero).
4. L'acquis acquis-hud-eco-gauge est etendu aux trois types une fois corrige.

## Preuve exigee
`hud_gauge_orb_size_defects == 0` dans `reports/hud-eco-gauge-yellow-red-orb/proof.txt`.
Le proof se produit par `lib/proof_run.sh hud-eco-gauge-yellow-red-orb device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : HUD en jeu, ramassage d'eco JAUNE puis ROUGE. Une question oui/non : l'orbe jaune et l'orbe rouge font-elles la meme taille que la bleue, sans retrecir ni disparaitre par moments ?.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
