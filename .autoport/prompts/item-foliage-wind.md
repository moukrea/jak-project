# La brise dans les arbres et les buissons

## Defaut cite
- 2026-09-06 : « Le feuilles de palmiers mériteraient de bouger plus à leur extrémités qu'à leur bases, de même pour l'ensemble des shrubs (la base au sol immobile, les extrémités qui bougent plus). Et plus convaincant les animations stp, ça doit varier en amplitude, distorsion, direction, comme de la brise/vent, fa… »
- 2026-09-07 : « La brise c'est vraiment pas mal, mais par contre j'ai l'impression que tu as cantonné à Sandover Village alors que c'est pour tout le jeu que je veux ça ! Et les shrubs/buissons/fleurs... Comme l'herbe rechargée ils devraient être influencés par le passage de Jak ! Et écrasés par les caisses/ennemis… »

## Cause connue
Deux refus complets de l'owner. Le 03/09 : « on dirait une ondulation bizarre [...] sous l'eau ». Le 06/09 : « les feuilles de palmiers meriteraient de bouger plus a leur extremites qu'a leur bases [...] ca doit varier en amplitude, distorsion, direction ». Les deux extremes sont refuses : ni sinusoide pure, ni basculement sec. Le critere tronc/cime ne jugeait que DEUX points d'un arbre entier, d'ou les verdicts 8 et 9.

## Livrable
`wind_owner_defects_open` = 0, preuve sur appareil. NEUF verdicts deja tenus le 2026-09-07 (natif conforme au stock, pivot des buissons a leur base, zero instance dessinee immobile, zero paire identique divergente, pic spectral <= 40 %, tronc/cime <= 0,15, enveloppe CV >= 0,30, gradient pointe/attache >= 3, direction variant >= 20 deg) — NE PAS LES CASSER. DEUX de plus, demandes par l'owner :
  (10) `wind_levels_uncovered` = 0 — TOUT LE JEU, pas seulement Sandover. Recenser les niveaux qui portent de la vegetation et prouver que chacun est couvert ; nommer ceux qui n'en portent pas.
  (11) `wind_contact_defects` = 0 — buissons, arbustes et FLEURS reagissent au PASSAGE de Jak et sont ECRASES par les caisses, les ennemis et les objets, exactement comme l'herbe rechargee. Reutiliser le mecanisme de l'herbe, ne pas en ecrire un second.

## Preuve exigee
`wind_owner_defects_open == 0` dans `reports/foliage-wind/proof.txt`.
Le proof se produit par `lib/proof_run.sh foliage-wind device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : les palmiers et les buissons de Sandover, option de brise eteinte PUIS allumee.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
