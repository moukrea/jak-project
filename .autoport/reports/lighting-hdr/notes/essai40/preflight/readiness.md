DIRECTIVES v708c60642a
Préflight lecture seule terminé : build disponible après instruction manager, Redmi déjà sur essai39.

Mesuré : aucun compilateur/ninja/cmake/Gradle actif à la prise de ps ; publieur PID 2331032 vivant. Verrou .autoport/.deploy-in-progress absent. Le shell de collecte PID 4171444, présent dans ps brut, est exclu du relevé des builds (sa ligne contient son propre script).
Git : .autoport/backlog.yaml modifié, plan 2026-09-07-codex-cli.md non suivi ; HEAD consigné dans git-head.txt.

Lib build-android/JNI/Redmi : SHA256 b58734a565c15f3bd907733dc2b799e54ed97eca20a4b0ab4f9a7b60e1647cec, conforme essai39.
APK Redmi et APK isolé essai39 : 01d0d925b28d8a7e0f33bcd541c67642ce7b57c4443c7d0dc027fc6fc0a35b05.
Anomalie attendue du repack isolé précédent : APK public android/app/build SHA 9767b7e77eac6c8eb5b676d9f6df5b4d326d3e3f104afe97ddb9e61ecaeb7e11, différent.
Packs, manifests, GAME/ENGINE/KERNEL.CGO locaux identiques packs-before.json essai39 ; CGO Redmi identiques aussi (device-cgos.txt).
Settings SHA 78108670e26658496f33a2a0dc50c45fe16a0f2e59c774ea70499c7fefb52fd6 inchangé. Jeu actif PID 30275.
Sélection : ANDROID_SERIAL=eae4df44 bash .autoport/lib/pick_device.sh, rc 0, eae4df44. Commandes ADB explicites et rc dans commands.json.

Tests existants à demander : PYTHONDONTWRITEBYTECODE=1 python3 -m pytest -p no:cacheprovider .autoport/tests/harness/test_hdr_batches.py -q.
Ce fichier teste agrégation/contrats HDR ; la courbe numérique est exercée en runtime dans game/graphics/opengl_renderer/hdr.cpp:158 (verdict_curve), publiée lignes 769–773. Aucun test C++ standalone HDR/courbe trouvé.
Build économique : cmake --build build-android --target gk -j4, arbre existant, sans reconfiguration. Poser auparavant verrou PID nettoyé par processus long.
Repack modèle exact : essai39/build/repack.py. Utiliser nouveau dossier isolé essai40 et init Gradle qui redirige :app ; depuis android : ./gradlew -I <init-isolé> assembleJak1Debug --no-daemon -x configureNativeLibs -x buildNativeLibs -x bundleJak1CgoPack -x bundleJak1CustomPack.
Exporter TMPDIR=/home/emeric/.autoport-tmp et GRADLE_OPTS=-Djava.io.tmpdir=/home/emeric/.autoport-tmp ; vérifier SHA lib ZIP, assets/bundle inchangés, APK public inchangé. copyNativeLibs demeure dépendance Gradle.

Non prouvé : correctif essai40, tests/runtime après correctif. Aucun build, test, déploiement, réglage, relance ni validateur lancé. Attente instruction manager.
