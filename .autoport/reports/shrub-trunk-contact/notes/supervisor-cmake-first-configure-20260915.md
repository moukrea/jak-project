# Reprise après l'essai 9

Le refus vient de `hooks/pre-tool.sh` : toute commande `cmake -B` était
assimilée à une reconfiguration, même sans dossier de build ni CMakeCache.
Le checkout témoin f54ea18c485ca156816824522d2e67ece9bc3992 est préparé,
mais aucune configuration n'a été exécutée et aucune course n'a été consommée.
Le validateur 009 rejette correctement la preuve historique de l'essai 3 ;
ce rejet ne décrit pas le comportement du nouveau binaire.

La garde accepte désormais une invocation CMake unique, avec -S/-B absolus
et littéraux, source CMake existante et destination vide ou inexistante.
Elle conserve le refus des builds contenant cache, objets ou fichiers cachés,
y compris par un alias symbolique ; les chemins ambigus restent refusés.
Les autres gardes de build et d'appareil sont inchangées.

Vérification locale : 46 tests passent (test_cmake_initial_configure.py et
test_cli_backend.py). La commande exacte refusée dans l'essai 9 passe la
garde corrigée, sans exécution de CMake. Aucune mesure du jeu effectuée ici.

Reprise : un essai de travail supplémentaire pour compiler le témoin préparé
puis suivre attempt-9-protocol.md avec les propres sources et le propre build
de chaque bras. Utiliser le harnais corrigé, ne pas contourner une copie ancienne
de sa garde. Budget appareil inchangé : trois bras de 130 s, zéro consommé.
Les critères et l'historique des échecs sont conservés.

Limites signalées par le worker : correspondance des états avant l'ancrage
et différences de vent TIE à vérifier dans le contrat ; l'herbe est échantillonnée
à une instance sur 256. Le coût réel de l'instrumentation reste à mesurer.
Des rechargements de shaders peuvent retenir des programmes en mode preuve ;
la compilation Windows de l'archive POSIX n'a pas été vérifiée. Ces observations
ne constituent ni une validation ni une autorisation de nouveaux chantiers.
