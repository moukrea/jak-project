# jak-project — instructions Codex

Ce dépôt porte OpenGOAL sur Android. Lis `CLAUDE.md` pour les conventions de code,
les pièges de build et les règles de preuve ; ce fichier est partagé avec Claude Code.
Le harnais est documenté dans `.autoport/README.md` et `.autoport/DIRECTIVES.md`.
Les anciens journaux de `.autoport/archive/` sont historiques, pas des ordres actifs.

Le rôle est donné par la session :
- Superviseur : `.autoport/SUPERVISOR_PROMPT.md`. Pilote le backlog, ne code pas le jeu,
  ne touche aucun appareil, ne fabrique jamais une validation de l'owner.
- Worker : périmètre du prompt, `AUTOPORT_PHASE_ID`, version DIRECTIVES et handoff.
  La preuve est produite par `lib/proof_run.sh`, jamais écrite à la main.
- Travail interactif demandé directement : suis la demande, sans prendre spontanément
  un item du backlog ni démarrer les démons.

En mode Codex, toute relance du harnais porte `--backend codex` (ou hérite
`AUTOPORT_BACKEND=codex`). Les sous-tâches du worker utilisent les sous-agents natifs
Codex, avec leur rôle et périmètre explicites. Ne lance pas de sous-session Claude.
La CLI Claude reste disponible avec `--backend claude`, sur le même backlog.
