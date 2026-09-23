# Le jeu STOCK tient 60 images par seconde sur le Redmi, en natif 21:9

## Defaut cite
- 2026-09-11 : « 74 au lieu de 71 et 91 au lieu de 84 respectivement... mais le HONOR ne struggle pas, c'est probablement plus sur le Redmi »

## Cause connue
Item de cloture : la meme campagne que perf-stock-baseline, apres tous les items perf. stock_frame_ms_p95 en centiemes de ms (1667 = 16,67 ms) a l'echelle 100 %. Si la porte ne tient qu'a une echelle < 100 %, l'item publie l'echelle atteinte et l'owner tranche : c'est le reglage par defaut de l'auto-echelle (cible 60, plancher releve) qui devient le livrable.

## Livrable
stock_frame_ms_p95 <= 1667 sur les trois vantages a 100 % ; sinon stock_60_scale_pct (la plus haute echelle qui tient) publie et la valeur par defaut de dyn-target-fps/min-render-scale ajustee en consequence (aujourd'hui 25/40 sur l'appareil contre 60/40 par defaut). Table finale dans reports/perf-stock-60/final.md, comparee ligne a ligne a baseline.md.

## Preuve exigee
`stock_frame_ms_p95 <= 1667` dans `reports/perf-stock-60/proof.txt`.
Le proof se produit par `lib/proof_run.sh perf-stock-60 device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : toutes les options Recharged OFF, 21:9, 2400x1080, compteur d'images a l'ecran : 60 stable en village1, beach, jungle.

## Hors perimetre
Aucune optimisation dans cet item : il mesure. Ne touche a aucune feature validee.
