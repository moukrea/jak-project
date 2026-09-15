# Baseline code machine sparticle
DIRECTIVES vaff5c1afea

Capture statique terminée, aucun build/appareil/proof_run ni modification source.
Tous les fichiers de capture sont dans ce répertoire et préfixés before-.

- before-sparticle.cpp, before-x86-sparticle.cpp.o, before-android-sparticle.cpp.o : copies conservant mtime ; SHA-256 et tailles dans before-metadata.json.
- before-{x86,android}-{3d,2d}.asm : désassemblage ciblé avec relocations.
- before-{x86,android}-nm.txt : symboles et tailles hexadécimales.
- before-{x86,android}-compile-command.txt : commande de compilation isolée depuis ninja -t commands.
- before-{x86,android}-ninja-commands.txt : sortie brute (inclut commandes de dépendances NON exécutées).

| Objet | 3D octets | 2D octets | instructions statiques 3D / 2D |
|---|---:|---:|---:|
| x86 | 4867 (0x1303) | 6210 (0x1842) | 961 / 1219 |
| Android | 3740 (0xe9c) | 4884 (0x1314) | 935 / 1221 |

Le bloc 3D source lignes 247–278 correspond par reconnaissance des opérations à Android 0x6c4..0x8f8 inclus (142 instructions, 568 octets).
Il contient 80 instructions load/store statiques, dont recharges/adresses ; ce nombre n’est ni un nombre d’accès exécutés sur toutes les branches ni une mesure de bande passante.
La branche friction optionnelle 0x77c..0x7bc contient 17 instructions.
Le code est déjà partiellement NEON : fmul v2.2s à 0x744, fadd v0.2s à 0x760 ; fmul v3.4s à 0x834, fadd v18.4s à 0x840, fmul v4.4s à 0x84c.
Des opérations scalaires et des assemblages de lanes restent présents : fmul s1 à 0x740, mov/ld1/dup/zip1 à 0x7d8..0x830.
Les 7 lqc2 copient chacune q0 vers ExecutionContext (str q0 à 0x6e8, 0x6f0, 0x6f8, 0x70c, 0x718, 0x720, 0x728), avant calculs/rechargements scalaires.
Le clamp final utilise fcmlt + bic (0x868/0x880), pas fmax ; préserver comportement NaN et zéros signés.
x86 utilise déjà vmulps/vaddps 128 bits et vmulps 256 bits (0x2127).

Flags déterminants : x86 /usr/bin/c++, -mavx -O3 -std=gnu++20 -ffp-contract=off ; Android clang++ NDK r27c, --target=aarch64-none-linux-android29, -O3 effectif après -O2, -g0, -std=gnu++20 -ffp-contract=off, GOALC_BACKEND_ARM64.
Les fichiers compile-command.txt donnent TOUS les flags/includes réels du graphe Ninja configuré ; cwd respectifs build/ et build-android/.
Commandes exécutées : ninja -C <build> -t commands <objet>, llvm-nm -S --defined-only <copie>, llvm-objdump -d -r --demangle --disassemble-symbols='Mips2C::jak1::sp_process_block_{3d,2d}::execute(void*)' <copie> ; sorties finales exit 0.
llvm-objdump et llvm-nm : /home/emeric/Android/android-ndk-r27c/toolchains/llvm/prebuilt/linux-x86_64/bin/.
Attention outil : --demangle exige le nom démanglé dans --disassemble-symbols ; contrôlé par présence du label execute et instructions.

Non prouvé : reproductibilité des objets avec le graphe actuel (pas de recompilation), rattachement exact à tous les headers actuels, performance matérielle, gain candidat, équivalence.
Aucun défaut nouveau identifié ; coûts décrits ici sont observations statiques à mesurer, pas verdict de performance.
