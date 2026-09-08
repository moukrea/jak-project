DIRECTIVES ve7fcbe0116
Non terminé : la preuve officielle conserve quatre défauts ; aucun correctif de rendu n’est livré dans cet essai.
Changement : deux vues diagnostiques exécutées et sources rapprochées, aucun code/configuration permanent modifié.
Redmi uniquement ; aucun build, aucun generic/owner-ok ; lib243591e44243b084 identique locale/APK/appareil.
Deux processus : ciel146s/36captures, hutte-portail131s/24captures ; 146sources scellées vérifiées.
Agrégat officiel proof_run : essai32-compatible, 2lots compatibles, 5cellules, 336obligations de couverture manquantes.
Huit lignes de proof.txt :
crash=0
frames=1740
hdr_chain_frames=389
hdr_batch_errors=0
hdr_batch_count=2
hdr_owner_regressions_missing=5
hdr_owner_regressions_failed=2
hdr_tonemap_defects=4
Soleil h18 enfin visible : disque et deux rayons, 36/36queries ; blancs/quasi-blancs OFF et ON absents, cas non jugé.
Nuages h12, région finale : blancs ON92,33/OFF105,17 ; quasi-blancs ON270,83/OFF262,83 ; aucune validation qualité.
Portail disque visible24/24captures ; luma ON/OFF h12=85,98/106,35, h18=80,73/95,92 ; saturation ON supérieure.
À entrée identique la courbe retire au plus3,1875/255 : elle seule n’explique pas cet écart portail (inférence, curve-bound.json).
Résolution native et populations varient ; composition/éclairage en amont non isolés, aucun réglage compensatoire ajouté.
Crash31 localisé dans spawn-bird lisant *default-dead-pool*=0 ; les deux départs retardés900 n’ont pas crashé, cause initiale non résolue.
La garde ABE31 ne sépare pas gradient8064 et nuages8096 : les deux portent prim_abe=true ; mesures séparées conservées.
Repères owner : Options > Recharged ; nuages, soleil couchant, éclairs éco bleue, sol devant Samos, portail.
non prouvé : correction des cinq cas, attribution du sol, couverture21niveaux×8h/ciels/intérieurs/vraie hutte, acquis et HDR natif.
App normale restaurée : PID10576 stable12s, propriétés debug vides, verrou absent ; aucun jugement Honor.
Détails : notes/essai32/diagnostic.md ; rapports sky/tester-result.md et hut-portal/tester-result.md ; handoff.md.
