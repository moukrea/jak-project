ÉTABLI
DIRECTIVES v19558ce1a8
Commit e41a530a64, APK installé USB eae4df44, MD5 051f95c972dd4b68ed6710978ef40ab8.
Deux courses finales via proof_run.sh : référence proof-prev.txt, comparaison proof.txt.
ao_static_defects=0, ao_probe_nondeterminism=0, samples=18, own_hits=18 ; cinq acquis=0.
Six paires statiques sans variation brute/finale ; six acquisitions vent allumé réussies (masque63).
Aucun crash dans ces deux courses ; détails et huit lignes de preuve dans report.txt.
TENTÉ
Sans fixed_tick=1, course initiale morte au titre avant téléportation ; trace conservée dans notes/bootstrap-crash-engine.log.
Régime maintenant épinglé ; warps mesurés aux ticks300/900, monde résident au second.
Première paire instrumentée : six écarts limités aux phases vent allumé ; toutes les prises statiques sont désormais vent coupé.
Les acquisitions vent allumé restent séparées, obligatoires et hors population de comparaison.
RESTE
L’orchestrateur doit lancer son validateur ; le worker ne l’a pas exécuté.
Arbitrer le format partagé FEATURE hits (total global) : own_hits=18 est correct, clause littérale non livrée ; FINDINGS.txt.
Reprendre auto_build_apk si souhaité : ancien PID60363 arrêté après collision avec build worker ; risque de reconstruction GOAL inutile consigné.
Non prouvé : --off, esthétique, coût, autres scènes/appareils. Aucun owner-ok écrit.

REPRISE SUPERVISEUR 14/09
Le validateur generique A tourne : validator-001.txt confirme ao_static_defects=0.
La fermeture a refuse le rouge herite de test_pin_props, pas le critere AO.
Le rouge est maintenant nomme dans report.txt et trie dans FINDINGS.txt ; suivre
harness-suite-temporary-files-outside-quota. Rejeu isole hors /tmp passe (0,25 s).
La consigne perimee venait de l ajout superviseur de « any news? », sans changement
au livrable ; consigne et contrat regeneres. Reprendre le travail etabli, aucune
relaxation de porte ni validation. Reutilisation des preuves seulement si les
portes de fraicheur et le binaire courant le permettent ; ne pas reconstruire
une sonde deja livree pour un refus documentaire. TMPDIR doit etre hors /tmp.
