DIRECTIVES v71a246738e

Test CPU autonome, sans reconfiguration CMake :
```sh
TMPDIR="$PWD/.autoport/reports/perf-dma-chain-copies/notes/tmp" g++ -std=c++17 -O2 -I. -Ithird-party/fmt/include -Ithird-party/spdlog/include test/common/test_dma_copy.cpp common/dma/dma_copy.cpp -Lbuild/common -lcommon -Lbuild/third-party/fmt -lfmt -Wl,-rpath,"$PWD/build/common:$PWD/build/third-party/fmt" -o .autoport/reports/perf-dma-chain-copies/notes/test_dma_copy
.autoport/reports/perf-dma-chain-copies/notes/test_dma_copy
```
Sortie mesurée (code 0) : `dma_copy_tests=passed cases=6 tags=5 payload_bytes=80 copied_bytes=655360`.
Le premier lien sans -lfmt a échoué ; ajout de la dépendance explicite, puis succès.
Le test compare la copie et son flux aplati au chemin legacy, puis vérifie conservation du buffer/statistiques après adresse basse, cycle et dépassements mémoire.
Revue researcher : aucune nouvelle course GOAL/GL ni bloqueur concret identifié ; ce constat statique n’est pas une preuve appareil.
Le compteur de marches est le maximum depuis démarrage, publié immédiatement à chaque nouveau pic ; les prévalidations de bucket encore exécutées sont comptées chacune (borne conservatrice).
Les frontières de buckets proviennent du parcours de copie ; répétition, pile CALL active ou réamorçage du follower rendent la prévalidation nécessaire.
