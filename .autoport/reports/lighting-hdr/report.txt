DIRECTIVES vb7966a3839
Critère machine atteint : hdr_tonemap_defects=0 sur Redmi ; validation de l’orchestrateur et appréciation owner non revendiquées.
Correction livrée : A42 lit le framebuffer HDR avec GL_FLOAT, conserve ses valeurs et restaure les états de lecture ; aucun effacement des erreurs après lecture.
Compilation incrémentale TFragment + lien, repack réussi en 19 s ; diff --check réussi. Harnais cumulatif et validateur inchangés dans cet essai.
Bibliothèque SHA256 ec1726c1202f3983a2ed0d6ff06da360efdee6a70f6b5088f34a088264804721 ; MD5 build/APK/Redmi e9611463df5d877d04d428061a9e92d3.
Provenance binaire neuve : campagne essai21-readback recapturée ; anciennes données conservées pour diagnostic, jamais déclarées compatibles sans preuve.
Huit lignes exactes du proof.txt officiel, début 2026-09-08T03:59:09Z, durée 360 s :
```text
serial=eae4df44
crash=0
frames=840
FEATURE lighting-hdr armed=1 hits=71072
hdr_batch_pairs=200
hdr_batch_missing=0
hdr_batch_errors=0
hdr_tonemap_defects=0
```
Couverture : 200 paires, 25 vues, 168/168 cellules, 21/21 niveaux ; tous ciels requis, intérieurs et hutte couverts (measurements.json).
25 lots conservés, dont 22 contribuent aux paires ; remplacements explicites, zéro erreur et quality_bad=0 ; aucun flag historique additionné.
Swamp : caméra native start 60:0:50:25, ciel 185‰ aux huit heures ; lot 20260908T032102-3631467.
Sunkenb : amorçage helix puis start −8:90:0:2700, ciel 303–304‰ aux huit heures et intérieur helix ; lot 20260908T031529-3628144.
Ogre : reprise ciblée après délai 160 s insuffisant ; 16 captures en 348 s, sans crash, lot 20260908T035912-3673185.
Chaîne finale : tonemap_sites=1, hdr_probe_max_x1000=10898 ; groupes hdr_defect_3/5/6=0 dans proof.txt.
225 traces A42 dont 103 lectures float, zéro erreur préexistante et zéro refus before-probe dans les 22 lots retenus (notes/essai21/readback-campaign-check.json).
Courbe Fidélité 0, exposition 1, genou 0,95 conservés ; luma équilibrée +4,6032/255, 94 cellules plus claires et 74 plus sombres.
Proportions équilibrées OFF→ON : blancs 0,03735 %→0 % ; quasi-blancs 0,06830 %→0,01459 % ; écrêtage coloré 2,27096 %→0,76752 %.
Résidus : Beach h12 conserve 15 545 pixels écrêtés et distance de teinte 0,360 ; Ogre h18 luma +37,630/255, Ogre h12 aplats +0,11387.
Ces mesures ne déterminent pas une correction uniforme ; aucune calibration locale supplémentaire appliquée. Détails pondérés et sources : notes/essai21/quality-review.md.
À regarder : Options > Recharged, ciels Swamp/Sunkenb, Beach/Training et hutte à midi, Ogre/Rolling ; luminosité, couleur et détails ombres/hautes lumières.
Un SIG11 Sunkenb avant warp reste archivé puis remplacé ; les arrivées Swamp dock/cave1 ne sont pas corrigées, leur couverture utilise la vue autorisée.
non prouvé : résolution de ces crashs, satisfaction artistique du défaut owner, calibration locale et ensemble des acquis.
non prouvé : ordre/identité GPU complet, Filmique 1, coût GPU et sortie écran HDR native.
Redmi relancé normalement ; propriétés debug.opengoal vides, aucun verrou (notes/essai21/device-restored.json).
Validateur réservé à l’orchestrateur ; aucun owner-ok/backlog modifié. Commandes, échecs et mappings : notes/essai21/campaign-runs.jsonl.
