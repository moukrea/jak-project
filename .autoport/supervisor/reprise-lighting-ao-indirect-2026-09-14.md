# Reprise AO — 14 septembre 2026

Le dernier refus du parent est toujours celui de l essai 13 : ao_owner_defects=1888.
Le handoff identifie une sonde non reproductible et un sur-decoupage alpha du TIE statique.
Ces deux causes ont deja leurs items ; aucun nouvel essai du parent ne se justifie.

La veille reclamait encore le parent parce que supervisor_recovery etait reste vrai.
Le suivi est transfere a ao-static-probe-deterministic et ao-prepass-tie-alpha ;
superseded_by porte explicitement les deux identifiants. Le statut blocked du parent reste
la trace du refus, aucune validation ni relaxation des criteres n a ete faite.

Verification du filtre de watch.py : le parent ne declenche plus une demande ; chacun des
successeurs la declenche s il devient blocked. Dependances intactes, aucun dependant du parent.
Veille --maintain et orchestrateur Codex vivants ; essai 1 de la sonde en cours.
Deux demons vivants, aucun etat proof-impossible actif. Aucune relance ni contact appareil.
Les modifications moteur et proof_props deja presentes appartiennent au travail en cours ;
elles sont exclues du commit superviseur.
