DIRECTIVES va841fb32b6
## ÉTABLI
- Courbe essai23 par canal et alpha essai22 conservés ; cet essai ne corrige PAS le rendu. hdr_tonemap_defects=4, owner missing5 maintenu.
- Refset option capture lighting-hdr `debug.opengoal.refset.temporal=6` : 6 images par bras, cadence12lf, particules animées une fois/lf ; sample0 seul alimente mesures historiques, suffixes-t01..t05 + provenance.
- Vue explicite village1-eco-blue : spawn(9.3109,19.2490,3.2525)m, caméra(-14,-163,0,20) ; évite de collecter aid10012. Parcours par défaut préservé.
- Sprite3.cpp relève texture+distance aux ancres10012/10013/1395, query fragments et4coins2D. camera_w négatif est NORMAL (pfog0=-0.04654684) ; garde >0 corrigée en !=0. Jointure par capture_logic_frame().
- Helper/proof gèrent séquences et mesures ImageMagick rectangles communs ON/OFF/temps ; cellules incomplètes conservées, aucun verdict artistique fabriqué. Tests133passed52.88s, notes/essai24/harness-tests.log.
- Build/repack/install rc0 ; MD5 lib build/APK/Redmi ba3d5711227381380fc9857c70f071b8. Logs/provenance notes/essai24/projection-build/, sources-final.json.
- Lots officiels essai24-projected/20260908T060523-3743175(éco) et20260908T060731-3746070(portail) :24captures chacun, crash0, aggregate4paires/errors0, dernières frames1140, tonemap_sites1.
- Éco :2867témoins,1460queries passed, chaque acteur à12/18h visible6/6frames de chaque bras ; ROIs réellement projetées, contexte inclus (analysis-projected.json).
- Éco10012 blancs moyens OFF→ON h12:89.33→0,h18:25→0 ; quasi-blancs217.83→146.33/89.33→109.67. Éco10013 blancs15.5→0/10→0. Non-validation persistante.
- Portail :4707témoins,686passed, ROIs[0,0,281,180]/[0,0,277,180] presque écran entier ; ne qualifient pas violet local. Tous les cas restent not_judged.
## TENTÉ
- Premier lot deux vues essai24-owner-regions/20260908T055814-3737806 :SIGILL frame1143 à transition éco (A18 type-method-zero),24/48captures ; ne pas refaire deux vues en un processus. Captures/logs conservés.
- Première projection avait688passed mais0supported car garde camera_w>0 injustifiée ; nouveau build corrige diagnostic, pas shader. Ancien binaire dans projection-build/before-build/.
- Lot AVANT essai24-portal-before/20260908T054523-3726435 récupéré par agrégation officielle après édition concurrente de proof_run(rc3). Ne JAMAIS éditer un script shell pendant son exécution ; offsets de lecture déplacés.
- AVANT portail figé vs APRÈS animé : notes/essai24/before-after-regional.json, diagnostic seulement. Aucun AVANT éco équivalent. Sources shader identiques, courbe non retouchée pour obtenir un chiffre.
## RESTE
- Priorité correction concrète : perte des blancs éco reste mesurée, ne pas déclarer les5cas réglés. Identifier domaine/composition avant nouveau réglage ; une simple épaule àk=.95 transforme1→.975 mais n’explique pas seule toutes différences ON/OFF.
- Resserrer attribution portail (textures hotdot/middot/bigpuff partagées, très grandes billboards) ; distinguer effets voisins/fond. Queries prouvent fragments, pas couleur ni silhouette. 3D/double_draw/non-instancié restent unsupported.
- Nuages/soleil/sol hutte toujours sans ROI qualifiée. Soleil direction *sky-parms* upload-data sun0pos ; petites zones sol non identifiées. Ne pas appeler le quart supérieur « nuages ».
- Ne pas utiliser legacy(-116,14,40)m comme hutte : vraie région près(-123,46,214)m. Acteurs et bornes dans entities/village1-actors.json, collectables-part.gc groupe42, village1-part2.gc groupe140.
- Brancher jugement régional défendable dans owner_regressions() : actuellement garde missing5 inconditionnelle, observations diagnostics conservées. Pas seuil arbitraire, pas zéro blanc comme succès.
- Après cinq cas seulement, équilibre21niveaux/8h par lots compatibles. Aucun cumul ancien binaire/config non compatible. Commandes exactes/projected-correspondence.txt dans notes/essai24.
- non prouvé : cinq corrections artistiques, tous acquis, alpha destination tous mélanges, HDR natif. Generic/owner-ok jamais touchés/exécutés.
- Redmi restauré normal PID31713 stable12s,58props debug vides, aucun verrou (notes/essai24/device-restored.json).
