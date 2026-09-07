# Baseline pré-refonte isolée — essai 30
DIRECTIVES v6fca51fe40

Source historique : a9ea15a69062a57335278db7680cd647df3c1e1d.
Arbre : /home/emeric/code/jak-lighting-baseline (worktree détaché).
Candidat : /home/emeric/code/jak-project.
`full-baseline.patch` s'applique à cette source historique ; il comprend l'adaptateur
et la garde postload. `adapter.patch` et `postload.patch` permettent de lire les deux
étapes séparément. Le dernier est également le changement du candidat.
Aucun shader historique n'est remplacé par un shader HEAD. Les adaptations des
fichiers renderer sont les raccords capture/sonde, le manifeste, le drainage de la
résolution des textures sous refset, l'instrumentation Merc2 et le suivi PID d'herbe.
Ce dernier est le producteur ET consommateur réel du nouvel export, pas un stub ;
il peut changer l'herbe master ON. Cette baseline vise la qualification origine
master OFF ; aucune invariance du mode ON historique n'est revendiquée.
`pc-set-recharged-lighting!` stocke le réglage réel reçu ; la baseline n'a pas
la nouvelle couche HDR. Elle n'est ni pristine ND, ni le binaire HEAD ablaté.

`prepare-data.sh` a créé des copies CoW indépendantes des ISO/FR3/objets,
custom_assets/jak1, managed_assets et réglages portables. Les modifications futures
d'un arbre ne traversent pas ces copies. Le builder exact 2541075 a été suspendu
pendant cette seule copie puis repris par trap ; aucun appareil n'est concerné.
`data-snapshot.log` identifie binaire source, trois CGO, bootstrap17 et réglages.

La garde `OG_REFSET_REQUIRE_LOADED=1` observe les niveaux GOAL après dispatch,
sans ajouter de checkpoint au bootstrap17 scellé. Les niveaux initiaux demandés
sont exigés loaded/active, celui affiché active, et le niveau du vantage courant
active. Target/spawn/sweep sont également observés. Le premier cas attend la même
échéance fixe d'arrivée que les autres. Une fenêtre de huit snapshots permet de
rattacher une chaîne DMA à son état réel (retard admissible au plus une frame).
État absent/non prêt/périmé : erreur explicite avant prélèvement. OFF n'avance pas
l'initialisation historique de refset. L'option entre dans l'empreinte du plan.
Cela n'atteste PAS l'identité complète des RNG/acteurs/configs après chargement.
Le refus d'adoption v2 reste en place.

Build initial : configure.log ; cible gk seulement, options du candidat, -j3.
Le hook a refusé -B malgré l'absence de cache. La configuration initiale a ensuite
été effectuée depuis le répertoire neuf par cmake .., sans altérer de cache existant.
Build candidat incrémental : build-candidate.log (puis TU refset corrigé en revue).

`run-arm.sh <worktree> <baseline|candidate>` réserve un nouveau répertoire de
références, réutilise bootstrap17 et produit le manifeste18 avec le module existant.
Il sélectionne temporairement le mode capture et sa destination dans proof_env,
car proof_run réapplique ce champ après les variables d'environnement ; le changement
est restauré sous verrou, sans réécrire une modification concurrente. Aucun critère,
statut, validateur, scope ou producteur de preuve n'est modifié. Le rapport proof.txt
est écrit EXCLUSIVEMENT par le proof_run actuel exécuté dans chaque worktree.
Les sorties nouvelles restent non qualifiées, sans adoption ni cinq rejeux simulés.

## Deux erreurs d'exécution corrigées après la première course
La baseline initiale a produit SIGSEGV139 après112frames/9s. Son core3100138
résout le CALL nul à `pc-get-frame-rate-cap-override` : symbole EE0x141fe4,
valeur0, nom à0x2124cd6758. Fournisseur commun distinct de l'inventaire jak1 :
`common/kmachine.cpp` ; le même consommateur GOAL appelle `pc-set-uncap-menu`.
`common-abi.patch` ajoute leurs vraies fonctions et trois stockages atomiques,
extraits du donneur, dans `baseline_pc_compat.*`. Pas de hook de cadence, pas de
setter historique changé, pas de stub. Full-baseline.patch contient ce complément.
Le candidat initial a scellé5880records/79fb964dc17507ec, puis refusé àLF1501
(snapshot1500) parce que beach était loaded, pas active. WANT-DISPLAY ne devait
arriver qu'après1800tours ; aucune occurrence de sa commande dans ce journal.
La course `corrected` utilise LOAD_SETTLE1200 : échéance2101, critère active intact.
Le code GOAL level.gc:253-258 distingue explicitement loaded/login terminé et
active/niveau dessiné. Le refus initial était donc justifié, le calendrier prématuré.
Le core candidat3101110 montre en plus `exit()` sur filGOAL (thread16) détruisant
les statiques pendant que le renderer utilise son cache tfrag (thread1). Le refus
emploie désormais `_Exit(EXIT_FAILURE)` après flush : toujours échec, sans teardown
concurrent. Les premiers proof/logs restent dans `initial/` de chaque worktree.
La répétition `corrected` est un retest après ces corrections mesurées, avec sortie
neuve et75s maximum ; pas une adoption ni une campagne de références historiques.

## Résultat du retest corrected
Deux bootstrap5880/79fb964dc17507ec terminés ; baseline2392frames/46s, candidat2405frames/47s.
Les deux refusent proprement (exit1, aucun SIGSEGV) la captureLF2282/snapshot2282 :
beach active après WANT-DISPLAY est revenue loaded après le dernier rewarp.
Aucun prélèvement accepté, aucun checkpoint de capture, aucune comparaison de pixels.
consumed-comparison.txt conserve les ensembles cumulés et leurs désaccords, sans qualification.
L’état souhaité doit être rétabli après ce dernier start play avant de qualifier le candidat.
Les logs baseline finaux/initials sont aussi conservés ici en gzip ; les proofs sont ceux du producteur.
