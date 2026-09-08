DIRECTIVES v6133a247b4
## ÉTABLI
- Livré30 libbuild/APK/Redmi SHA04bbe8aadcbdf269bab0f27b0957c4b4956e6e05b584057954681c38b3966547 ; seul source modifié TexturePool.cpp265 fallback page/name.
- Un objet C++ recompilé, lien gk/repack/install réussis ; notes30/name-fix/build-deploy.log. Ancienne lib/APK4da80e conservées name-fix/before-build/.
- Preuve livré officielle essai30-texture-name-final/20260908T090324-3899190 :123s/crash0/1260frames/chaîne388 ;24captures/144compositions complètes/61sources scellées.
- Preuve actuelle defects4/errors0/pairs2 ; owner measured1failed1missing4passed0. Aucun generic/owner-ok, aucun changement harnais.
- Éco10012h18 blanc natifON547,5/OFF1146,5 ; ROI finale[119,14,205,118] blancON14,8333/OFF66. H12 ROI[122,21,198,109] ON63,6667/OFF37,3333.
- Témoins finaux4188 : lightning3=1389/lightning=1354/lightning2=1343/hotdot=102 ; bigpuff/starflash=0. name-fix/witness-summary.json, engineSHAa81f03e5da5bf9a4fe56deea32fd21f70951adfa7f4792caf1393cfe0843c329.
- Ablation29 reste établie : perte éco10012h18 persiste HDR0 avantcourbe, populationsdifférentes ; ne pas la refaire ni régler courbe pour elle avant attribution.
- Diagnostic30initial essai30-particle-path/20260908T084935-3886407 spart.dump1 :112s/crash0,130naissances liées par spr/usr(5hotdot+30bigpuff+30starflash par acteur), sans nonfini.
- Diagnostic30différé essai30-particle-delayed/20260908T085446-3891165 spart.dump35 :111s/crash0 ; ORB pendant captures, mais effective OFFh12 perdu : lot officiellement rejeté/logs incomplets, pas preuvejeu.
- notes30/analyze-orbits.py→orbits.json vérifie61sources :13284paires PRE/POST bleues,1PREsansPOST ; alpha bigpuff32/starflash32..63,0POSTnonfini,maxcentre.449305/.717837m,écart rayon<=.14unitéGOAL.
- Différé engine318910-911 bigpuffCPU1a1c30alpha32,318966-967starflashCPU1a1600alpha54 avantONh18lf1001 ; OFF337749-750/337805-806sains. Sondes sanslf : ordre/horodatage seulement ; CPU scratchpad réutilisé.
- Parent10012 différé316694hotdotspr15e19c0→316778bigpuffspr15dbff0/usr15e19c0→starflashusr15dbff0 ; centre(9.3108873,20.0489807,11.2524662)m.10013centre(6.6918254,20.1725330,20.4516411)m.
- Rayon filtre1.73205m contient halos correctement liés (.8+.75<=1.55m). AlphaBORN0 volontaire puis restauré cpu+124→sprite+44(sparticle.cpp544/571), confirmé ORB.
- App normale restaurée PID30506stable12s/debugvides/verrouabsent/SHA04bbe8 : notes30/name-fix/normal-restoration.json.
## TENTÉ
- Sondes existantes uniquement : dump1 plafonne ORB avant bleu ; dump35 couvre orbite mais perd logs. Ne pas refaire ces campagnes, exploiter données scellées.
- TexturePool fallback concaténait effectsbigpuff, incompatible frontière de mot Sprite3 ; séparateur corrigé au producteur, mais toujours0halos mesurés : cause de leur absence non confirmée.
- Aucun réglage gamma/clamp/bloom, aucune réinitialisation forcée RNG, aucune extension aveugle ROI. Chaîne HDR et orbiteur ne suffisent pas à expliquer défaut observé.
## RESTE
- Attribuer disparition entre étatCPU sain et identification/soumission géométrique : slotglobal→DMA→do_block_common/culling→TBP/nom. Noms des buckets exclus non tracés ; zéroGORBSKIP n'est pas exhaustif, SPR3-CULL exclut bleu(B==0/G>=100).
- Correctif rendu éco demeure non livré ; AVANT24-projected/28/29 conservés, ne pas déclarer un effet absent sur seule absence du témoin.
- Nuages roof=SKY_DRAW+PRIM.tme(2×9quads),pas TEX08096seul ; soleil groupe35/1950-1952,middot/starflash2,centre camera+4096*sun.pos : aucune ROIruntime.
- Vraie hutte sage23aid15730 JSON6975(-132.6594,46.1975,213.4677)m ; camera-start15aid10345 JSON6794(-138.4481,49.2789,203.3405)m,q(0,.410689652,0,.911775172),visibilité/sol non prouvés. Legacy≠hutte.
- Portail27 disqueROI[110,28,192,152] inclutfond ; halos/violet non jugés ;30eco horsvueportail. Quatre cas manquants restent échec dans owner_regressions.
- Après corrections ciblées : couverture21niveaux×8h/ciels/intérieurs/vraie hutte et acquis ; anciens binaires diagnostic uniquement sauf compatibilité démontrée.
- non prouvé : cinq régressions corrigées, couverture finale/acquis complets, HDR natif. Notes30 diagnostic.md et name-fix/tester-result.md détaillent résultats et limites.
