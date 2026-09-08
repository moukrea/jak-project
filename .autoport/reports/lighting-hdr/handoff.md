# Handoff — lighting-hdr essai40
DIRECTIVES v708c60642a
## ÉTABLI
Lib32d5e7e2e9f427d8/APK883014b77b6fe30e… installés Redmi ; identité notes/essai40/build-final/device-identity.json, publieur inchangé.
Correctif4branches alpha HDR background/Generic ; source alpha séparée selon DirectRenderer, OFF conservé, HUD exclu explicitement par bool uses_hud aux3appels.
Tests GPU hôte8cas PASS dont HUD HDR ; build final17.7s/repack69.9s. Ce test ne lie pas les fonctions C++ et ne prouve pas image entière.
Portail officiel398s/4560frames/crash0/hits1029885 ;4captures/21fichiers scellés/0hash divergent ; hdr_batch_errors0,hdr_tonemap_defects4.
Attentes aprèspurge ON54.494/109.762s,OFF42.632/84.271s ; âges659/1319,notes/essai40/portal-final/timing-and-witnesses.json.
ROI disque natif7020pixels : alpha maxON2→1,alpha>1 occurrences87→0 sur2samples avant/après ;OFF max1/0. alpha-before-after.json conserve sources/hashes39/40.
RéglagesSHA78108670… exacts,propsvides,PID3726 identique aux lectures séparées de12s ; CGO/packs inchangés. Crashes/menu ON acquis39 conservés, pas refaits.
## TENTÉ
Premier candidat cf1aa0ff… appliquait aussi alpha au HUD HDR/RGBA8 ; revue a imposé bool uses_hud. Lot arrêtéSIGTERM PID4176807 avant capture,exit-15.
Trace portal/interrupted-engine.log conservée,réglages restaurés ; ne jamais agréger ce lot incomplet. Seul portal-final porte preuve complète.
Courbe/exposition inchangées : imposer f(1)=1 ne résout pas composition et nécessite plateau/expansion. Aucun bloom/assombrissement ajouté.
Alpha corrigé ne résout pas rendu : disque ON/OFF blancs27.5/29.5,nearwhite41.5/48.5,luma102.022/127.016,détail25.018/26.754,saturation.4889/.4263.
RG amont reste ON(.26316,.24246) contreOFF(.37386,.35096),B aprèssprites1.33186/.64777 ; voir portal-final/native-summary.json.
## RESTE
Corriger rendu nuages/soleil puis sol/portail indépendamment éco ; cinqcas inchangés,0passé,2échecs partiels dans lot40. Éco29/30 conservé sans répétition négative.
Nuages39 : f(1)=.9875,1537.5blancs→1117 après courbe sur mêmes pixels ; sourcefichier notes/essai39/sky/composition. Pas réutilisés comme preuve40.
Soleil39 disque+2rayons avecblancsOFF0 : helper nonjugé malgré photométrie partielle passée ; aucune garde changée40.
Helper nuages/portal_disc partiel,sol sansROI,HUT_VIEWS vide : résoudre couverture sémantique sans fabriquer réussite ;21niveaux×8h/ciels/intérieurs/vraie hutte non exécutés,343éléments manquants40.
non prouvé : ombresOFF/persistanceOFF,imageOFF et HUD entières,correction des5cas,stabilité horsparcours. MenuON/retourON établi39, ne pas refaire navigation.
Validateur à l’orchestrateur,aucun owner-ok ; dernier proof neuf rouge4,rapport≤40lignes mis à jour.
