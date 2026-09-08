DIRECTIVES v6133a247b4
## ÉTABLI
- Livré libSHA256008b1f81b596f3593cdd0db00fbbc56de1734f9b62ecc47112801d9ef2f3a480, build/APK/Redmi identiques ; notes/essai26/build-source-color/.
- Rendu : sprite3_3d{,_inst}.frag borne RGB SOURCE après texture avant blend, alpha brut testé avant bornage. Courbe finie essai25 inchangée ; aucun bloom/gain.
- Test GPU adapté essai22 :48PASS/failures0, SDR avant/après exact cas testés, somme additiveHDR>1, alpha conservé ; notes/essai26/source-color/. Pas preuve jeu.
- refset temporel : pas second warp après loadsettle240, ancre par séquence au tick après readback, purge àancre+1 puis samples à+12,+24... ; single-sample/replay conservés.
- Lot officiel essai26-source-color/20260908T070411-3795215 :24captures/crash0/frames1260/draws389/site1 ; probe max5.652 et5587px>1.
- Quatre purges842/916/990/1064 ; chaque bras âges11/23/35/47/59/71, slip0 ; retard interséquences2 explicitement loggé. Première ON12 n'a plus saut global64→109 observé essai25.
- Helper valide repin/date/âge/présence uniforme et exclut seulement timestamp repin des options comparées ; legacy ne couvre PLUS la hutte.171tests passent ; aucun critère qualité changé.
- Aggregate-only officiel : errors0/pairs2/quality_bad1/defects4 ; owner measured1/failed1/missing4/passed0 ;62fichiers du lot inchangés.
- Avant24 et après26 ROI communes/hashes : notes/essai26/before24-after26-regions.json. Avant source ON12 partiel→après : before-source-after-source-regions.json.
- ROI10012h12 avant/après source clipped2269.5→2095.67, blancs62.5→59.67 ; aprèsOFF clipped1648.33/blancs40.33. Réduction observée insuffisante, pas validation.
- H18 après10012 blancsON14.83/OFF65.5, nearwhite58.67/OFF134.17 ; quatre observations éco échouent. Source avantOFF absente, anciensOFF âges différents : pas attribution de tous deltas au shader.
- Témoins avant source1326/510passed : lightning3 nouvellement attribué aux2acteurs ; hotdot10013lf889 passed borneRGB(.251,.251,1.506). Bigpuff/starflash AUCUN événement, pas preuve d'absence rendu.
## TENTÉ
- Cycle1 premier lot20260908T065403-3786348 SIGSEGV GOAL avant mesures, processwarp-gate-switch-3/LRenter-state/lecture typeà-4 ; pas intern_from_c. Source conservée.
- Retry identique20260908T065654-3789494 :6ON12 puis exit1. Nouvelle échéance purgeOFF914 déjà dépassée quand logique915 ; corrigé en ancrant CHAQUE séquence après readback, sans augmenter settle ni enlever sample0.
- Premier agrégat livré rejetait h18 car comparait particle_repin_lf comme réglage ; corrigé/testé, proof_run aggregate-only recalcule sans nouveaux pixels ni changement date source.
- Clamp source ne suffit pas : h12 excès clipped global181, régional10012 manque détail ; h18 manque blancs10012 et excès blancs/aplats10013. Courbe actuelle garde risque plateau>1.05.
## RESTE
- Diagnostiquer contributions de fond éclairé et couches non attribuées avant autre réglage ; nearwhiteh12 dépendait aussi du transitoire et des populations OFF anciennes. Ne pas régler sur compteur255 seul.
- Bigpuff/starflash : PNG extraits directement extracted_textures/jak1/effects/, gris max255/alpha128 ; source bleue>1 possible, mais rayon1.732m actuel ne les attribue pas. Ne pas élargir aveuglément ROI.
- Soleil = groupe35 Sprite3, centreGOAL camera_pos+4096*gs.recharged_pbr_sky_sun brut ; middot1200²m, starflash2 2800×2200m/inverse. Projection/query existants réutilisables ; aucune attribution ni visibilité mesurée.
- Nuages : DirectRenderer vertices projetées/texture8096, mais18quads puis4triangles horizon même état ; aucune ROI actuelle. Ne pas appeler quart haut ou texture entière nuages sans qualification.
- Vraie hutte confirmée acteurs autour(-123,46,214)m, sage(-132.659,46.198,213.468)m. Legacy(-116,14,40)m fausse ; village1-out caméra+50m ne qualifie pas sol. HUT_VIEWS vide reste rouge.
- Portail ancienROI trop large, hotdot centre ne couvre pas portail entier ; harddot3D toujours non attribué. Les4autres cas restent manquants, aucun jugement artistique inventé.
- Après corrections ciblées : couverture21niveaux×8h/ciels/intérieurs/vraie hutte, lots compatibles seulement. Pas nouveau système général de capture ni campagne frame exacte.
- non prouvé : cinq régressions corrigées, tous acquis, alpha destination tous mélanges, HDR natif. Aucun generic/owner-ok lancé/écrit ; voir notes/essai26/ pour commandes, logs, état final Redmi.
- Redmi restauré normal PID14441 stable12s, A35-RENDER frame360/draws70 ; propsdebug vides/verrou absent ; notes/essai26/normal-restoration.json.
