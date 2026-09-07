# Reprise du superviseur — 7 septembre 2026

Source consultée en lecture seule : session Claude Code
`fc2d3cfc-f35f-4d52-b8cc-b3f3b2f92028`, active le 7 septembre jusqu'à 08:18 UTC.
Son historique reste dans `~/.claude/projects/-home-emeric-code-jak-project/`.
Il n'est ni converti, ni déplacé. La session `1126e4a5-…` active à proximité n'est
pas le superviseur : ne pas utiliser « dernière session » pour le retrouver.

Ce document est un point d'entrée daté. Pour l'état actuel, lire le backlog,
`autoport status`, les prompts d'items, les rapports et handoffs correspondants.
Ne jamais remettre ce contexte daté dans une boucle périodique.

Priorités exprimées le 7 septembre :
- Finir le lighting d'abord. L'owner refuse encore le HDR qui brûle les blancs,
  notamment les ciels. Il demande tous les niveaux pertinents, intérieurs ET
  extérieurs, avec plusieurs heures fixes (sunrise, sunset, noon, night).
- Reprendre ensuite la brise : tout le jeu, interaction des shrubs/fleurs avec
  Jak, caisses et ennemis comme pour l'herbe rechargée.
- Reprendre le framerate : choix 30/45/60/75/90/120/240/illimité, soupçon de
  plafond à 90 FPS, cible de résolution dynamique cohérente avec le plafond.
- Ces messages sont des retours de non-validation, jamais des feux verts.

La session utilisait un cron toutes les trente minutes : digest seulement si
changement, trois rubriques, ETA fondée sur des durées mesurées, vérification de
la vie de l'orchestrateur, pas de relance pendant un sommeil de quota.
Avec Codex, la veille externe est `supervisor.sh --backend codex --watch --maintain --notify-supervisor`.
Elle détecte les changements sans modèle et les remet via `codex queue` au thread
du superviseur. Le superviseur interactif arbitre les situations et dialogue avec
l'owner. Le cron Claude reste intact ; la veille externe est son équivalent Codex.

Divergence documentaire identifiée : le 6 septembre à 07:01 UTC, l'owner a
explicitement demandé que le Honor branché en USB puisse produire les preuves.
`pick_device.sh` et le contrat superviseur reflètent ce changement ; les anciens
paragraphes Redmi-only de CLAUDE.md, DIRECTIVES et des agents Claude sont en retard.
Aucun appareil n'est sollicité par la migration de CLI.
