# Réapplication du chargement après retéléport — essai 31
DIRECTIVES v6fca51fe40

`postwarp.patch` est le delta des trois fichiers du candidat ; appliqué également au
worktree baseline existant, sans y copier kmachine.cpp complet depuis HEAD.
`full-baseline.patch` reconstruit toute l'adaptation depuis
`a9ea15a69062a57335278db7680cd647df3c1e1d` (31 fichiers). Le reverse-check est passé
dans le worktree baseline. Aucun renderer/shader supplémentaire n'est modifié.
`patches.sha256` identifie ces deux patchs.

Le guard ON versionne sa configuration `require-loaded-state-restore-plus2-v2`.
Au dernier retéléport du premier vantage, les commandes initiales sont programmées
à ancre+2. Après dispatch, une unique fonction listener exécute WANT-LEVELS puis
WANT-DISPLAY ; retard, slot occupé, déplacement du listener ou commande invalide
font échouer la course. Ni le premier warp ni l'arrivée ne programment ce rappel.
Le garde de chargement existant reste le juge de l'état à la capture.

`run-arm.sh <worktree> <baseline|candidate> <cycle-neuf>` reprend le runner30.
Il réserve un répertoire neuf de candidats, conserve bootstrap17 et manifeste18,
active la trace pad/CAM existante, relève les SHA des quatre fichiers de réglages
portables avant/après et les entrées du bras. Une seule capture origine/h00/legacy
vise à vérifier la correction ; elle reste non qualifiée, pas un corpus adopté.
Le producteur reste exclusivement le proof_run actuel lancé depuis le worktree.
Le script sélectionne/restaure son proof_env sous lock en utilisant run-config.py30,
suspend/reprend uniquement le builder2541075 préalablement vérifié idle par PID.
Aucune relance du harnais, aucun appareil ni build Android, aucun validateur exécuté.

Les limites des témoins de l'état postload sont dans research.md.
Les logs de build, traces, manifestes et preuves produites sont les résultats des
exécutions ; les notes ne produisent aucun champ de proof.txt.

Résultats : deux builds gk réussis, garde PNJ47 tenue des deux côtés ; un run75s par
bras, crash0. Deux réapplications ancre2102/due2104/exécutée2104, sample2282,
captured1/compared0/slip0. Les SHA gk/CGO/bootstrap restent inchangés après les runs.
Au checkpoint de capture, les ensembles FR3/ISO/objets/textures sont identiques ;
les shaders restent distincts. CAM identique pendant180frames ; les quatre fichiers
de réglages sont identiques entre bras et inchangés. Détails postload-comparison.txt.
Les PNG ont des empreintes différentes ; aucun verdict pixels sans qualification
complète de l'état des autres acteurs/RNG. Le refus d'adoption v2 reste en place.
Le champ loaded_pending est ancien parce que publish_text ignore une chaîne vide ;
loaded_ready et loaded_levels ont bien été actualisés, voir les logs. Aucune retouche
de la preuve ni du producteur/validateur. Ce défaut de télémétrie est signalé.
