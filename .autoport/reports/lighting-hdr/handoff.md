DIRECTIVES ve7fcbe0116
## ÉTABLI
- Livré31 libbuild/APK/Redmi SHA243591e44243b0843b14d2bf70c353900936a51cdb94bc483a9bf97ec6cd2a73 ; final/build-deploy.log :1objetDirect+lien/repack15s/installOK.
- Première livraison31 cff81791ac7773bf865da7f1c5e7d891813ecffe49067063651cc35b915ab6a0 :5objets/repack19s. Les deux anciennes livraisons sont sauvegardées avant-build.
- Sources : DirectRenderer SKY_DRAW+tme+abe (dernière garde sépare gradient opaque8064 du roof8096) ; Sprite3 acteur0 sunset-sun,3couches/4eROI, contexte cloud séparé ; aucun réglage couleur.
- Soleil attribué par middot/starflash2 et camera/4096+sun brut ; résidu0m dans les lots cff817, borne0.05m ; projection/query existantes. Horsborne : HDR-OWNER-SUN-ASSOCIATION, sans ROI fabriquée.
- hdr_batches.py raccorde couches/provenance/ROI commune, soleil exige3composants distincts visibles+h18 ; nuages partiels ne passent jamais ; remplacements préservent pertes.210tests pass74.77s (hdr-batches-tests.log).
- Dernière preuve officielle essai31-sky-final/20260908T094715-3936986 :64s/crash1/frames420/chaîne0/0captures/11sources scellées ; defects5/errors6/owner measured0missing5.
- Crash frame431 :SIG11 fault0x7efffffffc PC_GOAL0x268920c LR0x2688e5c (final/gk_crash.txt), avant refsetstart600/cadrage500m/sondes. Cause inconnue ; nouvelle garde non activée.
- App normale restaurée PID8102stable12s/debugvides/verrouabsent/lib243591 ; final/normal-restoration.json. Pas generic ni owner-ok.
- Lot cff817 essai31-sky-attributed/20260908T093142-3927217 :140s/crash0/24captures/288compositions/61SHAOK/errors0 ; beach-start cam7:-35:0:30 h12/18 temporal6.
- Nuages8096 h12 natif aprèsdraw blancON5505/OFF5667, simulationcourbeON3226.33 ; nearwhiteON9173.5/OFF9731.33. Gradient8064 séparé dans attribution/attributed-native-summary.json.
- Région finale premierlot [0,0,320,123] mêle décor : blancs/quasi-blancs0deuxbras ; soleilh18 36associations exactes mais36passedfalse/deltaRGBA0 ; ciel82pm seulement.
- Lot cff817 essai31-sky-visible/20260908T093902-3931924 :117s/crash0/24captures/288compositions/61SHAOK ; h12cam45:-35:0:30, h18cam7:-35:0:250 via cambyhour.
- Secondlot soleil36témoins :9passedtrue tousOFFstarflash2, disque0deuxbras ; ONdeltaRGB0/OFFdeltaRGBmoy(.0660,.03595,0), région44663px. Nuagesh12 blancs/quasi-blancs natifs0deuxbras ; visible/native-summary.json.
## TENTÉ
- Baseline31 village1-out50m :235s/crash0 mais24captures achromatiques, jamaisvi1VIS/A42-VISl1=0/LOADSCREENarm5jusqu’à5760 ; LS_HOLD_TARGET. level.gc1230 exige inside-boxes depuis math-camera1253.
- Caméra haute probablement horsboîtes ; pas prédicat mesuré. Beachcam3m chargebeaVIS et atteint stance. WANT-LEVELS=village1 invalide aussi27/30 ; remplacé par beach,village1, pas cause unique revendiquée.
- Dernier cadrage intrinsèque ciel : h9cam7:-35:0:30 pour chargerVIS puis h12/18cam7:-35:0:5000 ; crash AVANT cette transition. Ne pas le qualifier de crash à500m. Correspondances explicites conservées.
- Ni genou/gamma/clamp/bloom retouchés ni mesure précédente réutilisée comme preuve du binaire243591. Les vues sans blancs/disque visibles ne permettent pas un réglage causal ; arrêter les cadrages aveugles.
## RESTE
- Résoudre crash GOAL ci-dessus et obtenir vue réellement lumineuse comparable via instruments existants ; démontrer gardeABE finale active. Exploiter sources31 avant nouveau réglage rendu.
- Nuages : distinguer accumulation HDR native (bleu>1) et perte courbe simulée du rendu FINAL ; ROI actuelle mêle décor. Soleil : disque encore occulté, pas de cas complet ; critère blancsOFF absent doit rester explicitement non jugé.
- Sol vraie hutte : sage23aid15730 JSON6975(-132.6594,46.1975,213.4677)m ; camera-start15aid10345 JSON6794(-138.4481,49.2789,203.3405)m q(0,.410689652,0,.911775172). Matériaux/ROI non attribués.
- Portail27 disqueaid1395/harddot mode3 ROI[110,28,192,152], ancre(-123.10158,50.40380,214.22531)m ; cam village1-out:0:-115:80:44, h12/18. Halos/rayon8m non qualifiés ; pas de nouvelle preuve31 du portail.
- Éco29/30 inchangé : perte10012h18 persisteHDR0 ;13284pairesCPU PRE/POST saines (notes30/orbits.json), mais bigpuff/starflash0sur4188témoins malgré fallback noms corrigé. Ne pas refaire clamps/quantification/nommage/ORB ; reste chaîne slot→DMA→soumission/culling/TBP.
- non prouvé : correction5cas, bilan21niveaux×8h/ciels/intérieurs/vraie hutte et acquis, HDR natif. Aucun nouveau correctif rendu livré31 ; notes détaillées notes/essai31/diagnostic.md.
