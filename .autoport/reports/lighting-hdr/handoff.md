DIRECTIVES va841fb32b6
## ÉTABLI
- Essai22 alpha conservé ; nouvelle correction : tonemap.frag épaule C1 indépendante par canal, miroir probe_scene hdr.cpp actualisé. Genou0.95/exposition1/Filmique/alpha inchangés.
- Shader réel Mesa : (2,1,2) vert0.498864→0.975 ; gris/Filmique/alpha inchangés, 27cas failures0 (notes/essai23/curve_gpu.log). Ce test ne vaut pas preuve jeu.
- Build incrémental/repack/install exit0 ; lib SHA256 f66f7e91a3e9c0217bcbdca549d93449062659559628133cba5e27dfb4fc7d98 ; MD5 build/APK/Redmi78ed373e74b40a8aa56ccfe28464d083.
- Proof officiel lot essai23-channel/20260908T053521-3717470 :120s, crash0, frames1200, hits672253, tonemap_sites1, quatre paires/deux cellules, erreurs0.
- hdr_tonemap_defects4 : groupes1/2/4=1 couverture incomplète ; groupe7=1 cas owner manquants5 ; groupes3/5/6=0. Aucun validateur modifié/exécuté.
- ImageMagick hashes/relecture vérifiés : village1-out h12 quasi-blancs ON0→1264, OFF1340 ; blancs ON0/OFF768 ; luma ON123.474→128.986/OFF133.197 (notes/essai23/after-analysis.json).
- Statistiques image entière seulement ; aucun LOADSCREEN-SHOW. Pas de preuve régionale ni séquence éco, pas de validation artistique.
## TENTÉ
- Remplacement maxRGB par même épaule par canal après diagnostic numérique ; restaure contributions faibles, mais blanc unitaire reste0.975, et (8,2,8) devient presque blanc.
- Parcours inchangé legacy,village1-out h12/18 ; warp village1-hut/loadsettle240/orderhour1/settle12/warpat300/want.display=village1,display/want.levels=village1. Commande et manifeste dans notes/essai23/after-channel.log et lot.
- AVANT réutilisé seulement en diagnostic : essai22-alpha/20260908T052020-3705704 ; shaders/proof/binaires AVANT conservés notes/essai23. Pas de cumul avec nouveau binaire.
- Recherche lecture seule trouve ancres sémantiques, pas des régions effectivement rendues ; les chiffres globaux ne lèvent donc aucun des cinq cas.
- Revue : ldr_ref_delta compare épaule Fidélité exposition1 au clamp du même pixel ; sa baisse est mathématique, jamais preuve ON/OFF. Limite préexistante Filmique/exposition documentée.
## RESTE
- Priorité régions : calculer cadrages/ROIs projetés et présence réellement rendue, conserver cas absents/non jugés ; ne pas appeler tout le quart supérieur « nuages ».
- Portail decompiler_out/jak1/entities/village1-actors.json : aid22318=(-123.1058,46.1975,214.2314)m ; émetteur aid1395 group-village1-sagehut-warpgate=(-123.1016,50.4038,214.2253)m, groupe140 village1-part2.gc.
- Éco bleue : aid10012=(9.3109,19.2490,11.2525)m et aid10013=(6.6918,19.3725,20.4516)m, eco-info[3,1]. refset.cpp particle_step_mode gèle après g_plan_base+g_step_settle : ajouter une courte fenêtre temporelle à la capture existante, pas exact-frame.
- Soleil : direction *sky-parms* upload-data sun0 pos déjà transmise hud-classes-pc.gc ; projection/cadrage absent. Petites zones sol hutte non identifiées.
- ATTENTION legacy=(-116,14,40)m est à~178m des entités sagehut : commentaire « hutte » insuffisant pour qualifier le sol demandé.
- Brancher jugement régional et séquence dans helper/proof autorisés, puis équilibre21niveaux/8h par lots compatibles. Ne pas refaire cumul ni census, garder garde missing5 tant que régions absentes.
- non prouvé : cinq corrections artistiques, tous acquis, alpha destination tous mélanges, HDR natif. Pas de campagne21niveaux tant que cinq cas prioritaires non qualifiés.
- Redmi relancé sans debug/verrou, PID24706 (notes/essai23/device-restored.json). Handoff précédent remplacé, détails préservés notes/essai22.
