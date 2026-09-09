# Voir enfin ou passe le temps d'une image, sur l'appareil comme sur PC

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
« Kernel dispatch time » (kboot.cpp:147-173) chronometre un tour du dispatcher AVEC les attentes sync-path/syncv du process display, et n'est imprime qu'au-dessus de 50 ms : ce n'est ni le CPU GOAL ni une mesure. Les 35 seaux with-profiler de GOAL (main.gc:1835-2126, drawable.gc:774-919) emettent vers GlobalProfiler, stub vide sur Android (android_runtime_compat.cpp:433-462). lighting_census.cpp pose deja des glQueryCounter par bucket (gpu_ms_*) mais seulement sous armed_for("lighting-census") et jamais appele depuis android/. Aucun perf map pour symboliser le code GOAL dans simpleperf (present sur l'appareil, APK debuggable).

## Livrable
Publie par le moteur, dans la ligne A35-SPART toutes les 60 images ET dans proof.txt : goal_busy_ms (dispatch moins attente sync-path moins attente vsync), goal_bucket_ms_<seau> pour les 35 seaux (recepteur Android de GlobalProfiler = accumulateur ns par nom), gpu_ms_<bucket> pour TOUS les buckets jak1 via lighting_census::pass_begin/end branches dans dispatch_buckets_jak1 et activables par prop/reglage hors armement, dma_chain_bytes_copied, actors_active/actors_paused/joints_evaluated par image, cpu_core_goal, et /data/local/tmp/perf-<pid>.map ecrit par klink. perf_instruments_missing = nombre de ces cles absentes d'une course appareil de 600 images en village1-hut. Aucun pixel ne change : refset_replay_maxdiff == 0 publie a cote.

## Preuve exigee
`perf_instruments_missing == 0` dans `reports/perf-instruments/proof.txt`.
Le proof se produit par `lib/proof_run.sh perf-instruments device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : rien a voir : instrument ; owner_test=false.

## Hors perimetre
Aucune optimisation. Un seul module GPU : etendre lighting_census (SPEC lumiere 7.2, eau 8), jamais un second. Ne touche a aucune feature validee. Le module lighting_census n'est pas archive meme si l'item lighting-census est bloque.
