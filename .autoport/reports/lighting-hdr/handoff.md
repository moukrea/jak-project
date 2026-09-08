DIRECTIVES v6133a247b4
## ÉTABLI
- Lib livrée d3a7658defe4286424968852bb7e4ac87e68eb9c20d6c1960687f0bf7a66047f identique build/APK/Redmi ; notes/essai27/build-deploy/final/.
- Quatre shaders Direct bornent RGB SOURCE après modulation/fog/tests, comme Sprite3 essai26. Alpha/destination HDR/courbe/exposition inchangés ; aucune causalité éco démontrée.
- GPU162PASS/failures0,48comparaisonsSDR exactes, HDRadditif>1 ; helper189passed. Notes direct-source-color/ et portal-regions/. Pas preuve jeu.
- Sprite3 mode 3 projeté selon vrai GLSL ; harddot+ancre1395+mode 3 porte layer=portal_disc.816rotations/12viewports/4 cas W invalides sans échec ; boîte conservative, pas empreinte exacte.
- Lots officiels campagneessai27-direct-source : éco20260908T073326-3821099 et portail20260908T073655-3825740, chacun 24 captures/crash0 ; 389 draws/site1 chacun.
- Éco : paramètres/configfiles/propriétés identiques avant26/après27,61 fichiers scellés par lot vérifiés ; before-after-compatibility.json et before26-after27-regions.json. Avant24 aussi conservé/comparé, protocole différent.
- Éco10012h18 blancsON14.83→14.67/OFF65.5→65.83 ; nearwhiteON58.67→58.83/OFF134.17→134.67. H12clippedON2095.67→2098.67/OFF1648.33→1647.83 : défaut persiste.
- Éco26 analyse4188témoins tous additifs : populationsh18diffèrent mais sample4 mêmes45dessins blancs2ON/23OFF ; sample5 mêmes43 blancs0/138. Fond et chevauchements non attribués ; eco-populations/.
- Bigpuff/starflash y0..16 est ANGLE orbiteur, pas une hauteur ; rayons.3..45m/.2..3m autour rootsphère+.8Y. Ne pas élargir rayon 1.732 ; collectables-part.gc et sparticle_launcher.cpp561-597.
- Portail caméra avant24 reprise : village1-out:0:-115:80:44.185 harddotmode 3,23 passed/24 captures ; ROI[110,28,192,152], distincte grand halo. H12sample4ON invisible : nonjugé.
- Portailh18 tous samples visibles, OFFwhite0 ; flatONmean.06060758>OFFmax.04978420. Helper juge partie photométrique sans exiger blanc OFF ; éco garde exigence blanc OFF. Warp reste missing, défaut partiel failed.
- Aggregate-only officiel : errors0/pairs4/defects4 ; ownermeasured1/failed2/missing4/passed0.122 sources scellées+mtime+started_at intacts ; aggregate-preservation-check.json.
- Redmi normal restauré PID 17645 stable 12s, A35-RENDER frame360/draws88, props debug vides/verrou absent ; normal-restoration.json. Aucun generic/owner-ok.
## TENTÉ
- Correctif Direct cohérent avec UNORM mais effet éco quasi inchangé : ne pas le présenter comme correction des blancs. Pas réglage de courbe supplémentaire sans cause.
- Dette négative avant éco non établie : groupes 42/140 additifs ; ombres Jak1 bucket47 multiplicatives ; faux shadows soustractifs après particules monde. Sonde pré-tone-map ne mesure pas minimum.
- Premier build supersédé après garde label portal_disc réservée mode 3 ; second incrément final livré, aucun run intermédiaire. Pas reconfiguration manuelle.
- Wrappernotes faux SIGILL sur commentaire «pckernel top-level doesn't SIGILL» ; signatures fatales corrigées et mêmes logs relus. Proof_run exit0/crash0 inchangés, aucun retry appareil.
## RESTE
- Corriger éco : diagnostiquer contribution du fond éclairé/couches non attribuées. ON/OFF coupe aussi RT/éclairage ; f(1)=.9875 seul n’explique pas perte>=245 avec des sources positives identiques. Courbe plateau>=1.05 persiste.
- Bigpuff/starflash toujours sans témoin attribué ; lien déterministe CPU cpuinfo.key.proc et user-sprite/binding disponible. Dump SPART-ORBPRE/POST existant expose cpu/centre/rayon, pas key.proc ; ne pas conclure absence de rendu.
- Portail : corriger aplats/couleur locale, qualifier halos ; conserver h12 non jugé et h18 failed partiel. Disque seul ne valide jamais warp entier. Sources notes/essai27/portal-events.json.
- Soleil groupe35 : centre math-camera-pos+4096*sun brut, middot1200m et starflash2 dimensions 2800/2200 ; projection/query existantes réutilisables, visibilité non mesurée.
- Nuages SKY_DRAW :18 quads puis4 triangles horizon texture8096 commune ; besoin d’attribution des primitives, pas quart d’écran arbitraire.
- Vraie hutte : legacy(-116,14,40) incorrect ; village1-out caméra haute ne qualifie pas sol. Trace(-132.6594,46.1975,213.4677) attribuée logo/logo-slave/jak-hd, pas explicitement sage ; matériaux des petites zones inconnus. HUT_VIEWS vide reste rouge.
- Après corrections ciblées : couverture21niveaux×8h/ciels/intérieurs/vraie hutte, lots compatibles seulement. non prouvé : cinq cas corrigés, acquis complets, HDR natif.
