DIRECTIVES ve7fcbe0116
Deuxième et dernier run sans crash : portail/disque mesurés, sol vraie hutte nonattribué ; aucune correction ou validation revendiquée.
Entrée proof_run lighting-hdr device, essai32-hut-portal, --timeout220, script exact run-hut-portal.sh, sortie0.
Cam village1-out:-10:-108:152:33, h12/18, warp village1-hut, warpat900 ; correspondance géométrique consignée view-correspondence.md.
Anciennevue50m et preuves ciel conservées ; aucun remplacement de manifeste.
Préflight : lib locale/APK/Redmi243591e44243b0843b14d2bf70c353900936a51cdb94bc483a9bf97ec6cd2a73 ; APK82309530… identique.
Aucun build/verrou ; 11sources essai31 identiques avant/après ; 24options nonlighting identiques entre samples.
Lot batches/essai32-hut-portal/20260908T100652-3955392 : 24captures,61fichiers SHA vérifiés,288compositions complètes,0non-joint.
duration_s=131
crash=0
frames=1740
hdr_chain_frames=389
hdr_batch_errors=0
hdr_owner_regressions_missing=5
hdr_owner_regressions_failed=2
hdr_tonemap_defects=4
Portail aid1395 : 2824témoins natifs, queries toutes connues ; disque harddot visible sur24/24frames.
Disque : 2queries/sample ; passées h12 recharged6/12,origine6/12 ; h18 recharged7/12,origine6/12.
Composition native portail agrégée après sprites, moyennes6samples W/N(blanc/nearwhite) :
h12 recharged4,17/6,17 (tonemap simulé3/6,17), origine8/10,67 (simulé0/10,67).
h18 recharged6,83/9,67 (simulé6,5/9,67), origine3/4,83 (simulé0/4,83).
Ces rectangles natifs mêlent fond/portail ; résolution variable et populations sprites différentes, pas de diagnostic causal isolé du disque.
ImageMagick final disque ROI[147,42,173,79] : W/N0 tousbras ; luma h12 recharged85,980 contre origine106,348 ; h18 80,734 contre95,916.
Disque saturation h12 0,52062 contre0,48738 ; h18 0,60209 contre0,55220 ; histogrammes12teintes disponibles image-region-summary.json.
Disque détail/aplats h12 21,846/0,01426 contre20,985/0,01167 ; h18 19,334/0,01370 contre19,808/0,00815.
ROI portail entière h12[106,13,197,89], h18[106,10,197,88] : W/N0, luma61,689/72,190 et52,372/62,762.
Portail détail/aplats h12 20,211/0,01207 contre19,410/0,01193 ; h18 16,348/0,02487 contre17,799/0,01503.
Queries/textures : portal-query-summary.json ; sources traces : portal-witnesses.json, composition/, native-summary.json.
Restauration normale : PID10576 stable12s, debug props vides, lib243591 identique, verrou absent ; normal-restoration.json.
Aucun build/source/validateur modifié ; aucun generic/owner-ok/autre appareil/relance.
Non prouvé : sol sage-hut-ground (aucune attribution instrumentée), couverture vraie hutte, correction5régressions, rendu Honor.
