DIRECTIVES vaff5c1afea

Les trois noyaux nommés dans le périmètre sont ciblés : bones-mtx-calc, cspace<-parented-transformq-joint!, sp-launch-particles-var.
La baseline perf-stock-baseline/proof.txt donne bones=0.131 ms, math_engine=0.244 ms, process_particles=0.502 ms.
Ces mesures classent des familles ; elles ne classent pas individuellement les noyaux. Le lancement des particules n’est pas toute leur intégration.
Le chercheur constate déjà SIMD dans les anciennes fonctions os/joints ; voir old-codegen-review.txt. Ne pas annoncer un gain à partir du source ou du nombre d’instructions.
Les primitives fusionnées madd/msub et min/max restent inchangées. La vérification intégrée compare les 16 octets de chaque résultat avec ExecutionContext et ne remplace aucun résultat vectoriel par celui de l’oracle.
Le test complet des noyaux, le rejeu image et hd-mtx-check-all sont des exigences distinctes des tests unitaires des primitives.
