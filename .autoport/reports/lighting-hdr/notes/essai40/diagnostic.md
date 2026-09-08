DIRECTIVES v708c60642a

Reprise depuis les acquis essai39, sans refaire les chargements/menu déjà établis.
Référence : notes/essai39/portal/composition/composition-events.json, acteur1395,
before_world_sprites : alpha max2 ON,1 OFF ; 43 à80 pixels alpha>1 selon échantillon/ROI.
Les alpha sources sont bornés dans generic.frag et tfrag3.frag ; les mélanges encore
couplés RGB/alpha produisent Ad+As², Ad-As² et Ad(As+1), hors intervalle possible.
Le générique précède PARTICLES ; le draw exact auteur du dépassement n'est pas attribué.

Correction candidate : uniquement chaîne HDR, quatre branches de background_common.cpp
et Generic2_OpenGL.cpp reprennent les facteurs alpha de DirectRenderer. RGB inchangé
pour un draw à destination identique ; l'évolution de la destination alpha change ensuite.
La branche OFF reste textuellement identique. Ce n'est pas une reproduction du clamp
alpha historique SDR ; c'est un alignement sur la convention déjà employée en HDR.
Ne pas revendiquer correction portail/sol avant mesure ni disparition des cinq défauts.

Courbe conservée : essai39 cielh12 mêmes pixels1537.5blancs→1117 simulés après courbe.
Avec k=.95, f(1)=.9875 ; imposer f(1)=1 à une courbe monotone bornée impose plateau
au-delà1, et une transition C1 exigerait expansion préalable. Aucun réglage arbitraire.
Soleilh18 blancs0/0 n'est pas défaut établi : photométrie partielle passée, disque+2rayons
présents. Le helper refuse actuellement de juger faute de blancsOFF ; aucune garde modifiée.
Le helper ne peut actuellement passer nuages/portail/sol ; HUT_VIEWS vide ne couvre
aucune vraie hutte. Couverture et cinq cas demeurent requis, non validés.

Revue avant fin du premier run : Generic setup sert aussi au HUD différé surRGBA8,
alors que chain_active reste vrai. Le premier candidat aurait changé son alpha.
SIGTERM exact4176807 avantpremièrecapture ; log conservé portal/interrupted-engine.log,
exit-15, restaurationSHA78108670… exacte, PID580 identique aux lectures séparées de12s, aucune preuve revendiquée.
Correction : bool uses_hud transmis aux3appels Generic, nouvelles équations seulement
chain_active&&!uses_hud. Nouvelle lib et nouveau lot requis ; le premier lot reste diagnostic.
