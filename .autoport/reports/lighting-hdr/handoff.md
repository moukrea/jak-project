DIRECTIVES ve7fcbe0116
## ÉTABLI
- Deux corrections d’attribution seulement33 : DirectRenderer garde ALPHA(0,2,0,1,0), Sprite3 ajoute ROI disque1395/harddot/mode3 sans lectureGPU nouvelle, union conservée ; aucun shader/courbe/exposition modifié.
- Build incrémental gk+repack rc0 ; lib locale/APK/Redmi dbc383605d0125ed543accfca9f8f471ecbee83839edf76e8492026700fef8b5 ; APKc03d2cd01b9ba4eb940110d25ae4042dca609ea492a0c0d4de713f26d534967e.
- Preuve officielle essai33-compatible/20260908T102706-3974235 :2lots/5paires/5cellules/errors0/missing336/defects4/ownerfailed2missing5measured0. Copies identiques146sources, originals33 et avant32 conservés.
- Ciel33/20260908T102415-3970238 :36captures/360compositions/crash0/frames2040 ;36témoins clouds TBP8096seul ALPHA(0,2,0,1,0), gradient8064exclu (sky/attribution-check.json).
- Cams identiques32 : warpat900,h9cam7:-35:0:30,puis h12/18cam7:-35:0:5000 ; temporal6. Nuages h12ROI[0,0,320,106] W_ON92.5/OFF105.17,N270.67/262.83,luma154.365/155.539.
- Nuages natifs h12pixelsON313200/OFF244800 : seules proportions/moyennes normalisées comparables ; delta luma encodée/pixelON.14224/OFF.13811. Pas ciel plein cadre àh9.
- Soleil h18 trois composants visibles, blanc/nearwhiteOFF0 ; ROI33[142,68,178,111]diffère32, lumaON193.020/OFF194.237,détail8.558/8.367 ; aucun avant/après interlots surROI différente.
- Source soleil32lf1749 middotRGB(1,.50196,0),rayons(.24706,.12549,0),deltaB0 ; weather-part.gc470-478 current-sun.sun-color. Helper attend blancsOFF, éclat reste nonjugé.
- Portail33/20260908T102706-3974235 :24captures/286compositions/crash0/frames1800,61SHAOK ; vraie caméra32 village1-out:-10:-108:152:33,h12/18,warp village1-hut,warpat900,loadsettle240,settle12,temporal6.
- ROI disque[147,42,173,79], native7020pixels,23/24samples ; ONh12-t03lf1489 deux harddot alpha0 passedfalse → ROI absente conservée. Union1395 reste24/24.
- ROI disque avant/après même fenêtre, luma encodéeRec709 h12ON.287784/.335942(n5),OFF.364923/.399655(n6) ; h18ON.260116/.306414,OFF.319271/.364290(n6).
- Delta groupe dans ROI disque h12ON.048157/OFF.034732,h18.046298/.045019 : inclut halos superposés, pas contribution isoléeharddot. L’écart de fond précède sprites/tone map.
- Disque final33W/N0 ; lumaON/OFFh12=85.959/104.012,h18=79.760/95.554 ; saturation.51215/.47884 et.59515/.56523 (hut-portal/image-region-summary.json).
- Sources couleur32harddot1973 variables ND : G*alpha h12ON.035494/OFF.063360,B*.316781/.315243 ; moyennes événements, h18ON7sprites/6frames. Ne pas compenser hasard par teinte.
- Candidat hutte assetGLB SHA479edc590f5362289efdb4aa3ad5e6c0fa56619d48d9b9d2b326a92d2877f028 : mesh0/prim6/material7 vil1-jng-leafyground,tri1104–1135,x[-127.485,-118.610],y[47.187,47.375],z[200.328,209.203].
- Candidat non attribué runtime/ROI ; normales winding-Y,doubleSided. COLOR_0B>R>G ne désigne aucuneheure12/18. Sable vil-beach-01 le plus proche y≈34m sous plateforme. Détails notes/essai33/diagnostic.md.
- Éco acquis29/30 conservés : HDR0déficit10012h18=543.67/1148.33 ;13284PRE/POSTsaines,0bigpuff/starflash/4188témoins. RNGacteur nonrestauré parsidecars ; aprèsORBPOST sparticle.cpp907-963 peut libérer, puis Sprite3culling/TBP/filtre association restent nonreliés.
- Crash31 spawn-bird : symbole*default-dead-pool*=0 avant get-process, LDURtypeee_base-4 PC0x268920c ; pas correction prouvée parwarpat900, seulement contrôle conservé32/33 sans crash.
- App normale restaurée PID16091 stable12s/debugvides/verrouabsent/SHAdbc383 ; notes/essai33/restoration-summary.json. Aucun generic/owner-ok.
## TENTÉ
- Exclusion gradient et ROI disque bornée validées techniquement sur appareil ; aucune correction photométrique déduite artificiellement de compteurs blancs ou couleurs aléatoires.
- Attribution sol parGLB trouve candidat précis, mais ni relation défautowner ni FR3chargé/projection/occlusion prouvés. Aucune nouvelle campagneéco, aucun clamp/quantification/genou/effet artistique.
## RESTE
- Corriger causalement nuages/soleil : attribution nuages maintenant additive seule ; région inclut fond/décor, soleil coloréOFF sans blancs ne prouve ni absence ni préservationéclat.
- Portail : poursuivre terme éclairage du fond identifié en ROI fixe, conserver absence alpha0 et populations ; ne pas retoucher courbe pour compenser l’écart préexistant. Attribuer sol candidat en jeu.
- Éco : liaison slotvecdata→état vivant aprèsORBPOST→soumission/culling/TBP nonrésolue ; aucune absence témoin ne vaut absence effet, pas refaire diagnostics négatifs29/30.
- non prouvé : correction5cas, bilan21niveaux×8h/ciels/intérieurs/vraie hutte/acquis/HDRnatif. Bilan final non exécuté car correctifs ciblés non établis ; cinq obligations restent rouges, aucune validationowner.
