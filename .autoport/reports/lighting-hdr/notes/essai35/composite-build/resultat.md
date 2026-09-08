DIRECTIVES ve7fcbe0116
Candidat composite construit/livré, aucune mesure après installation, bénéfice non prouvé.
cmake --build build-android --target gk -j3 rc0 ; Gradle repack quatre exclusions rc0 ; adb install -r rc0.
lib locale/APK/Redmi SHA256 83dae28ad662d5a21180b6f9792c7e672ca304fe60780a74b9a4e8e9b0223bf2.
APK local/Redmi SHA256 8e2f8293ea275c57e1206d2bbd479f12af93cc38bba129efdebe2d907e9d334d.
GAME c303f9cc… et ENGINE2080b539… identiquesGOAL35 dans APK et appareil ; pack e52794fb…/c4251f531cd32 inchangé.
Piège détecté : Shader.cpp.o encore candidat34 (tonemap3891octets/SHA319a488c) malgré source et lib restaurées33. Source tonemap touchéemtime uniquement, régénérateur officiel puis Shader.cpp recompilé.
99shaders GLSL embarqués avant/après identiques, aucun ajouté/retiré ; tonemap source fa9aa99… inchangée.
Ninja a automatiquement relancéCMake ; aucune commande cmake -B, cache CMake byte-identique scellé avant/après.
Compilation : Shader.cpp+android_opengl_renderer.cpp seulement ; warnings override préexistants opengl.h64/65 ; aucun Wreturn-type.
Sauvegardes before/ contiennent lib/APKGOAL35, pack, manifest, sourcesnapshot candidat ; patchHEAD conservé. Verrou PID libéré.
