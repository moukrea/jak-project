DIRECTIVES v6133a247b4
## ÉTABLI
- État rendu exact essai28, lib build/APK/Redmi SHA4da80ef748d4b54c5e916a1205bc00259b3d8941339900d2dc072ad99e8dfdda ; zéro changement jeu/harnais/build29.
- Diagnostic unique29 via proof_run : batches/essai29-hdr-disabled/20260908T083423-3872799, HDRfalse24/24, hdr_chain_frames0, crash0/duration109s/frames1200,144compositions complètes.
- Protocole identique28 : village1-eco-blue h12/18,temporal6,settle12,loadsettle240,warpat300,orderhour1 ; seule propriété hdr0, batch séparé et rejet _ON_capture_did_not_use_HDR maintenu.
- notes29/compare-ablation.py→ablation-comparison.json :61+61sources scellées intactes ; APK/binaire/config identiques ;4188événements sprites identiques horslf entre28/ablation29 dans24cas. Pas identité ON/OFF, textures/area fade non journalisées.
- Éco10012h18 blancs natifs après groupe : HDR28 ON553,83/OFF1149,67 ; HDRdésactivé29 ON543,67/OFF1148,33. Le déficit pré-courbe persiste sans chaîne HDR.
- ROI finale commune[119,14,205,118] : HDR28blancON14,5/OFF64,83 ; ablation29ON8,67/OFF65,67. H12 HDR63,5/40,5 ; ablation38,17/37,5. La chaîne augmente ici les blancs comptés.
- Populations28/29 éco10012h18 visibles ON239/OFF265,lightning3 72/89 ; h12 256/256. Majorant rouge avant texture h18ON9,20591/OFF10,32389 ; pas énergie attribuée.
- Fond natif28h18 RGBmoyenON(.217,.269,.217)/OFF(.192,.253,.190), blancs0/0 ; delta groupe/pixelON(.0997,.1902,.4888)/OFF(.1220,.2221,.3638). Boîtes variables/fond/toutescouches, aucune attribution locale.
- Éco10013h18 blanc natif28ON229,33/OFF126,17, inverse10012. Source28 engineSHA dafba3f288727c4c895bb0c305448b15dd562f5dc40f75d323e5fa0183e8b8f0 ; composition-events.json notes28/composition-final.
- Reprise CPU : bigpuff/starflash bit7 utilisent y=angle, PAS hauteur16m ; sparticle_launcher.cpp565-590,sparticle.gc194-228. Rayons .30..45m/.20..30m, chaîne<=.75m autour hotdot parent suivant centre primitive(sparticle-launcher.gc804).
- Trace28engine3675 actor_rng_state=not-restored-by-sidecars ; seed lf3 ligne3774 ; repins h18lf990/1064. kill-and-free-particles ne réinitialise pas accum/RNG/root ; kill-it modifie néanmoins flags des bindings vivants. Âges11..71≠même population.
- Hutte ancre village1-actors.json6975 aid15730 sage-23(-132.6594,46.1975,213.4677)m ; sol/matériaux/ROI inconnus. legacy n'est pas cette hutte.
- Nuages SKY_DRAW/PRIM.tme distingue roof(2×9quads) de horizon/base ; TEX08096 seul insuffisant. Soleil groupe35/parts1950-1952, chemin effectif/ROI non mesuré.
- Portail27 disque h18ROI[110,28,192,152],lumaON79,13/OFF96,39,saturationON.61494/OFF.57432 ; fond mêlé, halos/violet non jugés ; final28/29 portail no_visible_roi.
- Preuve livré réémise officiellement aggregate-only lot28 20260908T082212-3861448, timestamp original : defects4/errors0/pairs2,owner measured1/failed1/missing4/passed0 ; notes29/proof-delivered.txt.
- App normale restauréePID25963 stable12s,debugvides/verrouabsent,sha inchangé : notes29/normal-restoration.json. Aucun generic ni owner-ok.
## TENTÉ
- Ablation HDR0 ciblée ci-dessus exclut la nécessité du float/tone map pour reproduire le déficit10012. Elle ne prouve pas cause unique ni correction ; aucun réglage aveugle retenu.
- Piste Distort alpha fausse et retirée : Sprite3_Distort.cpp38-39 GL_TEXTURE_SWIZZLE_A=GL_ONE déjà présent ; ne pas la refaire.
- Pas de nouveaux clamps/quantification : essais26/27/28 les ont déjà traités ; pas nouveau système capture ni correction artistique.
- Source bigpuff/starflash reste sans attribution runtime ; le rayon de1.73m ne peut être déclaré fautif sur la seule lectureCPU. Ne pas élargir aveuglément ni réinitialiser le moteur pour forcer identité.
## RESTE
- Corriger la perte éco après attribution locale du fond/recouvrements/populations : HDR seul désormais insuffisant comme cause. Exploiter logs28/29 et ROI existantes ; ne pas refaire l'ablation ni régler courbe pour cette perte avant attribution.
- Absence bigpuff/starflash : établir lien entre parent hotdot/centre primitive réel et ancre fixe, sans inventer offsets ; statCPU dans notes29/diagnostic.md. État RNG/populations différent à traiter statistiquement, pas exact-frame.
- Nuages/soleil/vrai sol hutte/halos portail : quatre régions non jugées, aucun correctif rendu ; owner_regressions reste strict. Finir les corrections ciblées avant campagne finale21niveaux×8h/ciels/intérieurs/vraie hutte.
- non prouvé : cinq régressions corrigées, acquis complets, couverture finale, HDR natif. Notes29 diagnostic/comparaison/proof/tester-result sont conservées, sources24/27/28 intactes.
