#!/usr/bin/env bash
# keira_freshgk_redeploy.sh — rebatir libgk depuis les sources COMMITEES, le repackager,
# l'installer, et ne rendre la main que quand deploy_verify le certifie sur le telephone.
#
# POURQUOI CE SCRIPT EXISTE. Le close-gate refusait la phase sur
#   « libgk.so (21:58) is OLDER than newest source (14:05) — STALE build ».
# Deux faits mesures, pas une hypothese :
#   1. build_arm64_full_consistent.sh ne contient aucun cmake/gradle — il met en scene les 28
#      CGO/DGO et rien d'autre, donc il ne peut pas rebatir libgk.
#   2. la tache gradle buildNativeLibs declarait une sortie et aucune entree : gradle la sautait
#      (113/113 « UP-TO-DATE » dans .autoport/logs/auto_build_apk.txt) et ninja n'etait jamais
#      appele. Corrige au point de production dans android/app/build.gradle.kts (commit 18b2fe435d).
# Ce script est la reprise : il refait le .so, le fait voyager jusqu'au telephone, et PROUVE
# l'arrivee au lieu de l'annoncer.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44
GAME=jak1
PKG="org.opengoal.gk.${GAME}"
APK="android/app/build/outputs/apk/${GAME}/debug/app-${GAME}-debug.apk"
CUS_MAN="android/app/src/${GAME}/assets-slim/bundle/${GAME}_custom.manifest.properties"
CGO_MAN="android/app/src/${GAME}/assets-slim/bundle/${GAME}_cgo.manifest.properties"
BUILT_SO=build-android/lib/arm64-v8a/libgk.so
JNI_SO=android/app/src/main/jniLibs/arm64-v8a/libgk.so
LOG=.autoport/logs/keira_freshgk_redeploy.txt
mkdir -p .autoport/logs
say(){ printf '%s %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "$LOG"; }
die(){ say "ECHEC: $*"; exit 1; }

say "=== keira_freshgk_redeploy — HEAD $(git rev-parse --short HEAD) ==="

# --- PREFLIGHT ----------------------------------------------------------------------
# Match sur le NOM du process (ps -eo comm), jamais sur un motif dans les arguments : un
# grep sur les args matcherait ce script lui-meme et il s'auto-bloquerait.
busy=$(ps -eo comm --no-headers | awk '$1=="goalc"||$1=="cmake"||$1=="ninja"||$1=="cc1plus"{print $1}' | sort -u | tr '\n' ' ')
[ -z "$busy" ] || die "un build tourne ($busy) — refuse de compiler par-dessus (deux ninja dans build-android corrompent .ninja_deps)."
"$ADB" devices 2>/dev/null | grep -qE "^${S}[[:space:]]+device$" || die "telephone $S absent"

# --- VERROU DE LIVRAISON (convention DIRECTIVES 2026-08-14 07:10) --------------------
# PID + trap, JAMAIS un `touch` nu : un verrou sans detenteur a deja coute 108 min d'APK a
# l'owner. Il couvre TOUT le cycle — compilation, empaquetage, install, boot — parce que
# l'install est justement la fenetre ou aucun compilateur ne tourne et ou le constructeur
# automatique se croit libre de repartir sur le meme arbre.
LOCK=.autoport/.deploy-in-progress
printf 'keira_freshgk_redeploy.sh pid=%s started=%s\n' "$$" "$(date -Is)" > "$LOCK"
trap 'rm -f "$LOCK"' EXIT
say "verrou de livraison pose ($(cat "$LOCK"))"

# --- 1. LE .so, DEPUIS LES SOURCES ---------------------------------------------------
OLD_SO_SHA=$(sha256sum "$BUILT_SO" 2>/dev/null | cut -c1-16)
say "libgk AVANT : $(date -r "$BUILT_SO" +%F' '%H:%M 2>/dev/null) sha=$OLD_SO_SHA"
say "=== 1/5 ninja (cmake --build build-android --target gk) ==="
timeout 5400 cmake --build build-android --target gk -j"$(nproc)" >> "$LOG" 2>&1 \
  || die "la compilation arm64 de libgk a echoue — voir $LOG"
NEW_SO_SHA=$(sha256sum "$BUILT_SO" | cut -c1-16)
say "libgk APRES : $(date -r "$BUILT_SO" +%F' '%H:%M) sha=$NEW_SO_SHA"
[ "$OLD_SO_SHA" != "$NEW_SO_SHA" ] || say "note: le .so est binairement identique (le code commite n'y changeait rien) — la fraicheur est reelle quand meme"

# La gate de fraicheur, verifiee ICI plutot que decouverte a la fin.
NEWEST_SRC=$(find game/graphics game/kernel android -type f \( -name '*.cpp' -o -name '*.h' -o -name '*.vert' -o -name '*.frag' \) -printf '%T@\n' 2>/dev/null | sort -rn | head -1 | cut -d. -f1)
SO_MTIME=$(stat -c %Y "$BUILT_SO")
[ "$SO_MTIME" -ge "$NEWEST_SRC" ] || die "le .so ($(date -d @$SO_MTIME +%H:%M)) reste plus vieux que la source la plus recente ($(date -d @$NEWEST_SRC +%H:%M))"
say "fraicheur OK : .so posterieur a toute source C++/shader"

# --- 2. L'APK ------------------------------------------------------------------------
# :app:clean d'abord — un assemble incremental repete gonfle l'APK d'espace mort
# (588 Mo -> 1019 Mo constate le 2026-08-11), et c'est l'owner qui telecharge.
say "=== 2/5 gradle (clean + assembleJak1Debug) ==="
( cd android && timeout 900 ./gradlew :app:clean >> "../$LOG" 2>&1 ) || die "gradle clean a echoue"
( cd android && timeout 3600 ./gradlew assembleJak1Debug >> "../$LOG" 2>&1 ) || die "gradle assemble a echoue — voir $LOG"
grep -E 'Task :app:buildNativeLibs' "$LOG" | tail -1 | tee -a /dev/null
[ -f "$APK" ] || die "pas d'APK a $APK"

# --- 3. LA CHAINE DE SHA, AVANT DE TOUCHER LE TELEPHONE ------------------------------
# Piege « BUNDLE IDENTITY » : il y a TROIS copies du .so (cmake, jniLibs, APK) et rebatir
# la premiere ne bouge pas les deux autres. On le verifie hors-telephone, c'est gratuit.
B=$(sha256sum "$BUILT_SO" | cut -d' ' -f1)
J=$(sha256sum "$JNI_SO"   | cut -d' ' -f1)
A=$(unzip -p "$APK" lib/arm64-v8a/libgk.so | sha256sum | cut -d' ' -f1)
[ "$B" = "$J" ] || die "build libgk != jniLibs libgk (copyNativeLibs n'a pas tourne)"
[ "$B" = "$A" ] || die "build libgk != APK libgk (l'APK a empaquete un .so perime)"
say "chaine hors-telephone OK : build == jniLibs == APK ($(echo $B | cut -c1-16))"

WANT_CUS=$(grep -E '^version=' "$CUS_MAN" | cut -d= -f2)
WANT_CGO=$(grep -E '^version=' "$CGO_MAN" | cut -d= -f2)
APK_CUS=$(unzip -p "$APK" "assets/bundle/${GAME}_custom.manifest.properties" 2>/dev/null | grep -E '^version=' | cut -d= -f2)
APK_CGO=$(unzip -p "$APK" "assets/bundle/${GAME}_cgo.manifest.properties" 2>/dev/null | grep -E '^version=' | cut -d= -f2)
[ "$APK_CUS" = "$WANT_CUS" ] || die "l'APK embarque le pack custom '$APK_CUS' != bati '$WANT_CUS'"
[ "$APK_CGO" = "$WANT_CGO" ] || die "l'APK embarque le pack CGO '$APK_CGO' != bati '$WANT_CGO'"
say "l'APK embarque bien custom=$APK_CUS cgo=$APK_CGO"

# --- 4. INSTALL + DEBALLAGE ----------------------------------------------------------
say "=== 3/5 install (585 Mo, plusieurs minutes) ==="
"$ADB" -s "$S" shell svc power stayon true >/dev/null 2>&1
timeout 1800 "$ADB" -s "$S" install -r -d -t -i com.android.vending "$APK" >> "$LOG" 2>&1 \
  || die "adb install a echoue — voir $LOG"
say "install OK"

# Lancement par l'activite RESOLUE (LoaderActivity), JAMAIS MainActivity : MainActivity
# court-circuite l'extraction et n'ecrit aucun tampon — l'APK serait installe sans que les
# donnees soient jamais deballees, et la gate du pack serait infranchissable.
say "=== 4/5 deballage par LoaderActivity ==="
COMP=$("$ADB" -s "$S" shell cmd package resolve-activity --brief "$PKG" 2>/dev/null | tr -d '\r' | grep "^${PKG}/" | head -1)
[ -n "$COMP" ] || COMP="${PKG}/${PKG}.LoaderActivity"
say "activite resolue : $COMP"
"$ADB" -s "$S" shell am force-stop "$PKG" >/dev/null 2>&1
"$ADB" -s "$S" shell am start -n "$COMP" >/dev/null 2>&1
got_cus=""; got_cgo=""
for i in $(seq 1 60); do
  sleep 10
  got_cus=$("$ADB" -s "$S" exec-out run-as "$PKG" cat "files/.custom_pack_stamp_${GAME}" 2>/dev/null | tr -d '\r\n')
  got_cgo=$("$ADB" -s "$S" exec-out run-as "$PKG" cat "files/.cgo_pack_stamp_${GAME}" 2>/dev/null | tr -d '\r\n')
  [ $(( i % 6 )) -eq 0 ] && say "deballage en cours (${i}0s) : custom='$got_cus' cgo='$got_cgo'"
  [ "$got_cus" = "$WANT_CUS" ] && [ "$got_cgo" = "$WANT_CGO" ] && break
done
[ "$got_cus" = "$WANT_CUS" ] || die "pack custom NON deballe (device '$got_cus' != '$WANT_CUS')"
[ "$got_cgo" = "$WANT_CGO" ] || die "pack CGO NON deballe (device '$got_cgo' != '$WANT_CGO')"
say "tampons relus SUR LE TELEPHONE : custom=$got_cus cgo=$got_cgo"

# L'override externe est ce que le moteur lit VRAIMENT (kmachine.cpp donne la priorite a la
# copie /storage/emulated/0/... sur celle du pack). deploy_verify ne le regarde pas : un pack
# certifie peut coexister avec des parametres vieux de quatre heures.
if [ -f recharged_assets/physics_chains.txt ]; then
  ext=/storage/emulated/0/OpenGOAL/${GAME}/assets/recharged_assets/physics_chains.txt
  e=$("$ADB" -s "$S" shell "md5sum $ext 2>/dev/null" | tr -d '\r' | cut -d' ' -f1)
  l=$(md5sum recharged_assets/physics_chains.txt | cut -d' ' -f1)
  if [ -n "$e" ] && [ "$e" != "$l" ]; then
    "$ADB" -s "$S" push recharged_assets/physics_chains.txt "$ext" >> "$LOG" 2>&1 && say "override externe resynchronise ($e -> $l)"
  else
    say "override externe deja aligne (md5=$l)"
  fi
fi
"$ADB" -s "$S" shell am force-stop "$PKG" >/dev/null 2>&1

# --- 5. LA PREUVE --------------------------------------------------------------------
say "=== 5/5 deploy_verify ==="
bash .autoport/lib/deploy_verify.sh "$S" "$GAME" 2>&1 | tee -a "$LOG"
rc=${PIPESTATUS[0]}
[ "$rc" -eq 0 ] || die "deploy_verify refuse toujours (rc=$rc)"
say "=== DEPLOY-VERIFY PASS — le telephone porte le libgk bati depuis $(git rev-parse --short HEAD) ==="
