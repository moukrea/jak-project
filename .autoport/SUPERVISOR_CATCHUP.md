# Reprise du superviseur — 14 septembre 2026

Demande directe de l'owner : arrêter entièrement le harnais Claude en limite de quota,
empêcher son retour automatique, simplifier la bascule dans les deux sens, puis relancer
un superviseur Codex et rattraper le travail. Aucun verdict de validation dans cette demande.

## État à la reprise (historique : relire le backlog)

- Deux superviseurs Claude concurrents ont été trouvés : PID 1348789 et 2142423,
  tous deux avec une tâche planifiée en attente du quota de 19 h 50. Arrêt SIGTERM.
- Orchestrateur 1374469 arrêté proprement pendant l'attente API ; les deux démons
  2808508 (build) et 1779081 (livraison) ont également été arrêtés. Les reprendre.
- Les autres sessions Claude interactives de sujets distincts n'ont pas été arrêtées.
  Elles ne sont pas des superviseurs autoport enregistrés.
- Au début de l'intervention seuls backlog.yaml (shrub-trunk-contact in-progress → open)
  et .release_notes_hash étaient sales. Ne pas attribuer ces modifications à la bascule.
- HEAD de départ : e903a79e12, essai shrub-trunk-contact refusé par l'API, non compté.
  Pas de handoff de cet item. Le backlog donne actuellement ao-static-probe-deterministic
  comme prochain item, puis ao-prepass-tie-alpha ; respecter sa priorité, pas l'ancien écran Claude.
- lighting-ao-indirect reste bloqué et est remplacé par DEUX items (dernier arbitrage écrit),
  pas les trois de l'avant-dernier superviseur. Lire son handoff essai 13 et FINDINGS.txt.
  La sonde statique n'échantillonne pas le même état de scène ; l'autre défaut est
  l'alpha-test de la prépasse TIE statique. Ne pas repartir sur la piste du vent.
  Les cinq acquis sont dans les nouveaux prompts et portes ; aucune nouvelle validation owner.
- FINDINGS.txt contient d'autres coûts/défauts signalés : les rapprocher des items existants
  et présenter les non-traités à l'owner, sans ouvrir de chantier hors autorisation.

## Rattrapage du harnais partagé

Les correctifs Claude vivent déjà dans les fichiers que Codex exécute. Ne rien dupliquer.
Lire les changements récents de lib/proof_run.sh, lib/build_x86.sh, lib/suite_gate.py,
orchestrator.py, hooks/pre-tool.sh et tests/harness/conftest.py :
- build x86 via build_x86.sh, nanosecondes, dépendances Ninja et binaire réellement relié ;
- preuve verrouillée, fraîcheur contrôlée avant course, effacement après amorçage seulement ;
- preuve appareil : déployer le binaire local ou refuser avant toute mesure ;
- échecs de suite hérités séparés des nouvelles régressions à partir de la base de l'essai ;
- tests isolés de l'environnement du worker ; garde de build distinguant le démon Gradle ;
- rechargement atomique/tolérant et signalements désormais lus par les portes partagées.
L'adaptateur Codex réutilise pre-tool.sh pour les commandes shell et le même orchestrateur.
Lire CLAUDE.md et DIRECTIVES.md actuels, pas les archives ni le handoff Codex du 7 septembre.

## Suivi

Le contrat superviseur, le backlog, les prompts et les preuves restent les autorités.
La veille Codex lance le backend codex et remet les points au thread exact du superviseur.
Vérifier les PID des démons, les états « preuve impossible », l'arbre moteur et la revision APK
sans toucher d'appareil. Ne pas présenter une santé verte sans vérifier ces éléments.

## Environnement de test à la bascule

Le quota utilisateur de /tmp est atteint malgré l'espace libre global (Errno 122).
Pour la suite, définir TMPDIR sur un dossier neuf sous ~/.cache, pas seulement --basetemp :
les faux outils shell du banc appellent aussi mktemp. Ne pas diagnostiquer une régression
à partir d'un test dont les écritures temporaires ont échoué.
