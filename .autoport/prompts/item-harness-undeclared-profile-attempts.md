# Vingt-huit essais sont partis sans aucun profil de modèle choisi : aucun n'a abouti

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
Signale par l'etude owner-se-renseigner-sur-le-combo-le-plus-efficient-tou (reports/<id>/FINDINGS.txt, 19/09), items crees par le superviseur le 19/09 13:55. 28 essais portent un champ `model` VIDE dans `attempt_start` : 0 reussite, 46,4 % en boucle, le pire taux de tous les profils. Un essai part sur un modele que personne n'a choisi. TROUVER la voie de lancement qui perd le profil (bascule de CLI ? reprise apres coupure ? profil `defaut` des bannieres = 28 occurrences de `modèle=défaut` dans orchestrator.log) et la fermer : un lancement sans profil resolu doit REFUSER de partir et le dire, jamais partir sur un defaut. PORTE : les 28 journaux sont classes par voie de lancement (nommee) ; un test lance l'orchestrateur avec un profil casse et obtient un refus explicite, pas un essai ; 0 essai sans modele declare sur les essais posterieurs au correctif.

## Livrable
Le defaut ci-dessus corrige dans le moteur, livre dans un build, et une garde de non-regression qui echoue si le symptome revient.

## Preuve exigee
`undeclared_profile_defects == 0` dans `reports/harness-undeclared-profile-attempts/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-undeclared-profile-attempts x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Rien a regarder en jeu : preuve machine..

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
