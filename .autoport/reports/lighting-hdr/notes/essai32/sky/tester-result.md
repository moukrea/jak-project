DIRECTIVES ve7fcbe0116
Diagnostic ciel exécuté sans crash ; défauts conservés, aucune correction/validation de niveau revendiquée.
Un seul run device Redmi eae4df44, --timeout220, essai32-sky-before ; sortie0 ; paramètres31 identiques sauf warpat300→900.
Script exact run-sky-before.sh ; correspondance view-correspondence.md ; preuve originale préservée before-proof.txt.
Lib locale/APK/Redmi SHA243591e44243b0843b14d2bf70c353900936a51cdb94bc483a9bf97ec6cd2a73 ; APK82309530… identique.
Aucun build/verrou au départ ; 11 sources SHA31 vérifiées avant/après ; 85 fichiers du manifeste SHA vérifiés.
Lot batches/essai32-sky-before/20260908T100132-3950103 : 36captures/36samples,432événements composition complets,0non-joint.
duration_s=146
crash=0
frames=2160
hdr_chain_frames=463
hdr_batch_errors=0
hdr_owner_regressions_missing=5
hdr_owner_regressions_failed=1
hdr_tonemap_defects=4
Moyennes6samples nuages8096 après draw, W/N=blanc/nearwhite ; ROI native inclut fond et composition, pas masque nuage seul.
recharged h9 : natif2572,17/4565,83 ; tonemap simulé1728,17/4526,5 ; pixels244800.
recharged h12 : natif1820,17/2476,33 ; tonemap simulé1339,5/2465,5 ; pixels moyens290400 (résolution variable).
recharged h18 : natif0/0 ; simulé0/0 ; pixels244800.
origine h9 : natif2412,83/4511,5 ; simulé0/4511,5 ; h12 natif1418,83/1932,5 simulé0/1932,5 ; h18 tous0.
Queries nuages8096 : passé36/36, PRIM.abe=true ; 8064 mesuré séparément, W/N0.
Soleil h18 : 3composants passent chaque sample (2starflash2+1middot),36/36queries, erreur association0m.
Soleil après sprites : W/N natif et simulé0 dans les2bras ; deltaRGB recharged[1347,42;934,39;0], origine[274,26;426,28;0].
Mesure finale ImageMagick du producteur : ROI ciel[0,0,320,106], h12 recharged W92,33/N270,83 contre origine105,17/262,83.
ROI ciel finale h9 recharged0/0 contre origine0/0,83 ; h18 tous0 ; ces ROI ne sont pas identiques aux ROI natives.
ROI soleil finale[142,67,178,112] h18 W/N0 dans les2bras ; luma192,002 contre193,183.
Détails : native-summary.json, witnesses.json, image-region-summary.json, composition/, analyze.log.
Restauration normale réussie PID9400 stable12s, debug props vides, lib identique, verrou absent (normal-restoration.json).
Aucune source/build/validateur modifié ; aucun generic/owner-ok/autre appareil/relance.
Non prouvé : correction des5régressions, couverture niveau/hutte/village1, rendu Honor ; hdr_batch_missing338/hdr_owner_regressions_measured0.
