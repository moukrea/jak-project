# Handoff — lighting-hdr, essai44 hors appareil
DIRECTIVES v3909a9767c
## ÉTABLI
Correction 43 shade.glsl non-PBR conservée, aucune nouvelle modification rendu 44. Lib SHA 0f1a5b25e21ebb4a identique manifest 43;5/5 sources et 37/37 fichiers scellés conformes (notes/essai44/offline-integrity.json).
Acquis 43 : pièce luma ON/OFF64.223/91.365→91.299/91.099 et détail 15.767/20.222→20.191/20.216 ; sources notes/essai43-rendu/portal-comparison.json.
Garde 44 hdr_batches.py : check_owner_replacement protège actor=1395/portal_disc, échec régional et mesurabilité/configuration du remplacement ; aucun seuil/qualification owner modifié.
Tests : ancien helper : 19 échecs / 2 succès ; patch : 294 succès en 82,90 s exit 0 (notes/essai44/portal-replacement-{before-fixture-fixed,after}.log).
Replay officiel proof_run --hdr-aggregate-only ground43 exit 0 : defects=4, missing=338,owner required=5/measured=0/missing=5/failed=1/passed=0 ; pas preuve fraîche.
Preuve horodatée 8 septembre 18:26:35Z ; durée 159 s manifest contre 164 s ancienne proof ; mtime=18:29:14Z conservé (offline-replay-verification.json).
## TENTÉ
Prompt 44 indique « preuve exigée SUR APPAREIL aucun appareil » : aucun appareil, build, déploiement ou validateur exécuté. Restriction appliquée à cet essai.
Diagnostic portail existant43 revu : LF 2521/3181 bleu après 15,3359 / 17,2344, négatifs/nonfinis0 ; snapshots couvrent groupe Sprite3 entier. Pas faute de blend nouvelle établie.
Sources harddot diffèrent entre bras (alpha ON .831/.800,OFF .533/.125) ; pas identité exacte exigée, mais attribution quantitative causale manquante. Aucun patch couleur spéculatif.
La courbe 0 active est mathématiquement monotone/bornée ; perte de rapports chromatiques au plateau possible, aucun calcul fautif démontré. Notes/essai44/diagnostic.md.
Nuages/soleil 41 et éco 30 : pistes négatives déjà documentées non rejouées. Petites zones violettes sol toujours sans ROI sémantique.
## RESTE
Poursuivre rendu seulement sur vues exploitables quand appareil autorisé : sol vraie hutte/pièce/portail prioritaires, nuages/soleil et éco obligatoires ; aucune priorité HD/cache/allocateur/menu.
Le correctif 44 protège les défauts, ne résout aucun des cinq cas. Ne pas reconstruire cumul ni remplacer attribution absente par blanc 0 ou statistiques globales.
Portail après chaque reset : 10 s animées tracées ; snapshots actuels ne séparent pas chaque contribution. Pas écrêtage/blend/gain inventé à partir du seul surplusHDR.
Final toujours requis :21 niveaux × 8 h/ciels/intérieurs/vraie hutte, cinq cas, menu OFF/persistance et crash 0 global actuel. Pas de mélange de lots incompatibles.
Préférence historique restaurée 43 realtime-lighting?=#f ; tests 43 forcent RT=1. État appareil courant inconnu en 44 ; aucune restauration prétendue nouvelle.
Rapport ≤40 lignes avec 8 lignes proof livré ; validateur orchestrateur, aucun owner-ok. Ancien handoff complet dans notes/essai44/previous-handoff.md.
