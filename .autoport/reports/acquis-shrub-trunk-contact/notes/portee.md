DIRECTIVES v14fcd1a084

Critère préexistant du moteur : shrub_trunk_anchor_defects=0.
Publié par foliage_wind.cpp:1625 ; aucune nouvelle clé moteur.
La somme exige troncs et jonctions présents, zéro ancre de tronc, zéro écart de pivot arrondi au millimètre et des ancres de feuillage.
Elle ne mesure ni déplacement GPU ni mobilité de chaque couronne.

La garde locale lit des blocs contigus du code CPU et GLSL actuel ; elle ne lit aucune preuve historique.
Elle refuse leur suppression ou changement, même si le texte retiré subsiste en commentaire.
Un refactoring équivalent demande une revue explicite de ces blocs.
Le recensement exécute cette même garde et pytest ; son code retour est jugé par generic.sh.
Le banc C++ provient du test attempt-9-contract-test.cpp, promu sous tests/harness en source Python pour être inclus dans l’empreinte verdict_sources.
Ses échantillons sont synthétiques ; aucune sortie synthétique ne remplace une clé moteur de proof.txt.
Seuls les codes retour de la garde et de pytest sont publiés par le recensement.

Vérification avant course : build_x86.sh --target gk --check-only, sortie 0, bx_bin_fresh=1, bx_residual_work=0.
Tests ciblés avant course : 7 passed in 2.51s.
Cinq mutations de copies : exclusion du tronc, pivot au sol, ajout sur jonction fixée, clamp TIE supprimé, plan final remplacé par le sol.
Aucun fichier jeu, asset, appareil ou validateur modifié.
