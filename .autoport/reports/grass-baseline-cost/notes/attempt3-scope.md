# Reprise contractuelle — essai 3
DIRECTIVES v07b292c21f

HEAD de départ : 641076114f (rapport de l'essai 2).
Lecture seule du delta ; aucune reprise de l'audit moteur déjà établi.
`git diff 641076114f --stat -- game common scripts .autoport/lib/proof_run.sh .autoport/prompts/item-grass-baseline-cost.md .autoport/prompts/SPEC-refonte-herbe.md` : sortie vide, code 0.
Lecture YAML de l'item : proof_plan, proof_props, proof_env, harness_edit_allowlist,
supervisor_review ABSENTS ; out_of_scope conserve « Ne change RIEN ».
Version recalculée par lib/directives.py : v07b292c21f.
Le backlog est modifié à l'arrivée par d'autres travaux ; aucune édition par ce worker.

Nouveau verdict disponible depuis le handoff : logs/grass-baseline-cost/validator-002.txt.
Il contient trois FAIL : proof_attempt_id de l'essai 1 différent de l'essai 2,
proof_feature_state=absent, grass_baseline_gaps absent.
Ce verdict est relu, pas réexécuté ; aucune validation de l'essai 3 revendiquée.
Les dix fenêtres sont explicitement demandées ; leur répétition sans instrument
ne remplirait aucune lacune supplémentaire du contrat.

Empreintes SHA-256 avant toute édition documentaire :
proof.txt d1d3e048e096869268d26f4892185fa8b9f40338d5afec87ea3fdd74e1c811a8
proof.seal fb5ea5f1b214ea9438b04728956ce75ce4c22266bd3386db544643e6915299eb
Aucun de ces fichiers n'est modifié ni accepté comme preuve actuelle.
Aucun build, appareil, réglage, campagne, instrumentation ou ablation engagé.
Aucune conclusion nouvelle sur le comportement du moteur.

Researcher natif contract_delta (gpt-6-astra, high), terminé : confirme aucun delta
autorisant les instruments. Comparaison YAML avec 641076114f : seul changement de
l’item status open -> in-progress ; aucun champ ajouté. Aucun delta game/common/scripts.
