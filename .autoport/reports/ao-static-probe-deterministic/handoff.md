ÉTABLI
DIRECTIVES v19558ce1a8
Essai 3 : deux courses neuves proof_run.sh device --timeout 130, TMPDIR hors /tmp, code 0 chacune.
Référence 20260914T163556Z-249930-c9ae8c97 dans proof-prev.txt ; comparaison 20260914T163828Z-254726-683b88e9 dans proof.txt.
Identité des deux preuves : ao-static-probe-deterministic@3#1789403671.
USB eae4df44, MD5 local/appareil 051f95c972dd4b68ed6710978ef40ab8, moteur e41a530a64 inchangé.
Chaque course : 1800 images, crash=0 ; comparaison : ao_static_defects=0, nondeterminism=0, samples=18, own_hits=18.
18 ticks et empreintes identiques ; cinq acquis=0, termes séparés=0, masque acquisitions vent allumé=63.
Précontrôle final : 4276 fichiers, stale_total=0 ; 13 propriétés épinglées relues identiques.
TENTÉ
Ancienne preuve non réutilisable : generic.sh:101-108 exige l’identité de l’essai courant malgré la fraîcheur des sources.
Aucun build ni changement moteur ; seules les deux courses nécessaires ont été rejouées.
Test hérité test_pin_props.py::test_le_teardown_nomme_ce_qu_il_efface : 1 passed in 0.22s hors /tmp, code 0.
Rouge hérité nommé dans report/FINDINGS, suivi harness-suite-temporary-files-outside-quota ; cause initiale non démontrée.
RESTE
L’orchestrateur doit exécuter son validateur et ses portes de fermeture ; worker ne les a pas lancés.
Clause littérale FEATURE hits=<images> non livrée : compteur global ; own_hits=18 exact. Réserve conservée, aucune interdiction de toucher l’émetteur démontrée.
non prouvé : --off, esthétique, coût, autres scènes/appareils. Aucun owner-ok écrit.
Défauts antérieurs conservés dans FINDINGS ; aucun démon relancé pendant cette reprise.
