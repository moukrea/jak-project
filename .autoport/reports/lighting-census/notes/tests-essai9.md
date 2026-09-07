Essai 9 : build rc0 et preuve courte produite ; porte non validée, 24 PNG legacy identiques à essai 8 et différents des références.
DIRECTIVES v6fca51fe40
Rôle tester ; aucune source ni validateur modifié ; aucun appareil, commit, sous-agent ou autre CLI.
Commande unique : cmake --build build --target gk -j 6 ; rc=0 ; build-essai9.log.
SHA256 gk : c5872fcb023087e0385fdc16e9e547a96945facea43ef2dbfb908c0f0c8ec151.
Warnings build : bool vers int (-Wsign-promo), variables locales v/d masquées (-Wshadow).
Commande unique : OG_GECHO_MERC=1 bash .autoport/lib/proof_run.sh lighting-census x86 --timeout 150 ; rc=0.
Huit lignes recopiées de proof.txt :
duration_s=151
crash=0
frames=8581
light_census_total=3517130
light_census_residual=0
light_census_rb_mismatch=0
refset_compared=38
refset_replay_maxdiff=254
Autres grandeurs publiées : lc_orig_light_un=604632 ; gpu_ms_buckets=6.9000 ; refset_census_replay_runs=0.
Comparaisons brutes38 ; origine16 max249, recharged14 max255, origine-lumiere8 max210. Maximum brut255, global publié254.
24/24 SHA256 PNG legacy identiques essai8↔9 ; legacy-png-sha-essai8-essai9.tsv contient les deux empreintes.
575 fichiers de référence inchangés, contenu ET liste : manifests refs-before/after-essai9.sha256 identiques ; sha256sum -c rc0.
Archives essai8 : essai8-avant9/proof.txt, proof-engine.log et refset-actual/ (24PNG).
Archives essai9 : essai9-proof.txt et essai9-proof-engine.log ; sortie runner proof-run-essai9.log.
Erreurs : 7839 GL_INVALID_OPERATION sprite = 2613 chacune glUniform4 u_hdr_curve, glUniform(location=4), glUniformMatrix(non-matrix uniform).
Signature GL préexistante essai8 : 8784 GL_INVALID_OPERATION dont2928 u_hdr_curve, glReadBuffer0 (lecture archive confirmée par manager) ; aucune conclusion de non-régression globale.
38 erreurs screenshot to clipboard NYI non-Windows ; zéro glReadBuffer, SIGSEGV, SIGILL, SIGABRT ou terminate called.
Après première REFSET pose ligne5010 (x=-116 y14 z40 cap163) : hutlamp-lod0 présent146 fois ; aucune attribution de pixel.
Noms GECHO après pose : money, medres-beach3, medres-beach2, windspinner, crate-iron, farmer, hutlamp, medres-jungle1, medres-beach, medres-beach1, sidekick, eichar, seagull, lurkercrab, crate-wood (tous suffixe -lod0).
Comptes exacts dans gecho-models-essai9.json ; tris=0 ne prouve pas une absence de géométrie (compteur alimenté par un autre diagnostic).
Builder PID2541075 vérifié bash auto_build_apk.sh + unique enfant sleep240 ; aucun compilateur/verrou avant suspension.
STOP du seul PID2541075, trap EXIT CONT dans run-essai9.sh ; état final repris Ss (session-essai9.log).
Aucun generic.sh, ablation, capture/replay séparé ni reconfiguration CMake.
À examiner : persistance exacte des écarts legacy et erreurs uniformes sprite ; pas de verdict visuel produit.
Non prouvé : cinq rejeux complets, bit-identité aux références, couverture complète, causalité pixel de hutlamp et qualité owner.
