# Handoff — lighting-census, essai37
DIRECTIVES v6fca51fe40
## ÉTABLI
- Source livrée : qualification stricte v2 + état observé/reconstruit, provenance et runner lots ; docs .autoport/tools/refset_qualification.md et refset_campaign.md.
- Binaire final1082eb1b117c91f6 ; certificat notes/essai37-qualification/candidate-final-source.json. Baseline existante/scellée inchangée.
- Preuve finale :24comparaisons, maxdiff0/diffpx0, state_bad0, ressources2254/2254 égales ; gate254/incomplete, missing652, aucune adoption.
- Racine finale + baseline extérieure : chemins dans notes/essai37-qualification/qualification-final-plan.json ; env candidate-final-village1-out-replay.json.
- Capture finale attempt-1788809303428033159-a64e874d ; rejeu attempt-1788809533742803846-7365c806, sous notes/essai37-qualification/campaign/.
- Origine extérieure finale8/8 exactes ; TEX1 natif corrigé, hutte8/8 aussi exacte sur e46f852aaeb8c5a1 (diff final ultérieur : qualification uniquement).
- Cinq rejeux par bras d065f16c2f4a0165 archivés dans legacy-five-replays-audit.json ; NE PAS les créditer au binaire final.
- Sunkenb chargé h09 : LF=stateLF2282, bg0/57600 ; sky écrit57600RGB puis ocean28480/tie40035/tfrag50971. final-sunkenb-attribution.json cite les traces.
-575historiques, shaders123/118 intacts ; tests26Python+C++ stricts, NPC47 ; final-integrity.json/test-results.json. Aucun appareil touché.
## TENTÉ
- Qualification a refusé village1-out malgré selfreplay exact : baseline-image-diff, gate255 ; huit images maxdiff6/diffpx2429.
- Seule garde TEX1 maîtreOFF supprimée : écart extérieur éliminé, legacy reste exact. Ne pas refaire diagnostic shrub/bootstrap/ROI acquis.
- Audit a fermé datasetA adopté sous runB et assets changés avec snapshot réempreinté ; tests négatifs255, sans changer validateur.
- Sunkenb : sonde unique caméra livrée, pas calibration ; ciel exécuté mais aucun pixel final de fond. Cause/pose admissible non résolue.
- Pas de qualification globale : autres vues et cinq rejeux du binaire final non achevés ; état observé non exhaustif, HDR/Android non prouvés.
## RESTE
- Résoudre couverture Sunkenb sans masque/tolérance/exemption ni campagne visuelle ; sa présence sky ne démontre pas une pose admissible.
- Achever672cas/28vues/21niveaux/3modes/8heures/≥4intérieurs et ciel150..900‰ ; conserver Sunkenb manquant tant que non démontré.
- Recettes autres niveaux : bootstrap17 actors-sweep/CONTINUE=village1-hut inchangés, WANT_LEVELS="" et WANT_DISPLAY="", LOAD_SETTLE1200 ; exemple candidate-final-sunkenb-attribution.json.
- Ne changer aucune surcharge caméra pour qualifier : elles rendent calibrated=true. Aucun réglage testé n’est une preuve de couverture globale.
- Cinq rejeux par racine requis : finale extérieure candidat1/5, baseline0/5 ; noms distincts runner, puis manifeste des paires complètes.
- Réutiliser seulement si sources/binaire/données/entrées identiques ; source modifiée invalide les anciens reçus, un commit sans changement source ne les invalide pas.
- Pas de rebuild sans modification pertinente ; baseline déjà bâtie, acquisitions32/33/35 conservées. Aucun changement manuel version2→1.
- Produire uniquement par proof_run ; generic orchestrateur, aucune adoption forcée/owner-ok. Suite après qualification : HDR/tonemap SDR.
