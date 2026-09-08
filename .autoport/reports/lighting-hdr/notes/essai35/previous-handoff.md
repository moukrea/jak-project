DIRECTIVES ve7fcbe0116
## ÉTABLI
- Rendu33 RESTAURÉ : shader fa9aa99adec7be401c49b4f32f9529b8a8220f76f462ffe0f08f2843910335d3 ; lib locale/APK/Redmi dbc383605d0125ed543accfca9f8f471ecbee83839edf76e8492026700fef8b5 ; APKc03d2cd01b9ba4eb940110d25ae4042dca609ea492a0c0d4de713f26d534967e.
- Livré34 : hdr_batches expose partial_photometry sans faux measured/passed lorsque blancsOFF absents ; nuages requièrent TME+ABE+ALPHA(0,2,0,1,0), pas TBP codé en dur. 249tests synthétiques passent.
- Preuve officielle essai34-restored-compatible/20260908T105825-4009021 :2lots/5paires/5cellules/errors0/missing336/defects4/ownerfailed2missing5measured0 ; copies identiques146sources, originaux conservés.
- Cielrestauré/20260908T105548-4005557 :36captures/360compositions/crash0/frames2040,36nuages8096ALPHAadditif sans8064 ; h9cam7:-35:0:30 puish12/18cam7:-35:0:5000,temporal6,warpat900.
- Nuages h12 ROI fixe[0,0,320,106] restauréON W92.667/N271.167/détail3.7841 ; OFFW110.167. Soleil ROI fixe[142,68,178,111] ONdétail8.6609/flat.098186,OFFflat.088095. Éclat reste nonjugé.
- Portailrestauré/20260908T105825-4009021 :24captures/288compositions/crash0/frames1740,ROI[147,42,173,79],7020px/960x432,24disques/48harddot ; caméra33 village1-out:-10:-108:152:33,h12/18,warp village1-hut,settle12/load240.
- Pré/post sprites portail restauré h12ON.287597/.346022 OFF.364710/.399929 ; h18ON.260097/.308824 OFF.319212/.361915, codesRGB pondérésRec709, pas luminance linéaire. Finalh12ON/OFF89.658/103.708,h18=80.594/95.044,W/N0.
- Modulationunité retry/20260908T110110-4012960 :24captures/286compositions/crash0/1800frames,23disques ;4propriétés rt.litboost100/shadowmul100/tintlit0/tintshadow0 attestées, settings identiques. NON livré.
- Intradiag préON/OFF h12.372284/.370209,h18.326578/.324636 ; ROI[140,15,181,72]/16851px diffère témoin. Implication modulation, pas ampleur causale isolée. AbsenceOFFh18t05lf1735:2harddot passedfalse,alphas.015686 et0.
- Premier diagnostic34/20260908T104314-3989922 conservé :crash1/frames0/captures0,11SHA ; log4733 reserve-root existe. SIGABRT via exit→destructeurthread joignable. Créateurracine inconnu ; course garde enabled staticint plausible, non prouvée.
- Nouveaux settingsSHA78108670 diffèrent33d67a26ee (ambient-model2→1 notamment). Ne pas réutiliser33 comme preuve compatible. Même78108670 dans tous lots34 réussis ; préférences owner conservées.
- Retourowner bouton sans différence : settings master#t/lighting#t/pbr-materials#f/realtime-lighting#f ; campagnes épinglent RT1. Usage normal/menu non prouvé. Redmi restauré PID24040 stable12s/debugvides/verrouabsent.
- Sol candidat33 inchangé : GLB479edc59…,mesh0/prim6/material7 vil1-jng-leafyground,tri1104–1135,x[-127.485,-118.610],y[47.187,47.375],z[200.328,209.203] ; aucune attributionruntime/occlusion/ROI.
- Éco29/30 conservé : déficit HDR0 h18 acteur10012=543.67/1148.33 ;13284PRE/POSTsaines,0témoinsbigpuff/starflash/4188 ; actorRNG nonrestauré, lien aprèsORBPOST→libération→Sprite3culling/TBP non résolu. Pas reruns ORB/clamps.
## TENTÉ
- Candidat tonemap aux4texels avant bilerp UI : une build incrémentale Shader.cpp+repack, liba8a8ed4e…, ciel36+portail24captures sanscrash. Retiré faute bénéfice établi ; backups/patch/tests math sous notes/essai34/.
- 99shaders embarqués parbin,98identiques, seultonemapchange. Candidat nuagesW81.167/détail3.7722,soleilflat.133333 ; aucune amélioration démontrée. Comparaison33 confondait aussi changementsettings.
- Même config34 ne suffit pas : h12OFF candidat960x432,restauré5×1440x648+1×1680x756. Portail candidatROI[133,0,188,65] versus restauré33ROI, malgré mêmesposition/corner_w ; projection non expliquée. Ne pas attribuer strictement les écarts au filtre.
- Unitémodulation rapproche préON/OFF mais ROI différente ; pas de gain/teinte compensant aléatoire, aucun correctif artistique livré. Notes détaillées diagnostic.md et rapports parlot.
## RESTE
- Corriger nuages/soleil causalement ; source solaire33middotRGB(1,.50196,0),rayons/4,blancOFF absent ne prouve pas absence éclat. Nuages natifs perdent des blancs avec épaule mais aucun réglage correctif établi.
- Pour prochaine comparaison filtrage : stabiliser résolution via réglages existants dynamic-render-scale?#f+render-scale fixe<100, sauvegarder/restaurer préférences. renderscale.native1 existe mais supprime agrandissement donc ne teste pas cette hypothèse.
- Expliquer projection portail variable, garder absences/populations ; attribuer fond puis sol candidat en jeu. Ne pas comparer fenêtres différentes ni compenser couleurs RNG.
- Examiner écart régime preuveRT1/usage normalRT#f et nouveau retourmenu ; aucune validation du bouton à partir de captures forcées.
- Éco reste obligatoire avec traces29/30, absence de témoin jamais absence effet ; crash31spawn-bird/default-dead-pool0 non corrigé parwarpat900.
- non prouvé : cinq corrections, bilan21niveaux×8h/ciels/intérieurs/vraie hutte/acquis ; HDR natif ensuite. Aucune campagne finale car correctifs non établis, aucune validationowner ni generic lancé.
