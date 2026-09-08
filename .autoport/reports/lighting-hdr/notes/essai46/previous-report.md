DIRECTIVES v3909a9767c
Essai45 : rendu HDR toujours non validé ; aucune nouvelle correction justifiée hors appareil, preuve historique hdr_tonemap_defects=4.
Deux revues natives Codex researcher (high), vérifiées par le manager ; résultats dans notes/essai45/diagnostic.md.
Aucun doublon de modulation baked trouvé dans les quatre appelants non-PBR de shade.glsl ; correctif43 conservé.
PBR conserve une modulation assombrissante distincte ; activation sur les zones owner non établie, aucun changement spéculatif.
Sol : owner-regions.json43 conserve sage-hut-ground dans unattributed_cases ; rectangles chemin/entrée sans violet, donc sans attribution au défaut owner.
Les témoins disponibles couvrent ciel/sprites ; ni ROI sémantique du sol ni séparation terrain/TIE/décal/ombre. Une paire identique ne résout pas cette absence.
Huit lignes de proof.txt historique, started_at=2026-09-08T18:26:35Z ; aucune preuve fraîche en45 :
crash=0
hdr_batch_missing=338
hdr_owner_regressions_required=5
hdr_owner_regressions_measured=0
hdr_owner_regressions_missing=5
hdr_owner_regressions_failed=1
hdr_owner_regressions_passed=0
hdr_tonemap_defects=4
Le crash=0 cité ne vaut que pour ce lot historique ; aucune conclusion sur l’état courant de l’appareil.
Rendu et harnais inchangés ; aucun build, APK, appareil, replay ou validateur lancé. Rapport/handoff seuls mis à jour.
Empreinte SHA256 de proof.txt et mtime conservés ; contrôle dans notes/essai45/proof-preservation.json.
Owner : Options > Recharged, Lighting ON/OFF avec temps réel actif ; sol vraie hutte, pièce et portail après10s animées, nuages, soleil couchant et éclairs éco.
non prouvé : correction des cinq cas, 21 niveaux×8h/ciels/intérieurs/vraie hutte, détails pleine résolution, menu OFF/persistance, crash0 global et fraîcheur actuels.
Blocage à résoudre par le superviseur : cadrage « aucun appareil » incompatible avec les nouvelles observations nécessaires ; mêmes données seules insuffisantes.
Validateur réservé à l’orchestrateur ; aucun owner-ok. Handoff conservant les acquis43/44 et les manques précis livré.
