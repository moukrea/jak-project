# Reprise essai 4
DIRECTIVES v07b292c21f
Horodatage UTC : 2026-09-15T07:17:25.807628+00:00

$ git rev-parse HEAD
exit=0
fb95f8302d0905e93836fdc8b34b391a57229eb6
(stderr vide)

$ git diff --stat fb95f8302d -- game common scripts .autoport/lib/proof_run.sh .autoport/prompts/item-grass-baseline-cost.md .autoport/prompts/SPEC-refonte-herbe.md
exit=0
(stdout vide)
(stderr vide)

$ bash .autoport/lib/pick_device.sh
exit=0
eae4df44
(stderr vide)

proof.txt sha256=d1d3e048e096869268d26f4892185fa8b9f40338d5afec87ea3fdd74e1c811a8
proof.seal sha256=fb5ea5f1b214ea9438b04728956ce75ce4c22266bd3386db544643e6915299eb

Verdict orchestrateur de l’essai 3 :
[grass-baseline-cost FAIL] proof_attempt_id=grass-baseline-cost@1#1789455866 dans la preuve, essai courant 'grass-baseline-cost@3#1789456409' : cette preuve a ete produite par une AUTRE course (course=20260915T070543Z-2427381-9881edb8, pid=2427381, started_at=2026-09-15T07:05:44Z). Le verdict porterait sur la mauvaise course.
[grass-baseline-cost FAIL] aucun site moteur ne nomme grass-baseline-cost dans ce binaire (proof_feature_state=absent) et cet item n'a pas de recensement : rien ne prouve que l'instrument de CET item a tourne. 'hits=1158019' est le compteur GLOBAL, il monte pour tout le monde. Attribue la prise de ton instrument — note_hit_for("grass-baseline-cost", ...) et AUTOPORT_FEATURE_SITE("grass-baseline-cost") — ou publie ton verdict par un recensement.
[grass-baseline-cost FAIL] le proof ne porte pas 'grass_baseline_gaps=' : le moteur doit emettre cette grandeur
[grass-baseline-cost FAIL] 3 constat(s) ci-dessus, aucun n'a ete masque par un autre.

Lecture YAML de l’item :
proof_plan : 'ABSENT'
proof_props : 'ABSENT'
proof_env : 'ABSENT'
harness_edit_allowlist : 'ABSENT'
out_of_scope : Ne change RIEN. Aucune optimisation, aucun reglage, aucun shader. Cet item mesure l'etat present et s'arrete la. Tout ce qui n'est pas cet item.
Décision : les dix fenêtres restent demandées ; les instruments manquants ne sont toujours pas autorisés. Pas de course diagnostique répétée. Aucune preuve de cet essai.

Researcher natif contract_delta, gpt-6-astra/high, terminé : comparaison YAML depuis 641076114f, unique différence status open -> in-progress ; aucun proof_plan ajouté ; git diff --exit-code sur moteur/scripts/proof_run/prompt/SPEC exit=0 et sortie vide. Aucun audit moteur répété.
