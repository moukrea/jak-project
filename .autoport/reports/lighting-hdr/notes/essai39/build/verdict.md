DIRECTIVES v708c60642a
Tests ciblés, build incrémental, repack isolé et installation Redmi terminés, tous codes0.
Hash standalone : 5cas PASS, pile32768 garde4096, données196625octets (hash-test.log).
Kernel.HashTable et SymbolCandidateSurvivesOtherLookups PASS, 2tests48ms (tests.log).
Recette kernel isolée38 : recompile kscheme.cpp/test_kernel_jak1.cpp puis lie bibliothèques auxiliaires existantes ; pas de preuve runtime GOAL.
Unique cmake --build build-android --target gk -j4 : code0, 20,989s, 3actions (android.log).
Sources suivies game/common/test/android identiques avant/après compilation (sources-{before,after}.json).
Repack38 adapté ESSAI39, --no-daemon et quatre exclusions : aucun configure ni rebuild GOAL ; 37,916s.
Packs, manifests, GAME/ENGINE/KERNEL CGO inchangés ; membres assets/bundle identiques à APK précédent.
APK surveillé par publieur inchangé ; auto_push PID2331032 présent, aucun build concurrent constaté.
Sélection pick_device explicite ANDROID_SERIAL=eae4df44 ; chaque adb utilise -s eae4df44.
Installation -r et identité APK/lib installées vérifiées (device-identity.json, deploy-calls.json).
SHA lib build/copied/JNI/APK/device : b58734a565c15f3bd907733dc2b799e54ed97eca20a4b0ab4f9a7b60e1647cec
SHA APK installé : 01d0d925b28d8a7e0f33bcd541c67642ce7b57c4443c7d0dc027fc6fc0a35b05
Settings identiques avant/après installation ; verrou PID nettoyé.
Warnings kernel GCC array-bounds et Android missing-override ; aucune erreur, aucun Wreturn-type.
Sources/validateurs non édités. Jeu et preuve non lancés ; non prouvé : comportement runtime et rendu.
