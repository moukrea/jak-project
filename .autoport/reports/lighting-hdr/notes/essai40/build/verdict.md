DIRECTIVES v708c60642a
Build incrémental et APK isolé essai40 installés sur Redmi, identités vérifiées, aucun redémarrage jeu.
Deux C++ seulement construits ; sources suivies game/common/test/android inchangées pendant build.
CMake : cmake --build build-android --target gk -j3, rc 0 ; détail android.log.
Gradle : assembleJak1Debug --no-daemon, init isolé et exclusions configureNativeLibs/buildNativeLibs/bundleJak1CgoPack/bundleJak1CustomPack, rc 0 ; détail repack.log.
Avertissements préexistants : override draw_splash ; Gradle ne strippe pas libgk.so. Aucun échec ni Wreturn-type signalé.
Lib SHA256 cf1aa0ff72c8851299f61d3203f5e83851ae618fdd71148e36747fd1c2bdfd48 identique build/APK/appareil.
APK SHA256 f67ac6ee54571ee6fedb7e43d6e72391e7d94d005c54fae4a9d40d30e582f980 identique isolé/appareil.
APK : gradle-app/outputs/apk/jak1/debug/app-jak1-debug.apk.
Settings SHA256 78108670e26658496f33a2a0dc50c45fe16a0f2e59c774ea70499c7fefb52fd6 inchangé ; CGO appareil et packs locaux inchangés ; APK public inchangé.
Verrou détenu par run.py PID 4175383, nettoyage à la fin. Sélection via pick_device avec ANDROID_SERIAL=eae4df44, chaque ADB -s eae4df44.
Commandes/codes/durées : commands.json. Identité : device-identity.json. Tests hôte : ../alpha-test-verdict.md.
Non prouvé : effet jeu du candidat ; manager doit lancer son lot portail. Aucun proof_run ou validateur exécuté ici.
