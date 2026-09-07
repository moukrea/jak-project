DIRECTIVES v6fca51fe40
Essai12 : build et unique preuve x86150s réussis ; disparition mesurée des erreurs GL_INVALID_OPERATION.
Commande build : cmake --build build --target gk -j6 ; code 0.
Commande preuve : OG_REFSET_TRACE_ROI=1 bash .autoport/lib/proof_run.sh lighting-census x86 --timeout 150 ; code 0.
Script/session : run-essai12.sh, session-essai12.log.
Logs : build-essai12.log, proof-run-essai12.log ; preuve et journal moteur dans le dossier parent.
Lignes recopiées de proof.txt :
source=x86
binary=build/game/gk
sha=1aed1e5494ac62fa
started_at=2026-09-07T12:30:59Z
duration_s=150
crash=0
frames=8393
tonemap_draws=2389
SHA256 moteur : 1aed1e5494ac62faeb7d1564431ef091b10569f5abf43fcd13c05f6f9c77c3c1.
GL_INVALID_OPERATION : 0 contre7290 essai11 (glUniform4 u_hdr_curve, glUniform location4, glUniformMatrix non-matrix :2430 chacune).
Aucune ligne OpenGL error ; aucune erreur/alerte sprite.
SUBDUP passes_de_texte=1 reste=0 glyphes=25 blocs=50 blocs_encres=25 alpha_dup_dma=0 alpha_texte_dma=128 passes_ombre=7
Cette signature SUBDUP est identique à essai11.
Références SHA256 :575/575 OK avant,575/575 OK après ; codes0. Logs refs-preflight-essai12.log et refs-check-essai12.log.
Garde build : [npc-flicker] garde OK — 47 proprietes tenues.
Identité initiale PID2541075 : bash .autoport/auto_build_apk.sh ; unique enfant sleep PID2936038 ; aucun compilateur/verrou détecté.
Parent seul arrêté STOP pendant build/preuve, repris CONT par trap EXIT, état final Ss.
Anomalie informative : le build demandé a automatiquement régénéré CMake et exécuté la cible clang-format discord-rpc. Aucun cmake -B lancé ; statut Git discord-rpc vide ensuite.
Aucune édition manuelle des sources, validateurs, backlog ou preuve ; aucun appareil ; aucun deuxième run ni generic.sh.
Non prouvé : qualité visuelle, état Android et validation owner. Analyse24 PNG laissée au manager.
