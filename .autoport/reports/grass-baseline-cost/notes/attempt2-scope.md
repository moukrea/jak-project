# Reprise contractuelle — essai 2
DIRECTIVES v07b292c21f

Lecture statique uniquement, aucune mesure sur appareil dans cet essai.
HEAD de départ : 162cab6216 ; précédent rapport : f4f2fcb9d0.
`git diff f4f2fcb9d0 -- game common scripts .autoport/prompts/item-grass-baseline-cost.md .autoport/prompts/SPEC-refonte-herbe.md` : sortie vide, code 0.
`git show --stat HEAD` : seul .autoport/.release_notes_hash modifié par le WIP.
Backlog déjà modifié par le harnais à l'arrivée ; non édité par le worker.
Lecture YAML de l'item : owner_test=False, code_scope=jeu ; proof_plan, proof_props,
proof_env, harness_edit_allowlist, supervisor_review tous ABSENTS.
Prompt ligne 23 et backlog ligne 9707 : « Ne change RIEN » maintenu.

Le researcher natif Codex scope_delta (gpt-6-astra, high) a relu le contrat sans
répéter l'inventaire moteur et confirme l'absence d'autorisation nouvelle.
Les dix fenêtres sont explicitement demandées par le livrable ; le blocage retenu
est l'interdiction de modifier l'état pour ajouter les instruments qui leur manquent.
L'absence de proof_plan est un constat complémentaire, pas un refus de l'autorisation USB.

Verdict déjà produit par l'orchestrateur, validator-001.txt :
- aucun site moteur grass-baseline-cost ; proof_feature_state=absent ; hits global non attribuable ;
- grass_baseline_gaps absent, grandeur attendue du moteur.
Aucune exécution du validateur pendant cet essai, conformément à son prompt.

Le lien d'investigation de la SPEC a été ouvert via web ; retour :
URL is not safe to open (non-retryable error). Aucun contenu externe consultable.
Contrat local SPEC lu ; aucune affirmation déduite de l'artefact inaccessible.

Décision : ne pas répéter un diagnostic qui ne mesure aucun relevé du contrat.
Le rapport étiquette ses huit lignes obligatoires comme historique de l'essai 1.
Le prochain essai nécessite un arbitrage du superviseur autorisant la mesure neutre,
puis sa préparation avant toute course. Aucun zéro, hit ou champ de preuve fabriqué.
