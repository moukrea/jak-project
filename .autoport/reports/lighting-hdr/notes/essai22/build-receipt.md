Build et déploiement incrémentaux réussis, code de sortie 0.
DIRECTIVES va841fb32b6
Script : build-deploy.sh, copie essai21 avec seul changement de dossier notes.
Journal : build-deploy.log.
Commandes : cmake --build build-android --target gk -j 3 ; Gradle assembleJak1Debug --no-daemon -x configureNativeLibs -x buildNativeLibs -x bundleJak1CgoPack -x bundleJak1CustomPack.
Sauvegardes avant compilation : before-build/libgk.so et before-build/app-jak1-debug.apk.
SHA256 lib avant : ec1726c1202f3983a2ed0d6ff06da360efdee6a70f6b5088f34a088264804721
SHA256 APK avant : 7dae36b1737d99bfc770b76a1230859c4f1931f73a006086e731aac3f5c96884
SHA256 lib build = lib extraite APK : 5e525e7ca2ca6f248b354ad9b3a50632566411ba1ff8356c7c4520a642aaee32
SHA256 APK final (sha256sum, exit=0) : baed377cc6b5e246de3a93b8325d6c7fa8d6cb59236a56345052ec36ef93af1d
MD5 lib build = APK = installée Redmi eae4df44 : b5fcc76756a9d12bd1cc40875bd3b0a4
MD5 APK final : 03f5f9ac6bd7d4f045038c57e9b39703
Gradle : BUILD SUCCESSFUL in 35s ; 36 actionable tasks: 5 executed, 31 up-to-date.
adb -s eae4df44 install -r : Success.
Contrôle de concurrence initial passé ; verrou PID posé/nettoyé par le script long.
Anomalies : régénération automatique CMake par le build (aucun cmake -B) ; warnings missing-override, dépréciations CMake et libgk.so non strippée.
Aucune édition source/validateur ; aucun clean, compilation GOAL, lancement jeu/preuve ou commit.
Non prouvé : comportement graphique et exécution du jeu après installation.
