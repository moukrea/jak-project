DIRECTIVES vaff5c1afea

Les 13 primitives VuSimd passent les mêmes tests bit à bit SSE x86 et NEON AArch64 sous QEMU Linux.

- Source autonome : `vu_simd_parity.cpp` ; aucune source moteur ni aucun validateur modifié par le testeur.
- Par architecture : 951808 cas dans chacun des modes livré, verify, off ; zéro divergence sur le contexte entier.
- Mode verify : 835432 appels de comparaison réels, zéro défaut ; chaque méthode et chacun des trois kernels ont des comparaisons non nulles, vérifiées par assertions programmatiques.
- Modes livré et off : zéro appel record, résultats comparés indépendamment à ExecutionContext.
- Entrées : 16 masques, 4 broadcasts, 11 configurations d'alias/vf0 (lecture et écriture), ±zéro, subnormaux, normales extrêmes, ±inf, NaN silencieux/signalants avec signe/payload, 64 graines pseudoaléatoires fixes plus 40 jeux limites.
- Compilation x86 et AArch64 : exit 0. Exécution x86 et QEMU : exit 0, `RESULT PASS`.
- Journaux : `parity-{x86,aarch64}-{build,run}.log`.
- Header SHA256 : `9ddc2ddabf4f3994d1b8ececfe8559097b89707e981807daa91d53884048b708` (retest après extraction noinline/cold de la comparaison ; même test sans extension).
- Test SHA256 : `a522fb0449ef98a17de05f4914120d6dffe9f570ca9dd1d74e67f3a6f5e83f6e`.
- Non prouvé : intégration jeu/appareil, temps matériel ARM, 600 images de preuve. Aucun appareil utilisé, aucun proof.txt écrit.

Commandes depuis la racine du dépôt (sorties dirigées vers les journaux ci-dessus) :

```sh
TMPDIR=/home/emeric/.autoport-tmp g++ -std=c++17 -O2 -ffp-contract=off -I. -Ithird-party/fmt/include .autoport/reports/perf-mips2c-neon/notes/vu_simd_parity.cpp -o .autoport/reports/perf-mips2c-neon/notes/vu_simd_parity_x86
.autoport/reports/perf-mips2c-neon/notes/vu_simd_parity_x86
TMPDIR=/home/emeric/.autoport-tmp aarch64-linux-gnu-g++ -std=c++17 -O2 -ffp-contract=off -isystem /usr/aarch64-linux-gnu/include/c++/12 -isystem /usr/aarch64-linux-gnu/include/c++/12/aarch64-linux-gnu -L/usr/aarch64-linux-gnu/lib/gcc-cross/12 -Wl,-rpath-link,/usr/aarch64-linux-gnu/lib -I. -Ithird-party/fmt/include .autoport/reports/perf-mips2c-neon/notes/vu_simd_parity.cpp -o .autoport/reports/perf-mips2c-neon/notes/vu_simd_parity_aarch64
qemu-aarch64 -L /usr/aarch64-linux-gnu .autoport/reports/perf-mips2c-neon/notes/vu_simd_parity_aarch64
```

Anomalie d'environnement résolue : GCC cross 15 cherchait des headers C++15 absents (`fatal error: array: No such file or directory`) ; headers/runtime ARM C++12 présents employés explicitement. Un premier lien sans rpath-link échouait sur libgcc_s.so.1 ; chemin du sysroot passé explicitement au lieur. Les journaux finaux correspondent aux commandes réussies.
