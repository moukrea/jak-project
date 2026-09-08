DIRECTIVES v3909a9767c
Essai 44 : défaut de conservation du jugement portail corrigé ; rendu HDR toujours non validé, hdr_tonemap_defects=4.
Hors appareil conformément à la mention « aucun appareil » du prompt ; aucune nouvelle correction du rendu ni livraison APK.
hdr_batches.py protège désormais actor=1395/portal_disc lors des remplacements : échec régional conservé, identité/réglages compatibles et région cible mesurable exigés.
Une collecte incomplète reste remplaçable ; aucun seuil, critère final, cumul, validateur ou owner-ok modifié.
Tests synthétiques : ancien code : 19 échecs / 2 succès ; patch : 294 tests réussis en 82,90 s, exit 0 (notes/essai44/portal-replacement-after.log).
Revue indépendante tester et manager ; bash -n et git diff --check réussis. Ces tests ne prouvent pas le jeu.
Intégrité hors appareil : lib 0f1a5b25e21ebb4a identique au manifest, 5/5 sources contrôlées et 37/37 fichiers scellés conformes (offline-integrity.json).
proof_run.sh --hdr-aggregate-only a recalculé le lot essai43-rendu-ground ; exit 0, sans appareil ni rafraîchissement.
Preuve du 8 septembre : started_at=18:26:35Z, mtime=18:29:14Z ; durée 159 s du manifest contre 164 s ancienne proof, écart conservé dans offline-replay-verification.json.
Huit lignes recopiées de proof.txt, issues exclusivement de ce recalcul officiel historique :
crash=0
hdr_batch_missing=338
hdr_owner_regressions_required=5
hdr_owner_regressions_measured=0
hdr_owner_regressions_missing=5
hdr_owner_regressions_failed=1
hdr_owner_regressions_passed=0
hdr_tonemap_defects=4
Portail : revue des traces 43 LF 2521/3181, bleu maximal 15,3359 / 17,2344 après groupe Sprite3, canaux négatifs 0 / nonfinis 0 ; contribution individuelle non isolée.
Les alphas et positions des effets varient entre bras ; aucune faute de blend ou arithmétique nouvelle démontrée. Pas de réglage spéculatif de courbe/gain.
Correction 43 de shade.glsl conservée ; anciennes comparaisons pièce/sol dans notes/essai43-rendu/.
Nuages/soleil et éco : diagnostics négatifs 41/30 conservés, pas rejoués. Petites zones violettes du sol toujours sans attribution sémantique.
Owner : Options > Recharged, comparer Lighting ON/OFF, sous-option temps réel active ; pièce et sol de la vraie hutte, portail après 10 s animées, nuages, soleil couchant et éclairs éco.
non prouvé : correction visuelle des cinq cas, 21 niveaux × 8 h/ciels/intérieurs/vraie hutte, détails pleine résolution, menu OFF/persistance et crash 0 global actuel.
Aucune campagne ni navigation nouvelle possible dans la restriction appareil de cet essai ; aucune absence transformée en succès.
Rapport de diagnostic : notes/essai44/diagnostic.md ; handoff à jour. Validateur laissé à l’orchestrateur.
