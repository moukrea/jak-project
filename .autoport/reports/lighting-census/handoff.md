# Handoff — lighting-census, essai 14
DIRECTIVES v6fca51fe40
## ÉTABLI
- Build incrémental gk+goalc rc0, sha gk=483b75c9c4473b8c ; garde npc-flicker47.
- Preuve unique60s limitée legacy/origine/h00 : crash0 frames3353 compared1 maxdiff202 diffpx794 census_runs0.
- Origine draws1365858 classifiés0 stock1365858, residual0 rb_mismatch0 GPU7.9370ms ; hors plan complet.
- 575 SHA historiques OK ; preuves/écarts précédents archivés notes/essai13-avant14.
- API input chargée : selftest PASS, PAD DIFF0/120, fingerprint ab9b39af35c0de41 stable/error/reset PASS.
- Runtime input=f97b073c2df76fb4 source=loaded-replay ; ledger ajoute input et exige même config, archives intactes.
- Lecteur fork FR3 v43/v44 testé : PASS inputs27 (fixture writer pristine indépendant +26FR3 pristine dont GAME/sunkenb).
- V43 vide tangentes ; write44 header/footer ; réutilisation/roundtrip exacts ; quatre rejets SIGABRT6.
- Aucun candidat nouveau adopté ; essai13-provenance-v2 reste candidat partiel non qualifié.
## TENTÉ
- Corrigé incompatibilité FR3 : deux vecteurs u16 baked_tangents seuls ajouts sérialisés44 ; ne pas renuméroter fichiers.
- Audité frontière : actors-update trop tard (birth bsp-header crée déjà ambiances/caméras). Pas de restore implémenté.
- Piste DMA non autonome : pointeurs EE embarqués, textures hors chaîne, état renderer/loader absent ; aucun outil replay existant.
- Origine historique toujours différente sur le cas testé ; pas cinq autorejeux pour fabriquer qualification.
## RESTE
- Frontière commune AVANT play dans InitMachineScheme (fork5777/pristine641), avant premier KernelDispatch.
- Piste : session neuve par cas, (play #t #f), puis initialize! *game-info* game #f continue via contexte GOAL valide.
- Enregistrer/rejouer RTC dès DecodeTime, RNG GOAL/natif dont *knuth-rand-state* oublié, horloges, niveaux/permanences/acteurs.
- Adapter pristine au protocole ; mêmes CGO/FR3 pristine désormais lisibles ne qualifient PAS les CGO fork livrés.
- Qualifier origine baseline/candidat à état identique ; compléter provenance producteur sources/config/ressources effectivement chargées.
- Candidat complet trois modes/21niveaux/8heures/≥4intérieurs ; Sunkenb manque toujours ; ensuite cinq rejeux exacts.
- non prouvé : état rejouable, qualification, couverture rendue, HDR/tonemap SDR/Android ; aucune correction HDR livrée.
- notes/recovery-essai14.md + essai14-data/commands.txt/tests ; aucun appareil, builder2541075 repris, generic orchestrateur seul.
