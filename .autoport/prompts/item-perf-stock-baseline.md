# La ligne de base du jeu STOCK sur le Redmi, et la courbe cadence selon l'echelle

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
Aucune mesure n'a jamais ete prise en regime stock : settings.ini de l'appareil (lu le 09-09) a recharged-master ON, lighting ON, HD ON, brise ON, fixed-tick ON (l'arbre rejoue jusqu'a 4x par image sous 15 img/s), aspect 4:3, auto-echelle cible 25 collee a 40 %. Les seules cadences connues : 18-24 img/s en jeu (09-05/06), 37,6 ms de fil GL median dont 19,4 ms de defuse (09-07), 95-222 ms/img a 100 % avec features ON. Le PC n'a aucune mesure sous charge CPU.

## Livrable
Un profil de course « stock » fige dans proof_env (master OFF, fixed-tick OFF, 21:9, game-size 2400x1080, auto-echelle OFF, vsync OFF, cap 240) sur trois vantages nommes (village1-hut, beach, jungle) et cinq echelles (25/40/60/80/100 %), publiant par regime : frame_ms_p50/p95, goal_busy_ms, gpu_ms_total, gl_cpu_ms, actors_active. Meme campagne sur x86. perf_baseline_missing = nombre de (vantage x echelle) sans ligne. Table deposee dans reports/perf-stock-baseline/baseline.md et referencee par les items suivants comme reference « avant ». Rien ne change dans le moteur.

## Preuve exigee
`perf_baseline_missing == 0` dans `reports/perf-stock-baseline/proof.txt`.
Le proof se produit par `lib/proof_run.sh perf-stock-baseline device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : rien a voir : campagne de mesure ; owner_test=false.

## Hors perimetre
Aucune optimisation, aucun changement de code hors proof_env. Ne pas reecrire settings.ini de l'appareil hors de la course (la garde anti-boucle le reecrit : consigner l'etat effectif dans le proof).
