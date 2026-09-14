DIRECTIVES vaff5c1afea

État livré : e8620fd5df (sources moteur), headers SIMD inchangés depuis c6b978478e.

- Android : cmake --build build-android --target gk -j4, sortie 0 ; build-android-window.log, 4 arêtes, garde npc-flicker 47 propriétés tenue.
- x86 : .autoport/lib/build_x86.sh --target gk -j 3, sortie 0 ; build-x86-window.log, 4 arêtes en 16 s, bx_bin_fresh=1 et aucune arête restante.
- APK : gradlew assembleJak1Debug -x buildNativeLibs -x configureNativeLibs, sortie 0 ; apk-window.log, BUILD SUCCESSFUL in 8s.
- Empreinte et absence du diagnostic compilé : delivered-symbols.txt (nm du lib final).
- Tests du header livré : parity-results.md, 951808 cas par mode et architecture, aucune divergence.

Les journaux antérieurs gardent les échecs et états intermédiaires : lien Android initial sur reporter DMA résiduel, invocation x86 avec -j3 refusée, puis contrôle de fraîcheur x86 code 5 après correction du header DMA en cours de build. Les builds nommés ci-dessus sont ceux du dernier état.
