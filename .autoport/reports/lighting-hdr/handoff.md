DIRECTIVES v6133a247b4
## ÉTABLI
- Correctif expérimental livré : épaule quadratique C1 par canal (k=.95, blanc fini1.05), shader tonemap.frag + miroir hdr.cpp ; expo/alpha/Filmique conservés. Ce n'est PAS une correction complète.
- Build incrémental/repack/install rc0 ; MD5 lib build/APK/Redmi4040690090e5b5aa4a3989dc2c78d124 ; notes/essai25/build/. GPU shader réel8001points, max_slope_jump.0100732 ;27cas/0échec.
- APRÈS officiel essai25-finite-white/20260908T063147-3766137 :24captures, crash0, frames1140, hits271323, tonemap_draws388/sites1, agrégat errors0/pairs2, hdr_tonemap_defects4.
- Avant essai24-projected conservé et non réutilisé comme preuve du nouveau binaire ; vue/heures12,18/temporal6/config identiques. Comparaison ROI communes/hashes : notes/essai25/before-after-regions.json.
- Éco10012h12 blancs ON0→56.67, OFF88.67 ; quasi-blancs ON146.33→155.83, OFF217.17. h18 blancsON41.67/OFF25.5. Excès global clipped75 après tolérance : quality_bad1.
- owner_regressions branché aux mesures reconstruites scellées : measured1/failed1/missing4/passed0. Midi échoue nearwhite/aplats et clipped acteur10013 ; deux cellules soir satisfont les contraintes régionales.
- Qualification impose2acteurs par cellule sélectionnée, chaque sample visible ; moyenne ON dans enveloppe OFF, détail/aplats/clipped directionnels. Absence heure entière, doublons, remplacement effaçant défaut mesuré échouent.158tests passent (harness-tests-regional-final.log).
- Redmi restauré normal PID6459 stable12s, swap1200,58props debug vides/verrou absent ; notes/essai25/device-restored.json. Aucun generic/owner-ok touché.
## TENTÉ
- Premier APRÈS20260908T062547-3759803 :SIGSEGV frame385 avant toute capture, tonemap_draws0 ; PC libgk+0x7100b8 intern_from_c/kscheme.cpp:1296, écriture tag sur symbol_slot nul, pile jak1_work_v3. Source conservée.
- Unique retry IDENTIQUE avec --hdr-replace deux cellules : réussi, ancien crash conservé dans campagne ; aucune hausse arbitraire settle. Commandes notes/essai25/command-eco*.txt.
- L'épaule finie réduit le seuil blanc8bits rationnel~2.225 à~1.03, mais crée un plateau et ne suffit pas aux autres métriques. Ne pas déclarer « blancs revenus » égal à succès ; ne pas poursuivre réglages sur le seul compteur255.
- Clamp RGB sprites envisagé puis NON appliqué : lightning64/64/128→(.502,.502,1.004), ne rétablit pas blanc ; couchesbigpuff/starflash plus bleues non attribuées, causalité non prouvée.
- Transitoire conservé : éco10012h12 ON0 luma106.45/flat.125 puisON1 155.11/.011 ; identique AVANT106.33/.125→154.64/.011. Aucun sample retiré.
## RESTE
- Diagnostiquer transitoire avant nouveau réglage : config phase2/h12 dèslf600, ancre842, repin-particules843 tue lanceurs/remet local-clock0 ; ON0lf854 âge11,ON1lf866 âge23,OFF0lf926 âge83, pas nouveau repin OFF. Asymétrie établie, causalité couleur non prouvée.
- Ne pas augmenter settle ni retirer sample0 pour fabriquer vert. La préparation introduit population initiale différente ; vérifier ce point et les couches eco bigpuff/starflash/lightning3 hors attribution actuelle avant correction source.
- Corriger pertes h12/excès clippedh18 sans nouveau bloom ni assombrissement global ; la courbe finie actuelle est un essai rouge, risque d'aplats soleil à garder explicite.
- Portail : ROIs anciennes presque écran entier ;338hotdot/348middot passed, centrehotdot[151,87,158,93] seulement10frames, harddot3D non couvert. Ne pas appeler ce centre portail entier ; pas de nouveau lot portail cet essai.
- Nuages/soleil/sol hutte toujours sans ROI qualifiée : vraie hutte(-123,46,214)m, legacy(-116,14,40)m n'est PAS hutte. Le cumul historique compte encore legacy comme hutte : ne pas utiliser ce faux rattachement pour fermer couverture.
- Soleil18h direction calculée(-.033783,.126079,-.991445), caméra candidate village1-out:7:19:0:500 ; aucune visibilité prouvée. Nuages sky-tng.gc2couches9quads, aucune attribution capturée.
- Couverture21niveaux×8h/ciels/interieurs/vraie hutte après corrections ciblées ; non lancée car éco encore rouge, autres4non jugés. Données anciennes incompatibles restent diagnostic.
- non prouvé : cinq corrections artistiques, tous acquis, alpha destination tous mélanges et HDR natif. Pas de validation propriétaire fabriquée.
