Périmètre : lighting-census, build x86 et preuve courte essai 8.
DIRECTIVES v6fca51fe40
Rôle tester ; aucune source ni validateur modifié.
cmake --build build --target gk -j 6 : code 0, notes/build-essai8.log.
SHA256 gk : bccef39f945059799541dc041f8c099530554fc9837007825fffd8ca17924ab4.
Test direct OG_REFSET=capture OG_REFSET_DIR=.autoport/refset timeout 15 gk : code 1.
REFSET capture refused dir=.autoport/refset operation=reserve-root error=already exists; OG_REFSET_DIR must name a new directory
Lanceur .autoport/lib/refset.sh : bash -n code 0 ; comportement runtime non testé.
Unique bash .autoport/lib/proof_run.sh lighting-census x86 --timeout 180 : code 0.
Runner : frames=9823 crash=0 durée=181s ; preuve produite par runner exclusivement.
Preuve : refset_compared=44 ; refset_replay_maxdiff=254 ; refset_census_replay_runs=0.
Le maximum brut des lignes REFSET cmp est 255 ; le champ global 254 reste celui publié par moteur.
Log REFSET cmp origine : 16 comparaisons, maxdiff=255.
Log REFSET cmp recharged : 16 comparaisons, maxdiff=255.
Log REFSET cmp origine-lumiere : 13 comparaisons, maxdiff=255.
Lignes glReadBuffer dans proof-engine.log : 0.
575 fichiers SHA256 identiques avant/après : 572 PNG et 3 captured-by.txt ; sha256sum -c code0 et cmp manifests code0.
Build builder concurrent laissé finir restauration x86 (1325 targets in48.369s), aucune commande appareil émise par tester.
Parent2541075 suspendu/repris par PID exact avec trap EXIT ; état final Ss (sortie shell).
Preuve : light_census_residual=0 ; light_census_rb_mismatch=0 ; lc_orig_light_un=1047023.
GPU : gpu_timer_supported=1 ; gpu_ms_frames=9717 ; valeurs par passe dans proof.txt.
Horaires : refset_hours_mask=255 ; plan672 étapes ; 2 niveaux et1 intérieur seulement parcourus dans preuve courte.
Archives : essai7-avant8-proof.txt / essai7-avant8-proof-engine.log.
Non prouvé : nouveau dossier capture en exécution, ensemble complet, cinq rejeux, bit-identité des origines, qualité owner.
Aucun generic.sh, ablation, capture complète, build ARM, ni accès appareil exécuté par tester.
