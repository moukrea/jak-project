DIRECTIVES vbbd78e3a00
Baseline source : 30f3a9b540881303d31f3b93862275ada159fcdc.
Inventaire runtime capturé avant mutation : 378 objets disque,372 objets graphe,6 orphelins.
Le manifeste courant régénéré comporte373 objets runtime ; le delta ne remplace pas la preuve des6 déplacements.
Détecteurs : notes/detectors.json, une exécution avant/après des mêmes fonctions ; dix termes séparés.
Point10 utilise la capture brute du12/09 et le journal vivant, pas un faux disque reconstruit au commit baseline.
Point9 mesure désormais le banc existant C de4 objets ; aucun gain de performance du jeu n’en est déduit.

Validation agent : suite harnais 723passed en124,41s ; garde pré-outil rc0 ;4tests ménage ajoutés ensuite,4passed.
Porte ARM64 : troisABI configurées en fixtures, arguments exacts préservés, refus arbre/ABI incorrects, builder rc17 propagé.
Pas de construction SDK ni campagne appareil.

Construction : une passe incrémentale via build_x86 --target gk -j4 a compilé/relié les entrées en attente.
Le shell de cette première invocation a ensuite échoué rc2 : build_x86.sh avait été édité pendant son exécution.
Le script courant passe bash-n ; une seconde invocation de la porte a terminé en0, sans compilation ni lien.
Voir build-x86.txt (erreur initiale) et build-x86-final.txt (contrôle courant,46entrées,bx_bin_fresh=1).
La seconde invocation a archivé les6objets orphelins et publié le chemin ; aucun objet graphe supprimé.
Aucune source jeu modifiée ; aucun validateur modifié ou lancé manuellement.
