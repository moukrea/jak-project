# La brise dans les arbres et les buissons

## Defaut cite
- 2026-09-04 : « Déjà j'ai du mal à croire que la version native (quad réglé sur off) soit vraiment comme elle est actuellement, j'ai l'impression que c'est buggé. Réglé sur on... Bah l'effet est bizarre, t'as tous les éléments impactés… »

## Cause connue
L'anneau de vent a 48 slots morts sur 64 (index d'ecriture multiplie par `time-adjust-ratio`, index de lecture brut) : le ressort lit du vide trois images sur quatre. Le vent TIE est un affaissement lent VOULU ; le defaut du port est le pas de temps, qui avance par image RENDUE. La vegetation statique se classe par `TIE_PROTO_NAMES`, jamais par la geometrie.

## Livrable
Le moteur emet `wind_owner_defects_open=N`, somme de CINQ verdicts binaires qu'il publie aussi un par un : (1) `wind_native_stock_dev_pct` <= 1 — option ETEINTE, le mouvement natif compare au chemin stock (amplitude, frequence, forme) ; (2) `wind_shrub_base_shift_mm` == 0 — le pivot des buissons est leur base, un buisson enfonce sous le sol ne glisse pas ; (3) `wind_instances_still` == 0 sur les instances DESSINEES, les protos non classes expliques par nom ; (4) `wind_divergent_pairs` == 0 — deux instances identiques cote a cote bougent pareil ; (5) `wind_spectrum_peak_pct` <= 40 — le spectre du deplacement d'un sommet est celui d'une brise (large, enveloppe variable), pas d'UNE frequence (« ondulation sous l'eau »). Preuve sur le Redmi ; (6) `wind_base_to_crown_ratio` <= 0.15 — le tronc ne bouge pas, la cime oui (« ça twitch autant côté feuilles que le tronc ») ; (7) `wind_envelope_cv` >= 0.30 — l'amplitude varie dans le temps (rafales), ni sinusoide pure ni tilt binaire. wind_owner_defects_open somme les SEPT.

## Preuve exigee
`wind_owner_defects_open == 0` dans `reports/foliage-wind/proof.txt`.
Le proof se produit par `lib/proof_run.sh foliage-wind device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : les palmiers et les buissons de Sandover, option de brise eteinte PUIS allumee.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
