# Handoff — lighting-census, essai 15
DIRECTIVES v6fca51fe40
## ÉTABLI
- gk final05f7ba1f7280c962 build rc0 ; garde npc-flicker47. Preuve finale60s crash0 frames3397.
- legacy/origine/h00 : compared1 maxdiff202 diffpx794 census_runs0 ; 575 SHA historiques OK.
- Origine draws1402218 classifiés0 stock1402218 ; residual0 rb_mismatch0 GPU8.2137ms ; hors plan complet.
- Nouveau game/system/boot_replay : input RTC/RNG natifs avant GAME ; checkpoints RNG GOAL/natifs/display avant play.
- Capture20s puis replay : 11 records scellés fingerprint8cafacae708f4b5a, Knuth inclus ; aucune horloge EE/unix lue avant frontière dans ce run.
- Flux réutilisable : notes/essai15-data/fork-bootstrap.bin ; OG_BOOT_REPLAY_REPLAY=<chemin>, session OS neuve impérative.
- Tests parser roundtrip/rejets rc0 ; capture O_EXCL, EOF/checkpoints stricts, buffers sur tas pour appels GOAL.
- Registre/sidecars config inclut bootstrap scellé : 8a9493fa059e5429 ; ancien1bc0c751a065de33 conservé.
- Pristine source c4bc4d3ff4691902ff023319cb33df71c0040501 + notes/essai15-data/pristine-bootstrap.patch.
- /home/emeric/code/jak-original-v033/build/game/gk615f120e4e0de8f6 compile rc0, rejoue11 records même empreinte (12s).
- Pristine utilise ses CGO DISTINCTS : compatibilité pré-play mesurée, PAS qualification de rendu/données identiques.
## TENTÉ
- Le bootstrap réparé ne réduit pas l’écart historique202/794 ; aucun nouveau candidat adopté, aucune sentinelle retirée.
- Build pristine interrompu sur borne100 objets trop grossière (curl), repris incrémental : rc0 en142.5s/167objets.
- Revue tardive a ajouté identité bootstrap au registre ; preuve initiale archivée notes/essai15-avant-ledger/, flux conservé.
## RESTE
- Étendre frontière APRES initialisation commune sans gel du rendu ; RTC/RNG pré-GAME sont désormais traités, pas les acteurs.
- Voie auditée : remplacer play automatique par premier ListenerFunction ; kernel-dispatcher le lance via reset-and-call AVANT arbre acteurs.
- Ce listener fera (play #t #f), puis initialize! *game-info* game #f continue ; restart suspend ensuite avant start : encore à traiter.
- Enregistrer/rejouer naissances, permanences, horloges/chargements et état courant ; ne pas réutiliser pointeurs entre binaires.
- Qualifier baseline/candidat avec mêmes ressources effectivement chargées ; CGO pristine communs ne qualifient pas CGO fork livrés.
- Candidat complet trois modes/21niveaux/8heures/≥4intérieurs, Sunkenb+ciel manquants ; puis cinq rejeux exacts.
- non prouvé : acteurs/qualification/couverture/HDR/SDR/Android. Aucun HDR corrigé ; generic orchestrateur seul.
- Notes recovery-essai15.md et essai15-data ; builder2541075 repris, aucun appareil ni owner-ok.
