DIRECTIVES v14fcd1a084

Critère préexistant du moteur : shrub_trunk_anchor_defects=0.
Publié par foliage_wind.cpp:1625 ; aucune nouvelle clé moteur.
La somme exige troncs et jonctions présents, zéro ancre de tronc, zéro écart de pivot arrondi au millimètre et des ancres de feuillage.
Elle ne mesure ni déplacement GPU ni mobilité de chaque couronne.

La garde locale lit des blocs contigus du code CPU et GLSL actuel ; elle ne lit aucune preuve historique.
Elle refuse leur suppression ou changement, même si le texte retiré subsiste en commentaire.
Un refactoring équivalent demande une revue explicite de ces blocs.
Le recensement exécute cette même garde et pytest ; son code retour est jugé par generic.sh.
Le banc C++ provient du test attempt-9-contract-test.cpp, promu sous tests/harness en source Python pour être inclus dans l’empreinte verdict_sources.
Ses échantillons sont synthétiques ; aucune sortie synthétique ne remplace une clé moteur de proof.txt.
Seuls les codes retour de la garde et de pytest sont publiés par le recensement.

Vérification avant course : build_x86.sh --target gk --check-only, sortie 0, bx_bin_fresh=1, bx_residual_work=0.
Tests ciblés avant course : 7 passed in 2.51s.
Cinq mutations de copies : exclusion du tronc, pivot au sol, ajout sur jonction fixée, clamp TIE supprimé, plan final remplacé par le sol.
Aucun fichier jeu, asset, appareil ou validateur modifié.

Reprise essai 3 — DIRECTIVES v14fcd1a084
Le refus archivé validator-001.txt vient du test de comptage du bac à sable.
Reproduit : 1 failed in 0.31s, manque=['.autoport/tests/harness/shrub_contact_local.py'].
Le fichier était copié ; FAMILLES excluait son dossier du comptage.
FAMILLES inclut désormais .autoport/tests/ ; assertions manque/en_trop conservées.
Rejeu ciblé par l’implementer : 1 passed in 0.29s, code retour 0.
Revue researcher : initialisation SHRUB, sentinelles TIE et attachement exact non épinglés.
Ces trois blocs sont ajoutés à la garde ; cinq mutations supplémentaires dans le banc existant.
Pas de nouvelle instrumentation : même garde, même recensement, même critère moteur.
Fraîcheur actuelle : build_x86.sh --check-only retourne 0 ; 46 entrées, zéro travail résiduel.
L’ancienne preuve avait sha=8736e1cfa84c8efa et l’identité essai @1 ; le binaire actuel diffère.
Une unique course x86 via proof_run.sh renouvelle la preuve pour l’essai @3.

Résultat essai 3 : notes/local-tests.log = 12 passed in 3.16s, dix mutations refusées.
proof_run rc=0, frames=3397, crash=0, shrub_trunk_anchor_defects=0, proof_census_rc=0.
verdict_sources_count=36 et verdict_sources_sha=0a60f6f25952185c : identiques au recalcul.
