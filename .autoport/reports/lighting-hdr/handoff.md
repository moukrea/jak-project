DIRECTIVES v6133a247b4
## ÉTABLI
- Final livré libSHA2564da80ef748d4b54c5e916a1205bc00259b3d8941339900d2dc072ad99e8dfdda identique build/APK/Redmi ; notes/essai28/build-deploy/restored/.
- Seul diff jeu : Sprite3.cpp diagnostic deux lectures natives avant/après groupe2d entier, régions déjà projetées ; aucun correctif artistique retenu. Shaders/header exacts HEAD27.
- Composition lit float/half/UNORM sans écrêter la lecture, restaure états GL, loggue RGBA/min/max/mean/négatifs, Δ joint et simulation shoulder ; erreurs explicites. Cible MSAA ou >1920*1080 non mesurée.
- Émission initiale tronquée1023octets ; fragmentsJSON<=800 avec event_id/lf/actor/stage/index/count au producteur. Test240fragments/max798, manque/doublon rejetés ; collecteur notes28/collect-composition.py.
- Lot final essai28-composition-final/20260908T082212-3861448 : crash0/duration101s/frames1140/site1/draws390 ;24captures,144compositions complètes/0tronquée,61sources scellées intactes.
- Proof final defects4/errors0/pairs2/cells2 ; owner measured1/failed1/missing4/passed0. Pas de cumul des binaires incompatibles, pas generic/owner-ok.
- Éco10012h18 final blanc NATIF pré-courbe ON553,83/OFF1149,67 ; simulation ON478,33. H12 ON1413,17→1273,33/OFF1434,17. Boîtes variables par capture incluant fond et toutes couches, pas attribution particule.
- RGB et alpha non négatifs avant/après groupe, alpha[0,1] : dette négative pré-sprites écartée sur ces régions et étapes. ΔRGB légèrement négatif aussi OFF, pas soustraction individuelle attribuée.
- ImageMagick ROI commune27/final h18 : blancsON14,67→14,5, OFF65,83→64,83 ; nearwhiteON58,83→58,33/OFF134,17. H12clippedON2098,67→2116,67/OFF1656 ; défaut persiste.
- Sources avant24 comparées/conservées dans before24-after28-final-regions.json ; protocole24 différent, jamais preuve compatible finale ni correction attribuée à28.
- Sources27/28 h18 ne sont PAS identiques malgré mêmes45/43draws : upper somme rouge*alpha sample4ON10,212/OFF10,324, sample5ON9,001/OFF10,848 ; texture/area fade/contributions individuelles inconnues.
- Hutte confirmée par entité village1-actors.json6975 aid15730 etype=sage name=sage-23 à(-132,6594,46,1975,213,4677)m. Ancre valide, sol/materials et ROI non identifiés.
- Nuages : sky-tng.gc109 giftag-base sans tme/abe/iip ;114-124 roof avec cesbits ;794-802 deux couches9quads puis805/813-816 horizon nontexturé. TEX08096 commun ne suffit pas ; bucketSKY_DRAW+PRIM.tme distingue.
- Portail27 : harddot185/23passed,middot340/93passed,hotdot3276/234passed,bigpuff0attribué. Query passée peut porter alpha0 ; pas preuve apport lumineux. Halos/couleur et h12invisible restent non jugés.
- Redmi normal restauré PID24537 stable12s/A35-RENDER frame300 draws37 ; props debug vides/verrou absent, normal-restoration.json.
## TENTÉ
- Quantification contribution additive Q8(Cs*As)/As seulement sprites monde flottants, alpha/courbe intactes ; bancGPU réel1724PASS/264comparaisons, DITHERon, HDR>1. Équivalence exacte non revendiquée.
- Première comparaisonGPU avant=après accidentelle retirée, superseded conservé ; corrected-reference.log utilise vraiHEAD SHA64148feb. Aucun faux acquis retenu.
- APRES essai28-additive-quantized/20260908T081522-3855987 actif via quantized_instances, crash0/24captures : écoh18ON14,5 vs avant14,67 ; aucune correction. Candidat retiré intégralement, sourcesdiff et lots conservés.
- Premier run28 crash sig11/faultEE_BASE-4/PC0x30edf20/LR0x4d2f68 identique crash26, frame307 avant sonde ; warp-gate-switch-3/basebutton-down-idle, pool source nul inféré dans spawn. Aucun fix GOAL hors scope.
- Remplacement explicite h12/h18 essai28-composition/20260908T080341-3846859 réussi ; premier lot20260908T075934-3842984 conservé. Trois incréments groupés, aucun cmake-B/GOAL/clean.
## RESTE
- Attribuer la perte AVANT courbe à fond/recouvrements/populations réellement différentes, surtout bigpuff/starflash sans lienCPU proc ; ne pas recommencer clamps alpha/RGB ou quantification, ni régler courbe sans cause.
- Composition finale complète disponible notes28/composition-final/ ; utilise les champs/ROI natifs et Δ joint, pas des images comme preuve visuelle. Sourcecode final instrument seulement.
- Soleil groupe35/parts1950-1952 connu ; nuages attribution PRIM désormais précise mais ROI/visibilité non mesurées ; vraie hutte ancre confirmée mais petites zones non attribuées ; portail halos/violet non corrigés.
- Après corrections ciblées seulement : couverture21niveaux×8h/ciels/intérieurs/vraie hutte par lots compatibles. non prouvé : cinq régressions corrigées, acquis complets, HDR natif.
