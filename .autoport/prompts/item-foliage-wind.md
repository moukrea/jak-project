# La brise dans les arbres et les buissons

## Defaut cite
- 2026-09-04 : « Déjà j'ai du mal à croire que la version native (quad réglé sur off) soit vraiment comme elle est actuellement, j'ai l'impression que c'est buggé. Réglé sur on... Bah l'effet est bizarre, t'as tous les éléments impactés qui twitch à peine, c'est pas convainquant du tout, c'est un mouvement très bina… »
- 2026-09-06 : « Le feuilles de palmiers mériteraient de bouger plus à leur extrémités qu'à leur bases, de même pour l'ensemble des shrubs (la base au sol immobile, les extrémités qui bougent plus). Et plus convaincant les animations stp, ça doit varier en amplitude, distorsion, direction, comme de la brise/vent, fa… »

## Cause connue
Deux refus complets de l'owner. Le 03/09 : « on dirait une ondulation bizarre [...] sous l'eau ». Le 06/09 : « les feuilles de palmiers meriteraient de bouger plus a leur extremites qu'a leur bases [...] ca doit varier en amplitude, distorsion, direction ». Les deux extremes sont refuses : ni sinusoide pure, ni basculement sec. Le critere tronc/cime ne jugeait que DEUX points d'un arbre entier, d'ou les verdicts 8 et 9.

## Livrable
NEUF verdicts, publies un par un, sommes dans `wind_owner_defects_open` = 0, preuve sur appareil : (1) natif conforme au chemin stock a 1 % (option ETEINTE) ; (2) pivot des buissons a leur base, deplacement 0 mm — un buisson enfonce ne glisse pas ; (3) zero instance DESSINEE immobile ; (4) zero paire identique divergente ; (5) pic spectral <= 40 % — pas UNE frequence ; (6) tronc/cime <= 0,15 ; (7) enveloppe d'amplitude CV >= 0,30 — ni sinusoide, ni tilt binaire ; (8) `wind_tip_gradient_min` >= 3,0 — le deplacement croit de la base vers l'EXTREMITE le long de chaque element souple, mesure par segment : la pointe d'une palme bouge trois fois plus que son attache ; (9) `wind_dir_variation_deg` >= 20 — la DIRECTION varie dans le temps.

## Preuve exigee
`wind_owner_defects_open == 0` dans `reports/foliage-wind/proof.txt`.
Le proof se produit par `lib/proof_run.sh foliage-wind device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : les palmiers et les buissons de Sandover, option de brise eteinte PUIS allumee.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
