## ÉTABLI
DIRECTIVES vd321fc8caf
USB eae4df44 : proof.txt de cet essai, frames=6240, crash=0, codegen_lot_defects=2.
47 sites inspectés dans 5 fonctions, 46 allégés ; maxima 8/6/6/2/4 (pas un compte dynamique).
goalc SHA 6af735bd60a859c957bc5aad201d793ee7d17e2a19670d7f52c379baf1916e2c ; passe suivante no-op.
gk/APK md5 livré 35785e4ce6a3e9e09eb5591fabd0f961 ; pack ce406b6b71b5a chargé (proof-engine.log).
Encoding 438 assertions/247 cas, CFG v1/v2 14 assertions passent. Tracer conservé testé.
Archives ARM64 dans out/jak1-arm64-full/iso ; x86 restauré, 28 empreintes identiques.
X23 protégé dans les 3 entrées C++ : notes/x23-entry-wrappers.log ; wrappers inchangés.

## TENTÉ
Export live-out réel v1/v2 ; caller-save compacté par masque, zéro vivant donne ADD+BLR.
56 symboles fixes Jak1 par X14 et mémoire offset zéro register-offset ; autres chemins conservés.
Le compteur moteur lit display-frame-start/finish, display-sync, main-draw-hook, update-math-camera.
Le plan capture n’avait pas debug.opengoal.level.warp : aucune ancre/sample, candidat vide.
Candidate /sdcard/Android/data/org.opengoal.gk.jak1/files/codegen-calls-a1 déjà réservé ; ne pas réutiliser en capture.
village1-hut sélectionne 4 vues par continue-name, constat REFSET mode steps=4 vues=4.
Pas de rejeu : absence de référence. La seule course est restée courte (133 s mesurées).
GTest complet échoue hdr.cpp:622 recharged_pbr_exposure absent ; même CFG testé via libcompiler.so.

## RESTE
Atteindre 2 instructions sur tous les marqueurs sans perdre les GPR vivants : étudier prologues callee et asm-funcs.
Étendre les symboles courts dynamiques sans NOP de remplissage ni changement ABI C++.
Configurer dans l’item level.warp=village1-hut, choisir un nouveau candidat et une sélection explicite de vues.
Corriger aussi proof_env/proof_props pour un replay pad chargé sur Android (empreinte input actuelle nulle).
Capture/rejeu bornés par proof_run.sh seulement ; ne pas reconstruire gk pour changer ces propriétés.
Après tout edit codegen : goalc hôte, regen cohérente CGO puis APK ; notes/regenerate-cgos.sh conserve x86.
Le script de regen de cet essai utilise des dossiers déjà existants : choisir des noms neufs à la reprise.
Renseigner gate réel, rapport <=40 lignes et FINDINGS ; ne pas lancer generic.sh (orchestrateur).
